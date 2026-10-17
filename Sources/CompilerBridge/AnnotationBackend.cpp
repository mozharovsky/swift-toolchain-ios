#include "CompilerBackend.h"
#include "SemanticSupport.h"
#include "SwiftCompilerBridge.h"
#include "swift/AST/DiagnosticConsumer.h"
#include "swift/AST/DiagnosticEngine.h"
#include "swift/AST/Module.h"
#include "swift/AST/PluginLoader.h"
#include "swift/AST/SourceFile.h"
#include "swift/Basic/SourceManager.h"
#include "swift/Frontend/Frontend.h"
#include "swift/IDE/CodeCompletionResult.h"
#include "swift/IDE/SourceEntityWalker.h"
#include "swift/Parse/Lexer.h"
#include "swift/Subsystems.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/VirtualFileSystem.h"
#include "llvm/Support/raw_ostream.h"
#include <chrono>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace {

/// The most diagnostics that one annotation reports, which bounds the document for broken code.
constexpr size_t maximumDiagnostics = 100;

/// One error or warning with its location, which the annotation resolves against the primary file.
struct LocatedDiagnostic {
  /// Whether the compiler reported an error rather than a warning.
  bool error;
  /// The formatted message without its location.
  std::string message;
  /// The location in whichever buffer the compiler reported, which may be invalid.
  swift::SourceLoc location;
};

/// Errors and warnings of the type check, which an editor can show without a build.
///
/// Notes and remarks are left out because they explain other diagnostics.
class DiagnosticCollector : public swift::DiagnosticConsumer {
public:
  /// The collected diagnostics in reporting order, at most maximumDiagnostics.
  std::vector<LocatedDiagnostic> diagnostics;

  /// Records an error or a warning until the limit is reached.
  void handleDiagnostic(swift::SourceManager &, const swift::DiagnosticInfo &info) override {
    const bool error = info.Kind == swift::DiagnosticKind::Error;
    if ((!error && info.Kind != swift::DiagnosticKind::Warning) ||
        diagnostics.size() >= maximumDiagnostics) {
      return;
    }
    std::string text;
    llvm::raw_string_ostream stream(text);
    swift::DiagnosticEngine::formatDiagnosticText(stream, info.FormatString, info.FormatArgs);
    stream.flush();
    diagnostics.push_back({error, std::move(text), info.Loc});
  }
};

/// Whether a reference's text starts like an identifier, which excludes operators and brackets.
///
/// Editors color names, and SourceKit also reports operator functions and subscript brackets.
bool isNameStart(unsigned char byte) {
  return byte == '_' || byte == '$' || byte == '`' || byte >= 0x80 ||
         (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z');
}

/// One named reference in the primary file.
struct Reference {
  /// The UTF-8 byte offset of the name in the primary file.
  unsigned offset;
  /// The name's length in bytes.
  unsigned length;
  /// The kind of the referenced declaration.
  swift::ide::CodeCompletionDeclKind kind;
  /// The module that declares the referenced declaration.
  swift::ModuleDecl *module;
};

/// Collects the named references of a type-checked file, following SourceKit's semantic annotator.
///
/// Implicit references, `self`, unavailable declarations, and the `nil` literal that a pattern
/// turns into `Optional.none` are left out, as SourceKit does. A reference to an initializer
/// through its type's name reports the type.
class ReferenceCollector : public swift::SourceEntityWalker {
public:
  /// Creates a collector for the references inside one buffer.
  ///
  /// \param sourceManager The compiler instance's source manager.
  /// \param buffer The primary file's buffer. References in macro expansions are left out.
  ReferenceCollector(swift::SourceManager &sourceManager, unsigned buffer)
      : sourceManager(sourceManager), buffer(buffer) {}

  /// The references in walking order.
  std::vector<Reference> references;

  /// Records a reference to a declaration.
  bool visitDeclReference(swift::ValueDecl *decl, swift::SourceRange range,
                          swift::TypeDecl *constructorType, swift::ExtensionDecl *, swift::Type,
                          swift::ReferenceMetaData data) override {
    if (data.isImplicit || decl->isUnavailable()) {
      return true;
    }
    auto &context = decl->getASTContext();
    if (llvm::isa<swift::VarDecl>(decl) && decl->hasName() && decl->getName() == context.Id_self) {
      return true;
    }
    const auto characters = swift::Lexer::getCharSourceRangeFromSourceRange(sourceManager, range);
    if (!characters.isValid() ||
        sourceManager.findBufferContainingLoc(characters.getStart()) != buffer) {
      return true;
    }
    const llvm::StringRef text = sourceManager.extractText(characters, buffer);
    if (text.empty() || !isNameStart(static_cast<unsigned char>(text.front())) ||
        (decl == context.getOptionalNoneDecl() && text == "nil")) {
      return true;
    }
    if (constructorType) {
      decl = constructorType;
    }
    const auto kind = swift::ide::ContextFreeCodeCompletionResult::getCodeCompletionDeclKind(decl);
    references.push_back({sourceManager.getLocOffsetInBuffer(characters.getStart(), buffer),
                          characters.getByteLength(), kind, decl->getModuleContext()});
    return true;
  }

private:
  /// The source manager that resolves reference locations.
  swift::SourceManager &sourceManager;
  /// The primary file's buffer.
  unsigned buffer;
};

/// Whether the request's cancellation flag is set.
///
/// \param cancellation The flag that the bridge shares with swift_compiler_cancel_completion.
bool cancelled(const std::shared_ptr<std::atomic<bool>> &cancellation) {
  return cancellation && cancellation->load(std::memory_order_relaxed);
}

/// The document of a cancelled annotation.
swift_toolchain::BackendResult cancelledResult() {
  return {SWIFT_COMPILER_COMPLETION_CANCELLED, true,
          swift_toolchain::statusDocument("cancelled", "The annotation request was cancelled.")};
}

} // namespace

