import ArgumentParser
import Foundation
import ToolchainSupport

/// CI adapter for complete NUL-separated messages selected from the pull request's Git range.
struct CheckHistoryCommand: ParsableCommand {
    /// CI runs Git itself so this command never interprets a shell expression.
    static let configuration = CommandConfiguration(commandName: "check-history")

    /// Validates selected messages while accepting ranges containing only exempt merge commits.
    ///
    /// - Throws: `ValidationError` when the stream is not UTF-8, or `ToolchainError` when a
    ///   selected message fails the repository policy.
    mutating func run() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let source = String(data: data, encoding: .utf8) else {
            throw ValidationError("Provide UTF-8 commit messages separated by NUL bytes.")
        }
        let count = try CommitMessage.validateHistory(source)
        print("Validated \(count) commit messages and DCO trailers.")
    }
}
