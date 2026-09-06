#include "MacroEntry.h"
#include <dispatch/dispatch.h>
#include <pthread.h>

/// The patched upstream entry retains its actor isolation and response ownership contract.
extern "C" bool swift_toolchain_macro_message_on_main_actor(const uint8_t *input,
                                                            intptr_t inputLength, uint8_t **output,
                                                            intptr_t *outputLength);

namespace {

/// A private queue marker also recognizes main-queue execution after dispatch_main releases its
/// thread.
char mainQueueKey;

/// Concurrent compiler clients must install the queue marker exactly once.
dispatch_once_t markerOnce;

/// The marker belongs to this image and cannot collide with another embedding component.
void installMainQueueMarker(void *) {
  dispatch_queue_set_specific(dispatch_get_main_queue(), &mainQueueKey, &mainQueueKey, nullptr);
}

/// Borrowed request fields remain on the caller's stack until the main-queue operation completes.
struct Request {
  /// The upstream decoder consumes these immutable bytes only during the callback.
  const uint8_t *input;
  /// The byte count uses Swift Int's pointer-sized C representation.
  intptr_t inputLength;
  /// The upstream allocator stores a caller-owned response here.
  uint8_t **output;
  /// The response length excludes any storage outside the encoded message.
  intptr_t *outputLength;
  /// The compiler treats true as a transport failure rather than a source diagnostic.
  bool failed = true;
};

/// Swift's actor-isolated handler must only be entered while executing on the main queue.
void handleRequest(void *context) {
  auto &request = *static_cast<Request *>(context);
  request.failed = swift_toolchain_macro_message_on_main_actor(
      request.input, request.inputLength, request.output, request.outputLength);
}

} // namespace

bool swift_inproc_plugins_handle_message(const uint8_t *input, intptr_t inputLength,
                                         uint8_t **output, intptr_t *outputLength) {
  dispatch_once_f(&markerOnce, nullptr, installMainQueueMarker);
  Request request{input, inputLength, output, outputLength};
  if (pthread_main_np() || dispatch_get_specific(&mainQueueKey) == &mainQueueKey) {
    handleRequest(&request);
  } else {
    dispatch_sync_f(dispatch_get_main_queue(), &request, handleRequest);
  }
  return request.failed;
}