swift_toolchain::BackendResult
swift_toolchain::runAnnotation(const swift_toolchain::AnnotationRequest &request,
                               std::shared_ptr<std::atomic<bool>> cancellation) {
  const auto start = std::chrono::steady_clock::now();
  prepareNativeCompiler();
  // The compiler instance borrows the buffer, so it is declared first and destroyed last.
  std::unique_ptr<llvm::MemoryBuffer> buffer;
  swift::CompilerInvocation invocation;
  llvm::SmallString<256> target;
  const std::string invalid = prepareSemanticInvocation(
      "annotation", request.count, request.arguments, request.path,
      llvm::StringRef(request.source, request.sourceLength), invocation, target, buffer);
  if (!invalid.empty()) {
    return {1, true, statusDocument("failure", invalid)};
  }
  if (cancelled(cancellation)) {
    return cancelledResult();
  }

  DiagnosticCollector collector;
  swift::CompilerInstance instance;
  instance.addDiagnosticConsumer(&collector);
  instance.getSourceMgr().setFileSystem(llvm::vfs::getRealFileSystem());
  std::string setupError;
  if (instance.setup(invocation, setupError)) {
    return {1, true, statusDocument("failure", "The compiler could not start. " + setupError)};
  }
  auto &context = instance.getASTContext();
  context.getPluginLoader().setRegistry(semanticPluginRegistry().get());
  context.CancellationFlag = cancellation;
  swift::registerIDERequestFunctions(context.evaluator);
  const double setupMilliseconds = millisecondsSince(start);

  const auto typeCheckStart = std::chrono::steady_clock::now();
  instance.performSema();
  const double typeCheckMilliseconds = millisecondsSince(typeCheckStart);
  // A cancelled type check leaves expressions unsolved, so its references are incomplete.
  if (cancelled(cancellation)) {
    return cancelledResult();
  }
  const auto primaryFiles = instance.getPrimarySourceFiles();
  if (primaryFiles.size() != 1) {
    return {1, true, statusDocument("failure", "The primary file was not type-checked.")};
  }
  swift::SourceFile &primary = *primaryFiles.front();
  const unsigned bufferID = primary.getBufferID();

  const auto walkStart = std::chrono::steady_clock::now();
  ReferenceCollector references(instance.getSourceMgr(), bufferID);
  references.walk(primary);
  const double walkMilliseconds = millisecondsSince(walkStart);

  auto &sourceManager = instance.getSourceMgr();
  swift::ModuleDecl *mainModule = instance.getMainModule();
  std::string output;
  llvm::raw_string_ostream stream(output);
  llvm::json::OStream json(stream);
  json.object([&] {
    json.attribute("schema", 1);
    json.attribute("status", "success");
    json.attribute("module", mainModule->getName().str());
    json.attributeArray("references", [&] {
      for (const Reference &reference : references.references) {
        json.object([&] {
          json.attribute("offset", static_cast<int64_t>(reference.offset));
          json.attribute("length", static_cast<int64_t>(reference.length));
          json.attribute("kind", declarationKindName(reference.kind));
          json.attribute("module", reference.module->getName().str());
          json.attribute("project", reference.module == mainModule);
        });
      }
    });
    json.attributeArray("diagnostics", [&] {
      for (const LocatedDiagnostic &diagnostic : collector.diagnostics) {
        json.object([&] {
          json.attribute("severity", diagnostic.error ? "error" : "warning");
          json.attribute("message", diagnostic.message);
          if (diagnostic.location.isValid() &&
              sourceManager.findBufferContainingLoc(diagnostic.location) == bufferID) {
            json.attribute("offset", static_cast<int64_t>(sourceManager.getLocOffsetInBuffer(
                                         diagnostic.location, bufferID)));
          }
        });
      }
    });
    json.attributeObject("timingsMs", [&] {
      json.attribute("setup", setupMilliseconds);
      json.attribute("typeCheck", typeCheckMilliseconds);
      json.attribute("walk", walkMilliseconds);
    });
  });
  stream.flush();
  return {0, true, std::move(output)};
}
