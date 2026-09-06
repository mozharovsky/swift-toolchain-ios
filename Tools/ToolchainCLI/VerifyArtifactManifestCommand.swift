import ArgumentParser
import Foundation
import ToolchainSupport

/// Archive-record validation that remains usable before native SDK files are available.
struct VerifyArtifactManifestCommand: ParsableCommand {
    /// The command names metadata explicitly because byte validation is a separate operation.
    static let configuration = CommandConfiguration(commandName: "verify-artifact-manifest")

    /// The caller selects a local manifest without granting a runtime download mechanism.
    @Argument(help: "Path to the generated artifact manifest.")
    var manifest: String

    /// Successful metadata checks do not claim archive integrity or device execution.
    mutating func run() throws {
        let value = try ArtifactManifest.load(from: URL(fileURLWithPath: manifest))
        print("Validated \(value.artifacts.count) archive records for release \(value.version).")
        print("Run VerifyArtifacts.cmake to inspect archive bytes and framework contents.")
    }
}
