import Foundation

/// One immutable ZIP and its native executable identity for binary-target selection.
package struct CompilerArtifact: Codable, Equatable, Sendable {
    /// The identifier is shared by the framework, executable, and SwiftPM target.
    package let name: String
    /// A basename keeps the archive within a caller-selected release directory.
    package let archive: String
    /// SwiftPM checks this digest against the downloaded ZIP bytes.
    package let checksum: String
    /// Consumers can account for transfer size without treating it as installed size.
    package let archiveBytes: UInt64
    /// Post-extraction inspection checks the executable independently of ZIP metadata.
    package let binaryChecksum: String
    /// The executable size excludes SDK resources and any runtime preparation cache.
    package let binaryBytes: UInt64

    /// Path and digest checks keep a manifest from selecting another file or target identity.
    package func validate() throws(ToolchainError) {
        guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
              archive == "\(name).zip" else {
            throw .invalidArtifact("Use a framework identifier and its matching ZIP basename.")
        }
        guard archiveBytes > 0, binaryBytes > 0 else {
            throw .invalidArtifact("Record nonzero archive and executable sizes.")
        }
        try Self.validateChecksum(checksum)
        try Self.validateChecksum(binaryChecksum)
    }

    /// Every manifest digest uses the same lowercase SHA-256 representation as SwiftPM.
    package static func validateChecksum(_ checksum: String) throws(ToolchainError) {
        guard checksum.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw .invalidArtifact("Record a complete lowercase SHA-256 digest.")
        }
    }
}
