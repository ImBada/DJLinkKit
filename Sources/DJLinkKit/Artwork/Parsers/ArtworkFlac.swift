private enum MetadataBlockType {
    static let STREAMINFO = 0
    static let PICTURE = 6
}

private func parsePictureBlock(_ data: [UInt8]) throws -> ExtractedArtwork? {
    if data.count < 32 {
        return nil
    }

    var offset = 0

    let pictureType = PictureType(rawValue: try data.readUInt32BE(offset))
    offset += 4

    let mimeLength = try data.readUInt32BE(offset)
    offset += 4

    if offset + mimeLength > data.count {
        return nil
    }

    let mimeType = data.toString(.utf8, offset, offset + mimeLength)
    offset += mimeLength

    let descLength = try data.readUInt32BE(offset)
    offset += 4 + descLength

    if offset + 16 > data.count {
        return nil
    }

    let width = try data.readUInt32BE(offset)
    offset += 4

    let height = try data.readUInt32BE(offset)
    offset += 4 + 8 // Skip depth and colors

    let imageLength = try data.readUInt32BE(offset)
    offset += 4

    if offset + imageLength > data.count {
        return nil
    }

    let imageData = data.subarray(offset, offset + imageLength)
    if imageData.isEmpty {
        return nil
    }

    return ExtractedArtwork(
        data: imageData,
        mimeType: normalizeMimeType(mimeType),
        width: width > 0 ? width : nil,
        height: height > 0 ? height : nil,
        pictureType: pictureType
    )
}

func extractFromFlac(_ reader: any ArtworkFileReader) async throws -> ExtractedArtwork? {
    let signature = try await reader.read(0, 4)
    if signature.toString(.ascii) != "fLaC" {
        return nil
    }

    var offset = 4
    var isLastBlock = false

    var frontCover: ExtractedArtwork?
    var anyArtwork: ExtractedArtwork?

    while !isLastBlock && offset < reader.size {
        let blockHeader = try await reader.read(offset, 4)
        if blockHeader.count < 4 {
            break
        }

        isLastBlock = (blockHeader[0] & 0x80) != 0
        let blockType = Int(blockHeader[0] & 0x7f)
        let blockLength = (Int(blockHeader[1]) << 16) | (Int(blockHeader[2]) << 8) | Int(blockHeader[3])

        if blockLength <= 0 || offset + 4 + blockLength > reader.size {
            break
        }

        if blockType == MetadataBlockType.PICTURE {
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

    return frontCover ?? anyArtwork
}
