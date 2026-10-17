#include "TestBackend.h"
#include "CompilerBackend.h"
#include <atomic>
#include <chrono>
#include <cstring>
#include <string>
#include <thread>

namespace {

/// This test double exercises bridge contracts and does not compile or interpret Swift.
std::atomic<int> calls{0};

/// Concurrent callers expose a missing process-wide lock through this counter.
std::atomic<int> active{0};

/// Tests retain the highest observed overlap instead of relying on thread completion order.
std::atomic<int> maximum{0};

/// The fake backend supplies deterministic ownership and failure cases to the real C ABI wrapper.
swift_toolchain::BackendResult respond(const char *argument) {
  ++calls;
  const int current = ++active;
  int observed = maximum.load();
  while (observed < current && !maximum.compare_exchange_weak(observed, current)) {
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(1));
  --active;
  if (std::strcmp(argument, "invalid-source") == 0) {
    return {1, true, "The test source is invalid."};
  }
  if (std::strcmp(argument, "nonreusable") == 0) {
    return {1, false, "The test linker cannot be reused."};
  }
  return {0, true, std::string("a\0b", 3)};
}

} // namespace

swift_toolchain::BackendResult swift_toolchain::runFrontend(int32_t, const char *const *arguments) {
  return respond(arguments[0]);
}

swift_toolchain::BackendResult swift_toolchain::runAutolink(int32_t, const char *const *arguments) {
  return respond(arguments[0]);
}

swift_toolchain::BackendResult swift_toolchain::runLinker(int32_t, const char *const *arguments) {
  return respond(arguments[0]);
}

namespace {

/// Completion resets that the bridge requested.
std::atomic<int> resets{0};

/// Whether a completion is waiting for cancellation, which lets a test cancel at the right time.
std::atomic<bool> waiting{false};

/// Waits up to five seconds for a cancellation, which lets a test stop a running request.
///
/// \param cancellation The flag that the bridge passed to the backend.
swift_toolchain::BackendResult waitForCancellation(const std::atomic<bool> &cancellation) {
  ++calls;
  waiting = true;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (!cancellation.load() && std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  waiting = false;
  if (cancellation.load()) {
    return {2, true, "{\"schema\":1,\"status\":\"cancelled\"}"};
  }
  return {1, true, "{\"schema\":1,\"status\":\"failure\"}"};
}

} // namespace

swift_toolchain::BackendResult
swift_toolchain::runCompletion(const swift_toolchain::CompletionRequest &request,
                               std::shared_ptr<std::atomic<bool>> cancellation) {
  const std::string source(request.source, request.sourceLength);
  if (source == "wait-for-cancellation") {
    return waitForCancellation(*cancellation);
  }
  auto result = respond(request.arguments[0]);
  if (result.exitCode == 0) {
    result.message =
        "{\"schema\":1,\"status\":\"success\",\"offset\":" + std::to_string(request.offset) + "}";
  }
  return result;
}

swift_toolchain::BackendResult
swift_toolchain::runAnnotation(const swift_toolchain::AnnotationRequest &request,
                               std::shared_ptr<std::atomic<bool>> cancellation) {
  const std::string source(request.source, request.sourceLength);
  if (source == "wait-for-cancellation") {
    return waitForCancellation(*cancellation);
  }
  auto result = respond(request.arguments[0]);
  if (result.exitCode == 0) {
    result.message = "{\"schema\":1,\"status\":\"success\",\"sourceLength\":" +
                     std::to_string(request.sourceLength) + "}";
  }
  return result;
}

void swift_toolchain::resetCompletion() {
  ++resets;
}

int test_backend::completionResets() {
  return resets.load();
}

bool test_backend::completionWaiting() {
  return waiting.load();
}

int test_backend::callCount() {
  return calls.load();
}

int test_backend::maximumConcurrency() {
  return maximum.load();
}
