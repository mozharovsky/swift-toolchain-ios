#ifndef SWIFT_COMPILER_SEMANTIC_SUPPORT_H
#define SWIFT_COMPILER_SEMANTIC_SUPPORT_H

#include "swift/AST/PluginRegistry.h"
#include "swift/Frontend/Frontend.h"
#include "swift/IDE/CodeCompletionResult.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/VirtualFileSystem.h"
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>

namespace swift_toolchain {

/// The macro plugin registry that completion and annotation share for the life of the process.
///
/// The loader keeps macro libraries mapped, so the registry outlives every cache reset.
std::shared_ptr<swift::PluginRegistry> &semanticPluginRegistry();

/// Returns the milliseconds since a start on the monotonic clock, for the timings in result
/// documents.
///
/// \param start The time point that the measured step began at.
double millisecondsSince(std::chrono::steady_clock::time_point start);

/// Returns a JSON document with schema 1 for a request that produced no result.
///
/// Completion and annotation return it for invalid requests, setup failures, and cancellations.
///
/// \param status The outcome, such as failure or cancelled.
/// \param error The reason, which the JSON writer escapes.
std::string statusDocument(llvm::StringRef status, llvm::StringRef error);

/// Returns the stable name of a declaration kind, which an editor maps to icons and colors.
///
/// \param kind The kind that IDE support derives from a declaration.
const char *declarationKindName(swift::ide::CodeCompletionDeclKind kind);

/// Prepares a type-checking invocation whose only primary input is the file at a path.
///
/// The caller's arguments name every input of the project. The input whose real path equals the
/// requested path becomes the primary file, and the others stay secondary. LLVM arguments are
/// dropped because they configure process-wide state.
///
/// \param operation The request's name for error messages, such as completion.
/// \param count The number of frontend arguments, which is positive.
/// \param arguments The frontend arguments, which stay borrowed.
/// \param path The input that becomes the primary file.
/// \param primarySource The contents that replace the primary input, or nothing to keep its file.
/// \param invocation Receives the prepared invocation.
/// \param target Receives the primary input's real path.
/// \param primaryBuffer Receives a copy of the primary source when one is given. Its identifier is
/// the real path, which lets the frontend recognize a primary `main.swift` as the main file. The
/// caller keeps it alive for every compiler instance that uses the invocation.
/// \returns An error message for invalid arguments or a path outside the inputs, or an empty
/// string on success.
std::string prepareSemanticInvocation(llvm::StringRef operation, int32_t count,
                                      const char *const *arguments, const char *path,
                                      std::optional<llvm::StringRef> primarySource,
                                      swift::CompilerInvocation &invocation,
                                      llvm::SmallString<256> &target,
                                      std::unique_ptr<llvm::MemoryBuffer> &primaryBuffer);

} // namespace swift_toolchain

#endif
