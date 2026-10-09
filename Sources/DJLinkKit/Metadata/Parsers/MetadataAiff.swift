extension MetadataConnect {
    /// Extract metadata from an AIFF file
    ///
    /// AIFF files can contain ID3v2 tags in an 'ID3 ' chunk.
    /// We look for this chunk and delegate to the ID3 parser.
    public static func extractFromAiff(_ reader: any FileReader) async throws -> ExtractedMetadata? {
        // Read AIFF header (12 bytes minimum)
        let header = try await reader.read(0, 12)
        if header.count < 12 || header.toString(.ascii, 0, 4) != "FORM" {
            return nil
        }

        let formType = header.toString(.ascii, 8, 12)
        if formType != "AIFF" && formType != "AIFC" {
            return nil
        }

        let formSize = try header.readUInt32BE(4)
        let fileEnd = min(8 + formSize, reader.size)

        var offset = 12

        // Iterate through chunks looking for ID3 tag
        while offset + 8 < fileEnd {
            let chunkHeader = try await reader.read(offset, 8)
            if chunkHeader.count < 8 { break }

            let chunkId = chunkHeader.toString(.ascii, 0, 4)
            let chunkSize = try chunkHeader.readUInt32BE(4)

            if chunkSize <= 0 || offset + 8 + chunkSize > fileEnd { break }

            // Check for ID3 chunk (can be 'ID3 ' or 'id3 ')
            if chunkId == "ID3 " || chunkId == "id3 " {
                let id3Data = try await reader.read(offset + 8, chunkSize)
                let id3Reader = createBufferReader(id3Data, "mp3")
                return try await extractFromMp3(id3Reader)
            }

            // AIFF chunks are padded to even byte boundaries
            offset += 8 + chunkSize + (chunkSize % 2)
        }

        return nil
    }
}
