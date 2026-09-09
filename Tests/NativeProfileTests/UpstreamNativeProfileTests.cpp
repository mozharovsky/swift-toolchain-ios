#include "swift/Basic/Program.h"
#include "llvm/Support/DynamicLibrary.h"
#include "llvm/Support/Memory.h"
#include "llvm/Support/Program.h"
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <unistd.h>

namespace {

/// Reports every failed native restriction before CTest receives a failing exit status.
int check(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "%s\n", message);
    return 1;
  }
  return 0;
}

/// Checks the actual patched entry points with a missing executable inside an owned fixture.
int checkProcesses(const std::string &missing) {
  const llvm::StringRef arguments[] = {missing};
  const char *cArguments[] = {missing.c_str(), nullptr};
  int failures = 0;
  std::string error;
  bool executionFailed = false;
  const int status = llvm::sys::ExecuteAndWait(missing, arguments, std::nullopt, {}, 0, 0, &error,
                                               &executionFailed);
  failures +=
      check(status == -1 && executionFailed && error.find("embedded compiler") != error.npos,
            "LLVM synchronous execution must report a profile refusal.");
  error.clear();
  executionFailed = false;
  const auto process =
      llvm::sys::ExecuteNoWait(missing, arguments, std::nullopt, {}, 0, &error, &executionFailed);
  failures += check(process.Pid == 0 && executionFailed && !error.empty(),
                    "LLVM asynchronous execution must not create a process.");
  error.clear();
  const auto waited = llvm::sys::Wait({}, 0, &error);
  failures += check(waited.Pid == 0 && waited.ReturnCode == -1 && !error.empty(),
                    "Waiting on a refused operation must remain a local error.");
  errno = 0;
  failures += check(swift::ExecuteInPlace(missing.c_str(), cArguments) == -1 && errno == EPERM,
                    "Swift execution in place must refuse before consulting the executable.");
  const auto piped = swift::ExecuteWithPipe(missing, arguments);
  failures += check(!piped && piped.getError() == std::errc::operation_not_permitted,
                    "Swift piped execution must refuse before creating pipes or a process.");
  return failures;
}

/// Checks that denying executable pages preserves data mappings and their normal protection
/// changes.
int checkMemory() {
  using Memory = llvm::sys::Memory;
  int failures = 0;
  const unsigned requests[] = {Memory::MF_EXEC, Memory::MF_EXEC | Memory::MF_READ,
                               Memory::MF_EXEC | Memory::MF_WRITE,
                               Memory::MF_EXEC | Memory::MF_READ | Memory::MF_WRITE};
  for (unsigned flags : requests) {
    std::error_code error;
    auto block = Memory::allocateMappedMemory(4096, nullptr, flags, error);
    failures += check(block.base() == nullptr && error == std::errc::operation_not_permitted,
                      "Every executable-memory allocation must be refused.");
    if (block.base() != nullptr) {
      failures += check(!Memory::releaseMappedMemory(block), "Release an unexpected mapping.");
    }
    failures += check(Memory::protectMappedMemory({}, flags) == std::errc::operation_not_permitted,
                      "Even an empty mapping must refuse an executable protection request.");
  }
  std::error_code error;
  auto block =
      Memory::allocateMappedMemory(4096, nullptr, Memory::MF_READ | Memory::MF_WRITE, error);
  failures +=
      check(block.base() != nullptr && !error, "An ordinary data mapping must remain usable.");
  if (block.base() != nullptr && !error) {
    auto *bytes = static_cast<unsigned char *>(block.base());
    bytes[0] = 73;
    failures += check(!Memory::protectMappedMemory(block, Memory::MF_READ),
                      "Data mappings must retain ordinary read protection.");
    failures += check(Memory::protectMappedMemory(block, Memory::MF_READ | Memory::MF_EXEC) ==
                              std::errc::operation_not_permitted &&
                          bytes[0] == 73,
                      "A refused executable protection change must preserve the data mapping.");
    const bool writable = !Memory::protectMappedMemory(block, Memory::MF_READ | Memory::MF_WRITE);
    failures +=
        check(writable, "A data mapping must remain writable after a refused executable request.");
    if (writable) {
      bytes[0] = 19;
      Memory::InvalidateInstructionCache(block.base(), 1);
      failures +=
          check(bytes[0] == 19, "Instruction-cache invalidation must not alter data mappings.");
    }
    failures += check(!Memory::releaseMappedMemory(block), "Data mappings must remain releasable.");
  }
  return failures;
}

/// Checks both LLVM library-loading forms while preserving access to the existing process handle.
int checkLibraries(const std::string &missing) {
  std::string error;
  int failures = 0;
  const auto process = llvm::sys::DynamicLibrary::getPermanentLibrary(nullptr, &error);
  failures += check(process.isValid(), "LLVM must retain lookup in its already loaded process.");
  error.clear();
  const auto permanent = llvm::sys::DynamicLibrary::getPermanentLibrary(missing.c_str(), &error);
  failures += check(!permanent.isValid() && error.find("embedded compiler") != error.npos,
                    "LLVM permanent library loading must report a profile refusal.");
  error.clear();
  const auto transient = llvm::sys::DynamicLibrary::getLibrary(missing.c_str(), &error);
  failures += check(!transient.isValid() && error.find("embedded compiler") != error.npos,
                    "LLVM temporary library loading must report a profile refusal.");
  return failures;
}

} // namespace

/// Runs host checks of the pinned, patched implementations without a complete compiler build.
int main() {
  char temporary[] = "/tmp/swift-toolchain-native.XXXXXX";
  const auto created = mkdtemp(temporary);
  if (created == nullptr) {
    return check(false, "Create the owned native profile fixture.");
  }
  const std::filesystem::path root(created);
  const auto missing = (root / "missing").string();
  int failures = checkProcesses(missing) + checkMemory() + checkLibraries(missing);
  std::error_code error;
  std::filesystem::remove(root, error);
  failures += check(!error, "Remove the owned native profile fixture.");
  return failures == 0 ? 0 : 1;
}
