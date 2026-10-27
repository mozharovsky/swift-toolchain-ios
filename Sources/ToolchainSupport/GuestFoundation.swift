import Foundation

/// Provenance of the FoundationEssentials archive that packaging patches in place of the WASM SDK's
/// copy.
///
/// The patch lets a guest's current locale follow the `LC_ALL` and `LANG` environment variables.
/// Packaging compiles the SDK's pinned swift-foundation sources twice with the bootstrap Swift
/// release. The unpatched build must reproduce the SDK's objects before the patched objects replace
/// the members they change. The module interface stays identical, so the SDK's compiled module
/// remains valid.
///
/// Releases before this patch omit the record and ship the SDK's original archive.
package struct GuestFoundation: Codable, Equatable, Sendable {
    /// The archive's location relative to the SDK framework's `Payload` directory.
    package let path: String
    /// The pinned source component that supplied the Foundation sources, which is
    /// `swift-foundation`.
    package let component: String
    /// The component revision, which must equal the revision recorded in the release inputs.
    package let revision: String
    /// The module directory inside the component, which is `Sources/FoundationEssentials`.
    package let sourcePath: String
    /// The digest of the source patch applied before the second build.
    package let patchSHA256: String
    /// The first line of the compiling Swift release's version output.
    package let compiler: String
    /// The archive members that the patched build replaced, such as `Locale_Cache.swift.obj`.
    ///
    /// Each name is unique. The other members keep the SDK's bytes.
    package let members: [String]
    /// The SDK archive's digest before replacement, which ties the record to the pinned SDK.
    package let replacedSHA256: String
    /// The digest of the packaged archive, which both SDK slices share.
    package let sha256: String

    /// Checks that the record names a payload archive, the pinned Foundation sources, the pinned
    /// Swift release, and the replaced locale member.
    ///
    /// `verify-artifact-manifest` calls this through ``ArtifactManifest/validate()`` before a
    /// consumer selects a release. Archive bytes are checked separately by artifact verification.
    ///
    /// - Parameter inputs: The release inputs whose Swift version and source revisions the record
    ///   must match.
    /// - Throws: ``ToolchainError`` when the path escapes the payload, the record names another
    ///   source or compiler, a digest is malformed, the archive is unchanged, or the member list is
    ///   empty, repeats a name, or omits `Locale_Cache.swift.obj`.
    package func validate(inputs: ToolchainConfiguration) throws(ToolchainError) {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), path.hasSuffix(".a"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw .invalidArtifact("Record guest Foundation as a static archive in the payload.")
        }
        guard component == "swift-foundation", sourcePath == "Sources/FoundationEssentials",
              inputs.sources.contains(where: { $0.name == component && $0.revision == revision })
        else {
            throw .invalidArtifact("Build guest Foundation from the pinned sources.")
        }
        guard Self.banners(for: inputs.swiftVersion).contains(compiler) else {
            throw .invalidArtifact("Build guest Foundation with the pinned Swift release.")
        }
        for checksum in [patchSHA256, replacedSHA256, sha256] {
            try CompilerArtifact.validateChecksum(checksum)
        }
        guard sha256 != replacedSHA256, Set(members).count == members.count,
              members.contains("Locale_Cache.swift.obj"),
              members.allSatisfy({ $0.hasSuffix(".obj") && !$0.contains("/") }) else {
            throw .invalidArtifact("Record a patched guest Foundation archive and its members.")
        }
    }

    /// Returns the version banners that a standalone Swift release prints.
    ///
    /// A release such as 6.4.0 can print its version without the zero patch component, and builds
    /// for Apple platforms prefix the banner with `Apple`.
    ///
    /// - Parameter version: The released Swift version with three numeric components.
    /// - Returns: Every accepted first line of `swiftc --version`.
    private static func banners(for version: String) -> [String] {
        var versions = [version]
        if version.hasSuffix(".0") {
            versions.append(String(version.dropLast(2)))
        }
        return versions.flatMap { version in
            let banner = "Swift version \(version) (swift-\(version)-RELEASE)"
            return [banner, "Apple \(banner)"]
        }
    }
}
