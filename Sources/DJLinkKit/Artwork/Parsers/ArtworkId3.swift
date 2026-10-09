// 원본 주의: metadata-connect의 `readSyncsafe` 등과 이름이 같지만 이쪽은 이 파일 안에서만 쓰는 별도 사본이다.

/// 범위를 넘는 위치는 JS의 `undefined`처럼 0으로 본다(`undefined & 0x7f === 0`).
private func byteOrZero(_ buffer: [UInt8], _ index: Int) -> Int {
    index >= 0 && index < buffer.count ? Int(buffer[index]) : 0
}

private func readSyncsafe(_ buffer: [UInt8], _ offset: Int = 0) -> Int {
    ((byteOrZero(buffer, offset) & 0x7f) << 21)
        | ((byteOrZero(buffer, offset + 1) & 0x7f) << 14)
        | ((byteOrZero(buffer, offset + 2) & 0x7f) << 7)
        | (byteOrZero(buffer, offset + 3) & 0x7f)
}

private enum TextEncoding {
    case latin1
    case utf8
    case utf16le
    case utf16be

    var isUtf16: Bool { self == .utf16le || self == .utf16be }

    // Node에는 utf16be가 없어 원본은 바이트를 맞바꿔 utf16le로 읽는다. 기반의 `.utf16be`가 같은 결과를 낸다.
    var nodeEncoding: NodeEncoding {
        switch self {
        case .latin1: .latin1
        case .utf8: .utf8
        case .utf16le: .utf16le
        case .utf16be: .utf16be
        }
    }
}

private func readNullTerminatedString(
    _ buffer: [UInt8],
    _ offset: Int,
    _ encoding: TextEncoding
) -> (value: String, bytesConsumed: Int) {
    let isUtf16 = encoding.isUtf16
    var end = offset

    if isUtf16 {
        while end < buffer.count - 1 {
            if buffer[end] == 0 && buffer[end + 1] == 0 {
                break
            }
            end += 2
        }
    } else {
        while end < buffer.count && buffer[end] != 0 {
            end += 1
        }
    }

    let value = buffer.toString(encoding.nodeEncoding, offset, end)
    return (value, end - offset + (isUtf16 ? 2 : 1))
}

private func getTextEncoding(_ encodingByte: Int) -> TextEncoding {
    switch encodingByte {
    case 0: .latin1
    case 1: .utf16le
    case 2: .utf16be
    case 3: .utf8
    default: .latin1
    }
}

private func parseApicFrame(_ data: [UInt8]) throws -> ExtractedArtwork? {
    if data.count < 4 {
        return nil
    }

    var offset = 0
    let encodingByte = Int(data[offset])
    offset += 1
    var encoding = getTextEncoding(encodingByte)

    let mimeResult = readNullTerminatedString(data, offset, .latin1)
    let mimeType = mimeResult.value
    offset += mimeResult.bytesConsumed

    if offset >= data.count {
        return nil
    }

    let pictureType = PictureType(rawValue: Int(data[offset]))
    offset += 1
    if offset >= data.count {
        return nil
    }

    // PLAN §9: 원본은 인코딩 바이트 바로 뒤(MIME 문자열)에서 BOM을 찾았다. BOM은 설명 문자열 앞에 있다.
    if encodingByte == 1 && data.count > offset + 2 {
        let bom = try data.readUInt16BE(offset)
        if bom == 0xfeff {
            encoding = .utf16be
        } else if bom == 0xfffe {
            encoding = .utf16le
        }
    }

    let descResult = readNullTerminatedString(data, offset, encoding)
    offset += descResult.bytesConsumed

    if offset >= data.count {
        return nil
    }

    let imageData = data.subarray(offset)
    if imageData.isEmpty {
        return nil
    }

    let detectedType = detectImageType(imageData)
    let finalMimeType = detectedType ?? (mimeType.contains("png") ? .png : .jpeg)

    return ExtractedArtwork(data: imageData, mimeType: finalMimeType, pictureType: pictureType)
}

func extractFromMp3(_ reader: any ArtworkFileReader) async throws -> ExtractedArtwork? {
    let header = try await reader.read(0, 10)
    if header.count < 10 || header.toString(.ascii, 0, 3) != "ID3" {
        return nil
    }

    let majorVersion = Int(header[3])
    let flags = Int(header[5])
    let tagSize = readSyncsafe(header, 6)

    var extendedHeaderSize = 0
    if flags & 0x40 != 0 {
        let extHeader = try await reader.read(10, 4)
        if majorVersion == 4 {
            extendedHeaderSize = readSyncsafe(extHeader, 0)
        } else {
            // PLAN §9: v2.3의 확장 헤더 크기는 크기 칸 4바이트를 뺀 값이다(v2.4는 크기 칸을 포함한다).
            extendedHeaderSize = try extHeader.readUInt32BE(0) + 4
        }
    }

    let tagData = try await reader.read(
        10 + extendedHeaderSize,
        tagSize - extendedHeaderSize
    )

    var offset = 0
    let frameHeaderSize = majorVersion >= 3 ? 10 : 6

    var frontCover: ExtractedArtwork?
    var anyArtwork: ExtractedArtwork?

    while offset < tagData.count - frameHeaderSize {
        if tagData[offset] == 0 {
            break
        }

        let frameId: String
        let frameSize: Int

        if majorVersion >= 3 {
            frameId = tagData.toString(.ascii, offset, offset + 4)
            if majorVersion == 4 {
                frameSize = readSyncsafe(tagData, offset + 4)
            } else {
                frameSize = try tagData.readUInt32BE(offset + 4)
            }
        } else {
            frameId = tagData.toString(.ascii, offset, offset + 3)
            frameSize = (Int(tagData[offset + 3]) << 16) | (Int(tagData[offset + 4]) << 8) | Int(tagData[offset + 5])
        }

        if frameSize <= 0 || frameSize > tagData.count - offset {
            break
        }

        let frameIdNormalized = majorVersion >= 3 ? frameId : (frameId == "PIC" ? "APIC" : frameId)

        if frameIdNormalized == "APIC" {
            let frameData = tagData.subarray(
                offset + frameHeaderSize,
                offset + frameHeaderSize + frameSize
            )
            let artwork = try parseApicFrame(frameData)

            if let artwork {
                if artwork.pictureType == .frontCover {
                    frontCover = artwork
                } else if anyArtwork == nil {
                    anyArtwork = artwork
                }
            }
        }

        offset += frameHeaderSize + frameSize
    }

    return frontCover ?? anyArtwork
}
