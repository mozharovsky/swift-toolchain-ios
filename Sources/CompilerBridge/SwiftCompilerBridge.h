#ifndef SWIFT_COMPILER_BRIDGE_H
#define SWIFT_COMPILER_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

/// Consumers compare this version before exchanging result storage with the library.
#define SWIFT_COMPILER_BRIDGE_ABI_VERSION 1u

#ifdef __cplusplus
#define SWIFT_COMPILER_NOEXCEPT noexcept
extern "C" {
#else
#define SWIFT_COMPILER_NOEXCEPT
#endif

/// Diagnostic storage belongs to the caller until swift_compiler_release is called.
typedef struct {
  /// Zero reports a successful operation, while nonzero preserves a tool or bridge failure.
  int32_t exitCode;
  /// A zero value requires a process restart before another compiler operation is attempted.
  int32_t canRunAgain;
  /// The caller releases this allocation even when the diagnostic text is empty.
  char *message;
  /// The byte count excludes the trailing NUL and preserves embedded NUL bytes.
  size_t messageLength;
} SwiftCompilerResult;

/// The embedding application can inspect the ABI before submitting a source snapshot.
__attribute__((visibility("default"))) uint32_t swift_compiler_abi_version(void)
    SWIFT_COMPILER_NOEXCEPT;

/// Trusted frontend arguments are borrowed until this synchronous call returns.
/// Ordinary source errors leave compiler state reusable. Fatal compiler failures can terminate
/// the process. The iOS profile rejects process execution and executable LLVM memory requests.
/// Plugin libraries and the in-process server resolve to Name.framework/Name in the main
/// application's private frameworks directory. Resolved-plugin arguments require an empty
/// executable-server field. The application preserves these files throughout compiler use.
/// Bundled macros may call the main queue, so clients keep it available while awaiting worker
/// calls.
__attribute__((visibility("default"))) SwiftCompilerResult
swift_compiler_frontend(int32_t count, const char *const *arguments) SWIFT_COMPILER_NOEXCEPT;

/// The object reader writes link requirements to the output path supplied by the embedding recipe.
/// Detailed upstream errors may also be written to the process's standard error stream.
__attribute__((visibility("default"))) SwiftCompilerResult
swift_compiler_autolink(int32_t count, const char *const *arguments) SWIFT_COMPILER_NOEXCEPT;

/// The WebAssembly linker borrows trusted arguments and preserves its native reuse status.
/// A nonreusable result prevents every later frontend, linker, and object-reader call.
__attribute__((visibility("default"))) SwiftCompilerResult
swift_compiler_link(int32_t count, const char *const *arguments) SWIFT_COMPILER_NOEXCEPT;

/// The caller releases an owned diagnostic once, and a null pointer is accepted.
__attribute__((visibility("default"))) void
swift_compiler_release(char *message) SWIFT_COMPILER_NOEXCEPT;

#ifdef __cplusplus
}
#endif

#endif
