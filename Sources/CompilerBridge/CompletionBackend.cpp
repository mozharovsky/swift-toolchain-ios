#include "CompilerBackend.h"
#include "SwiftCompilerBridge.h"
#include "swift/AST/DiagnosticConsumer.h"
#include "swift/AST/DiagnosticEngine.h"
#include "swift/AST/PluginRegistry.h"
#include "swift/Basic/SourceManager.h"
#include "swift/Frontend/Frontend.h"
#include "swift/Frontend/PrintingDiagnosticConsumer.h"
#include "swift/IDE/CodeCompletionCache.h"
#include "swift/IDE/CodeCompletionContext.h"
#include "swift/IDE/CodeCompletionResult.h"
#include "swift/IDE/CodeCompletionResultPrinter.h"
#include "swift/IDE/FuzzyStringMatcher.h"
#include "swift/IDETool/IDEInspectionInstance.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/VirtualFileSystem.h"
#include "llvm/Support/raw_ostream.h"
#include <algorithm>
#include <chrono>
#include <memory>
#include <optional>
#include <string>
#include <vector>

using swift::ide::CodeCompletionDeclKind;
using swift::ide::CodeCompletionFlairBit;
using swift::ide::CodeCompletionResult;
using swift::ide::CodeCompletionResultKind;
using swift::ide::CodeCompletionResultTypeRelation;
using swift::ide::CompletionKind;
using swift::ide::SemanticContextKind;

namespace {

/// LLVM resolves the containing image from this address when it needs an executable path.
char completionAnchor;

/// Macro libraries stay loaded across cache resets because the loader keeps them mapped.
std::shared_ptr<swift::PluginRegistry> &pluginRegistry() {
  static auto *registry =
      new std::shared_ptr<swift::PluginRegistry>(std::make_shared<swift::PluginRegistry>());
  return *registry;
}

/// The module result cache and the inspection instance, which SourceKit keeps once per service.
struct CompletionState {
  /// Creates the state for a cache directory.
  ///
  /// \param directory The directory of the module results that persist across launches, or empty
  /// for results in memory only.
  explicit CompletionState(const std::string &directory) : cacheDirectory(directory) {
    if (!directory.empty()) {
      diskCache.emplace(directory);
    }
    cache.emplace(diskCache ? &*diskCache : nullptr);
  }

  /// The directory that the on-disk cache uses, or empty for a cache in memory.
  std::string cacheDirectory;
  /// The module results that persist across launches, when a directory was given.
  std::optional<swift::ide::OnDiskCodeCompletionCache> diskCache;
  /// The context-free results of each imported module, which later requests reuse.
  std::optional<swift::ide::CodeCompletionCache> cache;
  /// The cached compiler instance used for fast completion inside function bodies.
  swift::ide::IDEInspectionInstance instance{pluginRegistry()};
};

/// The completion context, which the bridge's operation lock guards.
CompletionState *completionState = nullptr;

/// Error diagnostics explain an empty result, so the result keeps the first of them.
class ErrorCollector : public swift::DiagnosticConsumer {
public:
  /// Formatted error messages without source locations.
  std::vector<std::string> messages;

  /// Records the first errors and ignores warnings, notes, and remarks.
  void handleDiagnostic(swift::SourceManager &, const swift::DiagnosticInfo &info) override {
    if (info.Kind != swift::DiagnosticKind::Error || messages.size() >= 12) {
      return;
    }
    std::string text;
    llvm::raw_string_ostream stream(text);
    swift::DiagnosticEngine::formatDiagnosticText(stream, info.FormatString, info.FormatArgs);
    messages.push_back(std::move(text));
  }
};

/// Milliseconds since the given start, measured on the monotonic clock.
double millisecondsSince(std::chrono::steady_clock::time_point start) {
  return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start)
      .count();
}

