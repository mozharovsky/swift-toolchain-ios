package import Foundation
#if canImport(Compression)
    import Compression
#endif

/// An LZFSE module codec used by artifact packaging and independent archive verification.
///
/// Both operations require Apple's Compression framework. Original and restored modules must
/// contain 1 byte through `maximumDecodedBytes`. Invalid bounds, unsupported hosts, and codec
/// failures use `ToolchainError.invalidArtifact`. Callers verify the original digest after
/// decoding.
package enum ModuleCompression {
    /// The 128 MiB output limit enforced by packaging and archive verification for each module.
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
    ///   compressed data, trailing bytes, or output that does not match the declared size.
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
                    var stream = compression_stream(
                        dst_ptr: destination, dst_size: 0, src_ptr: source, src_size: 0, state: nil,
                    )
                    guard compression_stream_init(
                        &stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZFSE,
                    ) == COMPRESSION_STATUS_OK else { return 0 }
                    defer { compression_stream_destroy(&stream) }
                    stream.dst_ptr = destination
                    stream.dst_size = output.count
                    stream.src_ptr = source
                    // Holding back one byte exposes an early end despite the decoder's input
                    // buffering.
                    stream.src_size = input.count - 1
                    guard compression_stream_process(&stream, 0) == COMPRESSION_STATUS_OK
                    else { return 0 }
                    stream.src_size += 1
                    let status = compression_stream_process(
                        &stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue),
                    )
                    guard status == COMPRESSION_STATUS_END, stream.src_size == 0 else { return 0 }
                    return output.count - stream.dst_size
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
