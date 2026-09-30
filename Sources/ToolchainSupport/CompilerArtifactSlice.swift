import Foundation

/// One native environment whose executable bytes are verified independently of its archive.
package struct CompilerArtifactSlice: Codable, Equatable, Sendable {
    /// The XCFramework directory selected by Xcode for this native environment.
    package let identifier: String
    /// The complete native triple distinguishes arm64 devices from arm64 simulators.
    package let compilerHost: String
    /// The digest of the executable after packaging and install-name relocation.
    package let binaryChecksum: String
    /// The executable size excludes the framework's resource payload.
    package let binaryBytes: UInt64

    /// Checks a slice's native environment and executable identity before archive selection.
    ///
    /// - Throws: ``ToolchainError`` when the platform, triple, digest, or size is unsupported.
    package func validate() throws(ToolchainError) {
        let suffix: String
        switch identifier {
        case "ios-arm64": suffix = ""
        case "ios-arm64-simulator": suffix = "-simulator"
        default: throw .invalidArtifact("Select an arm64 device or simulator slice.")
        }
        guard binaryBytes > 0,
              compilerHost.range(
                  of: "^arm64-apple-ios[0-9]+\\.[0-9]+" + suffix + "$",
                  options: .regularExpression,
              ) != nil else {
            throw .invalidArtifact(
                "Match the slice's native triple and record a nonempty executable.",
            )
        }
        try CompilerArtifact.validateChecksum(binaryChecksum)
    }
}
