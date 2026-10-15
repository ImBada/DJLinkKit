// DJCrate AnlzFile·AnlzColorWaveform·AnlzCueTags·AnlzMasks 리더에서 출발한 바이트 리더.
// 원본 localdb가 내보내는 단위(ms)·필드와 12바이트 픽스처 머리를 그대로 받는다.
public struct LocalDBAnlzFile: Sendable {
    public struct Tag: Equatable, Sendable {
        public var fourcc: String
        public var bytes: [UInt8]
    }
    public var header: [UInt8]
    public var tags: [Tag]
    public init(bytes: [UInt8]) throws {
        guard bytes.count >= 12, bytes.prefix(4).elementsEqual([0x50, 0x4d, 0x41, 0x49]) else {
            throw DJLinkError("Invalid ANLZ file: PMAI")
        }
        let headerLength = Int(try bytes.readUInt32BE(4))
        guard headerLength >= 12, headerLength <= bytes.count
        else { throw DJLinkError("Invalid ANLZ file length") }
        header = bytes.subarray(0, headerLength)
        tags = []
        var p = headerLength
        while p + 12 <= bytes.count {
            let length = Int(try bytes.readUInt32BE(p + 8))
            guard length >= 12, p + length <= bytes.count else {
                throw DJLinkError("Invalid ANLZ tag length")
            }
            tags.append(
                .init(
                    fourcc: String(decoding: bytes[p..<(p + 4)], as: UTF8.self),
                    bytes: bytes.subarray(p, p + length)))
            p += length
        }
        guard p == bytes.count else { throw DJLinkError("Invalid ANLZ trailing bytes") }
    }
}
public func readLocalDBAnlz(_ bytes: [UInt8]) throws -> [LocalDBAnlzSection] {
    try LocalDBAnlzFile(bytes: bytes).tags.map { tag in
        var b = tag.bytes
        func u32(_ at: Int) throws -> Int { Int(try b.readUInt32BE(at)) }
        func u16(_ at: Int) throws -> Int { Int(try b.readUInt16BE(at)) }
        func entryBytes(start: Int, count: Int, size: Int) throws -> [UInt8] {
            guard count >= 0, size >= 0, start <= b.count, count <= (b.count - start) / max(1, size),
                size > 0 || count == 0
            else { throw DJLinkError("Invalid ANLZ entry length") }
            return b.subarray(start, start + count * size)
        }
        var section = LocalDBAnlzSection(fourcc: tag.fourcc)
        switch tag.fourcc {
        case "PQTZ":
            let count = try u32(20)
            _ = try entryBytes(start: 24, count: count, size: 8)
            section.beats = try (0..<count).map { i in
                let p = 24 + 8 * i
                return .init(
                    time: Double(try u32(p + 4)), tempo: Double(try u16(p + 2)), beatNumber: try u16(p))
            }
        case "PCOB":
            let count = try u16(18)
            var p = 24
            for _ in 0..<count {
                guard b.subarray(p, p + 4) == Array("PCPT".utf8) else {
                    throw DJLinkError("Invalid ANLZ cue magic: PCPT")
                }
                // 원본은 len_entry와 무관하게 고정된 56바이트를 읽는다.
                _ = try entryBytes(start: p, count: 1, size: 56)
                section.cues.append(
                    .init(
                        hotCue: try u32(p + 12), status: try u32(p + 16), type: Int(b[p + 28]),
                        time: Double(try u32(p + 32)), loopTime: Double(try u32(p + 36))))
                p += 56
            }
        case "PCO2":
            let count = try u16(16)
            var p = 20
            for _ in 0..<count {
                guard b.subarray(p, p + 4) == Array("PCP2".utf8) else {
                    throw DJLinkError("Invalid ANLZ cue magic: PCP2")
                }
                _ = try entryBytes(start: p, count: 1, size: 40)
                let length = try u32(p + 8)
                var commentLength = 0
                var comment: String?
                var consumed = 40
                var colorCode: Int?
                var colorRed: Int?
                var colorGreen: Int?
                var colorBlue: Int?
                if length > 43 {
                    commentLength = try u32(p + 40)
                    let bytes = try entryBytes(start: p + 44, count: commentLength, size: 1)
                    comment = PdbStringDecoder.decodeUTF16(bytes, littleEndian: false)
                    consumed = 44 + commentLength
                    if length - commentLength > 44 {
                        colorCode = Int(try b.readUInt8(p + consumed))
                        consumed += 1
                    }
                    if length - commentLength > 45 {
                        colorRed = Int(try b.readUInt8(p + consumed))
                        consumed += 1
                    }
                    if length - commentLength > 46 {
                        colorGreen = Int(try b.readUInt8(p + consumed))
                        consumed += 1
                    }
                    if length - commentLength > 47 {
                        colorBlue = Int(try b.readUInt8(p + consumed))
                        consumed += 1
                    }
                    if length - commentLength > 48 {
                        _ = try entryBytes(start: p + consumed, count: length - consumed, size: 1)
                        consumed = length
                    }
                }
                section.cues.append(
                    .init(
                        hotCue: try u32(p + 12), type: Int(b[p + 16]), time: Double(try u32(p + 20)),
                        loopTime: Double(try u32(p + 24)),
                        colorId: Int(b[p + 28]), loopNumerator: try u16(p + 36),
                        loopDenominator: try u16(p + 38), lenComment: commentLength,
                        comment: comment, colorCode: colorCode,
                        colorRed: colorRed, colorGreen: colorGreen, colorBlue: colorBlue))
                p += consumed
            }
        case "PWAV", "PWV2":
            let count = try u32(12)
            section.entries = try entryBytes(start: 20, count: count, size: 1)
        case "PWV3":
            let size = try u32(12)
            let count = try u32(16)
            section.entries = try entryBytes(start: 24, count: count, size: size)
        case "PWV4":
            let size = try u32(12)
            let count = try u32(16)
            section.lenEntries = count
            section.entries = try entryBytes(start: 24, count: count, size: size)
        case "PWV6":
            let size = try u32(12)
            let count = try u32(16)
            section.lenEntries = count
            section.entries = try entryBytes(start: 20, count: count, size: size)
        case "PWV5", "PWV7":
            let size = try u32(12)
            let count = try u32(16)
            section.lenEntries = count
            section.entries = try entryBytes(start: 24, count: count, size: size)
        case "PWVC":
            section.thresholdLow = try u16(14)
            section.thresholdMid = try u16(16)
            section.thresholdHigh = try u16(18)
        case "PSSI":
            let count = try u16(16)
            let mask: [UInt8] = [
                0xCB, 0xE1, 0xEE, 0xFA, 0xE5, 0xEE, 0xAD, 0xEE, 0xE9, 0xD2, 0xE9, 0xEB, 0xE1, 0xE9, 0xF3,
                0xE8, 0xE9, 0xF4, 0xE1,
            ]
            for i in 18..<b.count {
                b[i] ^= mask[(i - 18) % mask.count] &+ UInt8(truncatingIfNeeded: count)
            }
            section.mood = try u16(18)
            section.endBeat = try u16(26)
            let size = try u32(12)
            // 원본 Kaitai는 항목마다 len_entry_bytes - 9바이트를 건너뛰므로 9보다 작으면 항목 읽기에 실패한다.
            guard count == 0 || size >= 9 else { throw DJLinkError("Invalid ANLZ phrase length") }
            // PLAN §9(#26): 1:1 기준선은 mood가 1~3 밖이면 EXT 전체를 실패시켰다.
            // 원본 Kaitai song_structure_entry: phrase_number u2, beat_number u2, kind,
            // (len_entry_bytes - 9)바이트 건너뜀, fill_in u1, fill_in_beat_number u2.
            // kind는 mood가 high·mid·low(1~3)일 때만 u2이고 그 밖에는 0바이트 unknown_tag다.
            // 그래서 알 수 없는 mood에서도 실패하지 않고, 항목이 2바이트씩 짧아 뒤 항목이 어긋난다.
            let kindLength = (1...3).contains(section.mood) ? 2 : 0
            let entryLength = count == 0 ? 0 : 4 + kindLength + (size - 9) + 3
            _ = try entryBytes(start: 32, count: count, size: entryLength)
            section.bank = Int(b[30])
            section.phrases = try (0..<count).map { i in
                let p = 32 + entryLength * i
                let kind: LocalDBAnlzPhraseKind = try kindLength == 0 ? .unknownTag : .init(id: u16(p + 4))
                return .init(
                    phraseNumber: try u16(p), beatNumber: try u16(p + 2), kind: kind,
                    fillIn: Int(b[p + entryLength - 3]), fillInBeatNumber: try u16(p + entryLength - 2))
            }
        default: break
        }
        return section
    }
}
