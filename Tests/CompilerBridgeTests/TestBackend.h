#ifndef SWIFT_COMPILER_TEST_BACKEND_H
#define SWIFT_COMPILER_TEST_BACKEND_H

namespace test_backend {

/// Contract tests compare this count before and after bridge-level rejection.
int callCount();

/// A value above one would violate the serialization required by real LLVM state.
int maximumConcurrency();

/// The number of times the bridge dropped the completion context.
int completionResets();

/// Whether a completion or an annotation is waiting for its cancellation flag inside the test
/// backend.
bool completionWaiting();

} // namespace test_backend

#endif
