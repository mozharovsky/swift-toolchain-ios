import Testing
@testable import ToolchainSupport

/// Commit cases that distinguish real DCO trailers from body text and incomplete messages.
struct CommitMessageTests {
    /// A valid message carries its reason before a final block of Git trailers.
    @Test func acceptsCompleteMessage() throws {
        try CommitMessage.validate(Self.validMessage)
    }

    /// Git metadata may precede or follow the sign-off inside the final trailer block.
    @Test(arguments: [0, 1, 2])
    func acceptsSignOffWithinFinalBlock(position: Int) throws {
        var trailers = [
            "Reviewed-by: Example Reviewer <reviewer@example.com>",
            "Co-authored-by: Example Contributor <contributor@example.com>",
        ]
        trailers.insert("Signed-off-by: Example Author <author@example.com>", at: position)
        let message = "build(compiler): pin source revisions\n\nKeep source inputs stable.\n\n"
            + trailers.joined(separator: "\n") + "\n"
        try CommitMessage.validate(message)
    }

    /// A sign-off mentioned in the body does not certify the final commit message.
    @Test func rejectsBodySignOff() {
        #expect(throws: ToolchainError.self) {
            try CommitMessage.validate(Self.validMessage + "\n\nMore body text.\n")
        }
    }

    /// A valid trailer does not replace the explanation required for future reviewers.
    @Test func rejectsMissingReason() {
        #expect(throws: ToolchainError.self) {
            try CommitMessage.validate(
                "build(compiler): pin sources\n\n"
                    + "Signed-off-by: Example Author <author@example.com>\n",
            )
        }
    }

    /// Subject checks keep arbitrary prefixes and oversized summaries out of repository history.
    @Test(arguments: ["Update compiler", "build(other): pin inputs"])
    func rejectsInvalidSubject(subject: String) {
        let message = subject + "\n\nKeep compiler inputs stable.\n\n"
            + "Signed-off-by: Example Author <author@example.com>\n"
        #expect(throws: ToolchainError.self) { try CommitMessage.validate(message) }
    }

    /// Long subjects fail even when their type, scope, body, and trailer are otherwise valid.
    @Test func rejectsLongSubject() {
        let message = "build(compiler): " + String(repeating: "x", count: 72)
            + "\n\nKeep inputs stable.\n\nSigned-off-by: Example Author <author@example.com>\n"
        #expect(throws: ToolchainError.self) { try CommitMessage.validate(message) }
    }

    /// Test messages use a reserved example domain rather than a maintainer's private address.
    private static let validMessage = "build(compiler): pin source revisions\n\n"
        + "Keep source inputs stable while the build recipes evolve.\n\n"
        + "Signed-off-by: Example Author <author@example.com>\n"
        + "Reviewed-by: Example Reviewer <reviewer@example.com>\n"
}
