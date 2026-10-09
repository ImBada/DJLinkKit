extension MetadataConnect {
    struct BufferReader: FileReader {
        let buffer: [UInt8]
        let `extension`: String
        var size: Int { buffer.count }

        func read(_ offset: Int, _ length: Int) async throws -> [UInt8] {
            let end = min(offset + length, buffer.count)
            return buffer.subarray(offset, end)
        }
    }

    /// Create a FileReader from a Buffer (for testing or in-memory data)
    public static func createBufferReader(_ buffer: [UInt8], _ extension: String) -> any FileReader {
        BufferReader(buffer: buffer, extension: `extension`)
    }
}
