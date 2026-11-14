import ArgumentParser
import Foundation
import ToolchainSupport

/// Payload file conversion used by packaging without invoking the native compiler.
struct PayloadCodecCommand: ParsableCommand {
    /// The codec operates on explicit files so CMake retains ownership of the artifact inventory.
    static let configuration = CommandConfiguration(
        commandName: "payload-codec",
        abstract: "Compress or restore one SDK payload file with LZFSE on an Apple platform.",
    )

    /// The conversion parsed by ArgumentParser and executed by `run()` on the input file.
    @Argument(help: "Select compress or decompress.")
    var operation: Operation

    /// The existing input path read by `run()` without changing the payload file or its encoding.
    @Argument(help: "Path to the existing input file.")
    var source: String

    /// A new output file prevents verification from replacing an existing payload file.
    @Argument(help: "Path to a new output file in an existing directory.")
    var destination: String

    /// Decompression bounds its allocation by the exact restored size from the payload record.
    @Option(help: "Exact restored byte count, required for decompression and limited to 128 MiB.")
    var decodedBytes: Int?

    /// Converts a packaging or verification input and writes a new file after the codec succeeds.
    ///
    /// - Throws: `ToolchainError.unreadableFile` when the source cannot be read, or
    ///   `ToolchainError.invalidArtifact` for conflicting arguments, output file errors,
    ///   or an unsupported platform, representation, or declared output size.
    mutating func run() throws(ToolchainError) {
        guard (operation == .decompress) == (decodedBytes != nil) else {
            throw .invalidArtifact("Provide --decoded-bytes only when decompressing a file.")
        }
        let input: Data
        do {
            input = try Data(contentsOf: URL(fileURLWithPath: source))
        } catch {
            throw .unreadableFile(source)
        }
        do {
            let output: Data
            switch operation {
            case .compress:
                output = try PayloadCompression.encode(input)
            case .decompress:
                guard let decodedBytes else {
                    throw ToolchainError.invalidArtifact("Declare the file's decoded byte count.")
                }
                output = try PayloadCompression.decode(input, expectedByteCount: decodedBytes)
            }
            try output.write(to: URL(fileURLWithPath: destination), options: .withoutOverwriting)
        } catch let error as ToolchainError {
            throw error
        } catch {
            throw .invalidArtifact("The payload files could not be processed. \(error)")
        }
    }

    /// A file conversion direction parsed by ArgumentParser independently of filename extensions.
    enum Operation: String, ExpressibleByArgument {
        /// Packaging stores an LZFSE representation of the original file.
        case compress
        /// Verification restores the file before checking its recorded digest.
        case decompress
    }
}
