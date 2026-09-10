import Testing
@testable import ToolchainSupport

/// Commit cases that distinguish real DCO trailers from body text and incomplete messages.
struct CommitMessageTests {
    /// Checks that CI's empty selected history succeeds with zero validated messages.
    @Test func acceptsEmptyHistory() throws {
        #expect(try CommitMessage.validateHistory("") == 0)
    }

    /// Git's NUL delimiters preserve each reason and final trailer block in a complete history.
    ///
    /// - Parameter trailingDelimiter: Whether Git's final message terminator is present.
    /// - Throws: History validation rejects either complete message.
    @Test(arguments: [false, true])
    func acceptsCompleteHistory(trailingDelimiter: Bool) throws {
        let source = Self.validMessage + "\0" + Self.validMessage
            + (trailingDelimiter ? "\0" : "")
        #expect(try CommitMessage.validateHistory(source) == 2)
    }

    /// An empty commit record must not disappear among otherwise valid messages.
    ///
    /// - Parameter position: The empty record's index before, between, or after valid records.
    @Test(arguments: [0, 1, 2])
    func rejectsEmptyHistoryRecord(position: Int) {
        var messages = [Self.validMessage, Self.validMessage]
        messages.insert("", at: position)
        #expect(throws: ToolchainError.self) {
            try CommitMessage.validateHistory(messages.joined(separator: "\0") + "\0")
        }
    }

    /// Git emits a NUL record for a selected empty message instead of an empty stream.
    @Test func rejectsSingleEmptyHistoryRecord() {
        #expect(throws: ToolchainError.self) {
            try CommitMessage.validateHistory("\0")
        }
    }

    /// A preceding valid commit cannot hide an incomplete message later in the stream.
    @Test func rejectsIncompleteHistory() {
        #expect(throws: ToolchainError.invalidCommit(
            "Separate the subject from a body that explains the change.",
        )) {
            try CommitMessage.validateHistory(Self.validMessage + "\0fix(ci): incomplete message\0")
        }
    }

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
