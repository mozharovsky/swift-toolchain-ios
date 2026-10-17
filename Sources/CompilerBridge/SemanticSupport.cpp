#include "SemanticSupport.h"
#include "swift/AST/DiagnosticEngine.h"
#include "swift/Basic/SourceManager.h"
#include "swift/Frontend/PrintingDiagnosticConsumer.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/raw_ostream.h"

using swift::ide::CodeCompletionDeclKind;

namespace {

/// LLVM resolves the containing image from this address when it needs an executable path.
char semanticAnchor;

} // namespace

std::shared_ptr<swift::PluginRegistry> &swift_toolchain::semanticPluginRegistry() {
  static auto *registry =
      new std::shared_ptr<swift::PluginRegistry>(std::make_shared<swift::PluginRegistry>());
  return *registry;
}

double swift_toolchain::millisecondsSince(std::chrono::steady_clock::time_point start) {
  return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start)
      .count();
}

std::string swift_toolchain::statusDocument(llvm::StringRef status, llvm::StringRef error) {
  std::string text;
  llvm::raw_string_ostream stream(text);
  llvm::json::OStream json(stream);
  json.object([&] {
    json.attribute("schema", 1);
    json.attribute("status", status);
    json.attribute("error", error);
  });
  stream.flush();
  return text;
}

const char *swift_toolchain::declarationKindName(CodeCompletionDeclKind kind) {
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

std::string swift_toolchain::prepareSemanticInvocation(
    llvm::StringRef operation, int32_t count, const char *const *arguments, const char *path,
    std::optional<llvm::StringRef> primarySource, swift::CompilerInvocation &invocation,
    llvm::SmallString<256> &target, std::unique_ptr<llvm::MemoryBuffer> &primaryBuffer) {
  swift::SourceManager sourceManager;
  swift::DiagnosticEngine diagnostics(sourceManager);
  std::string setupText;
  llvm::raw_string_ostream setupStream(setupText);
  swift::PrintingDiagnosticConsumer setupPrinter(setupStream);
  diagnostics.addConsumer(setupPrinter);
  const std::string executable =
      llvm::sys::fs::getMainExecutable("swift-compiler", &semanticAnchor);
  if (invocation.parseArgs({arguments, static_cast<size_t>(count)}, diagnostics, nullptr, {},
                           executable)) {
    setupStream.flush();
    return "The " + operation.str() + " arguments are invalid. " + setupText;
  }

  auto fileSystem = llvm::vfs::getRealFileSystem();
  if (fileSystem->getRealPath(path, target)) {
    target = path;
  }
  // The frontend finds a main.swift input by its buffer identifier, so the copy carries the same
  // real path as the input that it replaces.
  if (primarySource) {
    primaryBuffer = llvm::MemoryBuffer::getMemBufferCopy(*primarySource, target);
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
    replacement.addInput(swift::InputFile(
        name.str(), primary, primary && primaryBuffer ? primaryBuffer.get() : input.getBuffer()));
  }
  if (!foundTarget) {
    return "The " + operation.str() + " path is not one of the frontend inputs.";
  }
  replacement.setShouldRecoverMissingInputs();
  inputs = replacement;
  invocation.getFrontendOptions().RequestedAction = swift::FrontendOptions::ActionType::Typecheck;
  invocation.getFrontendOptions().IndexStorePath.clear();
  invocation.getFrontendOptions().LLVMArgs.clear();
  return {};
}
