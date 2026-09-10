import Foundation
import Testing
@testable import ToolchainSupport

#if canImport(Compression)
    /// Packaging preserves module contents while reducing repeated serialized data.
    @Test func compressedModulesRestoreOriginalBytes() throws {
        let original = Data((0 ..< 65536).map { UInt8($0 % 251) })
        let encoded = try ModuleCompression.encode(original)
        #expect(encoded.count < original.count)
        #expect(try ModuleCompression
            .decode(encoded, expectedByteCount: original.count) == original)
    }

    /// A full output buffer must not make a truncated module look complete.
    @Test(arguments: [-1, 1])
    func compressedModulesRejectWrongDecodedSize(offset: Int) throws {
        let original = Data(repeating: 42, count: 4096)
        let encoded = try ModuleCompression.encode(original)
        #expect(throws: ToolchainError.invalidArtifact(
            "The LZFSE module does not match its declared decoded size.",
        )) {
            try ModuleCompression.decode(encoded, expectedByteCount: original.count + offset)
        }
    }

    /// Damaged LZFSE data must fail before archive verification can accept restored bytes.
    @Test func compressedModulesRejectMalformedData() throws {
        let original = Data(repeating: 42, count: 4096)
        let encoded = try ModuleCompression.encode(original)
        for invalid in [Data(encoded.dropLast(4)), Data(repeating: 255, count: encoded.count)] {
            #expect(throws: ToolchainError.invalidArtifact(
                "The LZFSE module does not match its declared decoded size.",
            )) {
                try ModuleCompression.decode(invalid, expectedByteCount: original.count)
            }
        }
    }
#else
    /// Metadata-only hosts report unsupported compression without adding a substitute codec.
    @Test func compressedModulesRequireAppleCompression() throws {
        #expect(throws: ToolchainError.invalidArtifact(
            "LZFSE module processing requires an Apple platform.",
        )) {
            try ModuleCompression.encode(Data([1]))
        }
    }
#endif

/// Invalid metadata is rejected before allocating a decompression buffer.
@Test(arguments: [0, -1, ModuleCompression.maximumDecodedBytes + 1])
func compressedModulesBoundDecodedSize(count: Int) throws {
    #expect(throws: ToolchainError.invalidArtifact(
        "A serialized module must declare between 1 byte and 128 MiB.",
    )) {
        try ModuleCompression.decode(Data([1]), expectedByteCount: count)
    }
}

/// Empty input is not a serialized Swift module in either representation.
@Test func compressedModulesRejectEmptyInput() throws {
    #expect(throws: ToolchainError.invalidArtifact(
        "A serialized module must contain between 1 byte and 128 MiB.",
    )) {
        try ModuleCompression.encode(Data())
    }
    #expect(throws: ToolchainError.invalidArtifact(
        "A serialized module must declare between 1 byte and 128 MiB.",
    )) {
        try ModuleCompression.decode(Data(), expectedByteCount: 1)
    }
}
