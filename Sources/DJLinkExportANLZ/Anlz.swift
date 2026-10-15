// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/src/lib.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

public let SECTION_FRAME = 12
// Tag/FourCc 원본: crates/rbl-core/src/lib.rs의 FourCc(같은 고정 커밋).
public struct Tag: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var bytes: [UInt8]
    public init(_ bytes: [UInt8]) {
        precondition(bytes.count == 4)
        self.bytes = bytes
    }
    public init(_ text: String) { self.init(Array(text.utf8)) }
    public static func new(_ bytes: [UInt8]) -> Tag { Tag(bytes) }
    public static func new(_ text: String) -> Tag { Tag(text) }
    public func as_str() -> String { String(bytes: bytes, encoding: .utf8) ?? "????" }
    public var description: String { as_str() }
}
public typealias FourCc = Tag
public enum AnlzError: Error, Equatable, Sendable, CustomStringConvertible {
    case notAnlz, truncated(String)
    case badFileLength(declared: UInt64, actual: UInt64)
    case badSectionLength(tag: String, declared: UInt64, available: UInt64)
    case badSectionHeaderLength(tag: String, declared: UInt64, section_len: UInt64)
    case io(String)
    public var description: String {
        switch self {
        case .notAnlz: return "not an ANLZ file: expected a PMAI header"
        case let .truncated(s): return "file is truncated: \(s)"
        case let .badFileLength(d, a): return "file declares \(d) bytes but contains \(a)"
        case let .badSectionLength(t, d, a): return "section \(t) declares \(d) bytes but only \(a) remain"
        case let .badSectionHeaderLength(t, d, l):
            return "section \(t) has header length \(d), outside its \(l)-byte frame"
        case let .io(s): return s
        }
    }
}
public struct Beat: Equatable, Sendable {
    public var beat_number: UInt16, tempo_x100: UInt16, time_ms: UInt32
    public init(beat_number: UInt16, tempo_x100: UInt16, time_ms: UInt32) {
        self.beat_number = beat_number
        self.tempo_x100 = tempo_x100
        self.time_ms = time_ms
    }
}
func anlzBE<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    (0..<MemoryLayout<T>.size).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
}
func anlzLE<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    (0..<MemoryLayout<T>.size).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
}
func anlzByte(_ b: [UInt8], _ at: Int) -> UInt8 { b.indices.contains(at) ? b[at] : 0 }
func anlzBE16(_ b: [UInt8], _ at: Int) -> UInt16 { UInt16(anlzByte(b, at)) << 8 | UInt16(anlzByte(b, at + 1)) }
func anlzBE32(_ b: [UInt8], _ at: Int) -> UInt32 { (0..<4).reduce(0) { $0 << 8 | UInt32(anlzByte(b, at + $1)) } }
func anlzPut<T: FixedWidthInteger>(_ b: inout [UInt8], _ at: Int, _ value: T) {
    b.replaceSubrange(at..<(at + MemoryLayout<T>.size), with: anlzBE(value))
}
func utf16be_to_string(_ raw: [UInt8]) -> String {
    var units: [UInt16] = []
    for at in stride(from: 0, to: raw.count - raw.count % 2, by: 2) {
        let unit = anlzBE16(raw, at)
        if unit == 0 { break }
        units.append(unit)
    }
    return String(decoding: units, as: UTF16.self)
}
public struct Section: Equatable, Sendable {
    public var tag: Tag, header: [UInt8], payload: [UInt8]
    public init(tag: Tag, header: [UInt8], payload: [UInt8]) {
        self.tag = tag
        self.header = header
        self.payload = payload
    }
    public static func new(_ tag: [UInt8], _ header: [UInt8], _ payload: [UInt8]) -> Section {
        Section(tag: Tag(tag), header: header, payload: payload)
    }
    public static func new(_ tag: String, _ header: [UInt8], _ payload: [UInt8]) -> Section {
        new(Array(tag.utf8), header, payload)
    }
    public func len_header() -> UInt32 { UInt32(exactly: SECTION_FRAME + header.count) ?? .max }
    public func len_tag() -> UInt32 { UInt32(exactly: SECTION_FRAME + header.count + payload.count) ?? .max }
    public func as_path() -> String? { tag == Tag("PPTH") ? utf16be_to_string(payload) : nil }
    public func as_beat_grid() -> [Beat]? {
        guard tag == Tag("PQTZ") else { return nil }
        let count = min(Int(anlzBE32(header, 8)), payload.count / 8)
        return (0..<count).map { i in
            let at = i * 8
            return Beat(
                beat_number: anlzBE16(payload, at), tempo_x100: anlzBE16(payload, at + 2),
                time_ms: anlzBE32(payload, at + 4))
        }
    }
    public func waveform_stride() -> UInt32? {
        switch tag.as_str() {
        case "PWAV", "PWV2": return 1
        case "PWV3", "PWV4", "PWV5", "PWV6", "PWV7": return max(anlzBE32(header, 0), 1)
        default: return nil
        }
    }
    public func waveform() -> [UInt8]? { waveform_stride() == nil ? nil : payload }
    public func is_cue_list() -> Bool { tag == Tag("PCOB") || tag == Tag("PCO2") }
    public func as_cue_entries() -> [CueEntry]? {
        guard tag == Tag("PCO2") else { return nil }
        var entries: [CueEntry] = []
        var at = 0
        while at + 40 <= payload.count {
            guard Array(payload[at..<(at + 4)]) == Array("PCP2".utf8) else { break }
            let len = Int(anlzBE32(payload, at + 8))
            guard len >= 40, at + len <= payload.count else { break }
            entries.append(cue_entry(Array(payload[at..<(at + len)]), len))
            at += len
        }
        return entries
    }
}
public struct CueEntry: Equatable, Sendable {
    public var hot_cue: UInt32, kind: UInt8, time_ms: UInt32, loop_time_ms: UInt32, color_id: UInt8
    public var comment: String?, color_code: UInt8?, rgb: [UInt8]?
    public init(
        hot_cue: UInt32, kind: UInt8, time_ms: UInt32, loop_time_ms: UInt32, color_id: UInt8, comment: String? = nil,
        color_code: UInt8? = nil, rgb: [UInt8]? = nil
    ) {
        self.hot_cue = hot_cue
        self.kind = kind
        self.time_ms = time_ms
        self.loop_time_ms = loop_time_ms
        self.color_id = color_id
        self.comment = comment
        self.color_code = color_code
        self.rgb = rgb
    }
}
private func cue_entry(_ e: [UInt8], _ len: Int) -> CueEntry {
    var entry = CueEntry(
        hot_cue: anlzBE32(e, 12), kind: anlzByte(e, 16), time_ms: anlzBE32(e, 20), loop_time_ms: anlzBE32(e, 24),
        color_id: anlzByte(e, 28))
    guard len > 43 else { return entry }
    let length = Int(anlzBE32(e, 40))
    let start = 44
    let end = start + length
    guard end <= len else { return entry }
    if length > 0 { entry.comment = utf16be_to_string(Array(e[start..<end])) }
    if end + 4 <= len {
        entry.color_code = e[end]
        entry.rgb = Array(e[(end + 1)..<(end + 4)])
    }
    return entry
}
public struct Anlz: Equatable, Sendable {
    public var header_extra: [UInt8], sections: [Section]
    public init(header_extra: [UInt8] = [], sections: [Section] = []) {
        self.header_extra = header_extra
        self.sections = sections
    }
    public static func `default`() -> Anlz { Anlz() }
    public static func read(_ path: String) throws -> Anlz {
        let bytes: [UInt8]
        do { bytes = Array(try Data(contentsOf: URL(fileURLWithPath: path))) } catch {
            throw AnlzError.io(String(describing: error))
        }
        return try parse(bytes)
    }
    public func section(_ tag: [UInt8]) -> Section? { sections.first { $0.tag == Tag(tag) } }
    public func section(_ tag: String) -> Section? { section(Array(tag.utf8)) }
    public func beat_grid() -> [Beat]? { sections.lazy.compactMap { $0.as_beat_grid() }.first }
    public func grid_offset() -> Int16? {
        guard let section = section("PQTZ"), section.header.count >= 8 else { return nil }
        return Int16(bitPattern: anlzBE16(section.header, 6))
    }
    public func with_grid_offset(_ offset_ms: Int16) -> [UInt8]? {
        var next = self
        guard let at = next.sections.firstIndex(where: { $0.tag == Tag("PQTZ") }), next.sections[at].header.count >= 8
        else { return nil }
        anlzPut(&next.sections[at].header, 6, offset_ms)
        return next.to_bytes()
    }
    public func cue_entries() -> [CueEntry] { sections.compactMap { $0.as_cue_entries() }.flatMap { $0 } }
    public func path() -> String? { sections.lazy.compactMap { $0.as_path() }.first }
    public func waveform(_ tag: [UInt8]) -> (UInt32, [UInt8])? {
        guard let s = section(tag), let stride = s.waveform_stride() else { return nil }
        return (stride, s.payload)
    }
    public func waveform(_ tag: String) -> (UInt32, [UInt8])? { waveform(Array(tag.utf8)) }
    public func to_bytes() -> [UInt8] { Write.render(header_extra, sections) }
    public func has_extended_grid() -> Bool { section("PQT2") != nil }
    public func with_extended_grid_cleared() -> [UInt8]? {
        guard let at = sections.firstIndex(where: { $0.tag == Tag("PQT2") }), !sections[at].payload.isEmpty else {
            return nil
        }
        var copy = sections
        copy[at] = Write.extended_grid_empty_section()
        return Write.render(header_extra, copy)
    }
    public func with_extended_grid_edit(_ old: [Beat], _ new: [Beat], _ offset: Int16) -> [UInt8]? {
        guard let at = sections.firstIndex(where: { $0.tag == Tag("PQT2") }) else { return nil }
        let s = sections[at]
        func word(_ at: Int) -> UInt32? { s.header.count >= at + 4 ? anlzBE32(s.header, at) : nil }
        func packed(_ b: Beat) -> UInt32 { UInt32(b.beat_number) << 16 | UInt32(b.tempo_x100) }
        func checksum(_ b: [Beat]) -> UInt32 {
            b.reduce(0) { $0 &+ $1.time_ms &+ UInt32($1.beat_number) &+ UInt32($1.tempo_x100) }
        }
        let preserve =
            !old.isEmpty && old.count == new.count && s.header.count >= 36 && s.payload.count == old.count * 2
            && word(28) == UInt32(exactly: old.count) && word(12) == old.first.map(packed)
            && word(16) == old.first?.time_ms && word(20) == old.last.map(packed) && word(24) == old.last?.time_ms
            && word(32) == checksum(old) && Array(s.header[8..<10]) == anlzBE(offset)
            && zip(old, new).allSatisfy { pair in
                Int64(pair.0.time_ms) + Int64(offset) == Int64(pair.1.time_ms) && pair.0.tempo_x100 == pair.1.tempo_x100
            }
        var next = self
        if next.sections[at].header.count < 36 {
            next.sections[at] = Write.extended_grid_empty_section()
        } else {
            next.sections[at].header.replaceSubrange(8..<36, with: Array(repeating: 0, count: 28))
            if preserve {
                guard let first = new.first, let last = new.last, let count = UInt32(exactly: new.count) else {
                    return nil
                }
                for (offset, value) in [
                    (12, packed(first)), (16, first.time_ms), (20, packed(last)), (24, last.time_ms), (28, count),
                    (32, checksum(new)),
                ] { anlzPut(&next.sections[at].header, offset, value) }
            } else {
                next.sections[at].payload.removeAll()
            }
        }
        let out = next.to_bytes()
        return out != to_bytes() ? out : nil
    }
    public func with_beat_grid(_ beats: [Beat]) -> [UInt8] {
        let replacement = Write.beat_grid_section(beats)
        var copy = sections
        if let at = copy.firstIndex(where: { $0.tag == Tag("PQTZ") }) {
            copy[at] = replacement
        } else {
            let at = copy.prefix { $0.tag == Tag("PPTH") || $0.tag == Tag("PVBR") }.count
            copy.insert(replacement, at: at)
        }
        return Write.render(header_extra, copy)
    }
}
public func parse(_ bytes: [UInt8]) throws -> Anlz {
    guard bytes.count >= SECTION_FRAME else { throw AnlzError.truncated("header") }
    guard Array(bytes[0..<4]) == Array("PMAI".utf8) else { throw AnlzError.notAnlz }
    let len_header = Int(anlzBE32(bytes, 4))
    guard len_header >= SECTION_FRAME, len_header <= bytes.count else { throw AnlzError.truncated("header length") }
    let file_len = Int(anlzBE32(bytes, 8))
    guard file_len == bytes.count else {
        throw AnlzError.badFileLength(declared: UInt64(file_len), actual: UInt64(bytes.count))
    }
    var sections: [Section] = []
    var at = len_header
    while at + SECTION_FRAME <= bytes.count {
        let tag = Tag(Array(bytes[at..<(at + 4)]))
        let header = Int(anlzBE32(bytes, at + 4))
        let len = Int(anlzBE32(bytes, at + 8))
        guard len >= SECTION_FRAME, at + len <= bytes.count else {
            throw AnlzError.badSectionLength(
                tag: tag.description, declared: UInt64(len), available: UInt64(bytes.count - at))
        }
        guard header >= SECTION_FRAME, header <= len else {
            throw AnlzError.badSectionHeaderLength(
                tag: tag.description, declared: UInt64(header), section_len: UInt64(len))
        }
        sections.append(
            Section(
                tag: tag, header: Array(bytes[(at + SECTION_FRAME)..<(at + header)]),
                payload: Array(bytes[(at + header)..<(at + len)])))
        at += len
    }
    guard at == bytes.count else { throw AnlzError.truncated("section frame") }
    return Anlz(header_extra: Array(bytes[SECTION_FRAME..<len_header]), sections: sections)
}
public func resolve(_ share_root: String, _ analysis_data_path: String) -> String {
    let relative = String(String.UnicodeScalarView(analysis_data_path.unicodeScalars.drop(while: { $0 == "/" })))
    return share_root.isEmpty ? relative : share_root + (share_root.hasSuffix("/") ? "" : "/") + relative
}
public func sibling(_ dat: String, _ extensionName: String) -> String {
    (dat as NSString).deletingPathExtension + (extensionName.isEmpty ? "" : "." + extensionName)
}

