#include "SwiftCompilerBridge.h"
#include "CompilerBackend.h"
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>

namespace {

/// LLVM and LLD retain global state, so all callers share one operation lock.
std::mutex operationMutex;

/// A native failure can invalidate more than the operation that first observed it.
bool sessionReusable = true;

/// Cancellation has its own lock so another thread can stop a completion that holds the operation
/// lock.
std::mutex cancellationMutex;

/// The identifier of the completion that holds the operation lock, or zero when none runs.
uint64_t runningCompletion = 0;

/// The flag that the running completion's compiler instance checks.
std::shared_ptr<std::atomic<bool>> runningCancellation;

/// Identifiers cancelled before their request took the operation lock, oldest first.
std::deque<uint64_t> pendingCancellations;

/// The number of early cancellations remembered, which bounds the cost of stale identifiers.
constexpr size_t rememberedCancellations = 64;

/// A completion document for an outcome that the backend never sees.
///
/// The error text is fixed ASCII without quotes, so it needs no JSON escaping.
std::string completionDocument(const char *status, const char *error) {
  return std::string("{\"schema\":1,\"status\":\"") + status + "\",\"error\":\"" + error + "\"}";
}

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

SwiftCompilerResult
swift_compiler_complete(const SwiftCompilerCompletionRequest *request) noexcept {
  std::lock_guard<std::mutex> lock(operationMutex);
  if (!sessionReusable) {
    return copyResult(
        {1, false,
         completionDocument("failure",
                            "The compiler session cannot be reused. Restart the process.")});
  }
  if (request == nullptr || request->requestID == 0 ||
      !validArguments(request->argumentCount, request->arguments) || request->path == nullptr ||
      request->source == nullptr || request->offset > request->sourceLength ||
      request->maximumResults == 0) {
    return copyResult(
        {1, true, completionDocument("failure", "The completion request is incomplete.")});
  }
  // A cursor inside a multibyte character would split the filter text and the replacement range.
  if (request->offset < request->sourceLength &&
      (static_cast<unsigned char>(request->source[request->offset]) & 0xC0) == 0x80) {
    return copyResult(
        {1, true,
         completionDocument("failure", "The completion offset is inside a UTF-8 character.")});
  }
  const uint64_t identifier = request->requestID;
  std::shared_ptr<std::atomic<bool>> cancellation;
  {
    std::lock_guard<std::mutex> guard(cancellationMutex);
    auto pending = std::find(pendingCancellations.begin(), pendingCancellations.end(), identifier);
    if (pending != pendingCancellations.end()) {
      pendingCancellations.erase(pending);
      return copyResult({SWIFT_COMPILER_COMPLETION_CANCELLED, true,
                         completionDocument("cancelled", "The completion request was cancelled.")});
    }
    cancellation = std::make_shared<std::atomic<bool>>(false);
    runningCompletion = identifier;
    runningCancellation = cancellation;
  }
  const swift_toolchain::CompletionRequest backendRequest{
      request->argumentCount, request->arguments, request->path,           request->source,
      request->sourceLength,  request->offset,    request->maximumResults, request->cacheDirectory};
  auto result = swift_toolchain::runCompletion(backendRequest, cancellation);
  {
    std::lock_guard<std::mutex> guard(cancellationMutex);
    runningCompletion = 0;
    runningCancellation.reset();
  }
  return copyResult(result);
}

void swift_compiler_cancel_completion(uint64_t requestID) noexcept {
  if (requestID == 0) {
    return;
  }
  std::lock_guard<std::mutex> guard(cancellationMutex);
  if (requestID == runningCompletion && runningCancellation) {
    runningCancellation->store(true);
    return;
  }
  if (std::find(pendingCancellations.begin(), pendingCancellations.end(), requestID) ==
      pendingCancellations.end()) {
    pendingCancellations.push_back(requestID);
    if (pendingCancellations.size() > rememberedCancellations) {
      pendingCancellations.pop_front();
    }
  }
}

void swift_compiler_reset_completion(void) noexcept {
  std::lock_guard<std::mutex> lock(operationMutex);
  swift_toolchain::resetCompletion();
}

void swift_compiler_release(char *message) noexcept {
  std::free(message);
}
