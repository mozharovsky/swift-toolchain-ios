import ArgumentParser
import Foundation
import ToolchainSupport

/// Read-only configuration checks used by contributors before expensive compiler preparation.
struct VerifyCommand: ParsableCommand {
    /// The command name remains independent of the Swift implementation type.
    static let configuration = CommandConfiguration(commandName: "verify")

    /// A relative default keeps a clean checkout usable without machine-specific paths.
    @Option(help: "Path to the toolchain input lock file.")
    var configurationFile = "Toolchain.lock.json"

    /// A successful result describes validated metadata and does not claim a compiler build.
    mutating func run() throws {
        let value = try ToolchainConfiguration.load(from: URL(fileURLWithPath: configurationFile))
        print("Validated \(value.sources.count) pinned sources and SDK \(value.sdk.version).")
        print("Compiler host \(value.compilerHost). Program target \(value.programTarget).")
    }
}
