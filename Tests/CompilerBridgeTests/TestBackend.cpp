#include "TestBackend.h"
#include "CompilerBackend.h"
#include <atomic>
#include <chrono>
#include <cstring>
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

int test_backend::callCount() {
  return calls.load();
}

int test_backend::maximumConcurrency() {
  return maximum.load();
}
