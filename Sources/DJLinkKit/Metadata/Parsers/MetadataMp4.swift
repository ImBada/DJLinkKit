extension MetadataConnect {
    /// MP4 atom header information
    private struct AtomHeader {
        var size: Int
        var type: String
        var headerSize: Int
    }

    /// MP4 atom location
    private struct AtomLocation {
        var dataOffset: Int
        var dataSize: Int
    }

    /// iTunes metadata atom types
    private enum AtomTypes {
        // 원본 주의: 'ascii'로 읽으면 상위 비트가 지워져 0xa9가 ')'가 되므로, 아래 '\xa9…' 이름들은 원본에서도 맞는 일이 없다.
        // 기반의 `.ascii`가 같은 방식이라 Swift에서도 그대로 맞지 않는다(1:1이라 그대로 둔다).
        static let TITLE = "\u{a9}nam" // Title
        static let ARTIST = "\u{a9}ART" // Artist
        static let ALBUM = "\u{a9}alb" // Album
        static let GENRE = "\u{a9}gen" // Genre (text)
        static let GENRE_ID = "gnre" // Genre (ID3v1 numeric)
        static let YEAR = "\u{a9}day" // Release date/year
        static let BPM = "tmpo" // BPM (tempo)
        static let COVER = "covr" // Cover artwork
        static let FREEFORM = "----" // Non-standard field, identified by its own name atom
        // Additional useful atoms
        static let ALBUM_ARTIST = "aART" // Album artist
        static let COMPOSER = "\u{a9}wrt" // Composer
        static let COMMENT = "\u{a9}cmt" // Comment
    }

    /// Read an MP4 atom header
    private static func readAtomHeader(_ reader: any FileReader, _ offset: Int) async throws -> AtomHeader? {
        if offset + 8 > reader.size { return nil }

        let header = try await reader.read(offset, 8)
        let size = try header.readUInt32BE(0)
        let type = header.toString(.ascii, 4, 8)

        // Extended size (64-bit)
        if size == 1 {
            if offset + 16 > reader.size { return nil }
            let extHeader = try await reader.read(offset + 8, 8)
            // 원본은 Number(bigint)(2^53 넘으면 근사값). Int로 옮기며 넘치지 않게 상한을 둔다.
            let extSize = Int(min(try extHeader.readBigUInt64BE(0), UInt64(Int.max / 4)))
            return AtomHeader(size: extSize, type: type, headerSize: 16)
        }

        // Size 0 means atom extends to end of file
        if size == 0 {
            return AtomHeader(size: reader.size - offset, type: type, headerSize: 8)
        }

        return AtomHeader(size: size, type: type, headerSize: 8)
    }

    /// Find an atom within a range
    private static func findAtom(
        _ reader: any FileReader,
        _ startOffset: Int,
        _ endOffset: Int,
        _ targetType: String
    ) async throws -> AtomLocation? {
        var offset = startOffset

        while offset < endOffset {
            guard let header = try await readAtomHeader(reader, offset), header.size > 0 else { break }

            if header.type == targetType {
                return AtomLocation(
                    dataOffset: offset + header.headerSize,
                    dataSize: header.size - header.headerSize
                )
            }

            offset += header.size
        }

        return nil
    }

    /// Find the moov atom (contains all metadata)
    private static func findMoovAtom(_ reader: any FileReader) async throws -> AtomLocation? {
        try await findAtom(reader, 0, reader.size, "moov")
    }

    /// Navigate to ilst (iTunes metadata list) atom
    /// Path: moov -> udta -> meta -> ilst
    private static func findIlstAtom(
        _ reader: any FileReader,
        _ moovOffset: Int,
        _ moovSize: Int
    ) async throws -> AtomLocation? {
        guard let udta = try await findAtom(reader, moovOffset, moovOffset + moovSize, "udta") else { return nil }

        guard let meta = try await findAtom(reader, udta.dataOffset, udta.dataOffset + udta.dataSize, "meta") else {
            return nil
        }

        // meta atom has 4 bytes of version/flags before child atoms
        let metaDataStart = meta.dataOffset + 4
        let metaDataEnd = meta.dataOffset + meta.dataSize

        return try await findAtom(reader, metaDataStart, metaDataEnd, "ilst")
    }

    /// Read a text data atom value
    private static func readTextDataAtom(
        _ reader: any FileReader,
        _ atomOffset: Int,
        _ atomSize: Int
    ) async throws -> String? {
        guard let data = try await findAtom(reader, atomOffset, atomOffset + atomSize, "data"), data.dataSize >= 8 else {
            return nil
        }

        // data atom: 4 bytes type + 4 bytes locale + actual data
        let content = try await reader.read(data.dataOffset + 8, data.dataSize - 8)
        return cleanText(content.toString(.utf8))
    }

    /// Read a numeric data atom value (for BPM, genre ID)
    private static func readNumericDataAtom(
        _ reader: any FileReader,
        _ atomOffset: Int,
        _ atomSize: Int
    ) async throws -> Int? {
        guard let data = try await findAtom(reader, atomOffset, atomOffset + atomSize, "data"), data.dataSize >= 10 else {
            return nil
        }

        // data atom: 4 bytes type + 4 bytes locale + actual data
        let content = try await reader.read(data.dataOffset + 8, data.dataSize - 8)

        // BPM is typically stored as 16-bit big-endian
        if content.count >= 2 {
            return try content.readUInt16BE(0)
        }

        return nil
    }

    /// Field names taggers use inside a freeform atom for the record label.
    private static let FREEFORM_LABEL_NAMES: Set<String> = ["LABEL", "PUBLISHER", "ORGANIZATION"]

    /// Read the field name out of an iTunes freeform ('----') atom.
    ///
    /// iTunes never standardised an atom for the record label, so taggers store it
    /// as a freeform atom instead: a 'mean' atom holding the namespace (normally
    /// com.apple.iTunes), a 'name' atom holding the field name, and the usual
    /// 'data' atom holding the value. Every freeform atom has the same type, so the
    /// name is the only thing that says which field this one is.
    private static func readFreeformName(
        _ reader: any FileReader,
        _ atomOffset: Int,
        _ atomSize: Int
    ) async throws -> String? {
        guard let name = try await findAtom(reader, atomOffset, atomOffset + atomSize, "name"), name.dataSize >= 4 else {
            return nil
        }

        // name atom: 4 bytes version/flags + the field name
        let content = try await reader.read(name.dataOffset + 4, name.dataSize - 4)
        return cleanText(content.toString(.utf8))
    }

    /// Read cover artwork from covr atom
    private static func readCoverArtwork(
        _ reader: any FileReader,
        _ atomOffset: Int,
        _ atomSize: Int
    ) async throws -> (data: [UInt8], mimeType: ArtworkMimeType)? {
        guard let data = try await findAtom(reader, atomOffset, atomOffset + atomSize, "data"), data.dataSize >= 8 else {
            return nil
        }

        let imageData = try await reader.read(data.dataOffset + 8, data.dataSize - 8)
        if imageData.isEmpty { return nil }

        let mimeType = detectImageType(imageData) ?? .jpeg
        return (imageData, mimeType)
    }

    /// Extract metadata from an MP4/M4A file
    public static func extractFromMp4(_ reader: any FileReader) async throws -> ExtractedMetadata? {
        // Verify this is an MP4 file by checking for ftyp atom
        let ftypHeader = try await reader.read(0, 8)
        if ftypHeader.count < 8 || ftypHeader.toString(.ascii, 4, 8) != "ftyp" {
            return nil
        }

        // Find moov atom
        guard let moov = try await findMoovAtom(reader) else { return nil }

        // Find ilst atom (iTunes metadata)
        guard let ilst = try await findIlstAtom(reader, moov.dataOffset, moov.dataSize) else { return nil }

        var metadata = ExtractedMetadata()
        // JS의 `Object.keys(metadata).length === 0`는 값이 undefined여도 키가 있으면 세지 않는다. 키가 생겼는지 따로 센다.
        var hasKeys = false

        // Iterate through ilst child atoms
        var offset = ilst.dataOffset
        let endOffset = ilst.dataOffset + ilst.dataSize

        while offset < endOffset {
            guard let header = try await readAtomHeader(reader, offset), header.size > 0 else { break }

            let atomType = header.type
            let atomDataOffset = offset + header.headerSize
            let atomDataSize = header.size - header.headerSize

            // Extract metadata based on atom type
            switch atomType {
            case AtomTypes.TITLE:
                hasKeys = true
                if metadata.title == nil { metadata.title = try await readTextDataAtom(reader, atomDataOffset, atomDataSize) }

            case AtomTypes.ARTIST:
                hasKeys = true
                if metadata.artist == nil { metadata.artist = try await readTextDataAtom(reader, atomDataOffset, atomDataSize) }

            case AtomTypes.ALBUM:
                hasKeys = true
                if metadata.album == nil { metadata.album = try await readTextDataAtom(reader, atomDataOffset, atomDataSize) }

            case AtomTypes.GENRE:
                let genre = try await readTextDataAtom(reader, atomDataOffset, atomDataSize)
                hasKeys = true
                if metadata.genre == nil { metadata.genre = genre }

            case AtomTypes.GENRE_ID:
                let genreId = try await readNumericDataAtom(reader, atomDataOffset, atomDataSize)
                if let genreId, metadata.genre == nil {
                    hasKeys = true
                    metadata.genre = id3v1Genre(genreId - 1) // MP4 genre IDs are 1-based
                }

            case AtomTypes.YEAR:
                let yearStr = try await readTextDataAtom(reader, atomDataOffset, atomDataSize)
                if let yearStr, metadata.year == nil, let year = firstFourDigits(yearStr) {
                    hasKeys = true
                    metadata.year = year
                }

            case AtomTypes.BPM:
                let bpm = try await readNumericDataAtom(reader, atomDataOffset, atomDataSize)
                if let bpm, bpm > 0, bpm < 500 {
                    hasKeys = true
                    if metadata.bpm == nil { metadata.bpm = Double(bpm) }
                }

            case AtomTypes.FREEFORM:
                if metadata.label != nil { break }
                let name = try await readFreeformName(reader, atomDataOffset, atomDataSize)
                if let name, FREEFORM_LABEL_NAMES.contains(name.uppercased()) {
                    hasKeys = true
                    metadata.label = try await readTextDataAtom(reader, atomDataOffset, atomDataSize)
                }

            case AtomTypes.COVER:
                if metadata.artwork == nil {
                    if let artwork = try await readCoverArtwork(reader, atomDataOffset, atomDataSize) {
                        hasKeys = true
                        metadata.artwork = artwork.data
                        metadata.artworkMimeType = artwork.mimeType
                    }
                }

            default:
                break
            }

            offset += header.size
        }

        // Return null if no metadata was found
        if !hasKeys {
            return nil
        }

        return metadata
    }
}