public let MEASURED_CUE_COLOURS: [(UInt8, [UInt8])] = [
    (0, [0x00, 0x00, 0x00]),
    (1, [0x00, 0x00, 0xFF]),
    (2, [0x00, 0x1C, 0xFF]),
    (3, [0x00, 0x38, 0xFF]),
    (4, [0x00, 0x54, 0xFF]),
    (5, [0x00, 0x70, 0xFF]),
    (6, [0x00, 0x8C, 0xFF]),
    (7, [0x00, 0xA8, 0xFF]),
    (8, [0x00, 0xC4, 0xFF]),
    (9, [0x00, 0xE0, 0xFF]),
    (10, [0x00, 0xFF, 0xFF]),
    (11, [0x00, 0xFF, 0xE8]),
    (12, [0x00, 0xFF, 0xD1]),
    (13, [0x00, 0xFF, 0xBA]),
    (14, [0x00, 0xFF, 0xA3]),
    (15, [0x00, 0xFF, 0x8C]),
    (16, [0x00, 0xFF, 0x75]),
    (17, [0x00, 0xFF, 0x5E]),
    (18, [0x00, 0xFF, 0x47]),
    (19, [0x00, 0xFF, 0x30]),
    (20, [0x00, 0xFF, 0x1A]),
    (21, [0x00, 0xFF, 0x00]),
    (22, [0x1A, 0xFF, 0x00]),
    (23, [0x33, 0xFF, 0x00]),
    (24, [0x4D, 0xFF, 0x00]),
    (25, [0x66, 0xFF, 0x00]),
    (26, [0x80, 0xFF, 0x00]),
    (27, [0x99, 0xFF, 0x00]),
    (28, [0xB3, 0xFF, 0x00]),
    (29, [0xCC, 0xFF, 0x00]),
    (30, [0xE6, 0xFF, 0x00]),
    (31, [0xFF, 0xFF, 0x00]),
    (32, [0xFF, 0xE8, 0x00]),
    (33, [0xFF, 0xD1, 0x00]),
    (34, [0xFF, 0xBA, 0x00]),
    (35, [0xFF, 0xA3, 0x00]),
    (36, [0xFF, 0x8C, 0x00]),
    (37, [0xFF, 0x75, 0x00]),
    (38, [0xFF, 0x5E, 0x00]),
    (39, [0xFF, 0x47, 0x00]),
    (40, [0xFF, 0x30, 0x00]),
    (41, [0xFF, 0x1A, 0x00]),
    (42, [0xFF, 0x00, 0x00]),
    (43, [0xFF, 0x00, 0x17]),
    (44, [0xFF, 0x00, 0x2E]),
    (45, [0xFF, 0x00, 0x45]),
    (46, [0xFF, 0x00, 0x5C]),
    (47, [0xFF, 0x00, 0x73]),
    (48, [0xFF, 0x00, 0x8A]),
    (49, [0xFF, 0x00, 0xA1]),
    (50, [0xFF, 0x00, 0xB8]),
    (51, [0xFF, 0x00, 0xCF]),
    (52, [0xFF, 0x00, 0xE6]),
    (53, [0xFF, 0x00, 0xFF]),
    (54, [0xE6, 0x00, 0xFF]),
    (55, [0xCC, 0x00, 0xFF]),
    (56, [0xB3, 0x00, 0xFF]),
    (57, [0x99, 0x00, 0xFF]),
    (58, [0x80, 0x00, 0xFF]),
    (59, [0x66, 0x00, 0xFF]),
    (60, [0x4D, 0x00, 0xFF]),
    (61, [0x33, 0x00, 0xFF]),
    (62, [0x1A, 0x00, 0xFF]),
    (63, [0x00, 0x00, 0x00]),
    (64, [0xFF, 0xFF, 0xFF]),
]

