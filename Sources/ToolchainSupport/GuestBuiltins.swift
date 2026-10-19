import Foundation

/// Provenance of the compiler-rt builtins archive that packaging compiles in place of the WASM
/// SDK's unoptimized copy.
///
/// Guest programs link this archive for 128-bit integer arithmetic, `long double` arithmetic, and
/// other helpers that WebAssembly lacks as instructions. The packaged archive defines the same
/// members and global symbols as the SDK archive it replaces. Releases before this rebuild omit
/// the record and ship the SDK's original archive.
package struct GuestBuiltins: Codable, Equatable, Sendable {
    /// The archive's location relative to the SDK framework's `Payload` directory.
    package let path: String
    /// The pinned source component that supplied the compiler-rt sources, which is `llvm-project`.
    package let component: String
    /// The component revision, which must equal the revision recorded in the release inputs.
    package let revision: String
    /// The CMake project directory inside the component, which is `compiler-rt`.
    package let sourcePath: String
    /// The CMake build type, which is `Release` because packaging produces only optimized builds.
    package let buildType: String
    /// The first line of the compiling clang's version output, which ends with its LLVM revision.
    package let compiler: String
    /// The SDK archive's digest before replacement, which ties the record to the pinned SDK.
    package let replacedSHA256: String
    /// The digest of the packaged archive, which both SDK slices share.
    package let sha256: String
    /// The number of global symbols that both the packaged and the replaced archive define.
    package let definedSymbols: Int

    /// Checks that the record names a payload archive, the pinned compiler-rt sources, a release
    /// build, and a compiler built from the same revision.
    ///
    /// `verify-artifact-manifest` calls this through ``ArtifactManifest/validate()`` before a
    /// consumer selects a release. Archive bytes are checked separately by artifact verification.
    ///
    /// - Parameter inputs: The release inputs whose source revisions the record must match.
    /// - Throws: ``ToolchainError`` when the path escapes the payload, the record names another
    ///   source, build type, or compiler revision, a digest is malformed, or the archive defines no
    ///   symbols.
    package func validate(inputs: ToolchainConfiguration) throws(ToolchainError) {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), path.hasSuffix(".a"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw .invalidArtifact("Record the guest builtins as a static archive in the payload.")
        }
        guard component == "llvm-project", sourcePath == "compiler-rt",
              inputs.sources.contains(where: { $0.name == component && $0.revision == revision })
        else {
            throw .invalidArtifact("Build the guest builtins from the pinned compiler-rt sources.")
        }
        guard buildType == "Release", !compiler.contains(where: \.isNewline),
              compiler.hasSuffix(" \(revision))") else {
            throw .invalidArtifact("Record a release build and a compiler from that revision.")
        }
        try CompilerArtifact.validateChecksum(replacedSHA256)
        try CompilerArtifact.validateChecksum(sha256)
        guard sha256 != replacedSHA256, definedSymbols > 0 else {
            throw .invalidArtifact("Record a rebuilt guest builtins archive and its symbols.")
        }
    }
}
