import ArgumentParser
import Foundation
import ToolchainSupport

/// Git inventory adapter that avoids scanning downloaded upstream checkouts.
struct CheckRepositoryCommand: ParsableCommand {
    /// Scripts provide a NUL-separated inventory through standard input.
    static let configuration = CommandConfiguration(commandName: "check-repository")

    /// Tests and callers can select a checkout without changing the process directory.
    @Option(help: "Repository root for file inventory validation.")
    var root = "."

    /// The source inventory includes untracked authored files during local preparation.
    mutating func run() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let source = String(data: data, encoding: .utf8) else {
            throw ValidationError("Provide Git's UTF-8 file inventory separated by NUL bytes.")
        }
        let paths = source.split(separator: "\0").map(String.init)
        guard !paths.isEmpty else { throw ValidationError("The repository inventory is empty.") }
        try RepositoryPolicy.validate(paths: paths, root: URL(fileURLWithPath: root))
        print("Validated \(paths.count) source paths and the agent-instruction import.")
    }
}