/// A completion document for a request that the compiler rejected before completion ran.
///
/// \param error The reason, which the JSON writer escapes.
std::string failureDocument(const std::string &error) {
  std::string text;
  llvm::raw_string_ostream stream(text);
  llvm::json::OStream json(stream);
  json.object([&] {
    json.attribute("schema", 1);
    json.attribute("status", "failure");
    json.attribute("error", error);
  });
  stream.flush();
  return text;
}

/// Identifier bytes include UTF-8 sequences because Swift accepts Unicode identifiers.
bool isIdentifierByte(unsigned char byte) {
  return byte == '_' || byte >= 0x80 || (byte >= '0' && byte <= '9') ||
         (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z');
}

/// Stable names for the declaration kinds that an editor maps to icons.
const char *declKindName(CodeCompletionDeclKind kind) {
  switch (kind) {
  case CodeCompletionDeclKind::Module:
    return "module";
  case CodeCompletionDeclKind::Class:
    return "class";
  case CodeCompletionDeclKind::Actor:
    return "actor";
  case CodeCompletionDeclKind::Struct:
    return "struct";
  case CodeCompletionDeclKind::Enum:
    return "enum";
  case CodeCompletionDeclKind::EnumElement:
    return "enumElement";
  case CodeCompletionDeclKind::Protocol:
    return "protocol";
  case CodeCompletionDeclKind::AssociatedType:
    return "associatedType";
  case CodeCompletionDeclKind::TypeAlias:
    return "typeAlias";
  case CodeCompletionDeclKind::GenericTypeParam:
    return "genericTypeParam";
  case CodeCompletionDeclKind::Constructor:
    return "initializer";
  case CodeCompletionDeclKind::Destructor:
    return "deinitializer";
  case CodeCompletionDeclKind::Subscript:
    return "subscript";
  case CodeCompletionDeclKind::StaticMethod:
    return "staticMethod";
  case CodeCompletionDeclKind::InstanceMethod:
    return "instanceMethod";
  case CodeCompletionDeclKind::PrefixOperatorFunction:
  case CodeCompletionDeclKind::PostfixOperatorFunction:
  case CodeCompletionDeclKind::InfixOperatorFunction:
    return "operator";
  case CodeCompletionDeclKind::FreeFunction:
    return "function";
  case CodeCompletionDeclKind::StaticVar:
    return "staticProperty";
  case CodeCompletionDeclKind::InstanceVar:
    return "instanceProperty";
  case CodeCompletionDeclKind::LocalVar:
    return "localVariable";
  case CodeCompletionDeclKind::GlobalVar:
    return "globalVariable";
  case CodeCompletionDeclKind::PrecedenceGroup:
    return "precedenceGroup";
  case CodeCompletionDeclKind::Macro:
    return "macro";
  }
  return "declaration";
}

/// The result kind, refined by its declaration kind for declarations.
std::string resultKindName(const CodeCompletionResult &result) {
  switch (result.getKind()) {
  case CodeCompletionResultKind::Declaration:
    return declKindName(result.getAssociatedDeclKind());
  case CodeCompletionResultKind::Keyword:
    return "keyword";
  case CodeCompletionResultKind::Pattern:
    return "pattern";
  case CodeCompletionResultKind::Literal:
    return "literal";
  case CodeCompletionResultKind::BuiltinOperator:
    return "operator";
  }
  return "unknown";
}

/// The relation names follow SourceKit's typerelation values.
const char *typeRelationName(CodeCompletionResultTypeRelation relation) {
  switch (relation) {
  case CodeCompletionResultTypeRelation::NotApplicable:
    return "notApplicable";
  case CodeCompletionResultTypeRelation::Unknown:
    return "unknown";
  case CodeCompletionResultTypeRelation::Unrelated:
    return "unrelated";
  case CodeCompletionResultTypeRelation::Invalid:
    return "invalid";
  case CodeCompletionResultTypeRelation::Convertible:
    return "convertible";
  }
  return "unknown";
}

/// The context names follow SourceKit's semantic context values.
const char *semanticContextName(SemanticContextKind kind) {
  switch (kind) {
  case SemanticContextKind::None:
    return "none";
  case SemanticContextKind::Local:
    return "local";
  case SemanticContextKind::CurrentNominal:
    return "currentNominal";
  case SemanticContextKind::Super:
    return "super";
  case SemanticContextKind::OutsideNominal:
    return "outsideNominal";
  case SemanticContextKind::CurrentModule:
    return "currentModule";
  case SemanticContextKind::OtherModule:
    return "otherModule";
  }
  return "none";
}

/// The completion kinds an editor can use to decide how to present a list.
const char *completionKindName(CompletionKind kind) {
  switch (kind) {
  case CompletionKind::DotExpr:
    return "dotExpr";
  case CompletionKind::UnresolvedMember:
    return "unresolvedMember";
  case CompletionKind::StmtOrExpr:
    return "stmtOrExpr";
  case CompletionKind::PostfixExprBeginning:
    return "postfixExprBeginning";
  case CompletionKind::PostfixExpr:
    return "postfixExpr";
  case CompletionKind::CallArg:
    return "callArg";
  case CompletionKind::TypeBeginning:
  case CompletionKind::TypeSimpleBeginning:
  case CompletionKind::TypeSimpleOrComposition:
  case CompletionKind::TypeDeclResultBeginning:
  case CompletionKind::TypePossibleFunctionParamBeginning:
    return "type";
  case CompletionKind::NominalMemberBeginning:
    return "nominalMemberBeginning";
  case CompletionKind::AttributeBegin:
    return "attribute";
  case CompletionKind::None:
    return "none";
  default:
    return "other";
  }
}

/// SourceKit's ordering groups, from least to most preferred.
enum class Bucket {
  NotRecommended,
  Normal,
  Literal,
  NormalTypeMatch,
  LiteralTypeMatch,
  HighPriorityKeyword,
  Operator,
  ExpressionSpecific,
  ExactMatch,
};

/// One candidate with the values the ranking compares.
struct RankedResult {
  /// The completion owned by the compiler instance's result sink.
  CodeCompletionResult *result;
  /// The filter name used for matching and name ordering.
  llvm::StringRef name;
  /// The normalized fuzzy-match score in the range from zero to one.
  double matchScore;
  /// The weighted match and semantic context score.
  double score;
  /// Whether the filter equals the name ignoring case.
  bool exactMatch;
};

/// Keywords that SourceKit promotes at statement starts.
bool isHighPriorityKeyword(swift::ide::CodeCompletionKeywordKind kind) {
  using swift::ide::CodeCompletionKeywordKind;
  switch (kind) {
  case CodeCompletionKeywordKind::kw_let:
  case CodeCompletionKeywordKind::kw_var:
  case CodeCompletionKeywordKind::kw_if:
  case CodeCompletionKeywordKind::kw_for:
  case CodeCompletionKeywordKind::kw_while:
  case CodeCompletionKeywordKind::kw_return:
  case CodeCompletionKeywordKind::kw_func:
    return true;
  default:
    return false;
  }
}

/// A simplified port of SourceKit's result buckets without popularity data.
Bucket bucketFor(const RankedResult &ranked, bool skipMetaGroups) {
  const CodeCompletionResult &result = *ranked.result;
  if (ranked.exactMatch && !skipMetaGroups) {
    return Bucket::ExactMatch;
  }
  if (result.isNotRecommended() && !skipMetaGroups) {
    return Bucket::NotRecommended;
  }
  if (!skipMetaGroups) {
    auto flair = result.getFlair();
    if (flair.contains(CodeCompletionFlairBit::ExpressionSpecific) ||
        flair.contains(CodeCompletionFlairBit::SuperChain) ||
        flair.contains(CodeCompletionFlairBit::ArgumentLabels)) {
      return Bucket::ExpressionSpecific;
    }
  }
  if (result.isOperator()) {
    return Bucket::Operator;
  }
  const bool typeMatch =
      result.getExpectedTypeRelation() >= CodeCompletionResultTypeRelation::Convertible;
  switch (result.getKind()) {
  case CodeCompletionResultKind::Literal:
    return typeMatch ? Bucket::LiteralTypeMatch : Bucket::Literal;
  case CodeCompletionResultKind::Keyword:
    return isHighPriorityKeyword(result.getKeywordKind()) ? Bucket::HighPriorityKeyword
                                                          : Bucket::Normal;
  case CodeCompletionResultKind::Pattern:
  case CodeCompletionResultKind::Declaration:
    if (typeMatch) {
      return Bucket::NormalTypeMatch;
    }
    if (result.getExpectedTypeRelation() == CodeCompletionResultTypeRelation::Invalid &&
        !skipMetaGroups) {
      return Bucket::NotRecommended;
    }
    return Bucket::Normal;
  case CodeCompletionResultKind::BuiltinOperator:
    return Bucket::Operator;
  }
  return Bucket::Normal;
}

/// SourceKit's semantic context score without import-depth data.
double semanticContextScore(const CodeCompletionResult &result) {
  double order = 8.0;
  switch (result.getSemanticContext()) {
  case SemanticContextKind::Local:
    order = 1;
    break;
  case SemanticContextKind::CurrentNominal:
    order = 2;
    break;
  case SemanticContextKind::Super:
    order = 3;
    break;
  case SemanticContextKind::OutsideNominal:
    order = 4;
    break;
  case SemanticContextKind::CurrentModule:
    order = 5;
    break;
  case SemanticContextKind::OtherModule:
    order = 6.5;
    break;
  case SemanticContextKind::None:
    order = result.getKind() == CodeCompletionResultKind::Keyword ? 5.5 : 8.0;
    break;
  }
  return (8.0 - order) / 8.0;
}

/// Prints one completion string through a caller-provided printer.
template <typename Printer> std::string printed(const CodeCompletionResult &result, Printer print) {
  std::string text;
  llvm::raw_string_ostream stream(text);
  print(result, stream);
  return text;
}

/// The options shared by every request, matching an editor's completion list.
void configureContext(swift::ide::CodeCompletionContext &context) {
  context.setAnnotateResult(false);
  context.setIncludeObjectLiterals(false);
  context.setAddInitsToTopLevel(true);
  context.setAddCallWithNoDefaultArgs(true);
}

/// Filters, ranks, and serializes the results while the compiler instance keeps them alive.
///
/// An unfiltered list leaves out results that are not recommended or have an invalid type, as
/// SourceKit does. A filtered list keeps them and ranks them last.
void writeResults(llvm::json::OStream &json, std::vector<CodeCompletionResult *> &results,
                  llvm::StringRef filter, uint32_t maximumResults, size_t &matched,
                  size_t &hidden) {
  std::vector<RankedResult> ranked;
  ranked.reserve(results.size());
  swift::ide::FuzzyStringMatcher matcher(filter);
  matcher.normalize = true;
  for (CodeCompletionResult *result : results) {
    llvm::StringRef name = result->getFilterName();
    RankedResult candidate{result, name, 0.0, 0.0, false};
    if (filter.empty()) {
      if (result->isNotRecommended() ||
          result->getExpectedTypeRelation() == CodeCompletionResultTypeRelation::Invalid) {
        ++hidden;
        continue;
      }
    } else {
      bool match = filter.size() >= 2 ? matcher.matchesCandidate(name)
                                      : name.starts_with_insensitive(filter);
      if (!match) {
        continue;
      }
      candidate.matchScore = matcher.scoreCandidate(name);
      candidate.exactMatch = name.equals_insensitive(filter);
    }
    candidate.score = candidate.matchScore * 13 + semanticContextScore(*result) * 7;
    ranked.push_back(candidate);
  }
  matched = ranked.size();
  // SourceKit moves the best non-literal results above untyped literals, so filtering demotes them.
  const bool filtering = !filter.empty();
  auto bucket = [filtering](const RankedResult &result, bool skip) {
    Bucket value = bucketFor(result, skip);
    return filtering && value == Bucket::Literal ? Bucket::Normal : value;
  };
  std::stable_sort(ranked.begin(), ranked.end(), [&](const RankedResult &a, const RankedResult &b) {
    for (bool skip : {false, true}) {
      Bucket left = bucket(a, skip);
      Bucket right = bucket(b, skip);
      if (left != right) {
        return left > right;
      }
    }
    if (a.score != b.score) {
      return a.score > b.score;
    }
    if (int order = a.name.compare_insensitive(b.name)) {
      return order < 0;
    }
    return a.name.size() < b.name.size();
  });
  if (ranked.size() > maximumResults) {
    ranked.resize(maximumResults);
  }
  json.attributeArray("items", [&] {
    for (const RankedResult &candidate : ranked) {
      const CodeCompletionResult &result = *candidate.result;
      json.object([&] {
        json.attribute("name", candidate.name);
        json.attribute("description",
                       printed(result, [](const CodeCompletionResult &r, llvm::raw_ostream &os) {
                         swift::ide::printCodeCompletionResultDescription(r, os, false);
                       }));
        json.attribute("kind", resultKindName(result));
        json.attribute("type", printed(result, swift::ide::printCodeCompletionResultTypeName));
        json.attribute("sourceText",
                       printed(result, swift::ide::printCodeCompletionResultSourceText));
        json.attribute("typeRelation", typeRelationName(result.getExpectedTypeRelation()));
        json.attribute("context", semanticContextName(result.getSemanticContext()));
        json.attribute("module", llvm::StringRef(result.getModuleName()));
        json.attribute("brief", llvm::StringRef(result.getBriefDocComment()));
        json.attribute("notRecommended", result.isNotRecommended());
      });
    }
  });
}

} // namespace

