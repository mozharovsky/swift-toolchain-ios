#ifndef SWIFT_COMPILER_BACKEND_H
#define SWIFT_COMPILER_BACKEND_H

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace swift_toolchain {

/// The bridge copies backend-owned diagnostics before releasing the operation lock.
struct BackendResult {
  /// The native tool's status remains available to the embedding application.
  int exitCode;
  /// Native linker recovery decides whether compiler-global state remains usable.
  bool canRunAgain;
  /// Byte storage is independent of native diagnostic stream lifetimes.
  std::string message;
};

/// The bridge calls the real frontend only after validating and serializing the request.
BackendResult runFrontend(int32_t count, const char *const *arguments);

/// The bridge keeps object metadata extraction in the same process-wide operation sequence.
BackendResult runAutolink(int32_t count, const char *const *arguments);

/// The bridge retains LLD's reuse decision after every WebAssembly link.
BackendResult runLinker(int32_t count, const char *const *arguments);

/// A validated completion request whose buffers stay borrowed until runCompletion returns.
struct CompletionRequest {
  /// The number of frontend arguments, which the bridge has checked to be positive.
  int32_t count;
  /// The frontend argument strings, which remain owned by the caller.
  const char *const *arguments;
  /// The input path whose contents the source buffer replaces.
  const char *path;
  /// The UTF-8 source text, which need not end with a NUL byte.
  const char *source;
  /// The source length in bytes.
  size_t sourceLength;
  /// The cursor as a UTF-8 byte offset, at most sourceLength.
  size_t offset;
  /// The largest number of ranked items in the result, which is positive.
  uint32_t maximumResults;
  /// The module completion cache directory, or null for a cache in memory.
  const char *cacheDirectory;
};

/// Runs a completion under the bridge's operation lock and returns its JSON document.
///
/// The backend stops early and returns the cancelled status once the flag becomes true. The exit
/// code follows the public completion contract.
BackendResult runCompletion(const CompletionRequest &request,
                            std::shared_ptr<std::atomic<bool>> cancellation);

/// Drops the cached completion context while the bridge holds the operation lock.
void resetCompletion();

/// Registers LLVM targets and the Swift-implemented compiler modules once per process.
///
/// The frontend and completion call it before their first use of compiler state.
void prepareNativeCompiler();

} // namespace swift_toolchain

#endif
