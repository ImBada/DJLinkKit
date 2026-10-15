// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/src/write.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
public enum Write {
    public static func render(_ header_extra: [UInt8], _ sections: [Section]) -> [UInt8] {
        let len_header = SECTION_FRAME + header_extra.count
        let body_len = sections.reduce(0) { $0 + SECTION_FRAME + $1.header.count + $1.payload.count }
        var out =
            Array("PMAI".utf8) + anlzBE(UInt32(exactly: len_header) ?? 0)
            + anlzBE(UInt32(exactly: len_header + body_len) ?? 0) + header_extra
        for s in sections {
            out += s.tag.bytes
            out += anlzBE(s.len_header())
            out += anlzBE(s.len_tag())
            out += s.header
            out += s.payload
        }
        return out
    }
    public static func beat_grid_section(_ beats: [Beat]) -> Section {
        let header = anlzBE(UInt32(0)) + anlzBE(UInt32(0x00080000)) + anlzBE(UInt32(exactly: beats.count) ?? 0)
        return .new(
            "PQTZ", header, beats.flatMap { anlzBE($0.beat_number) + anlzBE($0.tempo_x100) + anlzBE($0.time_ms) })
    }
    public static func extended_grid_empty_section() -> Section {
        var h = [UInt8](repeating: 0, count: 44)
        anlzPut(&h, 4, UInt32(0x01000002))
        return .new("PQT2", h, [])
    }
    public static func vbr_table_zero_section() -> Section {
        .new("PVBR", anlzBE(UInt32(0)), [UInt8](repeating: 0, count: 401 * 4))
    }
}
public final class AnlzBuilder {
    private var extra: [UInt8] = [0, 0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]
    private var sections: [Section] = []
    public init() {}
    public static func new() -> AnlzBuilder { AnlzBuilder() }
    public static func `default`() -> AnlzBuilder { AnlzBuilder() }
    @discardableResult public func header_extra(_ bytes: [UInt8]) -> AnlzBuilder {
        extra = bytes
        return self
    }
    @discardableResult public func path(_ path: String) -> AnlzBuilder {
        let text = path.utf16.flatMap(anlzBE) + [0, 0]
        sections.append(.new("PPTH", anlzBE(UInt32(exactly: text.count) ?? 0), text))
        return self
    }
    @discardableResult public func beat_grid(_ beats: [Beat]) -> AnlzBuilder {
        sections.append(Write.beat_grid_section(beats))
        return self
    }
    @discardableResult public func waveform_preview(_ tag: [UInt8], _ data: [UInt8]) -> AnlzBuilder {
        let header = anlzBE(UInt32(exactly: data.count) ?? 0) + anlzBE(UInt32(0x00010000))
        sections.append(.new(tag, header, data))
        return self
    }
    @discardableResult public func waveform_preview(_ tag: String, _ data: [UInt8]) -> AnlzBuilder {
        waveform_preview(Array(tag.utf8), data)
    }
    @discardableResult public func waveform_scroll(_ tag: [UInt8], _ stride: UInt32, _ data: [UInt8]) -> AnlzBuilder {
        let entries = stride == 0 ? 0 : data.count / Int(stride)
        let trailer: UInt32 = tag == Array("PWV5".utf8) ? 0x00960305 : tag == Array("PWV4".utf8) ? 0 : 0x00960000
        var header = anlzBE(stride) + anlzBE(UInt32(exactly: entries) ?? 0)
        if tag != Array("PWV6".utf8) { header += anlzBE(trailer) }
        sections.append(.new(tag, header, data))
        return self
    }
    @discardableResult public func waveform_scroll(_ tag: String, _ stride: UInt32, _ data: [UInt8]) -> AnlzBuilder {
        waveform_scroll(Array(tag.utf8), stride, data)
    }
    @discardableResult public func vbr_table_zero() -> AnlzBuilder {
        sections.append(Write.vbr_table_zero_section())
        return self
    }
    @discardableResult public func cue_lists(_ extended: Bool) -> AnlzBuilder {
        for kind in [UInt32(1), 0] {
            sections.append(.new("PCOB", anlzBE(kind) + [0, 0, 0, 0, 255, 255, 255, 255], []))
        }
        if extended { for kind in [UInt32(1), 0] { sections.append(.new("PCO2", anlzBE(kind) + [0, 0, 0, 0], [])) } }
        return self
    }
    @discardableResult public func extended_grid_empty() -> AnlzBuilder {
        sections.append(Write.extended_grid_empty_section())
        return self
    }
    @discardableResult public func empty_cue_list(_ extended: Bool) -> AnlzBuilder { empty_cue_list_of(extended, 0) }
    @discardableResult public func empty_cue_list_of(_ extended: Bool, _ list_type: UInt32) -> AnlzBuilder {
        sections.append(.new(extended ? "PCO2" : "PCOB", anlzBE(list_type) + [UInt8](repeating: 0, count: 8), []))
        return self
    }
    @discardableResult public func copy_section(_ section: Section) -> AnlzBuilder {
        sections.append(section)
        return self
    }
    @discardableResult public func raw(_ tag: Tag, _ header: [UInt8], _ payload: [UInt8]) -> AnlzBuilder {
        sections.append(Section(tag: tag, header: header, payload: payload))
        return self
    }
    public func finish() -> [UInt8] { Write.render(extra, sections) }
}
