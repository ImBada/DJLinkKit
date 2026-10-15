// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-link/src/blobs.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import DJLinkExportANLZ
import DJLinkExportModel

private func blobLE<T: FixedWidthInteger>(_ v: T) -> [UInt8] {
    (0..<MemoryLayout<T>.size).map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) }
}
private func blobBE<T: FixedWidthInteger>(_ v: T) -> [UInt8] {
    (0..<MemoryLayout<T>.size).reversed().map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) }
}
private func blobPut<T: FixedWidthInteger>(_ bytes: inout [UInt8], _ at: Int, _ value: T) {
    bytes.replaceSubrange(at..<(at + MemoryLayout<T>.size), with: blobLE(value))
}
public func tag_blob(_ section: Section) -> [UInt8] {
    let framed_len = Int(section.len_tag())
    let padded = ((framed_len + 3) / 4) * 4
    var out =
        blobLE(UInt32(exactly: padded) ?? .max) + section.tag.bytes + blobBE(section.len_header())
        + blobBE(section.len_tag()) + section.header + section.payload
    if out.count < 4 + padded {
        out += [UInt8](repeating: 0, count: 4 + padded - out.count)
    } else if out.count > 4 + padded {
        out = Array(out.prefix(4 + padded))
    }
    return out
}
public func beat_grid_blob(_ beats: [DJLinkExportANLZ.Beat]) -> [UInt8] {
    let count = UInt32(exactly: beats.count) ?? .max
    let (size, overflow) = count.multipliedReportingOverflow(by: 16)
    var out: [UInt8] = [0, 0, 8, 0]
    out += blobLE(count)
    out += blobLE(overflow ? UInt32.max : size)
    out += blobLE(UInt32(1))
    out += blobLE(UInt32(1))
    for b in beats {
        out += [UInt8(exactly: b.beat_number) ?? 0, 0]
        out += blobLE(b.tempo_x100)
        out += blobLE(b.time_ms)
        out += [UInt8](repeating: 255, count: 8)
    }
    return out
}
public func waveform_preview_blob(_ pwav: [UInt8], _ pwv2: [UInt8]) -> [UInt8] {
    pwav.flatMap { byte in
        let column = Encode.device_preview_byte(byte)
        return [column & 0x1f, column >> 5]
    } + pwv2.map(Encode.device_tiny_preview_byte) + [0x9e, 0xeb, 0x78, 0x10]
}
public func waveform_detail_blob(_ pwv3: [UInt8]) -> [UInt8] {
    let count = UInt32(exactly: pwv3.count) ?? .max
    return [count, 1, count, 150, 1].flatMap(blobLE) + pwv3
}
public struct ExtendedCue: Equatable, Sendable {
    public var position_ms: UInt32, out_ms: UInt32, hot_slot: UInt8, comment: String, colour: UInt8
    public init(
        position_ms: UInt32 = 0, out_ms: UInt32 = 0, hot_slot: UInt8 = 0, comment: String = "", colour: UInt8 = 0
    ) {
        self.position_ms = position_ms
        self.out_ms = out_ms
        self.hot_slot = hot_slot
        self.comment = comment
        self.colour = colour
    }
    public init(_ cue: DJLinkExportModel.Cue) {
        let slot = cue.hot_letter()?.unicodeScalars.first.map { $0.value - 65 + 1 } ?? 0
        self.init(
            position_ms: cue.position_ms, out_ms: cue.out_ms, hot_slot: (1...8).contains(slot) ? UInt8(slot) : 0,
            colour: cue.colour)
    }
    public static func from(_ cue: DJLinkExportModel.Cue) -> ExtendedCue { ExtendedCue(cue) }
}
public func extended_cues_blob(_ cues: [ExtendedCue]) -> ([UInt8], UInt32) {
    // 원본 stable sort의 같은 슬롯 내 순서도 보존한다.
    let hot = cues.enumerated().filter { $0.element.hot_slot != 0 }.sorted {
        $0.element.hot_slot == $1.element.hot_slot ? $0.offset < $1.offset : $0.element.hot_slot < $1.element.hot_slot
    }.map(\.element)
    let memory = cues.filter { $0.hot_slot == 0 }
    var out: [UInt8] = []
    for cue in hot { out += extended_cue_entry(cue, nil, nil) }
    for (index, cue) in memory.enumerated() {
        out += extended_cue_entry(
            cue, index > 0 ? UInt16(exactly: index - 1) ?? .max : nil,
            index + 1 < memory.count ? UInt16(exactly: index + 1) ?? .max : nil)
    }
    return (out, UInt32(exactly: hot.count + memory.count) ?? .max)
}
public func vbr_compatibility_blob() -> [UInt8] { [UInt8](repeating: 0, count: 1604) }
private func extended_cue_entry(_ cue: ExtendedCue, _ previous: UInt16?, _ next: UInt16?) -> [UInt8] {
    let comment = cue.comment.isEmpty ? [] : cue.comment.utf16.flatMap(blobLE) + [0, 0]
    let len = 0x4a + comment.count + 8 + 0x2a
    var e = [UInt8](repeating: 0, count: len)
    blobPut(&e, 0, UInt32(exactly: len) ?? 0)
    e[4] = cue.hot_slot
    let is_loop = cue.out_ms > cue.position_ms
    e[6] = is_loop ? 2 : 1
    blobPut(&e, 10, UInt16(1000))
    blobPut(&e, 12, cue.position_ms)
    blobPut(&e, 16, is_loop ? cue.out_ms : .max)
    blobPut(&e, 0x20, previous ?? .max)
    blobPut(&e, 0x22, next ?? .max)
    e[0x34] = 0x56
    blobPut(&e, 0x48, UInt16(exactly: comment.count) ?? .max)
    var at = 0x4a
    e.replaceSubrange(at..<(at + comment.count), with: comment)
    at += comment.count
    e.replaceSubrange(at..<(at + 4), with: [0x2c, 0, 0, 0])
    at += 4
    if cue.hot_slot != 0 {
        let code: UInt8 = cue.colour > 64 ? 0 : cue.colour
        e[at] = code
        e.replaceSubrange((at + 1)..<(at + 4), with: DJLinkExportANLZ.Cues.export_colour(code, UInt32(cue.hot_slot)))
    }
    return e
}
public struct Analysis: Sendable {
    public var dat: Anlz?, ext: Anlz?, two_ex: Anlz?
    public init(dat: Anlz? = nil, ext: Anlz? = nil, two_ex: Anlz? = nil) {
        self.dat = dat
        self.ext = ext
        self.two_ex = two_ex
    }
    public func beat_grid() -> [UInt8]? { dat?.beat_grid().map(beat_grid_blob) }
    public func waveform_preview() -> [UInt8]? {
        guard let dat, let (_, pwav) = dat.waveform("PWAV") else { return nil }
        return waveform_preview_blob(pwav, dat.waveform("PWV2")?.1 ?? [])
    }
    public func waveform_detail() -> [UInt8]? { ext?.waveform("PWV3").map { waveform_detail_blob($0.1) } }
    public func tag(_ fourcc: [UInt8], _ extensionName: [UInt8]) -> [UInt8]? {
        let file: Anlz?
        if extensionName == Array("EXT".utf8) {
            file = ext
        } else if extensionName == Array("2EX".utf8) {
            file = two_ex
        } else if extensionName == Array("DAT".utf8) {
            file = dat
        } else {
            return nil
        }
        return file?.section(fourcc).map(tag_blob)
    }
    public func tag(_ fourcc: String, _ extensionName: String) -> [UInt8]? {
        tag(Array(fourcc.utf8), Array(extensionName.utf8))
    }
}
