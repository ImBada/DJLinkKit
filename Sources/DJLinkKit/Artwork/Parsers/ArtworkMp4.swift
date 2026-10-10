private struct AtomHeader {
    var size: Int
    var type: String
    var headerSize: Int
}

private struct AtomLocation {
    var dataOffset: Int
    var dataSize: Int
}

private func readAtomHeader(_ reader: any ArtworkFileReader, _ offset: Int) async throws -> AtomHeader? {
    if offset + 8 > reader.size {
        return nil
    }

    let header = try await reader.read(offset, 8)
    let size = try header.readUInt32BE(0)
    let type = header.toString(.ascii, 4, 8)

    if size == 1 {
        if offset + 16 > reader.size {
            return nil
        }
        let extHeader = try await reader.read(offset + 8, 8)
        // 원본은 Number(bigint)(2^53 넘으면 근사값). Int로 옮기며 넘치지 않게 상한을 둔다.
        let extSize = Int(min(try extHeader.readBigUInt64BE(0), UInt64(Int.max / 4)))
        return AtomHeader(size: extSize, type: type, headerSize: 16)
    }

    if size == 0 {
        return AtomHeader(size: reader.size - offset, type: type, headerSize: 8)
    }

    return AtomHeader(size: size, type: type, headerSize: 8)
}

private func findAtom(
    _ reader: any ArtworkFileReader,
    _ startOffset: Int,
    _ endOffset: Int,
    _ targetType: String
) async throws -> AtomLocation? {
    var offset = startOffset

    while offset < endOffset {
        guard let header = try await readAtomHeader(reader, offset), header.size > 0 else {
            break
        }

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

private func findMoovAtom(_ reader: any ArtworkFileReader) async throws -> AtomLocation? {
    try await findAtom(reader, 0, reader.size, "moov")
}

private func findCoverArtData(
    _ reader: any ArtworkFileReader,
    _ moovOffset: Int,
    _ moovSize: Int
) async throws -> [UInt8]? {
    guard let udta = try await findAtom(reader, moovOffset, moovOffset + moovSize, "udta") else {
        return nil
    }

    guard let meta = try await findAtom(
        reader,
        udta.dataOffset,
        udta.dataOffset + udta.dataSize,
        "meta"
    ) else {
        return nil
    }

    let metaDataStart = meta.dataOffset + 4
    let metaDataEnd = meta.dataOffset + meta.dataSize

    guard let ilst = try await findAtom(reader, metaDataStart, metaDataEnd, "ilst") else {
        return nil
    }

    guard let covr = try await findAtom(
        reader,
        ilst.dataOffset,
        ilst.dataOffset + ilst.dataSize,
        "covr"
    ) else {
        return nil
    }

    guard let data = try await findAtom(
        reader,
        covr.dataOffset,
        covr.dataOffset + covr.dataSize,
        "data"
    ), data.dataSize >= 8 else {
        return nil
    }

    return try await reader.read(data.dataOffset + 8, data.dataSize - 8)
}

func extractFromMp4(_ reader: any ArtworkFileReader) async throws -> ExtractedArtwork? {
    let ftypHeader = try await reader.read(0, 8)
    if ftypHeader.count < 8 || ftypHeader.toString(.ascii, 4, 8) != "ftyp" {
        return nil
    }

    guard let moov = try await findMoovAtom(reader) else {
        return nil
    }

    guard let imageData = try await findCoverArtData(reader, moov.dataOffset, moov.dataSize), !imageData.isEmpty else {
        return nil
    }

    let mimeType = detectImageType(imageData) ?? .jpeg

    return ExtractedArtwork(data: imageData, mimeType: mimeType, pictureType: .frontCover)
}
