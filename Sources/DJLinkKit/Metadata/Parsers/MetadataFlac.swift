extension MetadataConnect {
    /// FLAC metadata block types
    private enum MetadataBlockType {
        static let STREAMINFO = 0
        static let PADDING = 1
        static let APPLICATION = 2
        static let SEEKTABLE = 3
        static let VORBIS_COMMENT = 4
        static let CUESHEET = 5
        static let PICTURE = 6
    }

    /// Vorbis comment field names (case-insensitive)
    private enum VorbisFields {
        static let title = ["TITLE"]
        static let artist = ["ARTIST"]
        static let album = ["ALBUM"]
        static let genre = ["GENRE"]
        // Vorbis never standardised a label field, so taggers picked their own:
        // ORGANIZATION is the one the spec suggests for the producing entity, and
        // LABEL/PUBLISHER are what everything from Picard to Mixed In Key writes.
        static let label = ["LABEL", "PUBLISHER", "ORGANIZATION", "ORGANISATION"]
        static let date = ["DATE", "YEAR"]
        static let bpm = ["BPM", "TEMPO"]
        static let key = ["KEY", "INITIALKEY"]
    }

    /// Parse a FLAC PICTURE metadata block
    private static func parsePictureBlock(_ data: [UInt8]) throws -> ArtworkResult? {
        if data.count < 32 { return nil }

        var offset = 0

        let pictureType = PictureType(rawValue: try data.readUInt32BE(offset))
        offset += 4

        let mimeLength = try data.readUInt32BE(offset)
        offset += 4

        if offset + mimeLength > data.count { return nil }

        let mimeType = data.toString(.utf8, offset, offset + mimeLength)
        offset += mimeLength

        let descLength = try data.readUInt32BE(offset)
        offset += 4 + descLength

        if offset + 16 > data.count { return nil }

        let width = try data.readUInt32BE(offset)
        offset += 4

        let height = try data.readUInt32BE(offset)
        offset += 4 + 8 // Skip depth and colors

        let imageLength = try data.readUInt32BE(offset)
        offset += 4

        if offset + imageLength > data.count { return nil }

        let imageData = data.subarray(offset, offset + imageLength)
        if imageData.isEmpty { return nil }

        return ArtworkResult(
            data: imageData,
            mimeType: normalizeMimeType(mimeType),
            pictureType: pictureType,
            width: width > 0 ? width : nil,
            height: height > 0 ? height : nil
        )
    }

    /// Parse a Vorbis comment block
    /// Format: vendor string length (32-bit LE) + vendor string + comment count (32-bit LE) + comments
    /// Each comment: length (32-bit LE) + "FIELD=value"
    private static func parseVorbisCommentBlock(_ data: [UInt8]) throws -> [String: String] {
        var comments: [String: String] = [:]

        if data.count < 8 { return comments }

        var offset = 0

        // Skip vendor string
        let vendorLength = try data.readUInt32LE(offset)
        offset += 4 + vendorLength

        if offset + 4 > data.count { return comments }

        // Read comment count
        let commentCount = try data.readUInt32LE(offset)
        offset += 4

        // Read each comment
        var i = 0
        while i < commentCount && offset + 4 <= data.count {
            let commentLength = try data.readUInt32LE(offset)
            offset += 4

            if offset + commentLength > data.count { break }

            let comment = data.toString(.utf8, offset, offset + commentLength)
            offset += commentLength

            // Split on first '='
            let scalars = comment.unicodeScalars
            if let eqIndex = scalars.firstIndex(of: "="), eqIndex != scalars.startIndex {
                let field = String(scalars[scalars.startIndex..<eqIndex]).uppercased()
                let value = String(scalars[scalars.index(after: eqIndex)...])
                // Only store first value for each field
                if comments[field]?.isEmpty ?? true {
                    comments[field] = value
                }
            }
            i += 1
        }

        return comments
    }

    /// Match a Vorbis comment field name against known field names
    private static func getFieldValue(_ comments: [String: String], _ fieldNames: [String]) -> String? {
        for name in fieldNames {
            if let value = comments[name], !value.isEmpty { return cleanText(value) }
        }
        return nil
    }

    /// Extract metadata from a FLAC file
    public static func extractFromFlac(_ reader: any FileReader) async throws -> ExtractedMetadata? {
        // Verify FLAC signature
        let signature = try await reader.read(0, 4)
        if signature.toString(.ascii) != "fLaC" {
            return nil
        }

        var metadata = ExtractedMetadata()
        var frontCover: ArtworkResult?
        var anyArtwork: ArtworkResult?

        var offset = 4
        var isLastBlock = false

        while !isLastBlock && offset < reader.size {
            // Read metadata block header (4 bytes)
            let blockHeader = try await reader.read(offset, 4)
            if blockHeader.count < 4 { break }

            isLastBlock = (blockHeader[0] & 0x80) != 0
            let blockType = Int(blockHeader[0] & 0x7f)
            let blockLength = (Int(blockHeader[1]) << 16) | (Int(blockHeader[2]) << 8) | Int(blockHeader[3])

            if blockLength <= 0 || offset + 4 + blockLength > reader.size { break }

            // Process metadata blocks
            if blockType == MetadataBlockType.VORBIS_COMMENT {
                let commentData = try await reader.read(offset + 4, blockLength)
                let comments = try parseVorbisCommentBlock(commentData)

                // Extract metadata from Vorbis comments
                if metadata.title == nil { metadata.title = getFieldValue(comments, VorbisFields.title) }
                if metadata.artist == nil { metadata.artist = getFieldValue(comments, VorbisFields.artist) }
                if metadata.album == nil { metadata.album = getFieldValue(comments, VorbisFields.album) }
                if metadata.genre == nil { metadata.genre = getFieldValue(comments, VorbisFields.genre) }
                if metadata.label == nil { metadata.label = getFieldValue(comments, VorbisFields.label) }

                if let dateValue = getFieldValue(comments, VorbisFields.date), metadata.year == nil || metadata.year == 0 {
                    metadata.year = parseYear(dateValue)
                }

                if let bpmValue = getFieldValue(comments, VorbisFields.bpm), metadata.bpm == nil || metadata.bpm == 0 {
                    metadata.bpm = parseBpm(bpmValue)
                }

                if metadata.key == nil { metadata.key = getFieldValue(comments, VorbisFields.key) }
            } else if blockType == MetadataBlockType.PICTURE {
                let pictureData = try await reader.read(offset + 4, blockLength)
                let artwork = try parsePictureBlock(pictureData)

                if let artwork {
                    if artwork.pictureType == .frontCover {
                        frontCover = artwork
                    } else if anyArtwork == nil {
                        anyArtwork = artwork
                    }
                }
            }

            offset += 4 + blockLength
        }

        // Use front cover if available, otherwise any artwork
        if let artwork = frontCover ?? anyArtwork {
            metadata.artwork = artwork.data
            metadata.artworkMimeType = artwork.mimeType
        }

        // Return null if no metadata was found
        // PLAN §9: 원본은 `Object.keys(metadata).length === 0`이라 undefined 값의 키도 세어 값이 없어도 null이 아니었다.
        // 실제 값이 하나도 없으면 nil이다.
        if metadata == ExtractedMetadata() {
            return nil
        }

        return metadata
    }
}
