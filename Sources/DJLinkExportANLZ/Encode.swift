// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/src/encode.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

public struct BandColumn: Equatable, Sendable {
    public var low: UInt8, mid: UInt8, high: UInt8, peak: UInt8
    public init(low: UInt8 = 0, mid: UInt8 = 0, high: UInt8 = 0, peak: UInt8 = 0) {
        self.low = low
        self.mid = mid
        self.high = high
        self.peak = peak
    }
    public static func `default`() -> BandColumn { BandColumn() }
}
public struct AnalysisFiles: Equatable, Sendable {
    public var dat: [UInt8], ext: [UInt8], two_ex: [UInt8]
    public init(dat: [UInt8], ext: [UInt8], two_ex: [UInt8]) {
        self.dat = dat
        self.ext = ext
        self.two_ex = two_ex
    }
}
public struct Existing: Equatable, Sendable {
    public var dat: Anlz?, ext: Anlz?, two_ex: Anlz?
    public init(dat: Anlz? = nil, ext: Anlz? = nil, two_ex: Anlz? = nil) {
        self.dat = dat
        self.ext = ext
        self.two_ex = two_ex
    }
    public static func `default`() -> Existing { Existing() }
}
public enum Encode {
    public static let OVERVIEW_COLUMNS = 1200, PREVIEW_COLUMNS = 400, TINY_COLUMNS = 100
    static let BAND_FULL_SCALE: UInt32 = 44, PWAV_CEILING: UInt32 = 25, PWV2_CEILING: UInt32 = 15,
        DETAIL_CEILING: UInt32 = 31
    static let PWAV_FLOOR: UInt8 = 2, PWV2_FLOOR: UInt8 = 1
    public static let PWV2_MAX_BYTE: UInt8 = 15
    public static func resample(_ columns: [BandColumn], _ n: Int) -> [BandColumn] {
        guard n > 0 else { return [] }
        guard !columns.isEmpty else { return [BandColumn](repeating: BandColumn(), count: n) }
        return (0..<n).map { bucket in
            let start = bucket * columns.count / n
            let end = min(max((bucket + 1) * columns.count / n, start + 1), columns.count)
            return columns[start..<end].reduce(BandColumn()) {
                BandColumn(
                    low: max($0.low, $1.low), mid: max($0.mid, $1.mid), high: max($0.high, $1.high),
                    peak: max($0.peak, $1.peak))
            }
        }
    }
    static func band(_ value: UInt8) -> UInt8 { UInt8(UInt32(value) * BAND_FULL_SCALE / 255) }
    static func band_height(_ column: BandColumn, _ ceiling: UInt32) -> UInt32 {
        min(UInt32(max(band(column.low), band(column.mid), band(column.high))) * ceiling / BAND_FULL_SCALE, ceiling)
    }
    static func detail_height(_ column: BandColumn) -> UInt32 {
        let full: UInt32 = 255 * 255
        let peak = UInt32(column.peak)
        return min((DETAIL_CEILING * peak * peak + full / 2) / full, DETAIL_CEILING)
    }
    static func mono_byte(_ column: BandColumn, _ height: UInt32) -> UInt8 {
        let total = UInt32(column.low) + UInt32(column.mid) + UInt32(column.high)
        let whiteness = total == 0 ? 0 : (UInt32(column.high) * 7 + total / 2) / total
        return UInt8(min(whiteness, 7) << 5 | min(height, DETAIL_CEILING))
    }
    public static func pwav(_ columns: [BandColumn]) -> [UInt8] {
        resample(columns, PREVIEW_COLUMNS).map { device_preview_byte(mono_byte($0, band_height($0, PWAV_CEILING))) }
    }
    public static func pwv2(_ columns: [BandColumn]) -> [UInt8] {
        resample(columns, TINY_COLUMNS).map { device_tiny_preview_byte(UInt8(band_height($0, PWV2_CEILING))) }
    }
    public static func device_preview_byte(_ byte: UInt8) -> UInt8 { (byte & 0xe0) | max(byte & 0x1f, PWAV_FLOOR) }
    public static func device_tiny_preview_byte(_ byte: UInt8) -> UInt8 {
        min(max(byte & 0x1f, PWV2_FLOOR), PWV2_MAX_BYTE)
    }
    public static func with_device_preview(_ section: Section) -> Section {
        let repair: (UInt8) -> UInt8
        if section.tag == Tag("PWAV") {
            repair = device_preview_byte
        } else if section.tag == Tag("PWV2") {
            repair = device_tiny_preview_byte
        } else {
            return section
        }
        return Section(tag: section.tag, header: section.header, payload: section.payload.map(repair))
    }
    public static func pwv3(_ columns: [BandColumn]) -> [UInt8] { columns.map { mono_byte($0, detail_height($0)) } }
    public static func pwv4(_ columns: [BandColumn]) -> [UInt8] {
        resample(columns, OVERVIEW_COLUMNS).flatMap { c in
            [c.peak >> 1, 0, 0, c.low >> 1, UInt8(UInt32(c.mid >> 1) * 4 / 5), UInt8(UInt32(c.high >> 1) * 13 / 20)]
        }
    }
    static func pwv5_colour(_ column: BandColumn) -> (UInt16, UInt16, UInt16) {
        let low = 2 * UInt32(column.low)
        let mid = 2 * UInt32(column.mid)
        let high = 3 * UInt32(column.high)
        let strongest = max(low, mid, high)
        guard strongest != 0 else { return (0, 0, 0) }
        func share(_ value: UInt32, _ full: UInt32) -> UInt16 {
            UInt16((2 * full * value + strongest) / (2 * strongest))
        }
        return (share(low, 7), share(mid, 5), share(high, 7))
    }
    public static func pwv5(_ columns: [BandColumn]) -> [UInt8] {
        columns.flatMap { c in
            let (red, green, blue) = pwv5_colour(c)
            let word = red << 13 | green << 10 | blue << 7 | UInt16(detail_height(c)) << 2
            return anlzBE(word)
        }
    }
    public static func pwv6(_ columns: [BandColumn]) -> [UInt8] {
        resample(columns, OVERVIEW_COLUMNS).flatMap { [band($0.low), band($0.mid), band($0.high)] }
    }
    public static func pwv7(_ columns: [BandColumn]) -> [UInt8] {
        columns.flatMap { [$0.low >> 1, $0.mid >> 1, $0.high >> 1] }
    }
    public static func share_tree_ppth(_ audio_path: String) -> String {
        "?/" + (audio_path.components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? audio_path)
    }
    private static let AUTHORED = [
        "PPTH", "PVBR", "PQTZ", "PWAV", "PWV2", "PWV3", "PWV4", "PWV5", "PWV6", "PWV7", "PQT2",
    ].map(Tag.init)
    private static let CUE_LISTS = [Tag("PCOB"), Tag("PCO2")]
    public static func author(_ ppth: String, _ beats: [Beat], _ columns: [BandColumn], _ existing: Existing)
        -> AnalysisFiles
    { author_with_overview(ppth, beats, columns, nil, existing) }
    public static func author_with_overview(
        _ ppth: String, _ beats: [Beat], _ columns: [BandColumn], _ overview: [[UInt8]]?, _ existing: Existing
    ) -> AnalysisFiles {
        func builder(_ existing: Anlz?) -> AnlzBuilder {
            let b = AnlzBuilder()
            if let existing { b.header_extra(existing.header_extra) }
            return b.path(ppth)
        }
        let dat = builder(existing.dat)
        if let pvbr = existing.dat?.section("PVBR") { dat.copy_section(pvbr) } else { dat.vbr_table_zero() }
        dat.beat_grid(beats).waveform_preview("PWAV", pwav(columns)).waveform_preview("PWV2", pwv2(columns))
        cue_lists_of(dat, existing.dat, false)
        carry(dat, existing.dat)
        let ext = builder(existing.ext).waveform_scroll("PWV3", 1, pwv3(columns))
        cue_lists_of(ext, existing.ext, true)
        ext.waveform_scroll("PWV5", 2, pwv5(columns)).waveform_scroll("PWV4", 6, pwv4(columns))
        carry(ext, existing.ext)
        let two = builder(existing.two_ex)
        let preview = overview.map { $0.flatMap { $0.map { min($0, 127) } } } ?? pwv6(columns)
        two.waveform_scroll("PWV7", 3, pwv7(columns)).waveform_scroll("PWV6", 3, preview)
        carry(two, existing.two_ex)
        return AnalysisFiles(dat: dat.finish(), ext: ext.finish(), two_ex: two.finish())
    }
    private static func cue_lists_of(_ builder: AnlzBuilder, _ existing: Anlz?, _ extended: Bool) {
        let carried = existing?.sections.filter { CUE_LISTS.contains($0.tag) } ?? []
        if carried.contains(where: { !$0.payload.isEmpty }) {
            for section in carried { builder.copy_section(section) }
        } else {
            builder.cue_lists(extended)
        }
    }
    private static func carry(_ builder: AnlzBuilder, _ existing: Anlz?) {
        for s in existing?.sections ?? [] where !AUTHORED.contains(s.tag) && !CUE_LISTS.contains(s.tag) {
            builder.copy_section(s)
        }
    }
    public static func beat_grid_of<S: Sequence>(_ beats: S) -> [Beat] where S.Element == (UInt16, UInt16, UInt32) {
        beats.map { Beat(beat_number: $0.0, tempo_x100: $0.1, time_ms: $0.2) }
    }
    public static func grid_section(_ beats: [Beat]) -> Section { Write.beat_grid_section(beats) }
}
public func author(_ ppth: String, _ beats: [Beat], _ columns: [BandColumn], _ existing: Existing) -> AnalysisFiles {
    Encode.author(ppth, beats, columns, existing)
}
public func author_with_overview(
    _ ppth: String, _ beats: [Beat], _ columns: [BandColumn], _ overview: [[UInt8]]?, _ existing: Existing
) -> AnalysisFiles { Encode.author_with_overview(ppth, beats, columns, overview, existing) }
public func share_tree_ppth(_ audio_path: String) -> String { Encode.share_tree_ppth(audio_path) }
