import Foundation

/// Commit checks shared by the local hook and CI's complete-message stream.
package enum CommitMessage {
    /// Repository history requires a scoped subject, a reason, and a DCO entry in its final trailer
    /// block.
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
