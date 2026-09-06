package import Foundation

/// Source inventory checks that keep build outputs and SDK interfaces outside version control.
package enum RepositoryPolicy {
    /// Compiler and linker outputs belong in ignored caches or release archives.
    private static let artifactExtensions: Set<String> = [
        "a", "app", "dylib", "gz", "ipa", "o", "so", "swiftinterface", "swiftmodule",
        "tar", "wasm", "xcframework", "xcodeproj", "xcworkspace", "zip",
    ]

    /// Ignored work directories must not become tracked inputs through a forced Git add.
    private static let workDirectories: Set<String> = [
        ".build", ".cache", ".git", ".swiftpm", "Artifacts", "DerivedData", "Upstreams",
    ]

    /// CI supplies Git's file list so ignored upstream checkouts are never traversed.
    package static func validate(paths: [String], root: URL) throws(ToolchainError) {
        for path in paths {
            try validate(path: path)
            let url = root.appending(path: path)
            do {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true else {
                    throw ToolchainError
                        .invalidRepository("Commit a regular source file at \(path).")
                }
                guard (values.fileSize ?? 0) <= 1_000_000 else {
                    throw ToolchainError
                        .invalidRepository("Keep \(path) in a release or ignored cache.")
                }
            } catch let error as ToolchainError {
                throw error
            } catch {
                throw .unreadableFile("Inspect the repository file at \(path). \(error)")
            }
        }
        do {
            let alias = try String(contentsOf: root.appending(path: "CLAUDE.md"), encoding: .utf8)
            guard alias == "@AGENTS.md\n" else {
                throw ToolchainError
                    .invalidRepository("Keep CLAUDE.md as the single AGENTS.md import.")
            }
        } catch let error as ToolchainError {
            throw error
        } catch {
            throw .unreadableFile("Read the repository's CLAUDE.md import. \(error)")
        }
    }

    /// File checks reject traversal and binary containers before inspecting filesystem metadata.
    package static func validate(path: String) throws(ToolchainError) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !path.contains("\\"), !path.contains("\0") else {
            throw .invalidRepository("Use a repository-relative source path for \(path).")
        }
        for part in parts {
            let suffix = (part as NSString).pathExtension.lowercased()
            guard !artifactExtensions.contains(suffix), !workDirectories.contains(part) else {
                throw .invalidRepository("Remove generated or downloaded artifacts from \(path).")
            }
        }
    }
}
