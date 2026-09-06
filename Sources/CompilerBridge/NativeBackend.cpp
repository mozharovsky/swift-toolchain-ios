#include "CompilerBackend.h"
#include "lld/Common/Driver.h"
#include "swift/AST/DiagnosticEngine.h"
#include "swift/Frontend/Frontend.h"
#include "swift/Frontend/PrintingDiagnosticConsumer.h"
#include "swift/FrontendTool/FrontendTool.h"
#include "llvm/Support/raw_ostream.h"
#include <utility>

LLD_HAS_DRIVER(wasm)

/// The build links the upstream object-reader implementation without invoking a subprocess.
int autolink_extract_main(llvm::ArrayRef<const char *> arguments, const char *programName,
                          void *mainAddress);

namespace {

/// LLVM locates the containing image without requiring an executable on the filesystem.
char imageAnchor;

/// The frontend observer keeps the diagnostic consumer alive throughout compilation.
class DiagnosticCapture : public swift::FrontendObserver {
  /// The diagnostic engine borrows this consumer after frontend setup completes.
  swift::PrintingDiagnosticConsumer consumer;

public:
  /// The caller owns the destination stream until performFrontend returns.
  explicit DiagnosticCapture(llvm::raw_ostream &stream) : consumer(stream) {}

  /// Setup diagnostics emitted before this callback can still reach standard error.
  void configuredCompiler(swift::CompilerInstance &instance) override {
    instance.getDiags().addConsumer(consumer);
  }
};

} // namespace

swift_toolchain::BackendResult swift_toolchain::runFrontend(int32_t count,
                                                            const char *const *arguments) {
  std::string message;
  llvm::raw_string_ostream stream(message);
  DiagnosticCapture capture(stream);
  const int result = swift::performFrontend({arguments, static_cast<size_t>(count)},
                                            "swift-compiler", &imageAnchor, &capture);
  return {result, true, std::move(message)};
}

swift_toolchain::BackendResult swift_toolchain::runAutolink(int32_t count,
                                                            const char *const *arguments) {
  const int result = autolink_extract_main({arguments, static_cast<size_t>(count)},
                                           "swift-autolink-extract", &imageAnchor);
  return {result, true, result == 0 ? "" : "Autolink extraction failed. Inspect standard error."};
}

swift_toolchain::BackendResult swift_toolchain::runLinker(int32_t count,
                                                          const char *const *arguments) {
  std::string message;
  llvm::raw_string_ostream stream(message);
  const lld::DriverDef drivers[] = {{lld::Wasm, &lld::wasm::link}};
  const auto result =
      lld::lldMain({arguments, static_cast<size_t>(count)}, stream, stream, drivers);
  return {result.retCode, result.canRunAgain, std::move(message)};
}
