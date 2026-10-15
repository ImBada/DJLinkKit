import DJLinkExportTestSupport
import DJLinkKit
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-dbserver/tests/my_tags.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportDBServer

private typealias Message = DJLinkExportDBServer.Message
private typealias Query = DJLinkExportDBServer.Query
private typealias Item = DJLinkExportDBServer.Item

private let PLAYLIST: UInt32 = 0xbbfb_546b
private let FOLDER: UInt32 = 0x7c15_7ab2
private let OTHER_PLAYLIST: UInt32 = 0x0736_200d
private let REESE: UInt32 = 0x0677_d658
private let WUBBY: UInt32 = 0x0e7a_8716
private let MC_BARS: UInt32 = 0x0be5_c94d
private let UNUSED: [UInt32] = [0x7000_001e, 0x7000_001f, 0x054e_6c12]
private let CTX: UInt32 = 0x0b01_0401
private func my_tags() -> [DJLinkExportDBServer.MyTag] {
    var out: [DJLinkExportDBServer.MyTag] = []
    func category(_ id: UInt32, _ seq: UInt32, _ name: String, _ tags: [(UInt32, String)]) {
        out.append(DJLinkExportDBServer.MyTag(id: id, parent: 0, seq: seq, name: name))
        for (at, tag) in tags.enumerated() {
            out.append(DJLinkExportDBServer.MyTag(id: tag.0, parent: id, seq: UInt32(at + 1), name: tag.1))
        }
    }
    category(
        1, 1, "Sub-genre",
        [
            (0x0fcc_f39f, "DnB Neuro"), (0x07ae_781a, "DnB Jump-up"), (0x0116_4f68, "DnB Jungle"),
            (0x0d40_2d69, "DnB Liquid"), (0x0917_59b2, "DnB Dancefloor"),
        ])
    var traits: [(UInt32, String)] = [
        (REESE, "reese"), (WUBBY, "wubby"), (0x024d_98b8, "growly"), (0x050f_ac24, "sub"), (0x06f9_9f77, "distorted"),
        (0x0ba0_f793, "gritty"), (0x067f_5448, "buzzy"), (0x05f5_5332, "roller"),
    ]
    traits += (UInt32(0)..<32).map { (0x7000_0000 + $0, "trait \($0)") }
    category(2, 2, "Traits", traits)
    category(
        3, 3, "Vocals",
        [
            (0x0e72_3f7d, "vocals"), (0x054e_6c12, "sung"), (MC_BARS, "mc-bars"), (0x0538_c9ea, "ragga"),
            (0x04b6_11c1, "one-shot"), (0x0991_213e, "full-vocal"), (0x07c7_3257, "us-vocal"),
            (0x0e5c_721e, "uk-vocal"),
        ])
    return out
}
@DJLinkActor private final class Library: Catalog {
    let playlist: [UInt32] = Array(1...41), all: [UInt32] = Array(1...130)
    var tags: [UInt32: [UInt32]] = [:], bpm: [UInt32: UInt32] = [:]
    init() {
        for track: UInt32 in 1...21 { tags[track] = [REESE, WUBBY] }
        for track: UInt32 in 22...30 { tags[track] = [REESE] }
        for track: UInt32 in 31...35 { tags[track] = [WUBBY] }
        tags[22]!.append(MC_BARS)
        for track: UInt32 in 42...46 { tags[track] = [REESE] }
        let reese_like = [REESE, WUBBY, MC_BARS]
        tags[100] = my_tags().filter { $0.parent != 0 && !reese_like.contains($0.id) && !UNUSED.contains($0.id) }.map {
            $0.id
        }
        let reese = tags.keys.sorted().filter { tags[$0]!.contains(REESE) }
        #expect(reese.count == 35)
        for track in all { bpm[track] = 12_800 }
        for (at, track) in reese.enumerated() { bpm[track] = at < 7 ? 17_000 : 17_400 }
    }
    func list(_ query: Query) -> [Row] {
        func tracks(_ ids: [UInt32]) -> [Row] {
            ids.enumerated().map { .track(id: $0.element, position: UInt32($0.offset + 1)) }
        }
        func lists(_ n: UInt32) -> [Row] {
            (UInt32(0)..<n).map { .list(id: 0x100 + $0, name: "list \($0)", folder: false, position: $0) }
        }
        switch query {
        case .folder(0): return lists(5)
        case .folder(FOLDER): return lists(6)
        case .tracks(scope: .playlist(PLAYLIST), sort: _): return tracks(playlist)
        case .tracks(scope: .playlist(OTHER_PLAYLIST), sort: _): return tracks(Array(all.prefix(37)))
        case .tracks(scope: .all, sort: _): return tracks(all)
        default: return []
        }
    }
    func track_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? {
        bpm[id].map { TrackRow(id: id, title: "track \(id)", bpm_x100: $0) }
    }
    func track(_ id: UInt32) -> TrackDetails? { track_row(id, nil).map { TrackDetails(row: $0) } }
    func artwork(_ id: UInt32) -> [UInt8]? { nil }
    func item_artwork(_ id: UInt32) -> [UInt8]? { nil }
    func analysis(_ track: UInt32, _ what: Analysis) -> [UInt8]? { nil }
    func my_tags() -> [DJLinkExportDBServer.MyTag] { DJLinkExportDBServerTestsMyTags() }
    func track_my_tags(_ track: UInt32) -> [UInt32] { tags[track] ?? [] }
    func my_tags_in_use() -> Set<UInt32> { Set(tags.values.flatMap { $0 }) }
}
private func DJLinkExportDBServerTestsMyTags() -> [DJLinkExportDBServer.MyTag] { my_tags() }
private func decode(_ stream: [UInt8]) throws -> [(Message, [UInt8])] {
    #expect(stream.starts(with: GREETING))
    var at = GREETING.count
    var out: [(Message, [UInt8])] = []
    while at < stream.count {
        let (m, n) = try Message.decode(Array(stream[at...]))
        out.append((m, Array(stream[at..<(at + n)])))
        at += n
    }
    return out
}
@DJLinkActor private func replay(_ player: [UInt8], _ rekordbox: [UInt8]) throws -> [UInt16: Int] {
    var recorded: [UInt32: [[UInt8]]] = [:]
    for (message, bytes) in try decode(rekordbox) { recorded[message.transaction, default: []].append(bytes) }
    let s = LinkSession(Library())
    var compared: [UInt16: Int] = [:]
    for (request, _) in try decode(player) {
        let ours = s.handle(request).map { $0.encode() }
        guard let theirs = recorded[request.transaction] else { continue }
        #expect(ours.count == theirs.count)
        for (a, b) in zip(ours, theirs) { #expect(a == b) }
        compared[request.kind, default: 0] += 1
    }
    return compared
}
@DJLinkActor private func ask(_ s: LinkSession, _ kind: UInt16, _ arguments: [UInt32]) -> [Message] {
    s.handle(.new(7, kind, arguments.map { .number($0) }))
}
private func status(_ replies: [Message]) -> Argument { replies[0].arguments[1] }
@DJLinkActor private func session() -> LinkSession {
    let s = LinkSession(Library())
    _ = ask(s, kind.SETUP, [0x0b])
    return s
}
@DJLinkActor private func playlist_count(_ s: LinkSession) -> Argument {
    status(ask(s, kind.PLAYLIST_MENU, [CTX, 0, PLAYLIST, 0]))
}
@DJLinkActor private func items(_ s: LinkSession, _ location: UInt32, _ total: UInt32) -> [Message] {
    ask(s, kind.RENDER, [0x0b00_0401 | location << 16, 0, total, 0, total, 0]).filter { $0.kind == kind.MENU_ITEM }
}
@Suite @DJLinkActor struct MyTagsTests {
    @Test("capture_one_one_tag_per_category_replays_byte_for_byte")
    func capture_one_one_tag_per_category_replays_byte_for_byte() throws {
        let compared = try replay(
            UpstreamFixtures.bytes(crate: "rbl-dbserver", path: "tests/corpus/mytag-rx3-1.player.bin"),
            UpstreamFixtures.bytes(crate: "rbl-dbserver", path: "tests/corpus/mytag-rx3-1.rekordbox.bin"))
        #expect(compared[kind.MY_TAG] == 48)
        #expect(compared[kind.FILTER_MY_TAG] == 6)
        #expect(compared[kind.FILTER_MY_TAG_ITEM] == 2)
        #expect(compared[kind.FILTER_SWITCH] == 28)
        #expect(compared[kind.PLAYLIST_MENU] == 69)
        #expect(compared[kind.RENDER] == 48)
    }
    @Test("capture_two_and_or_untick_all_tracks_and_bpm_replays_byte_for_byte")
    func capture_two_and_or_untick_all_tracks_and_bpm_replays_byte_for_byte() throws {
        let compared = try replay(
            UpstreamFixtures.bytes(crate: "rbl-dbserver", path: "tests/corpus/mytag-rx3-2.player.bin"),
            UpstreamFixtures.bytes(crate: "rbl-dbserver", path: "tests/corpus/mytag-rx3-2.rekordbox.bin"))
        #expect(compared[kind.MY_TAG] == 33)
        #expect(compared[kind.FILTER_MY_TAG] == 3)
        #expect(compared[kind.FILTER_MY_TAG_ITEM] == 3)
        #expect(compared[kind.FILTER_SWITCH] == 28)
        #expect(compared[kind.PLAYLIST_MENU] == 40)
        #expect(compared[kind.TRACK_MENU] == 44)
        #expect(compared[kind.RENDER] == 33)
    }
    @Test("my_tag_setters_refuse_what_rekordbox_refuses") func my_tag_setters_refuse_what_rekordbox_refuses() {
        let s = session()
        let refused = Argument.number(0x32)
        let ok = Argument.number(0)
        for args: [UInt32] in [
            [CTX, 1, 2, 1, 16], [CTX, 0, 2, 1, 18], [CTX, 0, 9, 1, 16], [CTX, 0, REESE, 1, 16], [CTX, 0, 0, 1, 16],
        ] { #expect(status(ask(s, kind.FILTER_MY_TAG, args)) == refused) }
        #expect(status(ask(s, kind.FILTER_MY_TAG, [CTX, 0, 2, 1, 17])) == ok)
        for args: [UInt32] in [[CTX, 1, 2, REESE, 1], [CTX, 0, 9, REESE, 1], [CTX, 0, 2, .max, 1]] {
            #expect(status(ask(s, kind.FILTER_MY_TAG_ITEM, args)) == refused)
        }
        for args: [UInt32] in [
            [CTX, 0, 2, .max, 0], [CTX, 0, 2, WUBBY, 0], [CTX, 0, 2, REESE, 1], [CTX, 0, 2, REESE, 1],
        ] { #expect(status(ask(s, kind.FILTER_MY_TAG_ITEM, args)) == ok) }
        #expect(status(ask(s, kind.FILTER_MY_TAG, [CTX, 0, 2, 1])) == refused)
    }
    @Test("ticks_are_a_set_and_selected_only_lists_what_is_ticked")
    func ticks_are_a_set_and_selected_only_lists_what_is_ticked() {
        let s = session()
        _ = ask(s, kind.FILTER_MY_TAG_ITEM, [CTX, 0, 2, REESE, 1])
        _ = ask(s, kind.FILTER_MY_TAG_ITEM, [CTX, 0, 2, REESE, 1])
        _ = ask(s, kind.FILTER_MY_TAG_ITEM, [CTX, 0, 2, WUBBY, 1])
        _ = ask(s, kind.FILTER_MY_TAG, [CTX, 0, 2, 1, 16])
        _ = ask(s, kind.FILTER_SWITCH, [CTX, 1])
        #expect(playlist_count(s) == .number(21))
        _ = ask(s, kind.FILTER_MY_TAG_ITEM, [CTX, 0, 2, REESE, 0])
        #expect(playlist_count(s) == .number(26))
        #expect(status(ask(s, 0x1015, [0x0b05_0401, 0, 2, 1])) == .number(1))
        let ticked = items(s, 5, 1)
        #expect(ticked[0].arguments[1] == .number(WUBBY))
        #expect(ticked[0].arguments[6] == .number(0x4b))
        #expect(status(ask(s, 0x1015, [0x0b07_0401, 0, 0, 1])) == .number(1))
        #expect(items(s, 7, 1)[0].arguments[1] == .number(2))
        _ = ask(s, kind.FILTER_MY_TAG_ITEM, [CTX, 0, 2, .max, 0])
        #expect(status(ask(s, 0x1015, [0x0b05_0401, 0, 2, 1])) == .number(0))
        #expect(playlist_count(s) == .number(41))
    }
    @Test("a_tag_rows_number_skips_unused_tags_and_survives_selected_only")
    func a_tag_rows_number_skips_unused_tags_and_survives_selected_only() {
        func rows(_ replies: [Message]) -> [(String, UInt32)] {
            replies.map { m in
                guard case let .string(name) = m.arguments[3], case let .number(n) = m.arguments[9] else {
                    Issue.record("row")
                    return ("", 0)
                }
                return (name, n)
            }
        }
        let s = session()
        #expect(status(ask(s, kind.MY_TAG, [0x0b05_0401, 0, 3, 0])) == .number(7))
        let listed = rows(items(s, 5, 7))
        let expected = ["vocals", "mc-bars", "ragga", "one-shot", "full-vocal", "us-vocal", "uk-vocal"].enumerated().map
        { ($0.element, UInt32($0.offset)) }
        #expect(listed.map { $0.0 } == expected.map { $0.0 })
        #expect(listed.map { $0.1 } == expected.map { $0.1 })
        _ = ask(s, kind.FILTER_MY_TAG_ITEM, [CTX, 0, 3, MC_BARS, 1])
        _ = ask(s, kind.FILTER_MY_TAG_ITEM, [CTX, 0, 3, 0x07c7_3257, 1])
        #expect(status(ask(s, kind.MY_TAG, [0x0b05_0401, 0, 3, 1])) == .number(2))
        let selected = rows(items(s, 5, 2))
        #expect(selected.map { $0.0 } == ["mc-bars", "us-vocal"])
        #expect(selected.map { $0.1 } == [1, 5])
    }
    @Test("an_empty_or_oversized_category_and_the_master_switch_leave_the_list_whole")
    func an_empty_or_oversized_category_and_the_master_switch_leave_the_list_whole() {
        let s = session()
        _ = ask(s, kind.FILTER_SWITCH, [CTX, 1])
        _ = ask(s, kind.FILTER_MY_TAG, [CTX, 0, 3, 1, 16])
        #expect(playlist_count(s) == .number(41))
        _ = ask(s, kind.FILTER_MY_TAG_ITEM, [CTX, 0, 3, MC_BARS, 1])
        #expect(playlist_count(s) == .number(1))
        _ = ask(s, kind.FILTER_SWITCH, [CTX, 0])
        #expect(playlist_count(s) == .number(41))
        _ = ask(s, kind.FILTER_SWITCH, [CTX, 1])
        #expect(playlist_count(s) == .number(1))
        for n: UInt32 in 0..<50 { _ = ask(s, kind.FILTER_MY_TAG_ITEM, [CTX, 0, 3, 0x6000_0000 + n, 1]) }
        #expect(playlist_count(s) == .number(41))
    }
    @Test("a_tracks_my_tags_come_under_their_categories") func a_tracks_my_tags_come_under_their_categories() {
        let s = session()
        #expect(status(ask(s, kind.MY_TAG_ON_TRACK, [0x0b05_0401, 0, 22])) == .number(4))
        let rows = items(s, 5, 4)
        let expected: [(UInt32, UInt32, String, UInt32)] = [
            (2, 2, "Traits", 1), (2, REESE, "reese", 0x4a), (3, 3, "Vocals", 1), (3, MC_BARS, "mc-bars", 0x4a),
        ]
        #expect(rows.count == expected.count)
        for (m, v) in zip(rows, expected) {
            #expect(m.arguments[0] == .number(v.0))
            #expect(m.arguments[1] == .number(v.1))
            #expect(m.arguments[3] == .string(v.2))
            #expect(m.arguments[6] == .number(v.3))
        }
        #expect(status(ask(s, kind.MY_TAG_ON_TRACK, [0x0b05_0401, 0, 41])) == .number(0))
    }
}
