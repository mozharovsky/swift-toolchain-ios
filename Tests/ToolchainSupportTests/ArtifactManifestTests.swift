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
            binaryChecksum: String(repeating: "b", count: 64), binaryBytes: 30,
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

    /// Digests with the right length still fail when they contain non-hexadecimal bytes.
    @Test func rejectsInvalidDigest() throws {
        let manifest = try Self.modified { object in object["macroPatchSHA256"] = String(
            repeating: "z",
            count: 64,
        ) }
        #expect(throws: ToolchainError.self) { try manifest.validate() }
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
        let names = [
            "SwiftCompilerBridge",
            "SwiftCompilerSDK",
            "SwiftInProcPluginServer",
            "SwiftLibraryPluginProvider",
            "ObservationMacros",
            "SwiftMacros",
        ]
        return ArtifactManifest(
            schemaVersion: 1, version: "0.1.0", bridgeABI: 1,
            compilerHost: inputs.compilerHost, programTarget: inputs.programTarget,
            configurationSHA256: String(repeating: "a", count: 64),
            frontendPatchSHA256: String(repeating: "b", count: 64),
            macroPatchSHA256: String(repeating: "c", count: 64),
            producerRevision: String(repeating: "a", count: 40),
            producerHasUncommittedChanges: false,
            noticesSHA256: String(repeating: "b", count: 64), macroAdapterSHA256: String(
                repeating: "c",
                count: 64,
            ), inputs: inputs,
            artifacts: names.map { name in
                CompilerArtifact(
                    name: name,
                    archive: "\(name).zip",
                    checksum: String(repeating: "d", count: 64),
                    archiveBytes: 100,
                    binaryChecksum: String(repeating: "e", count: 64),
                    binaryBytes: 200,
                )
            },
        )
    }
}
