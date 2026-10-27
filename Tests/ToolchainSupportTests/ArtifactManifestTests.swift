import Foundation
import Testing
@testable import ToolchainSupport

/// Release-record checks reject path changes and identity mismatches before consumers select
/// binaries.
struct ArtifactManifestTests {
    /// A complete metadata fixture passes without requiring native artifacts on the test machine.
    @Test func acceptsCompleteManifest() throws {
        try Self.fixture().validate()
    }

    /// Archive paths cannot escape their release directory or select another framework's ZIP.
    @Test(arguments: ["../SwiftCompilerBridge.zip", "/tmp/SwiftCompilerBridge.zip", "Another.zip"])
    func rejectsArchivePaths(archive: String) throws {
        let artifact = CompilerArtifact(
            name: "SwiftCompilerBridge", archive: archive,
            checksum: String(repeating: "a", count: 64), archiveBytes: 20,
            binaryChecksum: String(repeating: "b", count: 64), binaryBytes: 30, slices: nil,
        )
        #expect(throws: ToolchainError.self) { try artifact.validate() }
    }

    /// A target mismatch changes compiler behavior even when every archive hash remains valid.
    @Test func rejectsTargetMismatch() throws {
        let manifest = try Self
            .modified { object in object["programTarget"] = "arm64-apple-ios18.0" }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Duplicate names would make binary-target selection depend on record order.
    @Test func rejectsDuplicateArtifacts() throws {
        let manifest = try Self.modified { object in
            var artifacts = try #require(object["artifacts"] as? [[String: Any]])
            try artifacts.append(#require(artifacts.first))
            object["artifacts"] = artifacts
        }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// A complete compiler release must include its macro transport and base SDK.
    @Test func rejectsMissingServer() throws {
        let manifest = try Self.modified { object in
            let artifacts = try #require(object["artifacts"] as? [[String: Any]])
            object["artifacts"] = artifacts
                .filter { $0["name"] as? String != "SwiftInProcPluginServer" }
        }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// A release that pins swift-foundation cannot omit the Foundation macros built from it.
    @Test func rejectsMissingFoundationMacros() throws {
        let manifest = try Self.modified { object in
            let artifacts = try #require(object["artifacts"] as? [[String: Any]])
            object["artifacts"] = artifacts.filter { $0["name"] as? String != "FoundationMacros" }
        }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Releases before the Foundation macros remain valid because their inputs omit the source.
    ///
    /// These releases also predate the guest Foundation patch, which needs the same source.
    ///
    /// - Throws: Fixture loading or JSON conversion fails, or decoded metadata is invalid.
    @Test func acceptsLegacyFoundationMacros() throws {
        let manifest = try Self.modified { object in
            object.removeValue(forKey: "predicateStringComparisonsPatchSHA256")
            object.removeValue(forKey: "guestFoundation")
            var inputs = try #require(object["inputs"] as? [String: Any])
            let sources = try #require(inputs["sources"] as? [[String: Any]])
            inputs["sources"] = sources.filter { $0["name"] as? String != "swift-foundation" }
            object["inputs"] = inputs
            let artifacts = try #require(object["artifacts"] as? [[String: Any]])
            object["artifacts"] = artifacts.filter { $0["name"] as? String != "FoundationMacros" }
        }
        #expect(!manifest.artifacts.contains { $0.name == "FoundationMacros" })
        try manifest.validate()
    }

    /// Digests with the right length still fail when they contain non-hexadecimal bytes.
    @Test func rejectsInvalidDigest() throws {
        let manifest = try Self.modified { object in object["macroPatchSHA256"] = String(
            repeating: "z",
            count: 64,
        ) }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Earlier release manifests remain readable without claiming the newer filesystem profile.
    @Test func acceptsLegacyFilesystemMetadata() throws {
        let manifest = try Self.modified { object in
            object.removeValue(forKey: "filesystemMetadataPatchSHA256")
        }
        #expect(manifest.filesystemMetadataPatchSHA256 == nil)
        try manifest.validate()
    }

    /// Reads releases that predate the stackification backport without claiming the fix, so
    /// consumers can tell which compilers support `-mwide-arithmetic`.
    ///
    /// - Throws: Fixture loading or JSON conversion fails, or decoded metadata is invalid.
    @Test func acceptsLegacyStackifyPatch() throws {
        let manifest = try Self.modified { object in
            object.removeValue(forKey: "webAssemblyStackifyPatchSHA256")
        }
        #expect(manifest.webAssemblyStackifyPatchSHA256 == nil)
        try manifest.validate()
    }

    /// Rejects a stackification patch identity that is not a complete SHA-256 digest.
    ///
    /// - Throws: Fixture loading or JSON conversion fails.
    @Test func rejectsInvalidStackifyPatchDigest() throws {
        let manifest = try Self.modified { object in
            object["webAssemblyStackifyPatchSHA256"] = String(repeating: "g", count: 64)
        }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Reads releases without the predicate string comparison patch.
    ///
    /// - Throws: Fixture loading or JSON conversion fails, or decoded metadata is invalid.
    @Test func acceptsLegacyPredicatePatch() throws {
        let manifest = try Self.modified { object in
            object.removeValue(forKey: "predicateStringComparisonsPatchSHA256")
        }
        #expect(manifest.predicateStringComparisonsPatchSHA256 == nil)
        try manifest.validate()
    }

    /// Rejects a predicate patch identity that is not a SHA-256 digest or that describes a release
    /// without the Foundation macros.
    ///
    /// - Parameter fault: The digest or framework inventory change applied to the fixture.
    /// - Throws: Fixture loading or JSON conversion fails.
    @Test(arguments: ["digest", "framework"])
    func rejectsInvalidPredicatePatch(_ fault: String) throws {
        let manifest = try Self.modified { object in
            if fault == "digest" {
                object["predicateStringComparisonsPatchSHA256"] = "invalid"
            } else {
                var inputs = try #require(object["inputs"] as? [String: Any])
                let sources = try #require(inputs["sources"] as? [[String: Any]])
                inputs["sources"] = sources.filter { $0["name"] as? String != "swift-foundation" }
                object["inputs"] = inputs
                let artifacts = try #require(object["artifacts"] as? [[String: Any]])
                object["artifacts"] = artifacts
                    .filter { $0["name"] as? String != "FoundationMacros" }
            }
        }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// A present filesystem patch identity must use the same checksum format as other inputs.
    @Test func rejectsInvalidFilesystemMetadataDigest() throws {
        let manifest = try Self.modified { object in
            object["filesystemMetadataPatchSHA256"] = "invalid"
        }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Accepts every bridge ABI version and rejects one that no consumer header defines.
    ///
    /// - Parameter version: A bridge ABI version.
    /// - Throws: Fixture loading or JSON conversion fails, or a supported version fails validation.
    @Test(arguments: [1, 2, 3, 4, 0])
    func checksBridgeABI(version: Int) throws {
        let manifest = try Self.modified { object in object["bridgeABI"] = version }
        if (1 ... 3).contains(version) {
            try manifest.validate()
        } else {
            #expect(throws: ToolchainError.self) { try manifest.validate() }
        }
    }

    /// Reads releases that predate the native compiler record, so `verify-artifact-manifest`
    /// keeps accepting alpha releases that consumers already pin.
    ///
    /// - Throws: Fixture loading or JSON conversion fails, or decoded metadata is invalid.
    @Test func acceptsLegacyNativeCompiler() throws {
        let manifest = try Self.modified { object in object.removeValue(forKey: "nativeCompiler") }
        #expect(manifest.nativeCompiler == nil)
        try manifest.validate()
    }

    /// Rejects a compiler record that does not name the selected Xcode's clang and its version,
    /// so `verify-artifact-manifest` fails before a consumer selects such a release. Every
    /// version component must be numeric.
    ///
    /// - Parameter compiler: A malformed or foreign compiler record.
    /// - Throws: Fixture loading or JSON conversion fails.
    @Test(arguments: [
        "", "Clang 21.0.0", "AppleClang", "AppleClang 21.0.0\nGNU", "AppleClang .",
        "AppleClang 21..0", "AppleClang 21.",
    ])
    func rejectsInvalidNativeCompiler(compiler: String) throws {
        let manifest = try Self.modified { object in object["nativeCompiler"] = compiler }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Reads earlier manifests without inferring native restrictions from absent metadata.
    ///
    /// - Throws: Fixture loading or JSON conversion fails, or decoded metadata is invalid.
    @Test func acceptsLegacyNativeProfile() throws {
        let manifest = try Self.modified { object in
            object.removeValue(forKey: "restrictedSwiftPatchSHA256")
            object.removeValue(forKey: "restrictedLLVMPatchSHA256")
            object.removeValue(forKey: "bundledMacroPatchSHA256")
        }
        #expect(manifest.restrictedSwiftPatchSHA256 == nil)
        #expect(manifest.restrictedLLVMPatchSHA256 == nil)
        #expect(manifest.bundledMacroPatchSHA256 == nil)
        try manifest.validate()
    }

    /// Rejects partial native profile claims before a consumer can resolve their archives.
    ///
    /// - Parameter field: The omitted member of the complete profile identity record.
    /// - Throws: Fixture loading or JSON conversion fails.
    @Test(arguments: [
        "restrictedSwiftPatchSHA256", "restrictedLLVMPatchSHA256", "bundledMacroPatchSHA256",
    ])
    func rejectsIncompleteNativeProfile(_ field: String) throws {
        let manifest = try Self.modified { object in object.removeValue(forKey: field) }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Applies checksum validation to each member of a complete native profile record.
    ///
    /// - Parameter field: The profile identity whose digest is replaced with invalid text.
    /// - Throws: Fixture loading or JSON conversion fails.
    @Test(arguments: [
        "restrictedSwiftPatchSHA256", "restrictedLLVMPatchSHA256", "bundledMacroPatchSHA256",
    ])
    func rejectsInvalidNativeProfileDigest(_ field: String) throws {
        let manifest = try Self.modified { object in object[field] = "invalid" }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Preserves every native profile identity through the manifest's public Codable contract.
    ///
    /// - Throws: Fixture loading, encoding, or decoding fails.
    @Test func preservesNativeProfileIdentities() throws {
        let original = try Self.fixture()
        let restored = try JSONDecoder().decode(
            ArtifactManifest.self, from: JSONEncoder().encode(original),
        )
        #expect(restored.restrictedSwiftPatchSHA256 == original.restrictedSwiftPatchSHA256)
        #expect(restored.restrictedLLVMPatchSHA256 == original.restrictedLLVMPatchSHA256)
        #expect(restored.bundledMacroPatchSHA256 == original.bundledMacroPatchSHA256)
        #expect(
            restored.webAssemblyStackifyPatchSHA256 == original.webAssemblyStackifyPatchSHA256,
        )
    }

    /// Development inputs must not select another archive or omit its transfer and integrity
    /// identity.
    @Test(arguments: ["archive", "size", "checksum"])
    func rejectsInvalidMacroBuildSupport(_ field: String) throws {
        let manifest = try Self.modified { object in
            var support = try #require(object["macroBuildSupport"] as? [String: Any])
            switch field {
            case "archive": support["archive"] = "../Other.zip"
            case "size": support["archiveBytes"] = 0
            default: support["checksum"] = "invalid"
            }
            object["macroBuildSupport"] = support
        }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Both arm64 environments retain independent executable identities in the release contract.
    ///
    /// - Throws: Fixture conversion or validation fails.
    @Test func acceptsDeviceAndSimulatorSlices() throws {
        let manifest = try Self.platformFixture()
        try manifest.validate()
        let restored = try JSONDecoder().decode(
            ArtifactManifest.self, from: JSONEncoder().encode(manifest),
        )
        #expect(restored == manifest)
    }

    /// A missing or mislabeled native environment must fail before binary-target selection.
    ///
    /// - Parameter fault: The invalid platform metadata applied to the first framework.
    /// - Throws: Fixture conversion fails.
    @Test(arguments: ["missing", "duplicate", "host", "checksum", "legacy"])
    func rejectsInvalidPlatformSlices(_ fault: String) throws {
        let manifest = try Self.platformFixture { object in
            var artifacts = try #require(object["artifacts"] as? [[String: Any]])
            var slices = try #require(artifacts[0]["slices"] as? [[String: Any]])
            switch fault {
            case "missing": slices.removeLast()
            case "duplicate": slices[1] = slices[0]
            case "host": slices[1]["compilerHost"] = "arm64-apple-ios18.0"
            case "checksum": slices[1]["binaryChecksum"] = "invalid"
            default: artifacts[0]["binaryBytes"] = 100
            }
            artifacts[0]["slices"] = slices
            object["artifacts"] = artifacts
        }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Reads releases that predate the builtins rebuild, so `verify-artifact-manifest` keeps
    /// accepting alpha releases that ship the SDK's original archive.
    ///
    /// - Throws: Fixture loading or JSON conversion fails, or decoded metadata is invalid.
    @Test func acceptsLegacyGuestBuiltins() throws {
        let manifest = try Self.modified { object in object.removeValue(forKey: "guestBuiltins") }
        #expect(manifest.guestBuiltins == nil)
        try manifest.validate()
    }

    /// Preserves the builtins provenance through the manifest's public Codable contract.
    ///
    /// - Throws: Fixture loading, encoding, or decoding fails.
    @Test func preservesGuestBuiltins() throws {
        let original = try Self.fixture()
        let restored = try JSONDecoder().decode(
            ArtifactManifest.self, from: JSONEncoder().encode(original),
        )
        #expect(restored.guestBuiltins == original.guestBuiltins)
        #expect(restored.guestBuiltins?.definedSymbols == 218)
    }

    /// Rejects a builtins record that escapes the payload, names another source or compiler, or
    /// claims an unchanged or empty archive.
    ///
    /// - Parameter fault: The invalid builtins metadata applied to the fixture record.
    /// - Throws: Fixture conversion fails.
    @Test(arguments: [
        "parent", "absolute", "empty", "archive", "source", "directory", "component", "revision",
        "compiler", "buildType", "debug", "checksum", "unchanged", "symbols",
    ])
    func rejectsInvalidGuestBuiltins(_ fault: String) throws {
        let manifest = try Self.modified { object in
            var record = try #require(object["guestBuiltins"] as? [String: Any])
            switch fault {
            case "parent": record["path"] = "../libclang_rt.builtins-wasm32.a"
            case "absolute": record["path"] = "/tmp/libclang_rt.builtins-wasm32.a"
            case "empty": record["path"] = "lib//libclang_rt.builtins-wasm32.a"
            case "archive": record["path"] = "lib/libclang_rt.builtins-wasm32.so"
            case "source": record["sourcePath"] = "../compiler-rt"
            case "directory": record["sourcePath"] = "compiler-rt/lib/builtins"
            case "component": record["component"] = "swift"
            case "revision": record["revision"] = String(repeating: "1", count: 40)
            case "compiler": record["compiler"] = "Apple clang version 21.0.0"
            case "buildType": record["buildType"] = ""
            case "debug": record["buildType"] = "Debug"
            case "checksum": record["sha256"] = "invalid"
            case "unchanged": record["sha256"] = record["replacedSHA256"]
            default: record["definedSymbols"] = 0
            }
            object["guestBuiltins"] = record
        }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Reads releases that predate the locale patch, so `verify-artifact-manifest` keeps accepting
    /// releases that ship the SDK's original Foundation archive.
    ///
    /// - Throws: Fixture loading or JSON conversion fails, or decoded metadata is invalid.
    @Test func acceptsLegacyGuestFoundation() throws {
        let manifest = try Self.modified { object in object.removeValue(forKey: "guestFoundation") }
        #expect(manifest.guestFoundation == nil)
        try manifest.validate()
    }

    /// Preserves the Foundation provenance through the manifest's public Codable contract.
    ///
    /// - Throws: Fixture loading, encoding, or decoding fails.
    @Test func preservesGuestFoundation() throws {
        let original = try Self.fixture()
        let restored = try JSONDecoder().decode(
            ArtifactManifest.self, from: JSONEncoder().encode(original),
        )
        #expect(restored.guestFoundation == original.guestFoundation)
        #expect(restored.guestFoundation?.members.contains("Locale_Cache.swift.obj") == true)
    }

    /// Accepts the banner of the pinned release with or without its zero patch component.
    ///
    /// - Parameter compiler: The first line of the compiling Swift release's version output.
    /// - Throws: Fixture conversion fails, or decoded metadata is invalid.
    @Test(arguments: [
        "Apple Swift version 6.4 (swift-6.4-RELEASE)",
        "Swift version 6.4.0 (swift-6.4.0-RELEASE)",
    ])
    func acceptsGuestFoundationCompilers(_ compiler: String) throws {
        let manifest = try Self.modified { object in
            var record = try #require(object["guestFoundation"] as? [String: Any])
            record["compiler"] = compiler
            object["guestFoundation"] = record
        }
        try manifest.validate()
    }

    /// Rejects a Foundation record that escapes the payload, names another source or compiler,
    /// claims an unchanged archive, or lists members that cannot hold the locale change.
    ///
    /// - Parameter fault: The invalid Foundation metadata applied to the fixture record.
    /// - Throws: Fixture conversion fails.
    @Test(arguments: [
        "parent", "archive", "component", "directory", "revision", "compiler", "development",
        "patch", "unchanged", "empty", "duplicate", "locale", "member",
    ])
    func rejectsInvalidGuestFoundation(_ fault: String) throws {
        let manifest = try Self.modified { object in
            var record = try #require(object["guestFoundation"] as? [String: Any])
            switch fault {
            case "parent": record["path"] = "../libFoundationEssentials.a"
            case "archive": record["path"] = "usr/lib/libFoundationEssentials.so"
            case "component": record["component"] = "swift-corelibs-foundation"
            case "directory": record["sourcePath"] = "Sources/FoundationInternationalization"
            case "revision": record["revision"] = String(repeating: "1", count: 40)
            case "compiler": record["compiler"] = "Apple Swift version 6.3 (swift-6.3-RELEASE)"
            case "development":
                record["compiler"] = "Swift version 6.4-dev (LLVM 1234, Swift 5678)"
            case "patch": record["patchSHA256"] = "invalid"
            case "unchanged": record["sha256"] = record["replacedSHA256"]
            case "empty": record["members"] = [String]()
            case "duplicate":
                record["members"] = ["Locale_Cache.swift.obj", "Locale_Cache.swift.obj"]
            case "locale": record["members"] = ["Calendar.swift.obj"]
            default: record["members"] = ["Locale_Cache.swift.obj", "Locale/Locale.swift.obj"]
            }
            object["guestFoundation"] = record
        }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
    }

    /// Builds a builtins record whose source and compiler match the pinned LLVM revision.
    ///
    /// - Parameter revision: The pinned llvm-project revision from the lock file.
    /// - Returns: A valid record with placeholder digests.
    private static func guestBuiltins(revision: String) -> GuestBuiltins {
        GuestBuiltins(
            path: "swift.xctoolchain/usr/lib/swift_static/clang/lib/wasip1/"
                + "libclang_rt.builtins-wasm32.a",
            component: "llvm-project", revision: revision, sourcePath: "compiler-rt",
            buildType: "Release",
            compiler: "Apple clang version 21.0.0 "
                + "(https://github.com/swiftlang/llvm-project.git \(revision))",
            replacedSHA256: String(repeating: "a", count: 64),
            sha256: String(repeating: "b", count: 64), definedSymbols: 218,
        )
    }

    /// Builds a Foundation record whose source and compiler match the pinned inputs.
    ///
    /// - Parameter revision: The pinned swift-foundation revision from the lock file.
    /// - Returns: A valid record with placeholder digests.
    private static func guestFoundation(revision: String) -> GuestFoundation {
        GuestFoundation(
            path: "swift.xctoolchain/usr/lib/swift_static/wasi/libFoundationEssentials.a",
            component: "swift-foundation", revision: revision,
            sourcePath: "Sources/FoundationEssentials",
            patchSHA256: String(repeating: "c", count: 64),
            compiler: "Apple Swift version 6.4 (swift-6.4-RELEASE)",
            members: ["Locale.swift.obj", "Locale_Cache.swift.obj"],
            replacedSHA256: String(repeating: "a", count: 64),
            sha256: String(repeating: "b", count: 64),
        )
    }

    /// Builds schema 2 data through the same JSON boundary used by release consumers.
    ///
    /// - Parameter edit: An optional mutation applied after converting every framework.
    /// - Returns: The decoded manifest, which may intentionally contain invalid metadata.
    /// - Throws: Fixture conversion or the requested mutation fails.
    private static func platformFixture(
        _ edit: (inout [String: Any]) throws -> Void = { _ in },
    ) throws -> ArtifactManifest {
        try modified { object in
            object["schemaVersion"] = 2
            var artifacts = try #require(object["artifacts"] as? [[String: Any]])
            for index in artifacts.indices {
                artifacts[index].removeValue(forKey: "binaryChecksum")
                artifacts[index].removeValue(forKey: "binaryBytes")
                artifacts[index]["slices"] = ["", "-simulator"].map { suffix in
                    [
                        "identifier": "ios-arm64" + suffix,
                        "compilerHost": "arm64-apple-ios18.0" + suffix,
                        "binaryChecksum": String(repeating: "e", count: 64),
                        "binaryBytes": 200,
                    ] as [String: Any]
                }
            }
            object["artifacts"] = artifacts
            try edit(&object)
        }
    }

    /// Fixture mutation preserves the decoder boundary used by release manifest consumers.
    private static func modified(_ edit: (inout [String: Any]) throws -> Void) throws
        -> ArtifactManifest {
        let data = try JSONEncoder().encode(fixture())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try edit(&object)
        return try JSONDecoder().decode(
            ArtifactManifest.self,
            from: JSONSerialization.data(withJSONObject: object),
        )
    }

    /// Current pinned inputs prevent fixture data from silently diverging from supported compiler
    /// releases.
    private static func fixture() throws -> ArtifactManifest {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let inputs = try ToolchainConfiguration
            .load(from: root.appending(path: "Toolchain.lock.json"))
        let llvmRevision = try #require(inputs.sources.first { $0.name == "llvm-project" }).revision
        let foundationRevision = try #require(
            inputs.sources.first { $0.name == "swift-foundation" },
        ).revision
        let names = [
            "SwiftCompilerBridge",
            "SwiftCompilerSDK",
            "SwiftInProcPluginServer",
            "_CompilerSwiftLibraryPluginProvider",
            "ObservationMacros",
            "SwiftMacros",
            "FoundationMacros",
        ]
        return ArtifactManifest(
            schemaVersion: 1, version: "0.1.0", bridgeABI: 1,
            compilerHost: inputs.compilerHost, programTarget: inputs.programTarget,
            configurationSHA256: String(repeating: "a", count: 64),
            frontendPatchSHA256: String(repeating: "b", count: 64),
            filesystemMetadataPatchSHA256: String(repeating: "c", count: 64),
            restrictedSwiftPatchSHA256: String(repeating: "d", count: 64),
            restrictedLLVMPatchSHA256: String(repeating: "e", count: 64),
            bundledMacroPatchSHA256: String(repeating: "f", count: 64),
            webAssemblyStackifyPatchSHA256: String(repeating: "a", count: 64),
            macroPatchSHA256: String(repeating: "c", count: 64),
            predicateStringComparisonsPatchSHA256: String(repeating: "d", count: 64),
            producerRevision: String(repeating: "a", count: 40),
            producerHasUncommittedChanges: false,
            noticesSHA256: String(repeating: "b", count: 64), macroAdapterSHA256: String(
                repeating: "c",
                count: 64,
            ), nativeCompiler: "AppleClang 21.0.0.21000123",
            guestBuiltins: guestBuiltins(revision: llvmRevision),
            guestFoundation: guestFoundation(revision: foundationRevision), inputs: inputs,
            macroBuildSupport: MacroBuildSupport(
                archive: "MacroBuildSupport.zip",
                checksum: String(repeating: "f", count: 64),
                archiveBytes: 100,
            ),
            artifacts: names.map { name in
                CompilerArtifact(
                    name: name,
                    archive: "\(name).zip",
                    checksum: String(repeating: "d", count: 64),
                    archiveBytes: 100,
                    binaryChecksum: String(repeating: "e", count: 64),
                    binaryBytes: 200, slices: nil,
                )
            },
        )
    }
}
