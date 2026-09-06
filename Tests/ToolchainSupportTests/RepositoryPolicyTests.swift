import Foundation
import Testing
@testable import ToolchainSupport

/// Publication inventory cases covering traversal, generated artifacts, and agent-rule drift.
struct RepositoryPolicyTests {
    /// Source, documentation, patches, and maintenance configuration remain valid Git inputs.
    @Test(arguments: ["Sources/Bridge/Compiler.cpp", "Patches/frontend.patch", "Docs/Build.md"])
    func acceptsSourcePaths(path: String) throws {
        try RepositoryPolicy.validate(path: path)
    }

    /// Binary directories and traversal remain invalid even when Git would accept their names.
    @Test(arguments: [
        "../outside.swift", "/absolute.swift", "Sources//File.swift", "Sources\\File.swift",
        ".cache/source.swift", "SDK/SwiftUI.swiftinterface", "Library.xcframework/Info.plist",
        "libCompiler.a", "program.wasm", "release.zip",
    ])
    func rejectsUnsupportedInventory(path: String) {
        #expect(throws: ToolchainError.self) { try RepositoryPolicy.validate(path: path) }
    }

    /// A source symlink must not expose files outside the publication inventory.
    @Test func rejectsSourceSymlink() throws {
        try withRepository { root in
            let target = root.appending(path: "Source.swift")
            try "import Foundation\n".write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "Alias.swift"), withDestinationURL: target,
            )
            #expect(throws: ToolchainError.self) {
                try RepositoryPolicy.validate(paths: ["Alias.swift"], root: root)
            }
        }
    }

    /// Claude instructions stay an exact import so the two agent files cannot diverge.
    @Test func rejectsIndependentClaudeRules() throws {
        try withRepository { root in
            try "Separate rules\n".write(
                to: root.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8,
            )
            #expect(throws: ToolchainError.self) {
                try RepositoryPolicy.validate(paths: ["CLAUDE.md"], root: root)
            }
        }
    }

    /// Valid inventories exercise file metadata and the shared instruction import together.
    @Test func acceptsRegularSourceInventory() throws {
        try withRepository { root in
            try RepositoryPolicy.validate(paths: ["CLAUDE.md"], root: root)
        }
    }

    /// Each filesystem test owns disposable storage so parallel tests cannot share state.
    private func withRepository(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "@AGENTS.md\n".write(
            to: root.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8,
        )
        try body(root)
    }
}
