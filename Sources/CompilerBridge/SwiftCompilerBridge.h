#ifndef SWIFT_COMPILER_BRIDGE_H
#define SWIFT_COMPILER_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

/// Consumers compare this version before exchanging result storage with the library.
///
/// Version 2 adds semantic completion and version 3 adds semantic annotation. The layouts of the
/// earlier operations are unchanged.
#define SWIFT_COMPILER_BRIDGE_ABI_VERSION 3u

/// The exit code of a completion or an annotation that swift_compiler_cancel_completion stopped.
#define SWIFT_COMPILER_COMPLETION_CANCELLED 2

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
/// A nonreusable result prevents every later frontend, linker, object-reader, completion, and
/// annotation call.
__attribute__((visibility("default"))) SwiftCompilerResult
swift_compiler_link(int32_t count, const char *const *arguments) SWIFT_COMPILER_NOEXCEPT;

/// One semantic completion request, which the embedding editor sends for a cursor in a source file.
///
/// Every pointer is borrowed until swift_compiler_complete returns.
typedef struct {
  /// A nonzero identifier for swift_compiler_cancel_completion. It stays unique for the process.
  uint64_t requestID;
  /// The number of frontend arguments, which is positive.
  int32_t argumentCount;
  /// The trusted frontend arguments that swift_compiler_frontend would receive for the project.
  const char *const *arguments;
  /// The input whose contents the source buffer replaces. It names one of the arguments' inputs.
  const char *path;
  /// The UTF-8 source of that input, which need not end with a NUL byte.
  const char *source;
  /// The source length in bytes.
  size_t sourceLength;
  /// The cursor as a UTF-8 byte offset into the source, at most sourceLength. It falls on a
  /// character boundary, so it never points at a continuation byte.
  size_t offset;
  /// The largest number of ranked items that the result lists, which is positive.
  uint32_t maximumResults;
  /// A writable directory for the module completion cache, or NULL to keep the cache in memory.
  ///
  /// The cache keeps the context-free results of each imported module across launches. A change of
  /// directory starts a new completion context.
  const char *cacheDirectory;
} SwiftCompilerCompletionRequest;

/// Lists the completions at a cursor as an owned JSON document with schema 1.
///
/// Identifier characters immediately before the cursor become the filter text, and completion runs
/// at the start of that identifier. The type-checked context stays cached between requests with the
/// same arguments, path, and cache directory, so a request inside a function body reuses it.
/// Completion shares the operation lock with the other entry points, and the same macro rules
/// apply, so clients call it from a worker while the main queue stays available.
///
/// The exit code is zero for a result list, SWIFT_COMPILER_COMPLETION_CANCELLED for a cancelled
/// request, and another nonzero value for an invalid request or a compiler failure. Every outcome
/// returns a JSON document whose status field names it. Ordinary failures leave the session
/// reusable.
__attribute__((visibility("default"))) SwiftCompilerResult
swift_compiler_complete(const SwiftCompilerCompletionRequest *request) SWIFT_COMPILER_NOEXCEPT;

/// One semantic annotation request, which an embedding editor sends to color the names in a source
/// file after the file changes.
///
/// Every pointer is borrowed until swift_compiler_annotate returns.
typedef struct {
  /// A nonzero identifier for swift_compiler_cancel_completion. It stays unique for the process
  /// across completions and annotations.
  uint64_t requestID;
  /// The number of frontend arguments, which is positive.
  int32_t argumentCount;
  /// The trusted frontend arguments that swift_compiler_frontend would receive for the project.
  const char *const *arguments;
  /// The input whose contents the source buffer replaces. It names one of the arguments' inputs.
  const char *path;
  /// The UTF-8 source of that input, which need not end with a NUL byte.
  const char *source;
  /// The source length in bytes.
  size_t sourceLength;
} SwiftCompilerAnnotationRequest;

/// Type-checks one input with the given source and lists its named references and its errors and
/// warnings as an owned JSON document with schema 1.
///
/// Every request builds a new compiler instance, so the cost follows the size of the input and
/// does not depend on earlier requests. The other inputs are parsed, and only the primary input's
/// function bodies are type-checked. A type check without errors continues into SILGen and the
/// mandatory diagnostic passes for the primary input, which add flow diagnostics such as a missing
/// return. SILGen and the passes do not stop for a cancellation, which takes effect before each of
/// them. Annotation shares the operation lock with the other entry points, and the same macro rules
/// apply, so clients call it from a worker with a large stack while the main queue stays available.
///
/// The exit code is zero for a result, SWIFT_COMPILER_COMPLETION_CANCELLED for a cancelled request,
/// and another nonzero value for an invalid request or a compiler failure. Source errors still
/// produce a result. Every outcome returns a JSON document whose status field names it. Ordinary
/// failures leave the session reusable.
__attribute__((visibility("default"))) SwiftCompilerResult
swift_compiler_annotate(const SwiftCompilerAnnotationRequest *request) SWIFT_COMPILER_NOEXCEPT;

/// Stops the completion or annotation with this identifier from any thread.
///
/// Completions and annotations share one identifier space. A running request stops at the
/// compiler's next cancellation check. A request that has not started yet, such as one waiting for
/// a compile, returns at once when it starts. Only the most recent 64 identifiers without a running
/// request are remembered, and an unknown identifier has no other effect.
__attribute__((visibility("default"))) void
swift_compiler_cancel_completion(uint64_t requestID) SWIFT_COMPILER_NOEXCEPT;

/// Drops the cached completion context and its module results, for example under memory pressure.
///
/// The call waits for any running compiler operation. The next completion rebuilds the context.
__attribute__((visibility("default"))) void
swift_compiler_reset_completion(void) SWIFT_COMPILER_NOEXCEPT;

/// The caller releases an owned diagnostic once, and a null pointer is accepted.
__attribute__((visibility("default"))) void
swift_compiler_release(char *message) SWIFT_COMPILER_NOEXCEPT;

#ifdef __cplusplus
}
#endif

#endif
