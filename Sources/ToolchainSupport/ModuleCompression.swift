package import Foundation
#if canImport(Compression)
    import Compression
#endif

/// An LZFSE module codec used by artifact packaging and independent archive verification.
package enum ModuleCompression {
    /// Decoding accepts at most 128 MiB per module so corrupt metadata cannot request unbounded
    /// output.
    package static let maximumDecodedBytes = 128 * 1024 * 1024

    /// Compresses one serialized module without changing the bytes restored by consumers.
    ///
    /// - Parameter module: Nonempty module bytes, limited to `maximumDecodedBytes`.
    /// - Returns: The binary LZFSE representation stored as a compiler resource.
    /// - Throws: `ToolchainError.invalidArtifact` when the input size is invalid, compression
    /// fails,
    ///   or the host lacks Apple's Compression framework.
    package static func encode(_ module: Data) throws(ToolchainError) -> Data {
        guard !module.isEmpty, module.count <= maximumDecodedBytes else {
            throw .invalidArtifact("A serialized module must contain between 1 byte and 128 MiB.")
        }
        #if canImport(Compression)
            do {
                return try (module as NSData).compressed(using: .lzfse) as Data
            } catch {
                throw .invalidArtifact("The serialized module could not be compressed with LZFSE.")
            }
        #else
            throw .invalidArtifact("LZFSE module processing requires an Apple platform.")
        #endif
    }

    /// Restores one module within the output size declared by its packaging metadata.
    ///
    /// Callers compare the restored bytes with the module's recorded content digest.
    ///
    /// - Parameters:
    ///   - encoded: The nonempty LZFSE representation from the artifact.
    ///   - expectedByteCount: The exact restored size in bytes, from 1 through
    /// `maximumDecodedBytes`.
    /// - Returns: Decoded bytes whose count equals the declared size.
    /// - Throws: `ToolchainError.invalidArtifact` for unsupported hosts, invalid sizes, malformed
    ///   compressed data, or output that does not match the declared size.
    package static func decode(
        _ encoded: Data,
        expectedByteCount: Int,
    ) throws(ToolchainError) -> Data {
        guard !encoded.isEmpty, expectedByteCount > 0,
              expectedByteCount <= maximumDecodedBytes else {
            throw .invalidArtifact("A serialized module must declare between 1 byte and 128 MiB.")
        }
        #if canImport(Compression)
            // One spare byte distinguishes exact output from a decoder that filled a smaller
            // buffer.
            var decoded = Data(count: expectedByteCount + 1)
            let count = decoded.withUnsafeMutableBytes { output in
                encoded.withUnsafeBytes { input in
                    guard let destination = output.bindMemory(to: UInt8.self).baseAddress,
                          let source = input.bindMemory(to: UInt8.self).baseAddress
                    else { return 0 }
                    return compression_decode_buffer(
                        destination, output.count, source, input.count, nil, COMPRESSION_LZFSE,
                    )
                }
            }
            guard count == expectedByteCount else {
                throw .invalidArtifact("The LZFSE module does not match its declared decoded size.")
            }
            decoded.count = count
            return decoded
        #else
            throw .invalidArtifact("LZFSE module processing requires an Apple platform.")
        #endif
    }
}
