import ArgumentParser
import Foundation
import ToolchainSupport

/// CI adapter for complete NUL-separated messages from the pull request's Git range.
struct CheckHistoryCommand: ParsableCommand {
    /// CI runs Git itself so this command never interprets a shell expression.
    static let configuration = CommandConfiguration(commandName: "check-history")

    /// The complete message stream preserves bodies and trailers across newline boundaries.
    mutating func run() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let source = String(data: data, encoding: .utf8) else {
            throw ValidationError("Provide UTF-8 commit messages separated by NUL bytes.")
        }
        let messages = source.split(separator: "\0").map(String.init)
        guard !messages.isEmpty else { throw ValidationError("The commit range is empty.") }
        for message in messages {
            try CommitMessage.validate(message)
        }
        print("Validated \(messages.count) commit messages and DCO trailers.")
    }
}
