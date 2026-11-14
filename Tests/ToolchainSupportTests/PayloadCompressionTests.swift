import Foundation
import Testing
@testable import ToolchainSupport

#if canImport(Compression)
    /// Packaging preserves file contents while reducing repeated data.
    @Test func compressedFilesRestoreOriginalBytes() throws {
        let original = Data((0 ..< 65536).map { UInt8($0 % 251) })
        let encoded = try PayloadCompression.encode(original)
        #expect(encoded.count < original.count)
        #expect(try PayloadCompression
            .decode(encoded, expectedByteCount: original.count) == original)
    }

    /// Verifies that packaging accepts both inclusive payload file size boundaries.
    ///
    /// - Parameter count: The original and restored byte count, either 1 or the 128 MiB limit.
    /// - Throws: Compression or restoration failures while checking the accepted boundaries.
    @Test(arguments: [1, PayloadCompression.maximumDecodedBytes])
    func compressedFilesAcceptSizeBoundaries(count: Int) throws {
        let original = Data(repeating: 42, count: count)
        let encoded = try PayloadCompression.encode(original)
        #expect(try PayloadCompression.decode(encoded, expectedByteCount: count) == original)
    }

    /// An archive without members holds only its 8-byte signature, and the SDK ships several.
    @Test func compressedFilesRestoreEmptyStaticArchive() throws {
        let original = Data("!<arch>\n".utf8)
        let encoded = try PayloadCompression.encode(original)
        #expect(try PayloadCompression.decode(encoded, expectedByteCount: 8) == original)
    }

    /// A full output buffer must not make a truncated file look complete.
    @Test(arguments: [-1, 1])
    func compressedFilesRejectWrongDecodedSize(offset: Int) throws {
        let original = Data(repeating: 42, count: 4096)
        let encoded = try PayloadCompression.encode(original)
        #expect(throws: ToolchainError.invalidArtifact(
            "The LZFSE file does not match its declared decoded size.",
        )) {
            try PayloadCompression.decode(encoded, expectedByteCount: original.count + offset)
        }
    }

    /// Damaged LZFSE data must fail before archive verification can accept restored bytes.
    @Test func compressedFilesRejectMalformedData() throws {
        let original = Data(repeating: 42, count: 4096)
        let encoded = try PayloadCompression.encode(original)
        for invalid in [Data(encoded.dropLast(4)), Data(repeating: 255, count: encoded.count)] {
            #expect(throws: ToolchainError.invalidArtifact(
                "The LZFSE file does not match its declared decoded size.",
            )) {
                try PayloadCompression.decode(invalid, expectedByteCount: original.count)
            }
        }
    }

    /// Rejects encoded suffixes that leave the restored file bytes unchanged.
    @Test func compressedFilesRejectTrailingData() throws {
        let original = Data(repeating: 42, count: 4096)
        let encoded = try PayloadCompression.encode(original)
        for suffix in [Data([0]), encoded] {
            #expect(throws: ToolchainError.invalidArtifact(
                "The LZFSE file does not match its declared decoded size.",
            )) {
                try PayloadCompression.decode(encoded + suffix, expectedByteCount: original.count)
            }
        }
    }
#else
    /// Metadata-only hosts report unsupported compression without adding a substitute codec.
    @Test func compressedFilesRequireAppleCompression() throws {
        #expect(throws: ToolchainError.invalidArtifact(
            "LZFSE payload processing requires an Apple platform.",
        )) {
            try PayloadCompression.encode(Data([1]))
        }
    }
#endif

/// Invalid metadata is rejected before allocating a decompression buffer.
@Test(arguments: [0, -1, PayloadCompression.maximumDecodedBytes + 1])
func compressedFilesBoundDecodedSize(count: Int) throws {
    #expect(throws: ToolchainError.invalidArtifact(
        "A payload file must declare between 1 byte and 128 MiB.",
    )) {
        try PayloadCompression.decode(Data([1]), expectedByteCount: count)
    }
}

/// Empty input is not a payload file in either representation.
@Test func compressedFilesRejectEmptyInput() throws {
    #expect(throws: ToolchainError.invalidArtifact(
        "A payload file must contain between 1 byte and 128 MiB.",
    )) {
        try PayloadCompression.encode(Data())
    }
    #expect(throws: ToolchainError.invalidArtifact(
        "A payload file must declare between 1 byte and 128 MiB.",
    )) {
        try PayloadCompression.decode(Data(), expectedByteCount: 1)
    }
}
