#ifndef SWIFT_COMPILER_BACKEND_H
#define SWIFT_COMPILER_BACKEND_H

#include <cstdint>
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

} // namespace swift_toolchain

#endif
