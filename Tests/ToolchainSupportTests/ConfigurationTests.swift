import Foundation
import Testing
@testable import ToolchainSupport

/// Configuration failures that would otherwise reach an expensive or incompatible compiler build.
struct ConfigurationTests {
    /// The checked-in configuration keeps the native host distinct from generated program targets.
    @Test func lockedInputsHaveDistinctArchitectures() throws {
        let configuration = try ToolchainConfiguration.load(from: Self.configurationURL)
        #expect(configuration.compilerHost == "arm64-apple-ios18.0")
        #expect(configuration.programTarget == "wasm32-unknown-wasip1")
        #expect(configuration.sources.count == 5)
    }

    /// A WASM host or native program target would invert the intended cross-compilation boundary.
    @Test(arguments: ["compilerHost", "programTarget"])
    func rejectsSwappedTargets(field: String) throws {
        let configuration = try Self.modified {
            $0[field] = field == "compilerHost" ? "wasm32-unknown-wasip1" : "arm64-apple-ios18.0"
        }
        #expect(throws: ToolchainError.self) { try configuration.validate() }
    }

    /// A new schema must introduce its semantics explicitly before the tooling accepts it.
    @Test func rejectsUnknownSchema() throws {
        let configuration = try Self.modified { $0["schemaVersion"] = 2 }
        #expect(throws: ToolchainError.self) { try configuration.validate() }
    }

    /// Branch names and abbreviated hashes cannot serve as immutable source identities.
    @Test(arguments: ["main", "swift-6.3.2-RELEASE", "1234567"])
    func rejectsMutableRevisions(revision: String) throws {
        let source = UpstreamSource(
            name: "swift", repository: "https://github.com/swiftlang/swift.git",
            revision: revision, license: "Apache-2.0 WITH Swift-exception",
        )
        #expect(throws: ToolchainError.self) { try source.validate() }
    }

    /// Embedded credentials and signed temporary URLs must not become public source pins.
    @Test(arguments: [
        "https://user:password@example.com/source.git",
        "https://example.com/source.git?token=temporary",
        "http://example.com/source.git",
    ])
    func rejectsCredentialURLs(repository: String) throws {
        let source = UpstreamSource(
            name: "source", repository: repository,
            revision: String(repeating: "a", count: 40), license: "Apache-2.0",
        )
        #expect(throws: ToolchainError.self) { try source.validate() }
    }

    /// Duplicate component identifiers would make source-directory ownership ambiguous.
    @Test func rejectsDuplicateSources() throws {
        let configuration = try Self.modified { object in
            var sources = try #require(object["sources"] as? [[String: Any]])
            try sources.append(#require(sources.first))
            object["sources"] = sources
        }
        #expect(throws: ToolchainError.self) { try configuration.validate() }
    }

    /// SDK versions and archive digests remain independently validated release inputs.
    @Test(arguments: ["version", "sha256", "url"])
    func rejectsInvalidSDK(field: String) throws {
        let configuration = try Self.modified { object in
            var sdk = try #require(object["sdk"] as? [String: Any])
            sdk[field] = "latest"
            object["sdk"] = sdk
        }
        #expect(throws: ToolchainError.self) { try configuration.validate() }
    }

    /// Fixture lookup exercises the repository's actual lock file without duplicating its pins.
    private static var configurationURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Toolchain.lock.json")
    }

    /// Mutation cases preserve unrelated fields so each failure isolates a release invariant.
    private static func modified(
        _ change: (inout [String: Any]) throws -> Void,
    ) throws -> ToolchainConfiguration {
        let data = try Data(contentsOf: configurationURL)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try change(&object)
        return try JSONDecoder().decode(
            ToolchainConfiguration.self, from: JSONSerialization.data(withJSONObject: object),
        )
    }
}
