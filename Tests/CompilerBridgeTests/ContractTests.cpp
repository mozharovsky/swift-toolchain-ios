#include "SwiftCompilerBridge.h"
#include "TestBackend.h"
#include <atomic>
#include <cstdio>
#include <cstring>
#include <thread>
#include <vector>

extern "C" uint32_t compiler_header_version(void);

namespace {

/// A failed expectation remains visible even when release builds define NDEBUG.
std::atomic<int> failures{0};

/// CTest receives a nonzero exit status after every failed contract is reported.
void expect(bool condition, const char *message) {
  if (!condition) {
    std::fprintf(stderr, "%s\n", message);
    ++failures;
  }
}

/// Callers can release diagnostics from successes, ordinary errors, and null storage.
void release(SwiftCompilerResult result) {
  swift_compiler_release(result.message);
}

/// Invalid argument shapes must return before any backend dereferences borrowed pointers.
void checkArguments() {
  const int before = test_backend::callCount();
  const char *invalid[] = {nullptr};
  auto first = swift_compiler_frontend(0, nullptr);
  auto second = swift_compiler_link(1, nullptr);
  auto third = swift_compiler_autolink(1, invalid);
  expect(first.exitCode != 0 && second.exitCode != 0 && third.exitCode != 0,
         "Incomplete argument vectors must fail.");
  expect(first.canRunAgain && second.canRunAgain && third.canRunAgain,
         "Argument validation must leave a healthy session reusable.");
  expect(test_backend::callCount() == before, "Invalid vectors reached the backend.");
  release(first);
  release(second);
  release(third);
}

/// Owned messages retain their bytes after later operations reuse backend storage.
void checkOwnershipAndRecovery() {
  const char *valid[] = {"valid"};
  const char *invalid[] = {"invalid-source"};
  auto first = swift_compiler_frontend(1, valid);
  auto error = swift_compiler_frontend(1, invalid);
  auto next = swift_compiler_frontend(1, valid);
  expect(first.exitCode == 0 && next.exitCode == 0, "Ordinary errors must allow a later request.");
  expect(error.exitCode != 0 && error.canRunAgain, "The source error lost its reusable status.");
  expect(first.message != nullptr && first.messageLength == 3, "The message byte count changed.");
  if (first.message != nullptr && first.messageLength == 3) {
    expect(std::memcmp(first.message, "a\0b", 3) == 0 && first.message[3] == '\0',
           "Owned diagnostics must preserve embedded NUL bytes and a terminator.");
  }
  release(first);
  release(error);
  release(next);
  swift_compiler_release(nullptr);
}

/// All three native entry points must share one lock because their upstream state is shared.
void checkSerialization() {
  std::atomic<bool> start{false};
  std::vector<std::thread> threads;
  for (int index = 0; index < 9; ++index) {
    threads.emplace_back([&start, index] {
      while (!start.load()) {
        std::this_thread::yield();
      }
      const char *arguments[] = {"valid"};
      for (int repeat = 0; repeat < 3; ++repeat) {
        SwiftCompilerResult result{};
        switch (index % 3) {
        case 0:
          result = swift_compiler_frontend(1, arguments);
          break;
        case 1:
          result = swift_compiler_link(1, arguments);
          break;
        default:
          result = swift_compiler_autolink(1, arguments);
        }
        expect(result.exitCode == 0 && result.canRunAgain, "A serialized operation failed.");
        release(result);
      }
    });
  }
  start = true;
  for (auto &thread : threads) {
    thread.join();
  }
  expect(test_backend::maximumConcurrency() == 1, "Native operations overlapped.");
}

/// No entry point may touch compiler state after LLD reports that it cannot run again.
void checkStickyFailure() {
  const char *failure[] = {"nonreusable"};
  const char *valid[] = {"valid"};
  auto result = swift_compiler_link(1, failure);
  expect(result.exitCode != 0 && !result.canRunAgain, "The nonreusable status was discarded.");
  release(result);
  const int before = test_backend::callCount();
  auto frontend = swift_compiler_frontend(1, valid);
  auto linker = swift_compiler_link(1, valid);
  auto autolink = swift_compiler_autolink(1, valid);
  expect(!frontend.canRunAgain && !linker.canRunAgain && !autolink.canRunAgain,
         "A poisoned compiler session was reused.");
  expect(test_backend::callCount() == before, "A poisoned session reached the native backend.");
  release(frontend);
  release(linker);
  release(autolink);
}

} // namespace

int main() {
  expect(compiler_header_version() == SWIFT_COMPILER_BRIDGE_ABI_VERSION,
         "The C ABI version differs.");
  checkArguments();
  checkOwnershipAndRecovery();
  checkSerialization();
  checkStickyFailure();
  return failures.load() == 0 ? 0 : 1;
}
