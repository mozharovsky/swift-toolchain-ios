#ifndef SWIFT_TOOLCHAIN_MACRO_ENTRY_H
#define SWIFT_TOOLCHAIN_MACRO_ENTRY_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// The compiler borrows request storage until the synchronous callback returns.
/// The caller frees the response buffer, and the main queue must remain available to worker calls.
__attribute__((visibility("default"))) bool
swift_inproc_plugins_handle_message(const uint8_t *input, intptr_t inputLength, uint8_t **output,
                                    intptr_t *outputLength);

#ifdef __cplusplus
}
#endif

#endif
