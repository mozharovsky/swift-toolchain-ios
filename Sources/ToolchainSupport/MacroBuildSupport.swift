/// Build-only inputs let consumers produce additional native macro implementations with the same
/// ABI.
package struct MacroBuildSupport: Codable, Equatable, Sendable {
    /// The fixed basename remains separate from application framework archives.
    package let archive: String
    /// Maintenance tools verify downloaded development inputs against this release identity.
    package let checksum: String
    /// Transfer size does not contribute to the installed application's framework size.
    package let archiveBytes: UInt64

    /// A consumer rejects another payload or an incomplete identity before building a native macro.
    package func validate() throws(ToolchainError) {
        guard archive == "MacroBuildSupport.zip", archiveBytes > 0 else {
            throw .invalidArtifact("Record the named macro build support archive and its size.")
        }
        try CompilerArtifact.validateChecksum(checksum)
    }
}
