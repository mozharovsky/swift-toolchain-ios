#include "SwiftCompilerBridge.h"
#include "TestBackend.h"
#include <atomic>
#include <cstdio>
#include <cstring>
#include <string>
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

/// Builds a completion request for the test backend.
SwiftCompilerCompletionRequest completionRequest(uint64_t identifier, const char *const *arguments,
                                                 const char *source) {
  return {identifier, 1, arguments, "main.swift", source, std::strlen(source), 3, 10, nullptr};
}

/// Whether an owned completion document contains a fragment.
bool documentContains(const SwiftCompilerResult &result, const char *fragment) {
  return result.message != nullptr &&
         std::string(result.message, result.messageLength).find(fragment) != std::string::npos;
}

/// Invalid completion requests fail as reusable JSON documents before reaching the backend.
void checkCompletionValidation() {
  const char *arguments[] = {"valid"};
  const int before = test_backend::callCount();
  auto missing = swift_compiler_complete(nullptr);
  auto zeroIdentifier = completionRequest(0, arguments, "let a = 1");
  auto pastEnd = completionRequest(1, arguments, "le");
  auto noResults = completionRequest(2, arguments, "let a = 1");
  noResults.maximumResults = 0;
  auto noPath = completionRequest(3, arguments, "let a = 1");
  noPath.path = nullptr;
  // The cursor at offset 3 falls between the two bytes of "é".
  auto insideCharacter = completionRequest(4, arguments, "le\xC3\xA9");
  for (const SwiftCompilerCompletionRequest *request :
       {&zeroIdentifier, &pastEnd, &noResults, &noPath, &insideCharacter}) {
    auto result = swift_compiler_complete(request);
    expect(result.exitCode == 1 && result.canRunAgain, "An invalid completion lost its status.");
    expect(documentContains(result, "\"status\":\"failure\""), "An invalid completion lacks JSON.");
    release(result);
  }
  expect(missing.exitCode == 1 && documentContains(missing, "\"schema\":1"),
         "A missing completion request must fail with a document.");
  release(missing);
  expect(test_backend::callCount() == before, "An invalid completion reached the backend.");
}

/// Completion forwards the cursor, honors cancellation before and during a run, and resets.
void checkCompletion() {
  const char *arguments[] = {"valid"};
  auto request = completionRequest(10, arguments, "let a = 1");
  auto success = swift_compiler_complete(&request);
  expect(success.exitCode == 0 && documentContains(success, "\"offset\":3"),
         "A completion lost its cursor or result.");
  release(success);

  const int before = test_backend::callCount();
  swift_compiler_cancel_completion(11);
  auto early = completionRequest(11, arguments, "let a = 1");
  auto earlyResult = swift_compiler_complete(&early);
  expect(earlyResult.exitCode == SWIFT_COMPILER_COMPLETION_CANCELLED && earlyResult.canRunAgain,
         "An early cancellation did not stop its request.");
  expect(documentContains(earlyResult, "\"status\":\"cancelled\""),
         "An early cancellation lacks its status.");
  expect(test_backend::callCount() == before, "An early cancellation reached the backend.");
  release(earlyResult);

  SwiftCompilerResult running{};
  std::thread worker([&running, &arguments] {
    auto waiting = completionRequest(12, arguments, "wait-for-cancellation");
    running = swift_compiler_complete(&waiting);
  });
  while (!test_backend::completionWaiting()) {
    std::this_thread::yield();
  }
  swift_compiler_cancel_completion(13);
  swift_compiler_cancel_completion(12);
  worker.join();
  expect(running.exitCode == SWIFT_COMPILER_COMPLETION_CANCELLED && running.canRunAgain,
         "A running completion ignored its cancellation.");
  release(running);
  // Cancelling another identifier during the run left an early cancellation for it.
  auto other = completionRequest(13, arguments, "let a = 1");
  auto otherResult = swift_compiler_complete(&other);
  expect(otherResult.exitCode == SWIFT_COMPILER_COMPLETION_CANCELLED,
         "A cancellation for a waiting request was lost.");
  release(otherResult);

  const int resets = test_backend::completionResets();
  swift_compiler_reset_completion();
  expect(test_backend::completionResets() == resets + 1, "The completion reset was not forwarded.");
  swift_compiler_cancel_completion(0);
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
  auto request = completionRequest(20, valid, "let a = 1");
  auto completion = swift_compiler_complete(&request);
  expect(!frontend.canRunAgain && !linker.canRunAgain && !autolink.canRunAgain &&
             !completion.canRunAgain,
         "A poisoned compiler session was reused.");
  expect(documentContains(completion, "\"status\":\"failure\""),
         "A poisoned completion lacks its document.");
  release(completion);
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
  checkCompletionValidation();
  checkCompletion();
  checkStickyFailure();
  return failures.load() == 0 ? 0 : 1;
}
