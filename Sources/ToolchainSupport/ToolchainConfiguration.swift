package import Foundation

/// Reviewed build inputs that separate the compiler's iOS host from its WebAssembly output.
package struct ToolchainConfiguration: Codable, Equatable, Sendable {
    /// Commands reject unknown schemas rather than infer new build semantics.
    package let schemaVersion: Int
    /// SDK compatibility checks use this released Swift version.
    package let swiftVersion: String
    /// Native compiler libraries run on this platform and deployment floor.
    package let compilerHost: String
    /// The frontend and linker emit programs for this supported guest ABI.
    package let programTarget: String
    /// Each source checkout is identified independently of its mutable release tag.
    package let sources: [UpstreamSource]
    /// The guest SDK supplies compiler input data rather than native host frameworks.
    package let sdk: SDKArchive

    /// The verify command reads this file without downloading or compiling an upstream project.
    package static func load(from url: URL) throws(ToolchainError) -> Self {
        let value: Self
        do {
            value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        } catch {
            throw .unreadableFile("Read a valid toolchain configuration at \(url.path). \(error)")
        }
        try value.validate()
        return value
    }

    /// Build preparation depends on rejecting target swaps and incomplete source identities early.
    package func validate() throws(ToolchainError) {
        guard schemaVersion == 1 else {
            throw .invalidConfiguration("Use toolchain configuration schema 1.")
        }
        guard swiftVersion.range(
            of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#,
            options: .regularExpression,
        ) != nil else {
            throw .invalidConfiguration(
                "Use a released Swift version with three numeric components.",
            )
        }
        guard compilerHost.range(
            of: #"^arm64-apple-ios[0-9]+\.[0-9]+$"#,
            options: .regularExpression,
        ) != nil else {
            throw .invalidConfiguration(
                "Select an arm64 iOS device host with a deployment version.",
            )
        }
        guard programTarget == "wasm32-unknown-wasip1" else {
            throw .invalidConfiguration("The current profile emits wasm32-unknown-wasip1 programs.")
        }
        let names = sources.map(\.name)
        guard Set(names).count == names.count else {
            throw .invalidConfiguration("Give each upstream component a unique identifier.")
        }
        guard Set(["swift", "llvm-project", "swift-syntax", "swift-cmark", "string-processing"])
            .isSubset(of: Set(names)) else {
            throw .invalidConfiguration("Record every source component required by the compiler.")
        }
        for source in sources {
            try source.validate()
        }
        try sdk.validate(swiftVersion: swiftVersion)
    }
}
