#include "SwiftCompilerBridge.h"
#include "CompilerBackend.h"
#include <cstdlib>
#include <cstring>
#include <mutex>

namespace {

/// LLVM and LLD retain global state, so all callers share one operation lock.
std::mutex operationMutex;

/// A native failure can invalidate more than the operation that first observed it.
bool sessionReusable = true;

/// The C ABI never lets a caller borrow a backend string or diagnostic stream.
SwiftCompilerResult copyResult(const swift_toolchain::BackendResult &result) {
  auto *message = static_cast<char *>(std::malloc(result.message.size() + 1));
  if (message == nullptr) {
    sessionReusable = false;
    return {1, 0, nullptr, 0};
  }
  std::memcpy(message, result.message.data(), result.message.size());
  message[result.message.size()] = '\0';
  sessionReusable = sessionReusable && result.canRunAgain;
  return {result.exitCode, sessionReusable ? 1 : 0, message, result.message.size()};
}

/// The embedding application must still provide valid readable pointer storage.
bool validArguments(int32_t count, const char *const *arguments) {
  if (count <= 0 || arguments == nullptr) {
    return false;
  }
  for (int32_t index = 0; index < count; ++index) {
    if (arguments[index] == nullptr) {
      return false;
    }
  }
  return true;
}

/// Every native operation receives the same validation, serialization, and lifetime policy.
template <typename Operation>
SwiftCompilerResult invoke(int32_t count, const char *const *arguments, Operation operation) {
  std::lock_guard<std::mutex> lock(operationMutex);
  if (!sessionReusable) {
    return copyResult({1, false, "The compiler session cannot be reused. Restart the process."});
  }
  if (!validArguments(count, arguments)) {
    return copyResult({1, true, "The compiler argument list is incomplete."});
  }
  return copyResult(operation(count, arguments));
}

} // namespace

uint32_t swift_compiler_abi_version(void) noexcept {
  return SWIFT_COMPILER_BRIDGE_ABI_VERSION;
}

SwiftCompilerResult swift_compiler_frontend(int32_t count, const char *const *arguments) noexcept {
  return invoke(count, arguments, swift_toolchain::runFrontend);
}

SwiftCompilerResult swift_compiler_autolink(int32_t count, const char *const *arguments) noexcept {
  return invoke(count, arguments, swift_toolchain::runAutolink);
}

SwiftCompilerResult swift_compiler_link(int32_t count, const char *const *arguments) noexcept {
  return invoke(count, arguments, swift_toolchain::runLinker);
}

void swift_compiler_release(char *message) noexcept {
  std::free(message);
}
