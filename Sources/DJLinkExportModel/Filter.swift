// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-index/src/filter.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 열별 필터와 원본의 재생목록·폴더·스마트 목록 범위를 옮겼다.
import Foundation

public let COLOR_NAMES = ["Pink", "Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple"]
public struct BpmFilter: Equatable, Sendable {
    public var values: [UInt32]
    public var tolerance_pct: UInt8
    public var master_bpm_x100: UInt32?
    public init(values: [UInt32] = [], tolerance_pct: UInt8 = 0, master_bpm_x100: UInt32? = nil) {
        self.values = values
        self.tolerance_pct = tolerance_pct
        self.master_bpm_x100 = master_bpm_x100
    }
    public static func `default`() -> Self { Self() }
}
public struct TrackFilter: Equatable, Sendable {
    public var bpm: BpmFilter?
    public var keys: [UInt32]?
    public var ratings: [UInt8]?
    public var colors: [UInt8]?
    public init(bpm: BpmFilter? = nil, keys: [UInt32]? = nil, ratings: [UInt8]? = nil, colors: [UInt8]? = nil) {
        self.bpm = bpm
        self.keys = keys
        self.ratings = ratings
        self.colors = colors
    }
    public static func `default`() -> Self { Self() }
    public func is_empty() -> Bool { bpm == nil && keys == nil && ratings == nil && colors == nil }
    func compile() -> CompiledFilter {
        let rating_mask = ratings.map { $0.reduce(UInt8(0)) { $0 | (UInt8(1) << min($1, 7)) } }
        let color_mask = colors.map { $0.reduce(UInt16(0)) { $0 | (UInt16(1) << min($1, 15)) } }
        let rule = bpm.map { b -> BpmRule in
            if b.values.isEmpty {
                return BpmRule(
                    ranges: b.master_bpm_x100.map { [band($0, b.tolerance_pct)] } ?? [], whole: [],
                    any: b.master_bpm_x100 == nil)
            }
            if b.tolerance_pct == 0 { return BpmRule(ranges: [], whole: Array(Set(b.values)).sorted(), any: false) }
            return BpmRule(ranges: b.values.map { band(sat_mul($0, 100), b.tolerance_pct) }, whole: [], any: false)
        }
        return CompiledFilter(
            bpm: rule, keys: keys.map { Array(Set($0)).sorted() }, ratings: rating_mask, colors: color_mask)
    }
}
func sat_add(_ a: UInt32, _ b: UInt32) -> UInt32 {
    let (v, overflow) = a.addingReportingOverflow(b)
    return overflow ? .max : v
}
func sat_mul(_ a: UInt32, _ b: UInt32) -> UInt32 {
    let (v, overflow) = a.multipliedReportingOverflow(by: b)
    return overflow ? .max : v
}
func band(_ centre_x100: UInt32, _ pct: UInt8) -> (UInt32, UInt32) {
    let spread = UInt32(exactly: UInt64(centre_x100) * UInt64(pct) / 100) ?? .max
    return (centre_x100 >= spread ? centre_x100 - spread : 0, sat_add(centre_x100, spread))
}
public func whole_bpm(_ bpm_x100: UInt32) -> UInt32 { sat_add(bpm_x100, 50) / 100 }
struct BpmRule {
    var ranges: [(UInt32, UInt32)]
    var whole: [UInt32]
    var any: Bool
    func matches(_ bpm: UInt32) -> Bool {
        any || (!whole.isEmpty ? whole.contains(whole_bpm(bpm)) : ranges.contains { $0.0 <= bpm && bpm <= $0.1 })
    }
}
struct CompiledFilter {
    var bpm: BpmRule?
    var keys: [UInt32]?
    var ratings: UInt8?
    var colors: UInt16?
    func matches(_ lib: Library, _ row: Row) -> Bool {
        let index = Int(row)
        if let bpm, !bpm.matches(lib.bpm_x100.at(index) ?? 0) { return false }
        if let keys, !keys.contains(lib.key.at(index) ?? NO_ID) { return false }
        if let ratings, ratings & (1 << min(lib.rating.at(index) ?? 0, 7)) == 0 { return false }
        if let colors, colors & (1 << min(lib.color.at(index) ?? 0, 15)) == 0 { return false }
        return true
    }
}
public struct Counted<T: Equatable & Sendable>: Equatable, Sendable {
    public var value: T
    public var count: UInt32
    public init(value: T, count: UInt32) {
        self.value = value
        self.count = count
    }
}
public struct TagCategory: Equatable, Sendable {
    public var name: String
    public var tags: [String]
    public init(name: String = "", tags: [String] = []) {
        self.name = name
        self.tags = tags
    }
}
public struct FilterValues: Equatable, Sendable {
    public var bpms: [Counted<UInt32>]
    public var keys: [Counted<String>]
    public var tags: [TagCategory]
    public init(bpms: [Counted<UInt32>] = [], keys: [Counted<String>] = [], tags: [TagCategory] = []) {
        self.bpms = bpms
        self.keys = keys
        self.tags = tags
    }
}
func filter_camelot_rank(_ name: String) -> (UInt8, UInt8) {
    // 원본 filter 모듈은 키 자체가 Camelot 코드인 경우를 인식하지 않는다.
    let minors = ["Abm", "Ebm", "Bbm", "Fm", "Cm", "Gm", "Dm", "Am", "Em", "Bm", "F#m", "Dbm"]
    let majors = ["B", "F#", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E"]
    let trimmed = modelTrim(name)
    let name =
        [
            "G#m": "Abm", "D#m": "Ebm", "A#m": "Bbm", "C#m": "Dbm", "Gbm": "F#m", "Gb": "F#", "C#": "Db", "G#": "Ab",
            "D#": "Eb", "A#": "Bb",
        ][trimmed] ?? trimmed
    if let i = minors.firstIndex(of: name) { return (UInt8(i), 0) }
    if let i = majors.firstIndex(of: name) { return (UInt8(i), 1) }
    return (.max, 2)
}
extension Library {
    public func filter_values(_ spec: ViewSpec) -> FilterValues { filter_values_scoped(spec, .all) }
    public func filter_values_scoped(_ spec: ViewSpec, _ field: SearchField) -> FilterValues {
        values_of(
            open_view_scoped(
                ViewSpec(
                    source: spec.source, sort: .trackNo, descending: false, query: spec.query, filter: TrackFilter()),
                field
            ).rows)
    }
    public func values_of(_ rows: [Row]) -> FilterValues {
        var bpm_counts: [UInt32: UInt32] = [:]
        var key_counts = [UInt32](repeating: 0, count: keys.len())
        for row in rows {
            let index = Int(row)
            let whole = whole_bpm(bpm_x100.at(Int(row)) ?? 0)
            if whole > 0 { bpm_counts[whole, default: 0] += 1 }
            let id = key.at(index) ?? NO_ID
            if Int(id) < key_counts.count { key_counts[Int(id)] += 1 }
        }
        let bpms = bpm_counts.map { Counted(value: $0.key, count: $0.value) }.sorted { $0.value < $1.value }.prefix(
            1000)
        var by_name: [String: UInt32] = [:]
        for (id, count) in key_counts.enumerated() {
            let name = keys.name(UInt32(exactly: id) ?? NO_ID)
            if count > 0, !modelTrim(name).isEmpty {
                by_name[name, default: 0] += count
            }
        }
        let sorted = by_name.map { Counted(value: $0.key, count: $0.value) }.sorted {
            let a = filter_camelot_rank($0.value)
            let b = filter_camelot_rank($1.value)
            return a == b ? fold($0.value).utf8.lexicographicallyPrecedes(fold($1.value).utf8) : a < b
        }
        return FilterValues(bpms: Array(bpms), keys: sorted, tags: my_tags())
    }
    public func key_ids_named(_ names: [String]) -> [UInt32] {
        (0..<keys.len()).compactMap { id in
            let dense = UInt32(exactly: id) ?? NO_ID
            return names.contains(keys.name(dense)) ? dense : nil
        }
    }
    public func source_rows(_ source: TrackSource) -> [Row] { source_rows_on(source, SmartDate.today()) }
    public func source_rows_on(_ source: TrackSource, _ today: SmartDate) -> [Row] {
        switch source {
        case .history(let index): return histories().members.at(index) ?? []
        case .related(let track, let criterion): return related_rows(track, criterion)
        case .tagList: return tag_list()
        default: return source_rows_unlocked_on(playlists(), source, today)
        }
    }
    public func source_rows_unlocked(_ playlists: Playlists, _ source: TrackSource) -> [Row] {
        source_rows_unlocked_on(playlists, source, SmartDate.today())
    }
    public func source_rows_unlocked_on(_ playlists: Playlists, _ source: TrackSource, _ today: SmartDate) -> [Row] {
        switch source {
        case .collection, .history: return (0..<count).compactMap(Row.init(exactly:))
        case .playlist(let index): return playlists.members.at(index) ?? []
        case .playlistFolder(let folder):
            guard playlists.is_folder(folder) else { return [] }
            var seen = Set<Row>()
            var rows: [Row] = []
            for index in 0..<playlists.len() {
                if playlists.is_folder(index) { continue }
                var parent = playlists.parent.at(index) ?? NO_ID
                var depth = 0
                while parent != NO_ID && depth < playlists.len() {
                    if Int(parent) == folder {
                        let members =
                            playlists.is_smart(index)
                            ? playlists.smart_rule(index)?.evaluate_on(self, today) ?? []
                            : playlists.members.at(index) ?? []
                        for row in members { if seen.insert(row).inserted { rows.append(row) } }
                        break
                    }
                    parent = playlists.parent.at(Int(parent)) ?? NO_ID
                    depth += 1
                }
            }
            return rows
        case .smartPlaylist(let index): return playlists.smart_rule(index)?.evaluate_on(self, today) ?? []
        case .related(let track, let criterion): return related_rows(track, criterion)
        case .tagList: return tag_list()
        }
    }
}