public let DRAWN_CUE_COLOURS: [(UInt8, [UInt8])] = [
    (0, [0x00, 0x00, 0x00]),
    (1, [0x30, 0x5A, 0xFF]),
    (2, [0x50, 0x73, 0xFF]),
    (3, [0x50, 0x8C, 0xFF]),
    (4, [0x50, 0xA0, 0xFF]),
    (5, [0x50, 0xB4, 0xFF]),
    (6, [0x50, 0xB0, 0xF2]),
    (7, [0x50, 0xAE, 0xE8]),
    (8, [0x45, 0xAC, 0xDB]),
    (9, [0x00, 0xE0, 0xFF]),
    (10, [0x19, 0xDA, 0xF0]),
    (11, [0x32, 0xD2, 0xE6]),
    (12, [0x21, 0xB4, 0xB9]),
    (13, [0x20, 0xAA, 0xA0]),
    (14, [0x1F, 0xA3, 0x92]),
    (15, [0x19, 0xA0, 0x8C]),
    (16, [0x14, 0xA5, 0x84]),
    (17, [0x14, 0xAA, 0x7D]),
    (18, [0x10, 0xB1, 0x76]),
    (19, [0x30, 0xD2, 0x6E]),
    (20, [0x37, 0xDE, 0x5A]),
    (21, [0x3C, 0xEB, 0x50]),
    (22, [0x28, 0xE2, 0x14]),
    (23, [0x7D, 0xC1, 0x3D]),
    (24, [0x8C, 0xC8, 0x32]),
    (25, [0x9B, 0xD7, 0x23]),
    (26, [0xA5, 0xE1, 0x16]),
    (27, [0xA5, 0xDC, 0x0A]),
    (28, [0xAA, 0xD2, 0x08]),
    (29, [0xB4, 0xC8, 0x05]),
    (30, [0xB4, 0xBE, 0x04]),
    (31, [0xBA, 0xB4, 0x04]),
    (32, [0xC3, 0xAF, 0x04]),
    (33, [0xE1, 0xAA, 0x00]),
    (34, [0xFF, 0xA0, 0x00]),
    (35, [0xFF, 0x96, 0x00]),
    (36, [0xFF, 0x8C, 0x00]),
    (37, [0xFF, 0x75, 0x00]),
    (38, [0xE0, 0x64, 0x1B]),
    (39, [0xE0, 0x46, 0x1E]),
    (40, [0xE0, 0x30, 0x1E]),
    (41, [0xE0, 0x28, 0x23]),
    (42, [0xE6, 0x28, 0x28]),
    (43, [0xFF, 0x37, 0x6F]),
    (44, [0xFF, 0x2D, 0x6F]),
    (45, [0xFF, 0x12, 0x7B]),
    (46, [0xF5, 0x1E, 0x8C]),
    (47, [0xEB, 0x2D, 0xA0]),
    (48, [0xE6, 0x37, 0xB4]),
    (49, [0xDE, 0x44, 0xCF]),
    (50, [0xDE, 0x44, 0x8D]),
    (51, [0xE6, 0x30, 0xB4]),
    (52, [0xE6, 0x19, 0xDC]),
    (53, [0xE6, 0x00, 0xFF]),
    (54, [0xDC, 0x00, 0xFF]),
    (55, [0xCC, 0x00, 0xFF]),
    (56, [0xB4, 0x32, 0xFF]),
    (57, [0xB9, 0x3C, 0xFF]),
    (58, [0xC5, 0x42, 0xFF]),
    (59, [0xAA, 0x5A, 0xFF]),
    (60, [0xAA, 0x72, 0xFF]),
    (61, [0x82, 0x72, 0xFF]),
    (62, [0x64, 0x73, 0xFF]),
    (63, [0x00, 0x00, 0x00]),
    (64, [0xFF, 0xFF, 0xFF]),
]
public func cue_colour(_ index: UInt8) -> [UInt8]? { MEASURED_CUE_COLOURS.first { $0.0 == index }?.1 }
public func cue_colour_drawn(_ index: UInt8) -> [UInt8]? { DRAWN_CUE_COLOURS.first { $0.0 == index }?.1 }
