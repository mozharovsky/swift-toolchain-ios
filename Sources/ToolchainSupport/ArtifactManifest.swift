package import Foundation

/// Consumer archive identities checked before a package can select a compiler release.
package struct ArtifactManifest: Codable, Equatable, Sendable {
    /// Unknown schemas require an explicit update to the consumer contract.
    package let schemaVersion: Int
    /// Framework bundle metadata uses the same three-part release version.
    package let version: String
    /// The C result layout must match the embedding package's compiled header.
    package let bridgeABI: Int
    /// Native libraries execute on this device platform rather than the WASM target.
    package let compilerHost: String
    /// Generated modules retain the target recorded in the source configuration.
    package let programTarget: String
    /// The producer records the original lock-file bytes independently of JSON formatting.
    package let configurationSHA256: String
    /// Consumers can identify the compiler's immediate-execution profile.
    package let frontendPatchSHA256: String
    /// The filesystem metadata patch identity, absent from releases before this profile existed.
    /// Artifact validation checks its checksum format before a consumer selects the release.
    package let filesystemMetadataPatchSHA256: String?
    /// The Swift restriction patch identity, absent from releases before the native profile.
    package let restrictedSwiftPatchSHA256: String?
    /// The LLVM restriction patch identity, present with the complete native profile record.
    package let restrictedLLVMPatchSHA256: String?
    /// The bundled macro policy identity, present with the complete native profile record.
    package let bundledMacroPatchSHA256: String?
    /// The macro adapter preserves the upstream main-actor callback requirement.
    package let macroPatchSHA256: String
    /// Source publication can pin the packaging code independently of upstream compiler revisions.
    package let producerRevision: String
    /// Local candidates remain distinguishable from artifacts assembled from committed producer
    /// code.
    package let producerHasUncommittedChanges: Bool
    /// The selected notice inventory is part of the consumer release identity.
    package let noticesSHA256: String
    /// Native main-queue routing is tracked independently of the upstream macro entry rename.
    package let macroAdapterSHA256: String
    /// Complete source and SDK identities remain available after archives leave the build tree.
    package let inputs: ToolchainConfiguration
    /// Native macro build inputs remain outside the application's SwiftPM product.
    package let macroBuildSupport: MacroBuildSupport
    /// Each framework remains replaceable behind the consumer's single product.
    package let artifacts: [CompilerArtifact]

    /// Loads validated release metadata without executing code or inspecting archive bytes.
    ///
    /// - Parameter url: The local artifact manifest to decode and validate.
    /// - Returns: The manifest with its input and archive contracts checked.
    /// - Throws: ``ToolchainError`` when file reading or decoding fails.
    ///   Invalid metadata also throws.
    package static func load(from url: URL) throws(ToolchainError) -> Self {
        let manifest: Self
        do {
            manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        } catch {
            throw .unreadableFile("Read a valid artifact manifest at \(url.path). \(error)")
        }
        try manifest.validate()
        return manifest
    }

    /// Validates release identities before a consumer resolves binary targets.
    ///
    /// A native profile record supplies every restriction patch identity together. Earlier
    /// manifests can omit the complete record without claiming those restrictions.
    ///
    /// - Throws: ``ToolchainError`` when required components are missing, identities are invalid,
    ///   or schema and platform metadata is inconsistent.
    package func validate() throws(ToolchainError) {
        guard schemaVersion == 1, bridgeABI == 1 else {
            throw .invalidArtifact("Use artifact schema 1 and compiler bridge ABI 1.")
        }
        guard version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
        else {
            throw .invalidArtifact("Use three numeric artifact version components.")
        }
        try inputs.validate()
        guard compilerHost == inputs.compilerHost, programTarget == inputs.programTarget else {
            throw .invalidArtifact("Match artifact platforms to their recorded build inputs.")
        }
        guard producerRevision.range(of: #"^[a-f0-9]{40}$"#, options: .regularExpression) != nil
        else {
            throw .invalidArtifact("Record a full producer commit identity.")
        }
        for checksum in [
            configurationSHA256,
            frontendPatchSHA256,
            macroPatchSHA256,
            noticesSHA256,
            macroAdapterSHA256,
        ] {
            try CompilerArtifact.validateChecksum(checksum)
        }
        try macroBuildSupport.validate()
        if let filesystemMetadataPatchSHA256 {
            try CompilerArtifact.validateChecksum(filesystemMetadataPatchSHA256)
        }
        let profileIdentities = [
            restrictedSwiftPatchSHA256,
            restrictedLLVMPatchSHA256,
            bundledMacroPatchSHA256,
        ]
        let suppliedIdentities = profileIdentities.compactMap(\.self)
        let hasCompleteProfile = suppliedIdentities.count == profileIdentities.count
        guard suppliedIdentities.isEmpty || hasCompleteProfile else {
            throw .invalidArtifact("Record every native profile patch identity together.")
        }
        for checksum in suppliedIdentities {
            try CompilerArtifact.validateChecksum(checksum)
        }
        let names = artifacts.map(\.name)
        guard Set(names).count == names.count else {
            throw .invalidArtifact("Artifact names must be unique.")
        }
        let required = [
            "SwiftCompilerBridge",
            "SwiftCompilerSDK",
            "SwiftInProcPluginServer",
            "_CompilerSwiftLibraryPluginProvider",
            "ObservationMacros",
            "SwiftMacros",
        ]
        guard Set(required).isSubset(of: Set(names)) else {
            throw .invalidArtifact(
                "Include the compiler, SDK, macro server, and standard macro libraries.",
            )
        }
        for artifact in artifacts {
            try artifact.validate()
        }
    }
}
