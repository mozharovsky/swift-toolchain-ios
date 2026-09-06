import ArgumentParser
import Foundation
import ToolchainSupport

/// Git hook adapter for the repository's shared commit policy.
struct CheckCommitCommand: ParsableCommand {
    /// Git supplies its commit-message file as one positional argument.
    static let configuration = CommandConfiguration(commandName: "check-commit-message")

    /// The hook passes Git's existing file without changing the proposed message.
    @Argument(help: "The commit-message file supplied by Git.")
    var path: String

    /// Invalid metadata reaches Git as a failed hook before a commit is created.
    mutating func run() throws {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        try CommitMessage.validate(source)
    }
}
