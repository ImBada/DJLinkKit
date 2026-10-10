import Foundation

@testable import DJLinkKit

// 원본 tests/localdb/fixtures/anlz-fixtures.ts
let localDBSectionTags: [String: UInt32] = [
    "BEAT_GRID": 0x5051_545a, "CUES": 0x5043_4f42, "CUES_2": 0x5043_4f32,
    "PATH": 0x5050_5448, "VBR": 0x5056_4252, "WAVE_PREVIEW": 0x5057_4156, "WAVE_TINY": 0x5057_5632,
    "WAVE_SCROLL": 0x5057_5633, "WAVE_COLOR_PREVIEW": 0x5057_5634, "WAVE_COLOR_SCROLL": 0x5057_5635,
    "WAVE_COLOR_3CHANNEL": 0x5057_5636, "WAVE_HD": 0x5057_5637, "SONG_STRUCTURE": 0x5053_5349,
    "VOCAL_CONFIG": 0x5057_5643,
]
func anlzBE32(_ value: Int) -> [UInt8] {
    (0..<4).map { UInt8(truncatingIfNeeded: value >> ((3 - $0) * 8)) }
}
func anlzBE16(_ value: Int) -> [UInt8] {
    [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
}
func anlzSection(_ fourcc: String, _ body: [UInt8], headerLength: Int = 12) -> [UInt8] {
    Array(fourcc.utf8) + anlzBE32(headerLength) + anlzBE32(12 + body.count) + body
}
struct AnlzWaveOptions {
    var numEntries: Int
    var data: [UInt8]?
    init(numEntries: Int, data: [UInt8]? = nil) {
        self.numEntries = numEntries
        self.data = data
    }
}
struct AnlzVocalOptions {
    var thresholdLow: Int
    var thresholdMid: Int
    var thresholdHigh: Int
    init(thresholdLow: Int = 80, thresholdMid: Int = 100, thresholdHigh: Int = 100) {
        self.thresholdLow = thresholdLow
        self.thresholdMid = thresholdMid
        self.thresholdHigh = thresholdHigh
    }
}
func createWaveSection(
    _ tag: String, numEntries: Int, entryBytes: Int, unknown: Bool, data: [UInt8]?
) -> [UInt8] {
    let dataLength = numEntries * entryBytes
    var values = [UInt8](repeating: 0, count: dataLength)
    let source = data ?? (0..<dataLength).map { UInt8($0 % 256) }
    values.replaceSubrange(0..<min(source.count, dataLength), with: source.prefix(dataLength))
    return anlzSection(
        tag, anlzBE32(entryBytes) + anlzBE32(numEntries) + (unknown ? anlzBE32(0x960000) : []) + values)
}
func createPWV6Section(numEntries: Int = 100, data: [UInt8]? = nil) -> [UInt8] {
    createWaveSection("PWV6", numEntries: numEntries, entryBytes: 3, unknown: false, data: data)
}
func createPWV7Section(numEntries: Int = 1000, data: [UInt8]? = nil) -> [UInt8] {
    createWaveSection("PWV7", numEntries: numEntries, entryBytes: 3, unknown: true, data: data)
}
func createPWV5Section(numEntries: Int = 1000, data: [UInt8]? = nil) -> [UInt8] {
    createWaveSection("PWV5", numEntries: numEntries, entryBytes: 2, unknown: true, data: data)
}
func createPWVCSection(thresholdLow: Int = 80, thresholdMid: Int = 100, thresholdHigh: Int = 100)
    -> [UInt8]
{
    anlzSection(
        "PWVC", anlzBE16(0) + anlzBE16(thresholdLow) + anlzBE16(thresholdMid) + anlzBE16(thresholdHigh))
}
func createAnlzFile(_ sections: [[UInt8]]) -> [UInt8] {
    let body = sections.flatMap { $0 }
    return Array("PMAI".utf8) + anlzBE32(12) + anlzBE32(12 + body.count) + body
}
func create2EXFile(
    pwv6: AnlzWaveOptions? = nil, pwv7: AnlzWaveOptions? = nil, pwvc: AnlzVocalOptions? = nil
) -> [UInt8] {
    let all = pwv6 == nil && pwv7 == nil && pwvc == nil
    var sections: [[UInt8]] = []
    if let options = pwv6 {
        sections.append(createPWV6Section(numEntries: options.numEntries, data: options.data))
    } else if all {
        sections.append(createPWV6Section())
    }
    if let options = pwv7 {
        sections.append(createPWV7Section(numEntries: options.numEntries, data: options.data))
    } else if all {
        sections.append(createPWV7Section())
    }
    if let options = pwvc {
        sections.append(
            createPWVCSection(
                thresholdLow: options.thresholdLow, thresholdMid: options.thresholdMid,
                thresholdHigh: options.thresholdHigh))
    } else if all {
        sections.append(createPWVCSection())
    }
    return createAnlzFile(sections)
}
func createEXTFile(pwv5: AnlzWaveOptions? = nil) -> [UInt8] {
    createAnlzFile([createPWV5Section(numEntries: pwv5?.numEntries ?? 1000, data: pwv5?.data)])
}

// 원본 통합 시험의 수동 파서: 제품 리더를 쓰지 않아서 픽스처→변환 경계를 따로 검사한다.
func parseAnlzSections(_ buffer: [UInt8]) throws -> [LocalDBAnlzSection] {
    var sections: [LocalDBAnlzSection] = []
    var offset = 12
    while offset < buffer.count {
        let fourcc = buffer.toString(.ascii, offset, offset + 4)
        let length = Int(try buffer.readUInt32BE(offset + 8))
        let bodyStart = offset + 12
        if fourcc == "PWV6" || fourcc == "PWV7" {
            let entryBytes = Int(try buffer.readUInt32BE(bodyStart))
            let count = Int(try buffer.readUInt32BE(bodyStart + 4))
            let start = bodyStart + (fourcc == "PWV6" ? 8 : 12)
            sections.append(
                .init(
                    fourcc: fourcc, lenEntries: count,
                    entries: buffer.subarray(start, start + count * entryBytes)))
        } else if fourcc == "PWVC" {
            sections.append(
                .init(
                    fourcc: fourcc, thresholdLow: Int(try buffer.readUInt16BE(bodyStart + 2)),
                    thresholdMid: Int(try buffer.readUInt16BE(bodyStart + 4)),
                    thresholdHigh: Int(try buffer.readUInt16BE(bodyStart + 6))))
        }
        offset += length
    }
    return sections
}
func convertPWV6ToBands(_ data: [UInt8], _ numEntries: Int) -> (
    low: [Double], mid: [Double], high: [Double]
) {
    (
        (0..<numEntries).map { Double(data[$0 * 3]) / 255 },
        (0..<numEntries).map { Double(data[$0 * 3 + 1]) / 255 },
        (0..<numEntries).map { Double(data[$0 * 3 + 2]) / 255 }
    )
}
