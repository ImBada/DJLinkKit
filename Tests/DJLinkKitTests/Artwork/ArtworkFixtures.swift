import DJLinkKit
import Foundation

// 원본 tests/artwork/fixtures.ts

// Tiny 1x1 red JPEG image
let TINY_JPEG: [UInt8] = [
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00,
    0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06,
    0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d,
    0x0c, 0x0b, 0x0b, 0x0c, 0x19, 0x12, 0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d,
    0x1a, 0x1c, 0x1c, 0x20, 0x24, 0x2e, 0x27, 0x20, 0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28,
    0x37, 0x29, 0x2c, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1f, 0x27, 0x39, 0x3d, 0x38, 0x32,
    0x3c, 0x2e, 0x33, 0x34, 0x32, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01, 0x00, 0x01,
    0x01, 0x01, 0x11, 0x00, 0xff, 0xc4, 0x00, 0x1f, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02,
    0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0xff, 0xda, 0x00, 0x08, 0x01,
    0x01, 0x00, 0x00, 0x3f, 0x00, 0x7f, 0xff, 0xd9,
]

// Tiny 1x1 PNG image
let TINY_PNG: [UInt8] = [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48,
    0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00,
    0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41, 0x54, 0x08,
    0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0x00, 0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xfe,
    0xd4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]

private func writeSyncsafe(_ value: Int) -> [UInt8] {
    var buf = [UInt8].alloc(4)
    buf[0] = UInt8((value >> 21) & 0x7f)
    buf[1] = UInt8((value >> 14) & 0x7f)
    buf[2] = UInt8((value >> 7) & 0x7f)
    buf[3] = UInt8(value & 0x7f)
    return buf
}

func createMp3WithArtwork(_ imageData: [UInt8], _ pictureType: Int = 3) -> [UInt8] {
    let mimeType = [UInt8]("image/jpeg\0", encoding: .latin1)
    let description = [UInt8]("\0", encoding: .latin1)

    let apicPayload = [UInt8].concat([
        [0x00],
        mimeType,
        [UInt8(pictureType)],
        description,
        imageData,
    ])

    let apicFrame = [UInt8].concat([
        [UInt8]("APIC", encoding: .ascii),
        writeSyncsafe(apicPayload.count),
        [0x00, 0x00],
        apicPayload,
    ])

    let id3Header = [UInt8].concat([
        [UInt8]("ID3", encoding: .ascii),
        [0x04, 0x00],
        [0x00],
        writeSyncsafe(apicFrame.count),
    ])

    return id3Header + apicFrame
}

func createFlacWithArtwork(_ imageData: [UInt8], _ pictureType: Int = 3) -> [UInt8] {
    let mimeType = [UInt8]("image/jpeg", encoding: .utf8)

    var pictureData = [UInt8].alloc(32 + mimeType.count + imageData.count)
    var offset = 0

    pictureData.writeUInt32BE(pictureType, offset)
    offset += 4
    pictureData.writeUInt32BE(mimeType.count, offset)
    offset += 4
    pictureData.set(mimeType, offset)
    offset += mimeType.count
    pictureData.writeUInt32BE(0, offset)
    offset += 4
    pictureData.writeUInt32BE(1, offset)
    offset += 4
    pictureData.writeUInt32BE(1, offset)
    offset += 4
    pictureData.writeUInt32BE(24, offset)
    offset += 4
    pictureData.writeUInt32BE(0, offset)
    offset += 4
    pictureData.writeUInt32BE(imageData.count, offset)
    offset += 4
    pictureData.set(imageData, offset)

    let streaminfoData = [UInt8].alloc(34)
    var streaminfoHeader = [UInt8].alloc(4)
    streaminfoHeader[0] = 0x00
    streaminfoHeader[3] = 34

    var pictureHeader = [UInt8].alloc(4)
    pictureHeader[0] = 0x80 | 0x06
    pictureHeader[1] = UInt8((pictureData.count >> 16) & 0xff)
    pictureHeader[2] = UInt8((pictureData.count >> 8) & 0xff)
    pictureHeader[3] = UInt8(pictureData.count & 0xff)

    return [UInt8].concat([
        [UInt8]("fLaC", encoding: .ascii),
        streaminfoHeader,
        streaminfoData,
        pictureHeader,
        pictureData,
    ])
}

func createMp4WithArtwork(_ imageData: [UInt8]) -> [UInt8] {
    func createAtom(_ type: String, _ data: [UInt8]) -> [UInt8] {
        var header = [UInt8].alloc(8)
        header.writeUInt32BE(8 + data.count, 0)
        header.set([UInt8](type, encoding: .ascii), 4)
        return header + data
    }

    var dataContent = [UInt8].alloc(8 + imageData.count)
    dataContent.writeUInt32BE(13, 0)
    dataContent.writeUInt32BE(0, 4)
    dataContent.set(imageData, 8)

    let dataAtom = createAtom("data", dataContent)
    let covrAtom = createAtom("covr", dataAtom)
    let ilstAtom = createAtom("ilst", covrAtom)
    let metaContent = [UInt8].alloc(4) + ilstAtom
    let metaAtom = createAtom("meta", metaContent)
    let udtaAtom = createAtom("udta", metaAtom)
    let moovAtom = createAtom("moov", udtaAtom)

    let ftypContent = [UInt8]("M4A \u{0}\u{0}\u{0}\u{0}M4A mp42isom", encoding: .latin1)
    let ftypAtom = createAtom("ftyp", ftypContent)

    return ftypAtom + moovAtom
}

func createAiffWithArtwork(_ imageData: [UInt8]) -> [UInt8] {
    let id3Data = createMp3WithArtwork(imageData)

    var commData = [UInt8].alloc(18)
    // writeInt16BE(1, 0), writeInt16BE(16, 6)
    commData.writeUInt16BE(1, 0)
    commData.writeUInt16BE(16, 6)

    var commChunk = [UInt8].alloc(8 + commData.count)
    commChunk.set([UInt8]("COMM", encoding: .ascii), 0)
    commChunk.writeUInt32BE(commData.count, 4)
    commChunk.set(commData, 8)

    var id3Chunk = [UInt8].alloc(8 + id3Data.count + (id3Data.count % 2))
    id3Chunk.set([UInt8]("ID3 ", encoding: .ascii), 0)
    id3Chunk.writeUInt32BE(id3Data.count, 4)
    id3Chunk.set(id3Data, 8)

    let formContent = [UInt8].concat([[UInt8]("AIFF", encoding: .ascii), commChunk, id3Chunk])

    var formHeader = [UInt8].alloc(8)
    formHeader.set([UInt8]("FORM", encoding: .ascii), 0)
    formHeader.writeUInt32BE(formContent.count, 4)

    return formHeader + formContent
}
