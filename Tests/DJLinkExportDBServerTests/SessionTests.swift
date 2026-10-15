import DJLinkExportSupport
import DJLinkExportTestSupport
import DJLinkKit
import DJLinkTestSupport
// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-dbserver/tests/session.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation
import Testing

@testable import DJLinkExportDBServer

private typealias Message = DJLinkExportDBServer.Message
private typealias Query = DJLinkExportDBServer.Query
private typealias Item = DJLinkExportDBServer.Item

private let CTX: UInt32 = 0x0101_0301
private let AALIYAH: UInt32 = 0x6d5c_28f2
private let ALBUM: UInt32 = 0xdc0d_0bca
private let GENRE: UInt32 = 0x8b0c_83f7
private let TRACK: UInt32 = 0x475f
// 민감할 수 있는 원본 곡 정보와 경로, 캡처 기대 문자열은 외부 고정 원본에서 읽는다.
private func upstream() throws -> String { try UpstreamFixtures.text(crate: "rbl-dbserver", path: "tests/session.rs") }
private func literals(_ text: String) -> [String] {
    let chars = Array(text)
    var i = 0
    var out: [String] = []
    while i < chars.count {
        guard chars[i] == "\"" else {
            i += 1
            continue
        }
        i += 1
        var value = ""
        while i < chars.count, chars[i] != "\"" {
            if chars[i] == "\\", i + 1 < chars.count {
                i += 1
                switch chars[i] {
                case "n": value += "\n"
                case "r": value += "\r"
                case "t": value += "\t"
                case "0": value += "\0"
                case "u" where i + 1 < chars.count && chars[i + 1] == "{":
                    i += 2
                    var digits = ""
                    while i < chars.count, chars[i] != "}" {
                        digits.append(chars[i])
                        i += 1
                    }
                    if let v = UInt32(digits, radix: 16), let s = Unicode.Scalar(v) { value.unicodeScalars.append(s) }
                default: value.append(chars[i])
                }
            } else {
                value.append(chars[i])
            }
            i += 1
        }
        out.append(value)
        i += 1
    }
    return out
}
private func source_string(_ marker: String) throws -> String {
    let text = try upstream()
    let r = try #require(text.range(of: marker))
    return try #require(literals(String(text[r.upperBound...])).first)
}
private func expected(_ fn: String) throws -> [String] {
    let text = try upstream()
    let start = try #require(text.range(of: "fn \(fn)()"))
    let tail = String(text[start.upperBound...])
    let body = tail.components(separatedBy: "#[test]").first!
    return literals(body).filter { $0.hasPrefix("0x") && $0.contains(", ") }
}
private func hex(_ s: String) -> [UInt8] {
    stride(from: 0, to: s.count, by: 2).map {
        let a = s.index(s.startIndex, offsetBy: $0)
        return UInt8(s[a..<s.index(a, offsetBy: 2)], radix: 16)!
    }
}
private func expected_hex(_ fn: String, _ index: Int = 0) throws -> [UInt8] {
    let text = try upstream()
    let start = try #require(text.range(of: "fn \(fn)()"))
    let body = String(text[start.upperBound...]).components(separatedBy: "#[test]").first!
    return hex(literals(body).filter { $0.hasPrefix("11872349ae") }[index])
}
private func the_track() throws -> TrackRow {
    TrackRow(
        id: TRACK, title: try source_string("title:"), secondary_text: try source_string("secondary_text:"),
        column: .comment, column_value: 0, key: 0x14, key_id: 0x1814_5d65, key_name: "D", bpm_x100: 0x1e80)
}
@DJLinkActor private class EmptyCatalog: Catalog {
    func sorts() -> [Sort] { Sort.DEFAULTS }
    func key_name(_ id: UInt32) -> String { keys.name(id) }
    func file_name_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? { track_row(id, column) }
    func played(_ track: UInt32) -> Bool { false }
    func hot_cue_banks(_ parent: UInt32?) -> [HotCueBank] { [] }
    func hot_cue_bank_cues(_ bank: UInt32) -> [HotCueBankCue] { [] }
    func hot_cue_bank_tracks(_ bank: UInt32) -> [TrackRow] { [] }
    func usb_cues(_ track: UInt32) -> [UsbCue] { [] }
    func edit(_ edit: Edit) -> Bool { false }
    func tagged(_ track: UInt32) -> Bool { false }
    func grid_offset(_ track: UInt32) -> Int16 { 0 }
    func list(_ query: Query) -> [Row] { [] }
    func track_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? { nil }
    func track(_ id: UInt32) -> TrackDetails? { nil }
    func artwork(_ id: UInt32) -> [UInt8]? { nil }
    func item_artwork(_ id: UInt32) -> [UInt8]? { nil }
    func analysis(_ track: UInt32, _ what: Analysis) -> [UInt8]? { nil }
}
@DJLinkActor private final class Small: EmptyCatalog {
    let wasPlayed: Bool
    let row: TrackRow
    let fileName: String
    let details: TrackDetails
    init(_ played: Bool = false) throws {
        wasPlayed = played
        row = try the_track()
        fileName = try source_string("track.title =")
        details = TrackDetails(
            row: row, comment: try source_string("comment:"), key_id: 0x1814_5d65, key_name: "11B", artist_id: AALIYAH,
            artist: try source_string("artist:"), duration_s: 0x122, genre_id: GENRE, genre: "Pop",
            date_added: "2023-08-06", year: 0x140, bit_rate_kbps: 0x7ca, path: try source_string("path:"),
            file_size: 0xb1_1858, file_type: 1)
    }
    override func list(_ query: Query) -> [Row] {
        switch query {
        case .bpmBuckets: return [.date(7800)]
        case .ratings: return [.date(1), .date(0)]
        case .bitrates: return [.date(320), .date(0)]
        case .colors: return [.named(id: 1, name: "Pink"), .named(id: 8, name: "Purple")]
        case .durationMinutes: return [.date(11), .date(0)]
        case .releaseDecades: return [.date(2020), .date(1990)]
        case .releaseYears(2020): return [.date(2024), .date(2023)]
        case .genres: return [.named(id: GENRE, name: "Pop")]
        case .genreArtists, .labelArtists, .artists: return [.named(id: AALIYAH, name: details.artist)]
        case .genreArtistAlbums, .labelArtistAlbums, .albums, .artistAlbums:
            return [.named(id: ALBUM, name: details.artist)]
        case .labels: return [.named(id: 0x1234, name: "Ablazing")]
        case .folder(0):
            return [
                .list(id: 0xaa1f_785f, name: "CURRENT", folder: true, position: 1),
                .list(id: 0xffb7_d23b, name: "NP3-TEST-MP3", folder: false, position: 0xb),
            ]
        case .histories: return [.named(id: 0x68ef_cd5c, name: "LINK HISTORY 2026-09-11")]
        case .years: return [.date(2026), .date(2025)]
        case .months(2026): return [.date(1), .date(2)]
        case .tracks(scope: .album(ALBUM), sort: _): return [.track(id: TRACK, position: 0x55)]
        case .tracks: return [.track(id: TRACK, position: 0)]
        default: return []
        }
    }
    override func track_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? {
        guard id == TRACK else { return nil }
        var track = row
        if let column {
            track.column = column
            switch column {
            case .artist:
                track.column_value = AALIYAH
                track.secondary_text = details.artist
            case .bpm:
                track.column_value = track.bpm_x100
                track.secondary_text = ""
            case .title:
                track.column_value = 0
                track.secondary_text = ""
            default: break
            }
        }
        return track
    }
    override func file_name_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? {
        guard var t = track_row(id, column) else { return nil }
        t.title = fileName
        return t
    }
    override func track(_ id: UInt32) -> TrackDetails? { id == TRACK ? details : nil }
    override func played(_ track: UInt32) -> Bool { wasPlayed && track == TRACK }
    override func hot_cue_banks(_ parent: UInt32?) -> [HotCueBank] {
        parent == nil ? [HotCueBank(id: 42, name: "WARMUP", folder: false)] : []
    }
    override func hot_cue_bank_cues(_ bank: UInt32) -> [HotCueBankCue] {
        bank == 42
            ? [
                HotCueBankCue(
                    slot: 1, content: TRACK, in_ms: 1000, out_ms: 2000, color: 3, color_table_index: 21,
                    active_loop: true, beat_loop_size: 0, cue_microsec: 0)
            ] : []
    }
    override func hot_cue_bank_tracks(_ bank: UInt32) -> [TrackRow] { bank == 42 ? [row] : [] }
    override func usb_cues(_ track: UInt32) -> [UsbCue] {
        track == TRACK
            ? [
                UsbCue(slot: 1, in_ms: 3000, out_ms: 4000, color_table_index: 21),
                UsbCue(slot: 0, in_ms: 5000, out_ms: nil, color_table_index: 0),
            ] : []
    }
    override func edit(_ edit: Edit) -> Bool {
        if case .hotCueBankCue(bank: 42, cue: _) = edit { return true }
        return false
    }
    override func artwork(_ id: UInt32) -> [UInt8]? { id == 0x14 ? [0xff, 0xd8, 0xff, 0xe1] : nil }
    override func item_artwork(_ id: UInt32) -> [UInt8]? { id == 0x6272 ? [0xff, 0xd8, 0xff, 0xe0] : nil }
    override func analysis(_ track: UInt32, _ what: Analysis) -> [UInt8]? {
        what == .tag(fourcc: Array("PWV4".utf8), extension_: Array("EXT".utf8)) && track == TRACK
            ? Array("PWV4".utf8) + [1, 2, 3] : nil
    }
}
@DJLinkActor private func session(_ catalog: any Catalog) throws -> any Session {
    let s = CatalogHandler(catalog).open()
    _ = s.handle(setup_request(1))
    return s
}
@DJLinkActor private func session() throws -> any Session { try session(Small()) }
private func numbers(_ kind: UInt16, _ tx: UInt32, _ args: [UInt32]) -> Message {
    .new(tx, kind, args.map { .number($0) })
}
@DJLinkActor private func browse(_ s: any Session, _ k: UInt16, _ args: [UInt32]) -> (UInt32, [Message]) {
    let h = s.handle(numbers(k, 0x100, args))
    #expect(h.count == 1)
    #expect(h[0].kind == kind.MENU_HEADER)
    #expect(h[0].arguments[0] == .number(UInt32(k)))
    guard case let .number(count) = h[0].arguments[1] else {
        Issue.record("count")
        return (0, [])
    }
    let rendered = s.handle(numbers(kind.RENDER, 0x101, [args[0], 0, count, 0, count, 0xc, 1, 0]))
    #expect(rendered[0] == .new(0x101, kind.RENDER_HEADER, [.number(1), .number(0)]))
    #expect(rendered.last?.kind == kind.MENU_FOOTER)
    return (count, Array(rendered.dropFirst().dropLast()))
}
private func rust_debug(_ s: String) -> String {
    var out = "\""
    for c in s.unicodeScalars {
        switch c.value {
        case 0xfffa, 0xfffb: out += "\\u{\(String(c.value,radix:16))}"
        case 34: out += "\\\""
        case 92: out += "\\\\"
        case 10: out += "\\n"
        case 13: out += "\\r"
        case 9: out += "\\t"
        default: out.unicodeScalars.append(c)
        }
    }
    return out + "\""
}
private func args(_ item: Message) -> String {
    item.arguments.map {
        switch $0 {
        case let .number(n): return "0x" + String(n, radix: 16)
        case let .string(s): return rust_debug(s)
        case let .blob(b): return "blob[\(b.count)]"
        }
    }.joined(separator: ", ")
}
@Suite @DJLinkActor struct SessionTests {
    @Test("xdj700_vbr_upload_is_silent_and_preserves_the_browse_menu")
    func xdj700_vbr_upload_is_silent_and_preserves_the_browse_menu() throws {
        let bytes = try UpstreamFixtures.bytes(crate: "rbl-dbserver", path: "tests/corpus/xdj700-save-vbr.bin")
        let (upload, consumed) = try Message.decode(bytes)
        #expect(consumed == bytes.count)
        #expect(upload.kind == kind.SAVE_VBR)
        #expect(upload.arguments[2] == .number(1604))
        let s = try session()
        let context: UInt32 = 0x0203_0401
        let render = numbers(kind.RENDER, upload.transaction + 1, [context, 0, 1, 0, 1, 0])
        _ = s.handle(numbers(kind.TRACK_MENU, upload.transaction - 1, [context, 0]))
        let expected = s.handle(render)
        #expect(expected.contains { $0.kind == kind.MENU_ITEM })
        #expect(s.handle(upload).isEmpty)
        #expect(s.handle(render) == expected)
    }
    @Test("waveform_upload_is_silent_and_preserves_the_browse_menu")
    func waveform_upload_is_silent_and_preserves_the_browse_menu() throws {
        let s = try session()
        let context: UInt32 = 0x0203_0401
        let upload = Message.new(
            0x5800_002f, kind.SAVE_WAVEFORM,
            [
                .number(context), .number(0), .number(TRACK), .number(0), .number(900),
                .blob(Array(repeating: 0, count: 900)),
            ])
        let render = numbers(kind.RENDER, upload.transaction + 1, [context, 0, 1, 0, 1, 0])
        _ = s.handle(numbers(kind.TRACK_MENU, upload.transaction - 1, [context, 0]))
        let expected = s.handle(render)
        #expect(expected.contains { $0.kind == kind.MENU_ITEM })
        #expect(s.handle(upload).isEmpty)
        #expect(s.handle(render) == expected)
    }
    @Test("the_root_menu_matches_the_captured_cdj_3000_rekordbox_response")
    func the_root_menu_matches_the_captured_cdj_3000_rekordbox_response() throws {
        let (count, items) = browse(try session(), kind.ROOT_MENU, [CTX, 0, 0x5cf_ffff])
        #expect(count == 9)
        let e: [(UInt32, String, UInt32)] = [
            (2, "ARTIST", 0x81), (3, "ALBUM", 0x82), (4, "TRACK", 0x83), (12, "KEY", 0x8b), (5, "PLAYLIST", 0x84),
            (22, "HISTORY", 0x95), (18, "SEARCH", 0x91), (26, "MATCHING", 0xaa), (27, "DATE ADDED", 0x8c),
        ]
        #expect(items.count == e.count)
        for (item, v) in zip(items, e) {
            #expect(item.arguments[1] == .number(v.0))
            #expect(item.arguments[3] == .string("\u{fffa}\(v.1)\u{fffb}"))
            #expect(item.arguments[6] == .number(v.2))
        }
        var captured = items[0]
        captured.transaction = 0x180
        #expect(captured.encode() == (try expected_hex(#function.components(separatedBy: "(")[0])))
    }
    @Test("the_root_menu_filters_configured_rows_with_the_players_mask")
    func the_root_menu_filters_configured_rows_with_the_players_mask() throws {
        for (bit, id): (UInt32, UInt32) in [
            (1, 2), (2, 3), (3, 4), (10, 12), (16, 5), (18, 22), (19, 18), (26, 26), (24, 27),
        ] {
            let (count, items) = browse(try session(), kind.ROOT_MENU, [CTX, 0, 1 << bit])
            #expect(count == 1)
            #expect(items[0].arguments[1] == .number(id))
        }
        let (count, items) = browse(try session(), kind.ROOT_MENU, [CTX, 0, 1 << 0 | 1 << 23])
        #expect(count == 0)
        #expect(items.isEmpty)
    }
    @Test("the_legacy_root_mask_appends_hot_cue_bank_like_rekordbox")
    func the_legacy_root_mask_appends_hot_cue_bank_like_rekordbox() throws {
        let (count, items) = browse(try session(), kind.ROOT_MENU, [CTX, 0, 0x00ff_ffff])
        #expect(count == 8)
        #expect(items.last?.arguments[1] == .number(23))
        #expect(items.last?.arguments[6] == .number(0x98))
    }
    @Test("the_root_menu_uses_rekordboxs_special_disable_rules")
    func the_root_menu_uses_rekordboxs_special_disable_rules() {
        func category(_ id: UInt32, _ menu_item_id: UInt32, _ disable: UInt32) -> RootCategory {
            RootCategory(id: id, menu_item_id: menu_item_id, disable: disable, name: "TEST", item_type: 0)
        }
        #expect(
            root_menu(
                [category(1, 2, 2), category(2, 22, 2), category(3, 27, 2), category(4, 27, 3), category(5, 24, 0)],
                1 << 1 | 1 << 24 | 1 << 26
            ).map { $0.id } == [2, 3])
    }
    @Test("numeric_filter_menus_use_the_captured_item_types") func numeric_filter_menus_use_the_captured_item_types()
        throws
    {
        let s = try session()
        let cases: [(UInt16, [UInt32], UInt32)] = [
            (kind.BPM_MENU, [7800], 0xd), (kind.RATING_MENU, [1, 0], 0xa), (kind.BITRATE_MENU, [320, 0], 0x10),
            (kind.TIME_MENU, [11, 0], 0xb), (kind.RELEASE_DECADES, [2020, 1990], 0x11),
        ]
        for (request, expected, type) in cases {
            let (count, rows) = browse(s, request, [CTX, 0])
            #expect(Int(count) == expected.count)
            #expect(rows.map { $0.arguments[1] } == expected.map { .number($0) })
            #expect(rows.allSatisfy { $0.arguments[6] == .number(type) })
        }
        let (_, colors) = browse(s, kind.COLOR_MENU, [CTX, 0])
        #expect(colors[0].arguments[3] == .string("Pink"))
        #expect(colors[0].arguments[6] == .number(0x14))
        #expect(colors[1].arguments[3] == .string("Purple"))
        #expect(colors[1].arguments[6] == .number(0x1b))
        let (_, ranges) = browse(s, kind.BPM_RANGES, [CTX, 0, 7800])
        #expect(ranges.count == 7)
        #expect(ranges[0].arguments[1] == .number(0))
        #expect(ranges[6].arguments[1] == .number(6))
        #expect(ranges.allSatisfy { $0.arguments[6] == .number(0xd) })
    }
    @Test("release_year_file_name_matching_and_label_paths_render")
    func release_year_file_name_matching_and_label_paths_render() throws {
        let s = try session()
        let (count, years) = browse(s, kind.RELEASE_YEARS, [CTX, 0, 2020])
        #expect(count == 3)
        #expect(years[0].arguments[1] == .number(.max))
        #expect(years[0].arguments[6] == .number(0xa0))
        #expect(years[1].arguments[1] == .number(2024))
        #expect(years[1].arguments[6] == .number(0x11))
        let (_, files) = browse(s, kind.FILE_NAME_MENU, [CTX, 0])
        #expect(files[0].arguments[3] == .string(try source_string("track.title =")))
        #expect(browse(s, kind.MATCHING_TRACKS, [CTX, 0, TRACK]).0 == 1)
        let (_, labels) = browse(s, kind.LABEL_MENU, [CTX, 0])
        #expect(labels[0].arguments[6] == .number(0xe))
        let (c, a) = browse(s, kind.LABEL_ARTISTS, [CTX, 0, 0x1234])
        #expect(c == 1)
        #expect(a[0].arguments[6] == .number(7))
        let (d, b) = browse(s, kind.LABEL_ARTIST_ALBUMS, [CTX, 0, 0x1234, AALIYAH])
        #expect(d == 1)
        #expect(b[0].arguments[6] == .number(2))
        #expect(browse(s, kind.LABEL_ARTIST_ALBUM_TRACKS, [CTX, 0, 0x1234, AALIYAH, ALBUM]).0 == 1)
    }
    @Test("genre_browsing_drills_through_artist_album_and_tracks")
    func genre_browsing_drills_through_artist_album_and_tracks() throws {
        let s = try session()
        for (k, a, id): (UInt16, [UInt32], UInt32) in [
            (kind.GENRE_MENU, [CTX, 0], GENRE), (kind.GENRE_ARTISTS, [CTX, 0, GENRE], AALIYAH),
            (kind.GENRE_ARTIST_ALBUMS, [CTX, 0, GENRE, AALIYAH], ALBUM),
            (kind.GENRE_ARTIST_ALBUM_TRACKS, [CTX, 0, GENRE, AALIYAH, ALBUM], TRACK),
        ] {
            let (c, r) = browse(s, k, a)
            #expect(c == 1)
            #expect(r[0].arguments[1] == .number(id))
            if k == kind.GENRE_MENU { #expect(r[0].arguments[6] == .number(6)) }
        }
    }
    @Test("the_sort_menu_matches_the_capture") func the_sort_menu_matches_the_capture() throws {
        let (c, i) = browse(try session(), kind.SORT_MENU, [0x0105_0301, 0, 0])
        let e = try expected("the_sort_menu_matches_the_capture")
        #expect(c == 7)
        #expect(args(i[0]) == e[0])
        #expect(args(i[6]) == e[1])
    }
    @Test("the_sort_menu_uses_the_catalog_configuration") func the_sort_menu_uses_the_catalog_configuration() throws {
        final class ConfiguredCatalog: EmptyCatalog {
            override func sorts() -> [Sort] { [.dateAdded, .genre, .djPlayCount] }
        }
        let (c, i) = browse(try session(ConfiguredCatalog()), kind.SORT_MENU, [CTX, 0, 0])
        #expect(c == 3)
        for (row, v) in zip(
            i, [(UInt32(0x11), "DATE ADDED", UInt32(0x8c)), (6, "GENRE", 6), (0x10, "DJ PLAY COUNT", 0x97)])
        {
            #expect(row.arguments[1] == .number(v.0))
            #expect(row.arguments[3] == .string("\u{fffa}\(v.1)\u{fffb}"))
            #expect(row.arguments[6] == .number(v.2))
        }
    }
    @Test("the_key_menus_match_the_capture") func the_key_menus_match_the_capture() throws {
        let s = try session()
        let (c, i) = browse(s, kind.KEY_MENU, [CTX, 0])
        let e = try expected("the_key_menus_match_the_capture")
        #expect(c == 24)
        #expect(args(i[0]) == e[0])
        #expect(args(i[23]) == e[1])
        let (d, j) = browse(s, kind.LEGACY_KEY_MENU, [CTX, 0])
        #expect(d == 24)
        #expect(j[0].arguments[1] == .number(1))
        let (f, r) = browse(s, kind.RELATED_KEYS, [0x0102_0301, 0, 1])
        #expect(f == 3)
        for n in 0..<3 { #expect(args(r[n]) == e[n + 2]) }
    }
    @Test("key_menus_use_catalog_display_names") func key_menus_use_catalog_display_names() throws {
        final class Alphanumeric: EmptyCatalog {
            override func key_name(_ id: UInt32) -> String { "\((id+1)/2)\(id%2==1 ? "A":"B")" }
        }
        let s = try session(Alphanumeric())
        let (_, k) = browse(s, kind.KEY_MENU, [CTX, 0])
        #expect(k[0].arguments[3] == .string("1A"))
        #expect(k[23].arguments[3] == .string("12B"))
        let (_, r) = browse(s, kind.RELATED_KEYS, [0x0102_0301, 0, 1])
        for (m, v) in zip(r, ["1A", "1A, 1B", "1A, 1B, 12A, 2A"]) { #expect(m.arguments[3] == .string(v)) }
    }
    @Test("rx3_legacy_key_tracks_are_exact_key_matches") func rx3_legacy_key_tracks_are_exact_key_matches() throws {
        final class Spy: EmptyCatalog {
            var query: Query?
            override func list(_ query: Query) -> [Row] {
                self.query = query
                return []
            }
        }
        let c = Spy()
        let s = try session(c)
        _ = s.handle(numbers(kind.LEGACY_KEY_TRACKS, 2, [CTX, 0, 0xc]))
        #expect(c.query == .tracks(scope: .key(key: 0xc, distance: 0), sort: .default))
    }
    @Test("artists_albums_and_their_tracks_are_shaped_as_captured")
    func artists_albums_and_their_tracks_are_shaped_as_captured() throws {
        let s = try session()
        let e = try expected("artists_albums_and_their_tracks_are_shaped_as_captured")
        let cases: [(UInt16, [UInt32])] = [
            (kind.ARTIST_MENU, [CTX, 0]), (kind.ARTIST_ALBUMS, [CTX, 0, AALIYAH]),
            (kind.ARTIST_ALBUM_TRACKS, [CTX, 0, AALIYAH, .max]), (kind.ALBUM_TRACKS, [CTX, 0, ALBUM]),
            (kind.TRACK_MENU, [CTX, 0]),
        ]
        for (n, v) in cases.enumerated() {
            let (count, i) = browse(s, v.0, v.1)
            if n == 1 { #expect(count == 1) }
            #expect(args(i[0]) == e[n])
        }
    }
    @Test("render_override_selects_the_requested_track_column")
    func render_override_selects_the_requested_track_column() throws {
        let s = try session()
        let h = s.handle(numbers(kind.TRACK_MENU, 1, [CTX, 2]))
        #expect(h[0].arguments[1] == .number(1))
        let row = s.handle(numbers(kind.RENDER, 2, [CTX, 0, 1, 0, 1, 12, 1, 2]))[1].arguments
        #expect(row[0] == .number(AALIYAH))
        #expect(row[5] == .string(try source_string("artist:")))
        #expect(row[6] == .number(0x0704))
        #expect(row[12] == .number(0x1814_5d65))
    }
    @Test("rx3_render_uses_the_active_sort_as_the_track_column")
    func rx3_render_uses_the_active_sort_as_the_track_column() throws {
        let s = try session()
        let h = s.handle(numbers(kind.TRACK_MENU, 1, [CTX, 2]))
        #expect(h[0].arguments[1] == .number(1))
        let row = s.handle(numbers(kind.RENDER, 2, [CTX, 0, 1, 0, 1, 12]))[1].arguments
        #expect(row[0] == .number(AALIYAH))
        #expect(row[5] == .string(try source_string("artist:")))
        #expect(row[6] == .number(0x0704))
        #expect(row[12] == .number(0x1814_5d65))
    }
    @Test("rx3_bpm_sort_renders_bpm_before_key") func rx3_bpm_sort_renders_bpm_before_key() throws {
        let s = try session()
        let h = s.handle(numbers(kind.TRACK_MENU, 1, [CTX, 4]))
        #expect(h[0].arguments[1] == .number(1))
        let row = s.handle(numbers(kind.RENDER, 2, [CTX, 0, 1, 0, 1, 12]))[1].arguments
        #expect(row[0] == .number(0x1e80))
        #expect(row[5] == .string("78.1 bpm - D"))
        #expect(row[6] == .number(0x0d04))
        #expect(row[12] == .number(0x1814_5d65))
        #expect(row[15] == .number(0x1e80))
    }
    @Test("extended_render_without_an_override_uses_the_configured_column")
    func extended_render_without_an_override_uses_the_configured_column() throws {
        let s = try session()
        let h = s.handle(numbers(kind.TRACK_MENU, 1, [CTX, 2]))
        #expect(h[0].arguments[1] == .number(1))
        let row = s.handle(numbers(kind.RENDER, 2, [CTX, 0, 1, 0, 1, 12, 1, 0]))[1].arguments
        #expect(row[5] == .string(try source_string("secondary_text:")))
        #expect(row[6] == .number(0x2304))
    }
    @Test("playlists_histories_and_dates_are_shaped_as_captured")
    func playlists_histories_and_dates_are_shaped_as_captured() throws {
        let s = try session()
        let e = try expected("playlists_histories_and_dates_are_shaped_as_captured")
        let (_, lists) = browse(s, kind.PLAYLIST_MENU, [CTX, 0, 0, 1])
        #expect(args(lists[0]) == e[0])
        #expect(args(lists[1]) == e[1])
        #expect(args(browse(s, kind.PLAYLIST_MENU, [CTX, 0, 0xffb7_d23b, 0]).1[0]).contains(e[2]))
        #expect(args(browse(s, kind.HISTORY_TRACKS, [CTX, 0, 0x68ef_cd5c]).1[0]).contains(e[3]))
        #expect(args(browse(s, kind.HISTORY_MENU, [CTX, 0]).1[0]) == e[4])
        #expect(args(browse(s, kind.YEARS, [CTX, 0]).1[0]) == e[5])
        let (c, m) = browse(s, kind.MONTHS, [CTX, 0, 2026])
        #expect(c == 3)
        #expect(args(m[0]) == e[6])
        #expect(args(m[1]) == e[7])
    }
    @Test("metadata_and_track_info_have_the_captured_rows") func metadata_and_track_info_have_the_captured_rows() throws
    {
        let s = try session()
        let e = try expected("metadata_and_track_info_have_the_captured_rows")
        let (c, i) = browse(s, kind.METADATA, [0x0102_0301, TRACK])
        #expect(c == 16)
        for (j, index) in [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 15].enumerated() { #expect(args(i[index]) == e[j]) }
        let (d, r) = browse(s, kind.TRACK_INFO, [0x0108_0301, TRACK])
        #expect(d == 7)
        for j in 0..<3 { #expect(args(r[j + 4]) == e[j + 12]) }
    }
    @Test("the_kuvo_user_info_and_delivery_info_are_answered_as_captured")
    func the_kuvo_user_info_and_delivery_info_are_answered_as_captured() throws {
        let s = try session()
        let user = s.handle(numbers(0x3006, 0xa2, [0x0309_0301]))
        #expect(user.count == 1)
        let encoded = user[0].encode()
        let header = try expected_hex("the_kuvo_user_info_and_delivery_info_are_answered_as_captured")
        #expect(Array(encoded.prefix(header.count)) == header)
        #expect(encoded.count == header.count + 160)
        #expect(encoded.dropFirst(header.count).allSatisfy { $0 == 0 })
        let (count, items) = browse(s, 0x2602, [0x0309_0301, TRACK])
        let e = try expected("the_kuvo_user_info_and_delivery_info_are_answered_as_captured")
        #expect(count == 13)
        #expect(items.map { args($0) } == e)
    }
    @Test("a_played_track_carries_the_played_bit_everywhere") func a_played_track_carries_the_played_bit_everywhere()
        throws
    {
        let s = try session(Small(true))
        let e = try expected("a_played_track_carries_the_played_bit_everywhere")
        let cases: [(UInt16, [UInt32])] = [
            (kind.ARTIST_ALBUM_TRACKS, [CTX, 0, AALIYAH, .max]), (kind.PLAYLIST_MENU, [CTX, 0, 0xffb7_d23b, 0]),
            (kind.TRACK_MENU, [CTX, 0]), (kind.METADATA, [0x0102_0301, TRACK]),
        ]
        for (j, v) in cases.enumerated() { #expect(args(browse(s, v.0, v.1).1[0]).contains(e[j])) }
    }
    @Test("artwork_and_tags_come_back_as_blobs_or_as_the_no_art_reply")
    func artwork_and_tags_come_back_as_blobs_or_as_the_no_art_reply() throws {
        let s = try session()
        let none = s.handle(numbers(kind.ARTWORK, 0x187, [0x0108_0301, 0xdc0d_0bca, 1]))
        #expect(none[0].encode() == (try expected_hex("artwork_and_tags_come_back_as_blobs_or_as_the_no_art_reply")))
        let e = try expected("artwork_and_tags_come_back_as_blobs_or_as_the_no_art_reply")
        let requests: [(UInt16, UInt32, [UInt32])] = [
            (kind.ARTWORK, 0x1a3, [0x0108_0301, 0x6272, 1]), (kind.CONTENT_ARTWORK, 0x1a3, [0x0108_0301, 0x6272, 0]),
            (kind.ARTWORK, 0x1a4, [0x0108_0301, 0x14]), (kind.ARTWORK, 0x1a5, [0x0108_0301, 0x6272]),
            (kind.ANLZ_TAG, 0x197, [0x0108_0301, TRACK, 0x3456_5750, 0x54_5845]),
            (kind.ANLZ_TAG_2EX, 0x198, [0x0108_0301, TRACK, 0x3656_5750, 0x58_4532]),
            (kind.BEAT_GRID, 0x199, [0x0108_0301, TRACK]),
        ]
        for (j, v) in requests.enumerated() {
            let reply = s.handle(numbers(v.0, v.1, v.2))
            if v.0 == kind.ANLZ_TAG { #expect(reply[0].kind == kind.ANLZ_TAG_REPLY) }
            #expect(args(reply[0]) == e[j])
        }
    }
    @Test("rx3_hot_cue_bank_uses_its_menu_and_cue_envelopes") func rx3_hot_cue_bank_uses_its_menu_and_cue_envelopes()
        throws
    {
        let s = try session()
        let banks = s.handle(numbers(kind.HOT_CUE_BANK, 0x1c0, [CTX, 0, 1]))
        #expect(banks[0].arguments == [.number(0x2001), .number(1)])
        let items = s.handle(numbers(kind.RENDER, 0x1c1, [CTX, 0, 8]))
        #expect(items[1].arguments[1] == .number(42))
        #expect(items[1].arguments[6] == .number(0x2b))
        let reply = s.handle(numbers(kind.HOT_CUE_BANK_CUES, 0x1c2, [CTX, 42]))
        let e = try expected("rx3_hot_cue_bank_uses_its_menu_and_cue_envelopes")
        #expect(reply.count == 1)
        #expect(reply[0].kind == kind.HOT_CUE_BANK_REPLY)
        #expect(args(reply[0]) == e[0])
        if case let .blob(record) = reply[0].arguments[3] {
            #expect(Array(record.prefix(8)) == [1, 1, 4, 0, 0x5f, 0x47, 0, 0])
        } else {
            Issue.record("cue record")
        }
        let tracks = s.handle(numbers(kind.HOT_CUE_BANK, 0x1c3, [CTX, 42, 0]))
        #expect(tracks[0].arguments == [.number(0x2001), .number(1)])
        #expect(s.handle(numbers(kind.RENDER, 0x1c4, [CTX, 0, 8]))[1].arguments[1] == .number(TRACK))
        func change(_ track: UInt32) -> Message {
            let words: [UInt32] = [0x0004_0101, track, 0, 150, 300, 0, 21, 0, 0]
            return .new(
                0x1c5, kind.CHANGE_HOT_CUE_BANK,
                [
                    .number(CTX), .number(42), .number(0x24), .blob(words.flatMap { dbLE($0) }), .number(8),
                    .blob(dbLE(UInt32(1000)) + dbLE(UInt32(2000))),
                ])
        }
        let changed = s.handle(change(TRACK))
        #expect(args(changed[0]) == e[1])
        if case let .blob(b) = changed[0].arguments[3] {
            #expect(Array(b.prefix(8)) == [1, 1, 1, 0, 0, 0, 0, 0])
        } else {
            Issue.record("USB cue records")
        }
        let (decoded, used) = try Message.decode(reply[0].encode())
        #expect(used == reply[0].encode().count)
        #expect(decoded == reply[0])
        #expect(args(s.handle(change(TRACK + 1))[0]) == e[2])
        let missing = s.handle(numbers(kind.HOT_CUE_BANK_CUES, 0x1c6, [CTX, 999]))
        #expect(args(missing[0]) == e[3])
        let (empty, n) = try Message.decode(missing[0].encode())
        #expect(n == missing[0].encode().count)
        #expect(empty == missing[0])
        #expect(args(s.handle(numbers(kind.HOT_CUE_BANK_CUES, 0x1c6, [CTX & ~UInt32(0xff), 42]))[0]) == e[4])
        #expect(args(s.handle(numbers(kind.CHANGE_HOT_CUE_BANK, 0x1c7, [CTX, 42]))[0]) == e[5])
    }
    @Test("a_page_of_a_long_list_is_the_window_asked_for") func a_page_of_a_long_list_is_the_window_asked_for() throws {
        final class Many: EmptyCatalog {
            override func list(_ query: Query) -> [Row] { (UInt32(1)...100).map { .track(id: $0, position: 0) } }
            override func track_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? {
                TrackRow(id: id, title: "Track \(id)")
            }
        }
        let s = CatalogHandler(Many()).open()
        let h = s.handle(numbers(kind.TRACK_MENU, 1, [CTX, 0]))
        #expect(h[0].arguments[1] == .number(100))
        let page = s.handle(numbers(kind.RENDER, 2, [CTX, 50, 25, 0, 100, 0xc, 1, 0]))
        #expect(page.count == 27)
        #expect(page[0].arguments == [.number(1), .number(50)])
        #expect(page[1].arguments[0] == .number(51))
        #expect(page[25].arguments[0] == .number(75))
        let past = s.handle(numbers(kind.RENDER, 3, [CTX, 100, 25, 0, 100, 0xc, 1, 0]))
        #expect(past.count == 3)
        #expect(past[0].arguments[1] == .number(99))
        #expect(past[1].arguments[0] == .number(100))
        let overrun = s.handle(numbers(kind.RENDER, 4, [CTX, 95, 25, 0, 100, 0xc, 1, 0]))
        #expect(overrun.count == 27)
        #expect(overrun[0].arguments[1] == .number(75))
        #expect(overrun[1].arguments[0] == .number(76))
        #expect(overrun[25].arguments[0] == .number(100))
        let zero = s.handle(numbers(kind.RENDER, 5, [CTX, 0, 0, 0, 100, 0xc, 1, 0]))
        #expect(zero.count == 3)
        #expect(zero[1].arguments[0] == .number(1))
        #expect(s.handle(numbers(kind.RENDER, 6, [CTX, .max, 1, 0, 100, 0xc, 1, 0])).isEmpty)
    }
    @Test("the_setup_reply_and_the_unknown_requests_answer_as_rekordbox_does")
    func the_setup_reply_and_the_unknown_requests_answer_as_rekordbox_does() throws {
        let s = CatalogHandler(try Small()).open()
        #expect(
            s.handle(setup_request(1))[0].encode()
                == (try expected_hex("the_setup_reply_and_the_unknown_requests_answer_as_rekordbox_does", 0)))
        #expect(
            s.handle(numbers(0x3007, 0x17e, [0x0108_0301, 0]))[0].encode()
                == (try expected_hex("the_setup_reply_and_the_unknown_requests_answer_as_rekordbox_does", 1)))
        _ = browse(s, kind.TRACK_MENU, [CTX, 0])
        #expect(
            s.handle(numbers(kind.ITEM_POSITION, 0x18d, [CTX, TRACK, 0, 1]))[0].encode()
                == (try expected_hex("the_setup_reply_and_the_unknown_requests_answer_as_rekordbox_does", 2)))
        #expect(args(s.handle(numbers(0x1017, 0x3cf, [0x0102_0301, 0, TRACK]))[0]) == "0x1017, 0x1")
    }
    @Test("tracks_are_sorted_the_way_the_player_asked") func tracks_are_sorted_the_way_the_player_asked() {
        final class Spy: EmptyCatalog {
            var q: Query?
            override func list(_ query: Query) -> [Row] {
                q = query
                return []
            }
        }
        let c = Spy()
        let s = CatalogHandler(c).open()
        _ = s.handle(numbers(kind.TRACK_MENU, 1, [CTX, 4]))
        #expect(c.q == .tracks(scope: .all, sort: .bpm))
        _ = s.handle(numbers(kind.KEY_TRACKS, 2, [CTX, 0xc, 3, 2]))
        #expect(c.q == .tracks(scope: .key(key: 3, distance: 2), sort: .key))
        _ = s.handle(.new(3, kind.SEARCH, [.number(CTX), .number(0), .number(8), .string("ACID"), .number(0)]))
        #expect(c.q == .tracks(scope: .search("ACID"), sort: .default))
        _ = s.handle(.new(4, kind.SEARCH_TRACK, [.number(CTX), .number(0), .number(8), .string("ABC")]))
        #expect(c.q == .tracks(scope: .search("ABC"), sort: .default))
    }
    @Test("the_extended_cue_reply_counts_its_entries_not_a_header_word")
    func the_extended_cue_reply_counts_its_entries_not_a_header_word() throws {
        final class Cued: EmptyCatalog {
            override func analysis(_ track: UInt32, _ what: Analysis) -> [UInt8]? {
                guard what == .extendedCueList else { return nil }
                return (0..<3).flatMap { _ in
                    dbLE(UInt32(16)) + dbLE(UInt16(0xffff)) + Array(repeating: UInt8(0), count: 10)
                }
            }
        }
        let s = try session(Cued())
        #expect(
            args(s.handle(numbers(kind.EXTENDED_CUES, 0x1c0, [0x0108_0301, TRACK, 0]))[0])
                == "0x2b04, 0x0, 0x30, blob[48], 0x3")
    }
    @Test("item_position_restores_categories_and_does_not_mark_tracks_played")
    func item_position_restores_categories_and_does_not_mark_tracks_played() throws {
        let s = try session()
        _ = browse(s, kind.PLAYLIST_MENU, [CTX, 0, 0, 1])
        #expect(s.handle(numbers(kind.ITEM_POSITION, 4, [CTX, 0xffb7_d23b, 0, 1]))[0].arguments[1] == .number(1))
        #expect(s.handle(numbers(kind.ITEM_POSITION, 5, [CTX, 123, 0, 1]))[0].arguments[1] == .number(.max))
        #expect(s.handle(numbers(kind.RENDER, 6, [CTX, 1, 1]))[1].arguments[1] == .number(0xffb7_d23b))
    }
    @Test("background_metadata_does_not_replace_the_browser_menu")
    func background_metadata_does_not_replace_the_browser_menu() throws {
        let s = try session()
        _ = browse(s, kind.PLAYLIST_MENU, [CTX, 0, 0, 1])
        _ = s.handle(numbers(kind.METADATA, 2, [0x0102_0301, TRACK]))
        #expect(s.handle(numbers(kind.RENDER, 3, [CTX, 1, 1]))[1].arguments[1] == .number(0xffb7_d23b))
        #expect(s.handle(numbers(kind.RENDER, 4, [0x0102_0301, 0, 16])).count == 18)
    }
    @Test("legacy_client_gets_a_bare_title_in_twelve_field_rows")
    func legacy_client_gets_a_bare_title_in_twelve_field_rows() throws {
        let s = try session()
        let r = s.handle(numbers(kind.SETUP, 0xffff_fffe, [5]))
        #expect(r[0].encode() == (try expected_hex("legacy_client_gets_a_bare_title_in_twelve_field_rows")))
        let (_, rows) = browse(s, kind.METADATA, [CTX, TRACK])
        #expect(rows.allSatisfy { $0.arguments.count == 12 })
        #expect(rows[0].arguments[6] == .number(item_type.TITLE))
        #expect(rows[0].arguments[3] == .string(try the_track().title))
        #expect(rows[6].arguments[1] == .number(0x1814_5d65))
        #expect(rows[6].arguments[3] == .string("11B"))
        #expect(rows[6].arguments[6] == .number(item_type.KEY))
        #expect(rows[0].arguments[5] == .string(""))
    }
    @Test("filter_properties_use_the_expected_reply_and_do_not_clobber_browsing")
    func filter_properties_use_the_expected_reply_and_do_not_clobber_browsing() throws {
        let s = try session()
        _ = browse(s, kind.TRACK_MENU, [CTX, 0])
        let r = s.handle(numbers(0x3107, 3, [0x0108_0301]))
        #expect(r[0].kind == 0x4004)
        #expect(r[0].arguments[1] == .number(0))
        #expect(r[0].arguments[4] == .number(4))
        #expect(s.handle(numbers(kind.RENDER, 4, [CTX, 0, 1]))[1].arguments[1] == .number(TRACK))
        let bytes: [UInt8] = [1, 6, 2, 0] + dbLE(UInt32(12000)) + dbLE(UInt32(13000))
        #expect(
            s.handle(.new(5, 0x3207, [.number(CTX), .number(6), .number(0), .number(12), .blob(bytes)]))[0].arguments[1]
                == .number(0))
        _ = s.handle(numbers(0x3007, 6, [CTX, 1]))
        #expect(browse(s, kind.TRACK_MENU, [CTX, 0]).0 == 0)
        _ = s.handle(numbers(0x3007, 7, [CTX, 0]))
        #expect(browse(s, kind.TRACK_MENU, [CTX, 0]).0 == 1)
    }
    @Test("read_only_catalog_refuses_tag_and_rating_edits") func read_only_catalog_refuses_tag_and_rating_edits() throws
    {
        let s = try session()
        for (k, a): (UInt16, [UInt32]) in [(0x3002, [CTX, TRACK, 1]), (0x3202, [CTX]), (0x2107, [CTX, TRACK, 5])] {
            #expect(s.handle(numbers(k, 1, a))[0].arguments[1] == .number(1))
        }
    }
    @Test("tag_and_rating_edits_are_shared_and_acknowledged_after_the_catalog_changes")
    func tag_and_rating_edits_are_shared_and_acknowledged_after_the_catalog_changes() throws {
        final class Editable: EmptyCatalog {
            let small: Small
            var tags: [UInt32] = [], rating: UInt32 = 0, offset: Int16 = 0
            init(_ small: Small) { self.small = small }
            override func list(_ q: Query) -> [Row] {
                if case .tracks(scope: .tagList, sort: _) = q {
                    return tags.enumerated().map { .track(id: $0.element, position: UInt32($0.offset + 1)) }
                }
                return small.list(q)
            }
            override func track_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? { small.track_row(id, column) }
            override func track(_ id: UInt32) -> TrackDetails? {
                guard var t = small.track(id) else { return nil }
                t.rating = rating
                return t
            }
            override func tagged(_ id: UInt32) -> Bool { tags.contains(id) }
            override func grid_offset(_ track: UInt32) -> Int16 { offset }
            override func edit(_ e: Edit) -> Bool {
                switch e {
                case let .tag(track, true): if !tags.contains(track) { tags.append(track) }
                case let .tag(track, false): tags.removeAll { $0 == track }
                case let .gridOffset(_, v): offset = v
                case .clearTags: tags = []
                case let .rating(_, v): rating = UInt32(v)
                default: return false
                }
                return true
            }
        }
        let h = CatalogHandler(Editable(try Small()))
        let one = h.open()
        let two = h.open()
        #expect(one.handle(numbers(0x3002, 1, [CTX, TRACK, 1]))[0].arguments[1] == .number(0))
        let (count, rows) = browse(two, 0x100f, [CTX, 0])
        #expect(count == 1)
        #expect(rows[0].arguments[7] == .number(0x0100_0001))
        #expect(browse(two, kind.METADATA, [0x0102_0301, TRACK]).1[0].arguments[7] == .number(1))
        _ = one.handle(numbers(0x3002, 2, [CTX, TRACK, 1]))
        #expect(browse(two, 0x100f, [CTX, 0]).0 == 1)
        _ = one.handle(numbers(0x2107, 3, [CTX, TRACK, 4]))
        let rating = try #require(browse(two, kind.METADATA, [CTX, TRACK]).1.first { $0.arguments[6] == .number(10) })
        #expect(rating.arguments[1] == .number(4))
        #expect(one.handle(numbers(0x2107, 4, [CTX, TRACK, 6]))[0].arguments[1] == .number(1))
        #expect(one.handle(numbers(kind.SAVE_GRID_OFFSET, 5, [CTX, TRACK, 0xffff_fe2d]))[0].arguments[1] == .number(0))
        #expect(two.handle(numbers(kind.GRID_OFFSET, 6, [CTX, TRACK]))[0].arguments[1] == .number(0xfe2d))
        _ = one.handle(numbers(0x3002, 7, [CTX, TRACK, 0]))
        #expect(browse(two, 0x100f, [CTX, 0]).0 == 0)
        #expect(browse(two, kind.METADATA, [0x0102_0301, TRACK]).1[0].arguments[7] == .number(0))
    }
    @Test("history_commands_reach_the_catalog_and_only_the_removal_is_answered")
    func history_commands_reach_the_catalog_and_only_the_removal_is_answered() throws {
        final class Recording: EmptyCatalog {
            let small: Small
            var edits: [Edit] = []
            init(_ s: Small) { small = s }
            override func list(_ q: Query) -> [Row] { small.list(q) }
            override func track_row(_ id: UInt32, _ c: TrackColumn?) -> TrackRow? { small.track_row(id, c) }
            override func track(_ id: UInt32) -> TrackDetails? { small.track(id) }
            override func edit(_ e: Edit) -> Bool {
                edits.append(e)
                return e != .historyRemove(track: 7)
            }
        }
        let c = Recording(try Small())
        let s = CatalogHandler(c).open()
        _ = browse(s, kind.TRACK_MENU, [CTX, 0])
        #expect(s.handle(numbers(kind.INSERT_HISTORY, 2, [CTX, TRACK])).isEmpty)
        #expect(s.handle(numbers(kind.RENDER, 3, [CTX, 0, 1]))[1].arguments[1] == .number(TRACK))
        #expect(s.handle(numbers(kind.DELETE_HISTORY, 4, [CTX, .max])).isEmpty)
        #expect(s.handle(numbers(kind.SET_ON_AIR, 4, [CTX, TRACK])).isEmpty)
        #expect(
            s.handle(numbers(kind.DELETE_HISTORY_TRACK, 5, [CTX, TRACK]))[0].arguments == [.number(0x3401), .number(0)])
        #expect(
            s.handle(numbers(kind.DELETE_HISTORY_TRACK, 6, [CTX, 7]))[0].arguments == [.number(0x3401), .number(.max)])
        #expect(s.handle(numbers(kind.INSERT_HISTORY, 7, [0x0101_0302, TRACK])).isEmpty)
        #expect(
            c.edits == [
                .historyAdd(track: TRACK), .historyDelete(history: .max), .historyRemove(track: TRACK),
                .historyRemove(track: 7),
            ])
    }
    @Test("rx3_browse_type_fallback_is_database_backed_media") func rx3_browse_type_fallback_is_database_backed_media()
        throws
    {
        #expect(
            try session().handle(numbers(kind.BROWSE_TYPE, 0x51, [CTX, 2]))[0].arguments == [
                .number(0x3303), .number(1),
            ])
    }
    @Test("rx3_scalar_track_and_mobile_queries_use_their_native_reply_shapes")
    func rx3_scalar_track_and_mobile_queries_use_their_native_reply_shapes() throws {
        let idle = try session()
        for (k, tx, a, e): (UInt16, UInt32, [UInt32], [Argument]) in [
            (kind.TRACK_BPM, 0x52, [CTX, TRACK], [.number(0x3008), .number(0x1e80)]),
            (kind.TRACK_PLAY_STATE, 0x53, [CTX, TRACK], [.number(0x3b03), .number(0)]),
            (kind.LEGACY_KEY_TO_NEW_KEY, 0x56, [CTX, 0x14], [.number(0x3a03), .number(0x14)]),
            (kind.LEGACY_KEY_TO_NEW_KEY, 0x57, [CTX, 25], [.number(0x3a03), .number(0)]),
            (kind.CONTENT_NEW_KEY, 0x58, [CTX, TRACK], [.number(0x3d03), .number(0x14)]),
        ] { #expect(idle.handle(numbers(k, tx, a))[0].arguments == e) }
        let loaded = try session(Small(true))
        #expect(
            loaded.handle(numbers(kind.TRACK_PLAY_STATE, 0x54, [CTX, TRACK]))[0].arguments == [
                .number(0x3b03), .number(0),
            ])
        let mobile = loaded.handle(numbers(kind.REKORDBOX_MOBILE, 0x55, [CTX]))
        #expect(mobile[0].kind == kind.REKORDBOX_MOBILE_REPLY)
        #expect(mobile[0].arguments == [.number(0), .number(2), .string("")])
    }
    @Test("rx3_content_tracks_is_the_sorted_all_tracks_alias") func rx3_content_tracks_is_the_sorted_all_tracks_alias()
        throws
    {
        let s = try session()
        let regular = browse(s, kind.TRACK_MENU, [CTX, 4])
        let content = browse(s, kind.CONTENT_TRACKS, [CTX, 4])
        #expect(content.0 == regular.0)
        #expect(content.1 == regular.1)
    }
    @Test("grid_offset_writes_do_not_claim_success_without_persistence")
    func grid_offset_writes_do_not_claim_success_without_persistence() throws {
        let s = try session()
        _ = browse(s, kind.TRACK_MENU, [CTX, 0])
        #expect(
            s.handle(numbers(kind.SAVE_GRID_OFFSET, 8, [CTX, TRACK, 234]))[0].arguments == [
                .number(0x2605), .number(1),
            ])
        #expect(s.handle(numbers(kind.GRID_OFFSET, 9, [CTX, TRACK]))[0].arguments == [.number(0x2804), .number(0)])
        #expect(s.handle(numbers(kind.RENDER, 10, [CTX, 0, 1]))[1].arguments[1] == .number(TRACK))
    }
    @Test("unsupported_command_keeps_the_active_menu_and_echoes_its_kind_in_4003")
    func unsupported_command_keeps_the_active_menu_and_echoes_its_kind_in_4003() throws {
        let s = try session()
        let (count, expected) = browse(s, kind.ROOT_MENU, [CTX, 0, 0x5cf_ffff])
        #expect(s.handle(numbers(0x2fff, 0x8123, [CTX, 0])) == [.new(0x8123, kind.ERROR, [.number(0x2fff)])])
        let rendered = s.handle(numbers(kind.RENDER, 0x8124, [CTX, 0, count, 0, count, 0xc, 1, 0]))
        #expect(rendered[0].kind == kind.RENDER_HEADER)
        let items = Array(rendered.dropFirst().dropLast())
        #expect(items.count == expected.count)
        for (a, e) in zip(items, expected) {
            #expect(a.kind == e.kind)
            #expect(a.arguments == e.arguments)
        }
        #expect(rendered.last?.kind == kind.MENU_FOOTER)
    }
    @Test("unsupported_command_reports_the_request_that_received_4003")
    func unsupported_command_reports_the_request_that_received_4003() throws {
        var reports: [(UInt32, UInt16, UInt8)] = []
        let h = CatalogHandler(try Small()).with_unsupported_command_reporter { reports.append(($0, $1, $2)) }
        let s = h.open()
        _ = s.handle(setup_request(3))
        #expect(s.handle(numbers(0x2fff, 0x8123, [CTX, 0]))[0].kind == kind.ERROR)
        #expect(reports.count == 1)
        #expect(reports[0].0 == 0x8123)
        #expect(reports[0].1 == 0x2fff)
        #expect(reports[0].2 == 3)
    }
    @Test("unsupported_command_wire_preserves_both_menu_locations_and_setup_modes")
    func unsupported_command_wire_preserves_both_menu_locations_and_setup_modes() throws {
        let SECOND: UInt32 = 0x0102_0301
        for (setup, reply, width) in [
            (
                "11872349ae11fffffffe1000000f011400000001061100000005",
                "11872349ae11fffffffe1040000f021400000002060611000000001100000011", 12
            ),
            (
                "11872349ae11fffffffe1000000f021400000002060611000000051100000014",
                "11872349ae11fffffffe1000000f021400000002060611000000111100000014", 16
            ),
        ] {
            let s = CatalogHandler(try Small()).open()
            #expect(try exchange_wire(s, hex(setup)) == [hex(reply)])
            let root = numbers(kind.ROOT_MENU, 0x8100, [CTX, 0, 0x5cf_ffff])
            let tracks = numbers(kind.TRACK_MENU, 0x8101, [SECOND, 0])
            #expect(
                try exchange_wire(s, root.encode()) == [
                    hex("11872349ae11000081001040000f021400000002060611000010001100000009")
                ])
            #expect(
                try exchange_wire(s, tracks.encode()) == [
                    hex("11872349ae11000081011040000f021400000002060611000010041100000001")
                ])
            let renders = [
                numbers(kind.RENDER, 0x8124, [CTX, 0, 9, 0, 9, 0xc, 1, 0]),
                numbers(kind.RENDER, 0x8124, [SECOND, 0, 1, 0, 1, 0xc, 1, 0]),
            ]
            let before = try renders.map { try exchange_wire(s, $0.encode()) }
            #expect(before[0].count == 11)
            #expect(before[1].count == 3)
            for rows in before {
                for row in rows.dropFirst().dropLast() { #expect(try Message.decode(row).0.arguments.count == width) }
            }
            #expect(try Message.decode(before[1][1]).0.arguments[1] == .number(TRACK))
            for request in [
                "11872349ae1100008123102fff0f021400000002060611010103011100000000",
                "11872349ae1100008123102fff0f021400000002060611010203011100000000",
                "11872349ae1100008123102fff0f021400000002060611010303011100000000",
                "11872349ae1100008123102fff0f001400000000",
            ] {
                #expect(
                    try exchange_wire(s, hex(request)) == [hex("11872349ae11000081231040030f011400000001061100002fff")])
                for (r, e) in zip(renders, before) { #expect(try exchange_wire(s, r.encode()) == e) }
            }
            #expect(
                try exchange_wire(s, hex("11872349ae1100008125103e030f011400000001061101010301")) == [
                    hex("11872349ae1100008125104b020f0314000000030606021100000000110000000226000000010000")
                ])
            for command in [kind.TEARDOWN, kind.SET_ON_AIR] {
                #expect(try exchange_wire(s, numbers(command, 0x8126, [CTX, 1]).encode()).isEmpty)
            }
            for (r, e) in zip(renders, before) { #expect(try exchange_wire(s, r.encode()) == e) }
        }
    }
    @Test("unsupported_command_keeps_filter_selection_and_enable_state")
    func unsupported_command_keeps_filter_selection_and_enable_state() throws {
        let s = try session()
        let property: [UInt8] = [1, 6, 2, 0] + dbLE(UInt32(12000)) + dbLE(UInt32(13000))
        let update = Message.new(
            0x8100, kind.FILTER_SET, [.number(CTX), .number(6), .number(0), .number(12), .blob(property)])
        _ = try exchange_wire(s, update.encode())
        _ = try exchange_wire(s, numbers(0x3007, 0x8101, [CTX, 1]).encode())
        #expect(browse(s, kind.TRACK_MENU, [CTX, 0]).0 == 0)
        #expect(
            try exchange_wire(s, hex("11872349ae1100008123102fff0f011400000001061101010301")) == [
                hex("11872349ae11000081231040030f011400000001061100002fff")
            ])
        #expect(browse(s, kind.TRACK_MENU, [CTX, 0]).0 == 0)
        _ = try exchange_wire(s, numbers(0x3007, 0x8102, [CTX, 0]).encode())
        #expect(browse(s, kind.TRACK_MENU, [CTX, 0]).0 == 1)
        _ = try exchange_wire(s, numbers(0x3007, 0x8103, [CTX, 1]).encode())
        #expect(browse(s, kind.TRACK_MENU, [CTX, 0]).0 == 0)
    }
    @Test("played_state_wire_uses_context_four_and_preserves_pending_menu")
    func played_state_wire_uses_context_four_and_preserves_pending_menu() throws {
        for played in [false, true] {
            let s = try session(Small(played))
            _ = browse(s, kind.TRACK_MENU, [CTX, 0])
            let render = numbers(kind.RENDER, 0x8100, [CTX, 0, 1])
            let before = try exchange_wire(s, render.encode())
            for location: UInt32 in [1, 2, 8] {
                for context: UInt32 in [0, 1, 2, 3, 4, 5, 255] {
                    let packed = (CTX & 0xff00_00ff) | (location << 16) | (context << 8)
                    for track: UInt32 in [TRACK, 0, .max] {
                        let scalar = played && track == TRACK && context == 4 ? "00000002" : "00000000"
                        #expect(
                            try exchange_wire(s, numbers(kind.TRACK_PLAY_STATE, 0x8130, [packed, track]).encode()) == [
                                hex("11872349ae11000081301040000f02140000000206061100003b0311" + scalar)
                            ])
                        #expect(try exchange_wire(s, render.encode()) == before)
                    }
                }
            }
            for a: [Argument] in [
                [], [.number(0x0101_0401)], [.string("context"), .number(TRACK)],
                [.number(0x0101_0401), .string("track")],
            ] {
                #expect(
                    try exchange_wire(s, Message.new(0x8130, kind.TRACK_PLAY_STATE, a).encode()) == [
                        hex("11872349ae11000081301040000f02140000000206061100003b031100000000")
                    ])
            }
            #expect(try exchange_wire(s, render.encode()) == before)
        }
    }
    @Test("filter_set_failure_is_32_and_keeps_existing_conditions_and_menu")
    func filter_set_failure_is_32_and_keeps_existing_conditions_and_menu() throws {
        let s = try session()
        _ = browse(s, kind.TRACK_MENU, [CTX, 0])
        let render = numbers(kind.RENDER, 0x8100, [CTX, 0, 1])
        let menu = try exchange_wire(s, render.encode())
        let get = numbers(kind.FILTER_GET, 0x8101, [CTX])
        let before = try exchange_wire(s, get.encode())
        let blob: [UInt8] = [1, 6, 2, 0] + dbLE(UInt32(12000)) + dbLE(UInt32(13000))
        let valid: [Argument] = [.number(CTX), .number(6), .number(0), .number(12), .blob(blob)]
        var invalid: [[Argument]] = [[]]
        for (index, value): (Int, Argument) in [
            (0, .string("context")), (1, .number(99)), (2, .number(1)), (2, .string("reserved")), (3, .number(3)),
            (3, .number(11)), (4, .blob([1, 6, 2, 0])), (4, .string("blob")),
        ] {
            var a = valid
            a[index] = value
            invalid.append(a)
        }
        for a in invalid {
            #expect(
                try exchange_wire(s, Message.new(0x8131, kind.FILTER_SET, a).encode()) == [
                    hex("11872349ae11000081311040000f021400000002060611000032071100000032")
                ])
            #expect(try exchange_wire(s, get.encode()) == before)
            #expect(try exchange_wire(s, render.encode()) == menu)
        }
        #expect(
            try exchange_wire(s, Message.new(0x8131, kind.FILTER_SET, valid).encode()) == [
                hex("11872349ae11000081311040000f021400000002060611000032071100000000")
            ])
        #expect(try exchange_wire(s, get.encode()) != before)
        #expect(try exchange_wire(s, render.encode()) == menu)
        let foreign: [Argument] = [.number(0x0208_0302), .number(6), .number(0), .number(4), .blob([0, 0, 0, 0])]
        #expect(
            try exchange_wire(s, Message.new(0x8131, kind.FILTER_SET, foreign).encode()) == [
                hex("11872349ae11000081311040000f021400000002060611000032071100000000")
            ])
    }
    @Test("scalar_and_silent_notices_preserve_menus_for_both_setup_modes")
    func scalar_and_silent_notices_preserve_menus_for_both_setup_modes() throws {
        for extended in [false, true] {
            let s = CatalogHandler(try Small()).open()
            _ = try exchange_wire(s, numbers(kind.SETUP, 0xffff_fffe, extended ? [5, 20] : [5]).encode())
            _ = browse(s, kind.ROOT_MENU, [CTX, 0, 0x5cf_ffff])
            let render = numbers(kind.RENDER, 0x8100, [CTX, 0, 9])
            let before = try exchange_wire(s, render.encode())
            for command: UInt16 in [0x3402, 0x3903] {
                #expect(
                    try exchange_wire(s, numbers(command, 0x8132, [CTX]).encode()) == [
                        hex(
                            "11872349ae11000081321040000f0214000000020606110000" + String(format: "%04x", command)
                                + "1100000000")
                    ])
                #expect(try exchange_wire(s, render.encode()) == before)
            }
            for command: UInt16 in [0x3203, 0x3503, kind.DELETE_HISTORY_TRACK] {
                #expect(try exchange_wire(s, numbers(command, 0x8132, [0x0101_0302, TRACK]).encode()).isEmpty)
                #expect(try exchange_wire(s, render.encode()) == before)
            }
        }
    }
    @Test("my_setting_flag_scalar_masks_the_low_byte_and_preserves_both_menus")
    func my_setting_flag_scalar_masks_the_low_byte_and_preserves_both_menus() throws {
        let SECOND: UInt32 = 0x0102_0301
        for extended in [false, true] {
            let s = CatalogHandler(try Small()).open()
            _ = try exchange_wire(s, numbers(kind.SETUP, 0xffff_fffe, extended ? [5, 20] : [5]).encode())
            _ = try exchange_wire(s, numbers(kind.ROOT_MENU, 0x8100, [CTX, 0, 0x5cf_ffff]).encode())
            _ = try exchange_wire(s, numbers(kind.TRACK_MENU, 0x8101, [SECOND, 0]).encode())
            let renders = [numbers(kind.RENDER, 0x8102, [CTX, 0, 9]), numbers(kind.RENDER, 0x8103, [SECOND, 0, 1])]
            let before = try renders.map { try exchange_wire(s, $0.encode()) }
            #expect(before[0].count == 11)
            #expect(before[1].count == 3)
            for context in [CTX, SECOND, 0x0208_0302] {
                for (value, scalar): (UInt32, Int) in [
                    (0, 1), (1, 1), (2, 0), (255, 0), (256, 1), (257, 1), (0x10000, 1),
                ] {
                    #expect(
                        try exchange_wire(s, numbers(0x3c03, 0x8133, [context, value]).encode()) == [
                            hex("11872349ae11000081331040000f02140000000206061100003c03110000000\(scalar)")
                        ])
                    for (r, e) in zip(renders, before) { #expect(try exchange_wire(s, r.encode()) == e) }
                }
            }
            for a: [Argument] in [
                [], [.number(CTX)], [.string("context"), .number(0)], [.number(CTX), .string("value")],
                [.number(CTX), .blob([0])],
            ] {
                #expect(
                    try exchange_wire(s, Message.new(0x8133, 0x3c03, a).encode()) == [
                        hex("11872349ae11000081331040030f011400000001061100003c03")
                    ])
                for (r, e) in zip(renders, before) { #expect(try exchange_wire(s, r.encode()) == e) }
            }
        }
    }
    @Test("analysis_write_early_refusals_preserve_menus_without_storage_calls")
    func analysis_write_early_refusals_preserve_menus_without_storage_calls() throws {
        let SECOND: UInt32 = 0x0102_0301
        for extended in [false, true] {
            let c = AnalysisBoundaryCatalog(try Small())
            let s = CatalogHandler(c).open()
            _ = try exchange_wire(s, numbers(kind.SETUP, 0xffff_fffe, extended ? [5, 20] : [5]).encode())
            _ = try exchange_wire(s, numbers(kind.ROOT_MENU, 0x8100, [CTX, 0, 0x5cf_ffff]).encode())
            _ = try exchange_wire(s, numbers(kind.TRACK_MENU, 0x8101, [SECOND, 0]).encode())
            let renders = [numbers(kind.RENDER, 0x8102, [CTX, 0, 9]), numbers(kind.RENDER, 0x8103, [SECOND, 0, 1])]
            let before = try renders.map { try exchange_wire(s, $0.encode()) }
            #expect(before[0].count == 11)
            #expect(before[1].count == 3)
            var cases: [(Message, Bool)] = []
            for command: UInt16 in [0x2805, 0x2905] {
                for length: UInt32 in [0, 1, 11, 12] {
                    cases.append(
                        (
                            atom_write(command, Array("PQT2".utf8), Array("EXT\0".utf8), 0, length),
                            command == 0x2805 ? (1..<12).contains(length) : length < 12
                        ))
                }
                for (atom, ext, reserved): (String, [UInt8], UInt32) in [
                    ("PWV4", Array("EXT\0".utf8), 0), ("PQT2", Array("2EX\0".utf8), 0), ("PQT2", Array("EXTX".utf8), 0),
                    ("PQT2", [0, 0, 0, 0], 0), ("PQT2", Array("EXT\0".utf8), 1),
                ] { cases.append((atom_write(command, Array(atom.utf8), ext, reserved, 12), true)) }
                for atom in ["PVB2", "PQT2", "PQTZ"] {
                    for ext in ["DAT\0", "EXT\0", "ext\0"] {
                        cases.append(
                            (
                                atom_write(command, Array(atom.utf8), Array(ext.utf8), 0, 12),
                                command == 0x2905 && (atom != "PQT2" || ext == "DAT\0")
                            ))
                    }
                }
            }
            for length: UInt32 in [0, 1, 55, 56] {
                var r = numbers(0x2705, 0x8134, [CTX, TRACK, 0, length])
                r.arguments.append(.blob(Array(repeating: 0xaa, count: Int(length))))
                cases.append((r, true))
            }
            let cueRefusal = hex(
                "11872349ae1100008134104e020f05140000000506060603061100002705110000003211000000001100000000")
            for context in [CTX, SECOND, 0x0208_0302] {
                for (original, refusal) in cases {
                    var request = original
                    request.arguments[0] = .number(context)
                    let expected: [UInt8]
                    if !refusal {
                        expected = hex(
                            "11872349ae11000081341040030f01140000000106110000" + String(format: "%04x", request.kind))
                    } else if request.kind == 0x2705 {
                        expected = cueRefusal
                    } else {
                        expected = hex(
                            "11872349ae11000081341040000f0214000000020606110000" + String(format: "%04x", request.kind)
                                + "1100000032")
                    }
                    #expect(try exchange_wire(s, request.encode()) == [expected])
                    for (r, e) in zip(renders, before) { #expect(try exchange_wire(s, r.encode()) == e) }
                }
            }
            for command: UInt16 in [0x2705, 0x2805, 0x2905] {
                var valid: Message
                if command == 0x2705 {
                    valid = numbers(command, 0x8134, [CTX, TRACK, 0, 55])
                    valid.arguments.append(.blob(Array(repeating: 0xaa, count: 55)))
                } else {
                    valid = atom_write(command, Array("PQT2".utf8), Array("EXT\0".utf8), 0, 11)
                }
                var malformed: [[Argument]] = [[], Array(valid.arguments.dropLast())]
                for index in valid.arguments.indices {
                    var a = valid.arguments
                    a[index] = .string("wrong type")
                    malformed.append(a)
                }
                for a in malformed {
                    let e =
                        command == 0x2705
                        ? cueRefusal
                        : hex("11872349ae11000081341040030f01140000000106110000" + String(format: "%04x", command))
                    #expect(try exchange_wire(s, Message.new(0x8134, command, a).encode()) == [e])
                    for (r, e) in zip(renders, before) { #expect(try exchange_wire(s, r.encode()) == e) }
                }
            }
            #expect(c.edits == 0)
            #expect(c.reads == 3)
        }
    }
    @Test("vbr_compatibility_placeholder_keeps_existing_complete_envelope_and_menu")
    func vbr_compatibility_placeholder_keeps_existing_complete_envelope_and_menu() throws {
        for extended in [false, true] {
            let s = CatalogHandler(AnalysisBoundaryCatalog(try Small())).open()
            _ = try exchange_wire(s, numbers(kind.SETUP, 0xffff_fffe, extended ? [5, 20] : [5]).encode())
            _ = try exchange_wire(s, numbers(kind.ROOT_MENU, 0x8100, [CTX, 0, 0x5cf_ffff]).encode())
            let render = numbers(kind.RENDER, 0x8102, [CTX, 0, 9])
            let before = try exchange_wire(s, render.encode())
            let e =
                hex("11872349ae11000081351045020f041400000004060606031100002504110000000011000006441400000644")
                + Array(repeating: UInt8(0), count: 1604)
            #expect(try exchange_wire(s, numbers(kind.VBR, 0x8135, [CTX, TRACK]).encode()) == [e])
            #expect(try exchange_wire(s, render.encode()) == before)
        }
    }
    @Test("ready_open_uses_one_assigned_number_snapshot_without_a_fallback")
    func ready_open_uses_one_assigned_number_snapshot_without_a_fallback() throws {
        let number = AtomicUInt8(0)
        let h = CatalogHandler(try Small()).with_device(number)
        #expect(h.open_ready() == nil)
        #expect(!h.serving())
        number.store(17)
        let first = try #require(h.open_ready())
        number.store(18)
        let second = try #require(h.open_ready())
        number.store(0)
        #expect(h.open_ready() == nil)
        #expect(
            try exchange_wire(first, setup_request(1).encode()) == [
                hex("11872349ae11fffffffe1000000f021400000002060611000000111100000014")
            ])
        #expect(
            try exchange_wire(second, setup_request(1).encode()) == [
                hex("11872349ae11fffffffe1000000f021400000002060611000000121100000014")
            ])
    }
    @Test("direct_database_socket_closes_unready_and_uses_negotiated_setup_identity")
    func direct_database_socket_closes_unready_and_uses_negotiated_setup_identity() async throws {
        let clock = TestClock()
        let factory = FakeExportSocketFactory(clock: clock)
        let number = AtomicUInt8(0)
        let h = CatalogHandler(try Small()).with_device(number)
        let bound = try await Bound.start(h, "127.0.0.1", 0, 0, socketFactory: factory, clock: clock)
        for assigned: UInt8 in [0, 17, 18, 0, 18] {
            number.store(assigned)
            let client = try factory.createTCPConnection()
            try await client.connect(port: bound.database_address().port, host: "127.0.0.1")
            if assigned == 0 {
                #expect(try await client.read(nil) == nil)
            } else {
                try await client.write(GREETING + setup_request(1).encode())
                let expected =
                    GREETING
                    + hex(
                        "11872349ae11fffffffe1000000f021400000002060611000000" + String(format: "%02x", assigned)
                            + "1100000014")
                #expect(try await client.read(expected.count) == expected)
            }
            client.destroy(nil)
        }
        await bound.shutdown()
    }
}
@DJLinkActor private func exchange_wire(_ s: any Session, _ request: [UInt8]) throws -> [[UInt8]] {
    let (m, n) = try Message.decode(request)
    #expect(n == request.count)
    #expect(m.encode() == request)
    return s.handle(m).map { $0.encode() }
}
@DJLinkActor private final class AnalysisBoundaryCatalog: EmptyCatalog {
    let small: Small
    var edits = 0, reads = 0
    init(_ small: Small) { self.small = small }
    override func list(_ q: Query) -> [Row] { small.list(q) }
    override func track_row(_ id: UInt32, _ c: TrackColumn?) -> TrackRow? { small.track_row(id, c) }
    override func track(_ id: UInt32) -> TrackDetails? { small.track(id) }
    override func artwork(_ id: UInt32) -> [UInt8]? { small.artwork(id) }
    override func item_artwork(_ id: UInt32) -> [UInt8]? { small.item_artwork(id) }
    override func analysis(_ track: UInt32, _ what: Analysis) -> [UInt8]? {
        reads += 1
        return track == TRACK && what == .vbr ? Array(repeating: 0, count: 1604) : nil
    }
    override func edit(_ edit: Edit) -> Bool {
        edits += 1
        return false
    }
}
private func atom_write(_ command: UInt16, _ atom: [UInt8], _ extension_: [UInt8], _ reserved: UInt32, _ length: UInt32)
    -> Message
{
    var r = numbers(command, 0x8134, [CTX, TRACK, le32(atom, 0), le32(extension_, 0), reserved, length])
    if command == 0x2905 { r.arguments.append(.number(length != 0 ? 1 : 0)) }
    r.arguments.append(.blob(Array(repeating: 0xaa, count: Int(length))))
    return r
}
