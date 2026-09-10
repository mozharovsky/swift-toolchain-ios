import Foundation

/// Commit checks shared by the local hook and CI's complete-message stream.
package enum CommitMessage {
    /// Validates the complete messages selected by CI's Git history adapter.
    ///
    /// - Parameter source: NUL-separated messages with their bodies and trailers preserved.
    ///   A final delimiter is optional. An empty record is an invalid empty commit message.
    /// - Returns: The number of validated messages. An empty history returns zero.
    /// - Throws: `ToolchainError.invalidCommit` when any message fails the repository policy.
    package static func validateHistory(_ source: String) throws(ToolchainError) -> Int {
        guard !source.isEmpty else { return 0 }
        var messages = source.split(separator: "\0", omittingEmptySubsequences: false)
        if source.hasSuffix("\0") { messages.removeLast() }
        for message in messages {
            try validate(String(message))
        }
        return messages.count
    }

    /// Repository history requires a scoped subject, a reason, and a DCO entry in its final trailer
    /// block.
    ///
    /// - Parameter source: One complete commit message, including its subject and final trailers.
    /// - Throws: `ToolchainError.invalidCommit` when the subject, reason, or final sign-off is
    /// invalid.
    package static func validate(_ source: String) throws(ToolchainError) {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let subject = lines.first ?? ""
        let pattern = #"^(feat|fix|docs|refactor|test|perf|ci|build|chore)"#
            + #"\((compiler|backend|bridge|sdk|macros|tools|ci|docs)\): [a-z0-9].*$"#
        guard subject.range(of: pattern, options: .regularExpression) != nil,
              subject.count < 72 else {
            throw .invalidCommit("Use a scoped Conventional Commit subject under 72 characters.")
        }
        guard lines.count > 3, lines[1].isEmpty else {
            throw .invalidCommit("Separate the subject from a body that explains the change.")
        }
        var end = lines.endIndex
        while end > 0, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            end -= 1
        }
        var start = end
        while start > 0,
              lines[start - 1].range(
                  of: #"^[A-Za-z0-9-]+: .+$"#,
                  options: .regularExpression,
              ) != nil {
            start -= 1
        }
        guard start > 2, start < end, lines[start - 1].isEmpty,
              lines[start ..< end].contains(where: {
                  $0.range(
                      of: #"^Signed-off-by: .+ <[^<>\s]+@[^<>\s]+>$"#,
                      options: .regularExpression,
                  ) != nil
              }) else {
            throw .invalidCommit(
                "Add your Signed-off-by name and email to the final trailer block.",
            )
        }
        guard lines[2 ..< start].contains(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else {
            throw .invalidCommit("Explain why the change is needed before its sign-off trailers.")
        }
    }
}
