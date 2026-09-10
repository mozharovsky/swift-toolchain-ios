import Foundation

/// Maintenance failures reported by source validation and artifact packaging.
package enum ToolchainError: Error, Equatable, CustomStringConvertible {
    /// Configuration failures identify the input that needs a reviewed correction.
    case invalidConfiguration(String)
    /// Artifact metadata and module codecs reject invalid inputs before consumer use.
    case invalidArtifact(String)
    /// Commit failures prevent hooks and CI from accepting incomplete history metadata.
    case invalidCommit(String)
    /// File inventory failures keep unsupported artifacts out of source control.
    case invalidRepository(String)
    /// Input failures preserve the path that the command could not read.
    case unreadableFile(String)

    /// ArgumentParser presents actionable text without exposing a Foundation error wrapper.
    package var description: String {
        switch self {
        case let .invalidConfiguration(message), let .invalidArtifact(message),
             let .invalidCommit(message),
             let .invalidRepository(message), let .unreadableFile(message):
            message
        }
    }
}
