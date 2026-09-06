import Foundation

/// Target SDK identity checked independently of the native compiler's architecture.
package struct SDKArchive: Codable, Equatable, Sendable {
    /// Serialized guest modules belong to this exact SDK release.
    package let version: String
    /// The eventual downloader uses a fixed archive URL recorded in the lock file.
    package let url: String
    /// Archive verification compares downloaded bytes against this lowercase SHA-256 digest.
    package let sha256: String

    /// Configuration checks fail before a mutable or unauthenticated identity reaches acquisition.
    package func validate(swiftVersion: String) throws(ToolchainError) {
        guard version == "swift-\(swiftVersion)-RELEASE_wasm" else {
            throw .invalidConfiguration("Match the SDK release to the selected Swift version.")
        }
        guard sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw .invalidConfiguration("Record the SDK archive's lowercase SHA-256 checksum.")
        }
        guard let archive = URLComponents(string: url), archive.scheme == "https",
              archive.host == "download.swift.org", archive.user == nil, archive.password == nil,
              archive.query == nil, archive.fragment == nil,
              archive.path.hasSuffix("/\(version).artifactbundle.tar.gz") else {
            throw .invalidConfiguration(
                "Use the versioned Swift SDK archive on download.swift.org.",
            )
        }
    }
}
