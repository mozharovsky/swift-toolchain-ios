#include "MacroEntry.h"
#include <atomic>
#include <cstdlib>
#include <dispatch/dispatch.h>

namespace {

/// CTest observes failures after the direct, worker, and nested main-queue paths finish.
std::atomic<int> failures{0};

/// The test double records real crossings through the production callback adapter.
std::atomic<int> calls{0};

/// A nested callback must recognize its queue instead of synchronously dispatching to itself.
void invoke(uint8_t input) {
  uint8_t *output = nullptr;
  intptr_t length = 0;
  const bool failed = swift_inproc_plugins_handle_message(&input, 1, &output, &length);
  if (failed || output == nullptr || length != 1 || output[0] != input) {
    ++failures;
  }
  std::free(output);
}

/// A worker waits for the adapter while dispatch_main keeps the main queue available.
void runWorker(void *) {
  invoke(2);
  if (calls != 3) {
    ++failures;
  }
  std::exit(failures == 0 ? 0 : 1);
}

} // namespace

/// The fixture substitutes only the actor-isolated handler, which must run on the main queue.
extern "C" bool swift_toolchain_macro_message_on_main_actor(const uint8_t *input, intptr_t length,
                                                            uint8_t **output,
                                                            intptr_t *outputLength) {
  dispatch_assert_queue(dispatch_get_main_queue());
  ++calls;
  if (length != 1) {
    return true;
  }
  if (input[0] == 2) {
    invoke(3);
  }
  *output = static_cast<uint8_t *>(std::malloc(1));
  if (*output == nullptr) {
    return true;
  }
  **output = input[0];
  *outputLength = 1;
  return false;
}

/// The initial call checks physical-main-thread entry before queued execution starts.
int main() {
  invoke(1);
  dispatch_async_f(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), nullptr, runWorker);
  dispatch_main();
}