void swift_toolchain::resetCompletion() {
  delete completionState;
  completionState = nullptr;
}

swift_toolchain::BackendResult
swift_toolchain::runCompletion(const swift_toolchain::CompletionRequest &request,
                               std::shared_ptr<std::atomic<bool>> cancellation) {
  const auto start = std::chrono::steady_clock::now();
  prepareNativeCompiler();
  const std::string cacheDirectory = request.cacheDirectory ? request.cacheDirectory : "";
  if (completionState != nullptr && completionState->cacheDirectory != cacheDirectory) {
    resetCompletion();
  }
  if (completionState == nullptr) {
    completionState = new CompletionState(cacheDirectory);
  }

  swift::SourceManager sourceManager;
  swift::DiagnosticEngine diagnostics(sourceManager);
  std::string setupText;
  llvm::raw_string_ostream setupStream(setupText);
  swift::PrintingDiagnosticConsumer setupPrinter(setupStream);
  diagnostics.addConsumer(setupPrinter);

  swift::CompilerInvocation invocation;
  const std::string executable =
      llvm::sys::fs::getMainExecutable("swift-compiler", &completionAnchor);
  if (invocation.parseArgs({request.arguments, static_cast<size_t>(request.count)}, diagnostics,
                           nullptr, {}, executable)) {
    setupStream.flush();
    return {1, true, failureDocument("The completion arguments are invalid. " + setupText)};
  }

  auto fileSystem = llvm::vfs::getRealFileSystem();
  llvm::SmallString<256> target;
  if (fileSystem->getRealPath(request.path, target)) {
    target = request.path;
  }
  auto &inputs = invocation.getFrontendOptions().InputsAndOutputs;
  swift::FrontendInputsAndOutputs replacement;
  bool foundTarget = false;
  for (const swift::InputFile &input : inputs.getAllInputs()) {
    llvm::SmallString<256> name;
    if (fileSystem->getRealPath(input.getFileName(), name)) {
      name = input.getFileName();
    }
    const bool primary = name == target;
    foundTarget = foundTarget || primary;
    replacement.addInput(swift::InputFile(name.str(), primary, input.getBuffer()));
  }
  if (!foundTarget) {
    return {1, true, failureDocument("The completion path is not one of the frontend inputs.")};
  }
  replacement.setShouldRecoverMissingInputs();
  inputs = replacement;
  invocation.getFrontendOptions().RequestedAction = swift::FrontendOptions::ActionType::Typecheck;
  invocation.getFrontendOptions().IndexStorePath.clear();
  invocation.getFrontendOptions().LLVMArgs.clear();
  invocation.getLangOptions().AttachCommentsToDecls = true;

  size_t identifierStart = request.offset;
  while (identifierStart > 0 &&
         isIdentifierByte(static_cast<unsigned char>(request.source[identifierStart - 1]))) {
    --identifierStart;
  }
  const llvm::StringRef filter(request.source + identifierStart, request.offset - identifierStart);
  auto original = llvm::MemoryBuffer::getMemBuffer(
      llvm::StringRef(request.source, request.sourceLength), target, false);
  unsigned completionOffset = static_cast<unsigned>(identifierStart);
  auto buffer =
      swift::ide::makeCodeCompletionMemoryBuffer(original.get(), completionOffset, target);

  // The argument hash decides context reuse, so the primary path joins the caller's arguments.
  std::vector<const char *> identity(request.arguments, request.arguments + request.count);
  identity.push_back(target.c_str());
  const double setupMilliseconds = millisecondsSince(start);

  ErrorCollector errors;
  swift::ide::CodeCompletionContext context(*completionState->cache);
  configureContext(context);
  std::string output;
  llvm::raw_string_ostream outputStream(output);
  int exitCode = 0;
  const auto completionStart = std::chrono::steady_clock::now();
  completionState->instance.codeComplete(
      invocation, identity, fileSystem, buffer.get(), completionOffset, &errors, context,
      cancellation, [&](swift::ide::CancellableResult<swift::ide::CodeCompleteResult> result) {
        const double completionMilliseconds = millisecondsSince(completionStart);
        llvm::json::OStream json(outputStream);
        json.object([&] {
          json.attribute("schema", 1);
          switch (result.getKind()) {
          case swift::ide::CancellableResultKind::Success: {
            const auto organizeStart = std::chrono::steady_clock::now();
            auto &value = result.getResult();
            auto *completionContext = value.Info.completionContext;
            size_t matched = 0;
            size_t hidden = 0;
            json.attribute("status", "success");
            json.attribute("reusedContext", completionContext->ReusingASTContext);
            json.attribute("completionKind",
                           completionKindName(completionContext->CodeCompletionKind));
            json.attribute("filterText", filter);
            json.attribute("replacementOffset", static_cast<int64_t>(identifierStart));
            json.attribute("replacementLength",
                           static_cast<int64_t>(request.offset - identifierStart));
            json.attribute("totalResults", static_cast<int64_t>(value.ResultSink.Results.size()));
            writeResults(json, value.ResultSink.Results, filter, request.maximumResults, matched,
                         hidden);
            json.attribute("matchedResults", static_cast<int64_t>(matched));
            json.attribute("hiddenResults", static_cast<int64_t>(hidden));
            json.attributeObject("timingsMs", [&] {
              json.attribute("setup", setupMilliseconds);
              json.attribute("completion", completionMilliseconds);
              json.attribute("organize", millisecondsSince(organizeStart));
            });
            break;
          }
          case swift::ide::CancellableResultKind::Failure:
            exitCode = 1;
            json.attribute("status", "failure");
            json.attribute("error", result.getError());
            break;
          case swift::ide::CancellableResultKind::Cancelled:
            exitCode = SWIFT_COMPILER_COMPLETION_CANCELLED;
            json.attribute("status", "cancelled");
            json.attribute("error", "The completion request was cancelled.");
            break;
          }
          json.attributeArray("diagnostics", [&] {
            for (const std::string &message : errors.messages) {
              json.value(message);
            }
          });
        });
      });
  outputStream.flush();
  return {exitCode, true, std::move(output)};
}
