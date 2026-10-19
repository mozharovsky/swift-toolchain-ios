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
    /// The pinned source component that supplied the compiler-rt sources, such as `llvm-project`.
    package let component: String
    /// The component revision, which must equal the revision recorded in the release inputs.
    package let revision: String
    /// The CMake project directory inside the component, such as `compiler-rt`.
    package let sourcePath: String
    /// The CMake build type that selected the optimization level, such as `Release`.
    package let buildType: String
    /// The first line of the compiling clang's version output, which ends with its LLVM revision.
    package let compiler: String
    /// The SDK archive's digest before replacement, which ties the record to the pinned SDK.
    package let replacedSHA256: String
    /// The digest of the packaged archive, which both SDK slices share.
    package let sha256: String
    /// The number of global symbols that both the packaged and the replaced archive define.
    package let definedSymbols: Int

    /// Checks that the record names a payload file, a pinned source, and its matching compiler.
    ///
    /// `verify-artifact-manifest` calls this through ``ArtifactManifest/validate()`` before a
    /// consumer selects a release. Archive bytes are checked separately by artifact verification.
    ///
    /// - Parameter inputs: The release inputs whose source revisions the record must match.
    /// - Throws: ``ToolchainError`` when a path escapes its directory, the source or compiler does
    ///   not match the pinned revision, a digest is malformed, or the archive defines no symbols.
    package func validate(inputs: ToolchainConfiguration) throws(ToolchainError) {
        for relativePath in [path, sourcePath] {
            let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
                  !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
                throw .invalidArtifact("Record guest builtins paths inside their directories.")
            }
        }
        guard path.hasSuffix(".a") else {
            throw .invalidArtifact("Record the guest builtins as a static archive.")
        }
        guard inputs.sources.contains(where: { $0.name == component && $0.revision == revision })
        else {
            throw .invalidArtifact("Build the guest builtins from a pinned source revision.")
        }
        guard !buildType.isEmpty, !compiler.contains(where: \.isNewline),
              compiler.hasSuffix(" \(revision))") else {
            throw .invalidArtifact("Record a build type and a compiler from the source revision.")
        }
        try CompilerArtifact.validateChecksum(replacedSHA256)
        try CompilerArtifact.validateChecksum(sha256)
        guard sha256 != replacedSHA256, definedSymbols > 0 else {
            throw .invalidArtifact("Record a rebuilt guest builtins archive and its symbols.")
        }
    }
}
