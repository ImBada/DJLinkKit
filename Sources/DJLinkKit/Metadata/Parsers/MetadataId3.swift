extension MetadataConnect {
    /// ID3v2 frame IDs for metadata extraction
    private enum FrameIds {
        // Text frames
        static let title = ["TIT2", "TT2"] // Title
        static let artist = ["TPE1", "TP1"] // Lead artist
        static let album = ["TALB", "TAL"] // Album
        static let genre = ["TCON", "TCO"] // Genre
        static let label = ["TPUB", "TPB"] // Publisher (the record label)
        static let year = ["TYER", "TYE", "TDRC"] // Year (TYER for v2.3, TDRC for v2.4)
        static let bpm = ["TBPM", "TBP"] // BPM
        static let key = ["TKEY", "TKE"] // Musical key
        // Picture frame
        static let picture = ["APIC", "PIC"]
    }

    struct ArtworkResult {
        var data: [UInt8]
        var mimeType: ArtworkMimeType
        var pictureType: PictureType
        var width: Int?
        var height: Int?
    }

    /// Parse an APIC (attached picture) frame
    private static func parseApicFrame(_ data: [UInt8]) throws -> ArtworkResult? {
        if data.count < 4 { return nil }

        var offset = 0
        let encodingByte = Int(data[offset])
        offset += 1
        var encoding = getTextEncoding(encodingByte)

        // Check for BOM in UTF-16
        if encodingByte == 1 && data.count > offset + 2 {
            let bom = try data.readUInt16BE(offset)
            if bom == 0xfeff {
                encoding = .utf16be
            } else if bom == 0xfffe {
                encoding = .utf16le
            }
        }

        let mimeResult = readNullTerminatedString(data, offset, .latin1)
        let mimeType = mimeResult.value
        offset += mimeResult.bytesConsumed

        if offset >= data.count { return nil }

        let pictureType = PictureType(rawValue: Int(data[offset]))
        offset += 1
        if offset >= data.count { return nil }

        let descResult = readNullTerminatedString(data, offset, encoding)
        offset += descResult.bytesConsumed

        if offset >= data.count { return nil }

        let imageData = data.subarray(offset)
        if imageData.isEmpty { return nil }

        let detectedType = detectImageType(imageData)
        let finalMimeType: ArtworkMimeType = detectedType ?? (mimeType.contains("png") ? .png : .jpeg)

        return ArtworkResult(data: imageData, mimeType: finalMimeType, pictureType: pictureType)
    }

    /// Parse a text frame (TIT2, TPE1, etc.)
    private static func parseTextFrame(_ data: [UInt8]) throws -> String? {
        if data.count < 2 { return nil }

        let encodingByte = Int(data[0])
        var encoding = getTextEncoding(encodingByte)
        var offset = 1

        // Check for BOM in UTF-16
        if encodingByte == 1 && data.count > offset + 2 {
            let bom = try data.readUInt16BE(offset)
            if bom == 0xfeff {
                encoding = .utf16be
                offset += 2
            } else if bom == 0xfffe {
                encoding = .utf16le
                offset += 2
            }
        }

        // Read until null terminator or end of data
        let textData = data.subarray(offset)

        if encoding.isUtf16 {
            // Find null terminator (two zeros)
            var end = textData.count
            var i = 0
            while i < textData.count - 1 {
                if textData[i] == 0 && textData[i + 1] == 0 {
                    end = i
                    break
                }
                i += 2
            }

            // utf16be는 바이트를 맞바꿔 utf16le로 읽는 것과 같다(`TextEncoding.nodeEncoding`)
            return cleanText(textData.toString(encoding.nodeEncoding, 0, end))
        }

        // Latin1 or UTF-8
        var end = textData.indexOf(0)
        if end == -1 { end = textData.count }
        return cleanText(textData.toString(encoding.nodeEncoding, 0, end))
    }

    /// Check if a frame ID matches any of the target IDs
    // PLAN §9: 원본은 `startsWith`로 앞부분만 비교해 TCOM·TCOP이 장르(TCO)로 읽혔다. 프레임 ID 전체를 비교한다.
    private static func matchesFrameId(_ frameId: String, _ targets: [String]) -> Bool {
        targets.contains(frameId)
    }

    /// Extract metadata from an MP3 file with ID3v2 tags
    public static func extractFromMp3(_ reader: any FileReader) async throws -> ExtractedMetadata? {
        // Read ID3v2 header (10 bytes)
        let header = try await reader.read(0, 10)
        if header.count < 10 || header.toString(.ascii, 0, 3) != "ID3" {
            return nil
        }

        let majorVersion = Int(header[3])
        let flags = Int(header[5])
        let tagSize = readSyncsafe(header, 6)

        // Handle extended header if present
        var extendedHeaderSize = 0
        if flags & 0x40 != 0 {
            let extHeader = try await reader.read(10, 4)
            if majorVersion == 4 {
                extendedHeaderSize = readSyncsafe(extHeader, 0)
            } else {
                extendedHeaderSize = try extHeader.readUInt32BE(0)
            }
        }

        // Read all tag data
        let tagData = try await reader.read(10 + extendedHeaderSize, tagSize - extendedHeaderSize)

        var metadata = ExtractedMetadata()
        var frontCover: ArtworkResult?
        var anyArtwork: ArtworkResult?

        // Parse frames
        var offset = 0
        let frameHeaderSize = majorVersion >= 3 ? 10 : 6

        while offset < tagData.count - frameHeaderSize {
            // End of frames (padding starts with zero)
            if tagData[offset] == 0 { break }

            let frameId: String
            let frameSize: Int

            if majorVersion >= 3 {
                // ID3v2.3 or ID3v2.4
                frameId = tagData.toString(.ascii, offset, offset + 4)
                if majorVersion == 4 {
                    frameSize = readSyncsafe(tagData, offset + 4)
                } else {
                    frameSize = try tagData.readUInt32BE(offset + 4)
                }
            } else {
                // ID3v2.2
                frameId = tagData.toString(.ascii, offset, offset + 3)
                frameSize = (Int(tagData[offset + 3]) << 16) | (Int(tagData[offset + 4]) << 8) | Int(tagData[offset + 5])
            }

            if frameSize <= 0 || frameSize > tagData.count - offset { break }

            let frameData = tagData.subarray(
                offset + frameHeaderSize,
                offset + frameHeaderSize + frameSize
            )

            // Normalize v2.2 frame IDs to v2.3/4 equivalents
            let normalizedId = majorVersion >= 3 ? frameId : normalizeV22FrameId(frameId)

            // Extract metadata from text frames
            if matchesFrameId(normalizedId, FrameIds.title) {
                if metadata.title == nil { metadata.title = try parseTextFrame(frameData) }
            } else if matchesFrameId(normalizedId, FrameIds.artist) {
                if metadata.artist == nil { metadata.artist = try parseTextFrame(frameData) }
            } else if matchesFrameId(normalizedId, FrameIds.album) {
                if metadata.album == nil { metadata.album = try parseTextFrame(frameData) }
            } else if matchesFrameId(normalizedId, FrameIds.genre) {
                if metadata.genre == nil { metadata.genre = try parseGenre(parseTextFrame(frameData)) }
            } else if matchesFrameId(normalizedId, FrameIds.label) {
                if metadata.label == nil { metadata.label = try parseTextFrame(frameData) }
            } else if matchesFrameId(normalizedId, FrameIds.year) {
                if metadata.year == nil { metadata.year = try parseYear(parseTextFrame(frameData) ?? "") }
            } else if matchesFrameId(normalizedId, FrameIds.bpm) {
                if metadata.bpm == nil { metadata.bpm = try parseBpm(parseTextFrame(frameData) ?? "") }
            } else if matchesFrameId(normalizedId, FrameIds.key) {
                if metadata.key == nil { metadata.key = try parseTextFrame(frameData) }
            } else if matchesFrameId(normalizedId, FrameIds.picture) {
                if let artwork = try parseApicFrame(frameData) {
                    if artwork.pictureType == .frontCover {
                        frontCover = artwork
                    } else if anyArtwork == nil {
                        anyArtwork = artwork
                    }
                }
            }

            offset += frameHeaderSize + frameSize
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

    /// Normalize ID3v2.2 frame IDs to v2.3/4 equivalents
    private static func normalizeV22FrameId(_ frameId: String) -> String {
        let mapping: [String: String] = [
            "TT2": "TIT2", // Title
            "TP1": "TPE1", // Artist
            "TAL": "TALB", // Album
            "TCO": "TCON", // Genre
            "TPB": "TPUB", // Publisher
            "TYE": "TYER", // Year
            "TBP": "TBPM", // BPM
            "TKE": "TKEY", // Key
            "PIC": "APIC", // Picture
        ]
        return mapping[frameId] ?? frameId
    }

    /// Parse genre string, handling ID3v1 numeric references
    /// Format: "(17)Rock" or "(17)" or "Rock"
    private static func parseGenre(_ genre: String?) -> String? {
        guard let genre, !genre.isEmpty else { return nil }

        // Check for ID3v1 numeric reference: /^\((\d+)\)(.*)$/
        let scalars = Array(genre.unicodeScalars)
        if scalars.first == "(" {
            var i = 1
            while i < scalars.count && isAsciiDigit(scalars[i]) { i += 1 }
            // 숫자가 하나 이상이고 ')'로 닫혀야 한다. `.*`는 줄 끝 문자를 넘지 못한다.
            if i > 1, i < scalars.count, scalars[i] == ")" {
                let rest = scalars[(i + 1)...]
                let hasLineTerminator = rest.contains { [0x0a, 0x0d, 0x2028, 0x2029].contains($0.value) }
                if !hasLineTerminator {
                    let id = Int(String(String.UnicodeScalarView(scalars[1..<i])))
                    let textGenre = jsTrim(String(String.UnicodeScalarView(rest)))
                    // If there's text after the number, use that
                    if !textGenre.isEmpty { return textGenre }
                    // Otherwise look up the ID3v1 genre
                    if let id, let name = id3v1Genre(id) { return name }
                    return genre
                }
            }
        }

        return genre
    }

    /// ID3v1 genre list
    static func id3v1Genre(_ id: Int) -> String? {
        id >= 0 && id < ID3V1_GENRES.count ? ID3V1_GENRES[id] : nil
    }

    private static let ID3V1_GENRES: [String] = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal",
        "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial",
        "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk",
        "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise",
        "Alternative Rock", "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic",
        "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native US", "Cabaret", "New Wave", "Psychedelic", "Rave", "Showtunes",
        "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll", "Hard Rock",
    ]
}
