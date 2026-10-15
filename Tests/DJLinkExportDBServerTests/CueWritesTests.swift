import DJLinkKit
// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-dbserver/tests/cue_writes.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportDBServer

private typealias Message = DJLinkExportDBServer.Message
private typealias Query = DJLinkExportDBServer.Query
private typealias Item = DJLinkExportDBServer.Item

private let CTX: UInt32 = 0x0101_0301
private let TRACK: UInt32 = 0x475f
@DJLinkActor private final class Recording: Catalog {
    var edits: [Edit] = []
    var accept = true
    var cueList: [UInt8]?
    init(_ list: [UInt8]?) { cueList = list }
    func list(_ query: Query) -> [Row] { [] }
    func track_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? { nil }
    func track(_ id: UInt32) -> TrackDetails? { nil }
    func artwork(_ id: UInt32) -> [UInt8]? { nil }
    func item_artwork(_ id: UInt32) -> [UInt8]? { nil }
    func analysis(_ track: UInt32, _ what: Analysis) -> [UInt8]? {
        what == .extendedCueList && track == TRACK ? cueList : nil
    }
    func usb_cues(_ track: UInt32) -> [UsbCue] {
        track == TRACK ? [UsbCue(slot: 0, in_ms: 1000, out_ms: nil, color_table_index: 0)] : []
    }
    func edit(_ edit: Edit) -> Bool {
        edits.append(edit)
        return accept
    }
}
@DJLinkActor private func session(_ catalog: Recording) -> any Session {
    let s = CatalogHandler(catalog).open()
    _ = s.handle(setup_request(1))
    return s
}
private struct Cdj3000Cue {
    var slot: UInt16 = 0
    var in_ms: UInt32 = 0
    var out_ms: UInt32? = nil
    var active = false
    var memory_colour: UInt8 = 0
    var beats: BeatLoop? = nil
    var comment = ""
    var rgb: [UInt8] = [0, 0, 0]
    func record() -> [UInt8] {
        let comment: [UInt8] = self.comment.isEmpty ? [] : (Array(self.comment.utf16) + [0]).flatMap { dbLE($0) }
        let hot = slot != 0
        var head = [UInt8](repeating: 0, count: 0x46)
        head.replaceSubrange(0..<2, with: dbLE(slot))
        head.replaceSubrange(2..<6, with: dbLE(UInt32(out_ms != nil ? 2 : 1)))
        head.replaceSubrange(6..<8, with: dbLE(UInt16(1000)))
        head.replaceSubrange(8..<12, with: dbLE(in_ms))
        head.replaceSubrange(12..<16, with: dbLE(out_ms ?? .max))
        if active { head[0x14] = 4 }
        head.replaceSubrange(0x20..<0x30, with: Array(repeating: 0xff, count: 0x10))
        let options = UInt32(0x12 + comment.count + (hot ? 8 : 0))
        head.replaceSubrange(0x30..<0x34, with: dbLE(options))
        head[0x36] = memory_colour
        if let beats {
            head.replaceSubrange(0x3e..<0x40, with: dbLE(beats.numerator))
            head.replaceSubrange(0x40..<0x42, with: dbLE(beats.denominator))
        }
        head.replaceSubrange(0x44..<0x46, with: dbLE(UInt16(comment.count)))
        var body = head + comment
        if hot { body += dbLE(UInt32(4)) + [0, rgb[0], rgb[1], rgb[2]] }
        body += Array(repeating: 0, count: body.count & 3)
        return dbLE(UInt32(body.count + 4)) + body
    }
}
private func save(_ op: UInt32, _ record: [UInt8]) -> Message {
    .new(
        0x8134, kind.SAVE_EXTENDED_CUE,
        [.number(CTX), .number(TRACK), .number(op), .number(UInt32(record.count)), .blob(record)])
}
private func two_cues() -> [UInt8] {
    (0..<2).flatMap { _ in dbLE(UInt32(0x38)) + Array(repeating: UInt8(0), count: 0x34) }
}
private func the_list(_ reply: [Message]) -> [Argument] {
    #expect(reply.count == 1)
    #expect(reply[0].kind == kind.EXTENDED_CUES_REPLY)
    #expect(reply[0].transaction == 0x8134)
    return reply[0].arguments
}
private func legacy(_ op: UInt32, _ flags: UInt32, _ in_ms: UInt32, _ out_ms: UInt32) -> Message {
    var record = Array(repeating: UInt8(0), count: 0x24)
    record.replaceSubrange(0..<4, with: dbLE(flags))
    record.replaceSubrange(0xc..<0x10, with: dbLE(in_ms * 3 / 20))
    record.replaceSubrange(0x10..<0x14, with: dbLE(flags & 1 != 0 ? out_ms * 3 / 20 - 1 : UInt32.max))
    return .new(
        0x8135, kind.SAVE_CUE,
        [
            .number(CTX), .number(TRACK), .number(op), .number(0x24), .blob(record), .number(8),
            .blob(dbLE(in_ms) + dbLE(out_ms)),
        ])
}
@Suite @DJLinkActor struct CueWritesTests {
    @Test("a_memory_cue_saved_on_a_cdj_3000_reaches_the_library_and_is_answered_with_the_list")
    func a_memory_cue_saved_on_a_cdj_3000_reaches_the_library_and_is_answered_with_the_list() {
        let catalog = Recording(two_cues())
        let s = session(catalog)
        let record = Cdj3000Cue(in_ms: 61_234, memory_colour: 3, comment: "drop").record()
        let reply = s.handle(save(1, record))
        #expect(the_list(reply) == [.number(0x2705), .number(0), .number(0x70), .blob(two_cues()), .number(2)])
        #expect(
            catalog.edits == [
                .saveCue(
                    track: TRACK,
                    cue: PlayerCue(
                        kind: 0, in_ms: 61_234, out_ms: nil, colour: 2, hot_colour: .index(21), comment: "drop",
                        beat_loop: nil))
            ])
    }
    @Test("hot_cues_and_loops_carry_their_slot_colour_and_beats")
    func hot_cues_and_loops_carry_their_slot_colour_and_beats() throws {
        let catalog = Recording(two_cues())
        let s = session(catalog)
        _ = s.handle(save(1, Cdj3000Cue(slot: 4, in_ms: 500, rgb: [0, 0x70, 0xff]).record()))
        _ = s.handle(save(1, Cdj3000Cue(slot: 8, in_ms: 1000, out_ms: 3000, beats: BeatLoop(4, 1)).record()))
        _ = s.handle(save(1, Cdj3000Cue(in_ms: 2000, out_ms: 2500, active: true).record()))
        let cues = catalog.edits.compactMap { edit -> PlayerCue? in
            if case let .saveCue(track, cue) = edit, track == TRACK { return cue }
            Issue.record("SaveCue")
            return nil
        }
        #expect(cues[0].kind == 5)
        #expect(cues[0].out_ms == nil)
        #expect(cues[0].hot_colour == .rgb([0, 0x70, 0xff]))
        #expect(cues[0].colour == nil)
        #expect(cues[1].kind == 9)
        #expect(cues[1].out_ms == 3000)
        #expect(cues[1].hot_colour == .index(36))
        #expect(cues[1].beat_loop == BeatLoop(4, 1))
        #expect(cues[2].kind == 4)
        #expect(cues[2].in_ms == 2000)
        #expect(cues[2].out_ms == 2500)
    }
    @Test("a_deleted_cue_is_a_delete_edit") func a_deleted_cue_is_a_delete_edit() {
        let catalog = Recording(two_cues())
        let s = session(catalog)
        let reply = s.handle(save(0, Cdj3000Cue(slot: 1, in_ms: 500).record()))
        #expect(the_list(reply)[1] == .number(0))
        if catalog.edits.count == 1, case let .deleteCue(track, cue) = catalog.edits[0] {
            #expect(track == TRACK)
            #expect(cue.kind == 1)
            #expect(cue.in_ms == 500)
        } else {
            Issue.record("DeleteCue")
        }
    }
    @Test("frame_based_records_round_up_to_milliseconds_as_rekordbox_does")
    func frame_based_records_round_up_to_milliseconds_as_rekordbox_does() {
        let cases: [(UInt16, UInt32, UInt32, UInt32, UInt32)] = [
            (150, 1, 2, 7, 20), (150, 3, 9, 20, 67), (150, 9000, 9149, 60000, 61000), (75, 1, 2, 14, 34),
        ]
        for (timebase, frames_in, frames_out, in_ms, out_ms) in cases {
            let catalog = Recording(two_cues())
            let s = session(catalog)
            var record = Cdj3000Cue(out_ms: 1).record()
            record.replaceSubrange(0xa..<0xc, with: dbLE(timebase))
            record.replaceSubrange(0xc..<0x10, with: dbLE(frames_in))
            record.replaceSubrange(0x10..<0x14, with: dbLE(frames_out))
            _ = s.handle(save(1, record))
            if catalog.edits.count == 1, case let .saveCue(_, cue) = catalog.edits[0] {
                #expect(cue.in_ms == in_ms)
                #expect(cue.out_ms == out_ms)
            } else {
                Issue.record("SaveCue")
            }
        }
    }
    @Test("records_rekordbox_leaves_alone_change_nothing_and_get_the_list")
    func records_rekordbox_leaves_alone_change_nothing_and_get_the_list() {
        let base = Cdj3000Cue(in_ms: 10).record()
        var cases: [[UInt8]] = []
        var past_h = base
        past_h.replaceSubrange(4..<6, with: dbLE(UInt16(9)))
        cases.append(past_h)
        for shape: UInt8 in [0, 3] {
            var record = base
            record[6] = shape
            cases.append(record)
        }
        var timebase = base
        timebase.replaceSubrange(0xa..<0xc, with: dbLE(UInt16(100)))
        cases.append(timebase)
        for record in cases {
            let catalog = Recording(two_cues())
            let s = session(catalog)
            let reply = s.handle(save(1, record))
            #expect(the_list(reply)[4] == .number(2))
            #expect(catalog.edits.isEmpty)
        }
    }
    @Test("a_cue_save_is_never_answered_with_4003") func a_cue_save_is_never_answered_with_4003() {
        let refusal: [Argument] = [.number(0x2705), .number(0x32), .number(0), .blob([]), .number(0)]
        let good = Cdj3000Cue(in_ms: 10).record()
        let requests = [
            save(1, Array(good[..<0x37])),
            Message.new(0x8134, kind.SAVE_EXTENDED_CUE, [.number(CTX), .number(TRACK), .number(1), .number(0)]),
            Message.new(
                0x8134, kind.SAVE_EXTENDED_CUE,
                [.number(CTX), .string("x"), .number(1), .number(UInt32(good.count)), .blob(good)]),
        ]
        let catalog = Recording(two_cues())
        let s = session(catalog)
        for request in requests { #expect(the_list(s.handle(request)) == refusal) }
        #expect(catalog.edits.isEmpty)
        let refusing = Recording(two_cues())
        refusing.accept = false
        #expect(the_list(session(refusing).handle(save(1, good))) == refusal)
        #expect(refusing.edits.count == 1)
    }
    @Test("a_track_left_without_cues_is_answered_with_status_1")
    func a_track_left_without_cues_is_answered_with_status_1() {
        let s = session(Recording([]))
        let reply = s.handle(save(0, Cdj3000Cue(in_ms: 10).record()))
        #expect(the_list(reply) == [.number(0x2705), .number(1), .number(0), .blob([]), .number(0)])
        let read = s.handle(.new(0x8134, kind.EXTENDED_CUES, [.number(CTX), .number(TRACK)]))
        #expect(Array(the_list(read).prefix(2)) == [.number(0x2b04), .number(1)])
    }
    @Test("a_legacy_cue_save_reaches_the_library_and_is_answered_with_the_legacy_list")
    func a_legacy_cue_save_reaches_the_library_and_is_answered_with_the_legacy_list() {
        let catalog = Recording(two_cues())
        let s = session(catalog)
        let reply = s.handle(legacy(1, 2 << 16, 1234, 0))
        #expect(reply.count == 1)
        #expect(reply[0].kind == kind.HOT_CUE_BANK_REPLY)
        #expect(Array(reply[0].arguments.prefix(2)) == [.number(0x2105), .number(0)])
        _ = s.handle(legacy(0, 0x201, 2000, 4000))
        #expect(
            catalog.edits[0]
                == .saveCue(
                    track: TRACK,
                    cue: PlayerCue(
                        kind: 2, in_ms: 1234, out_ms: nil, colour: nil, hot_colour: .index(21), comment: "",
                        beat_loop: nil)))
        if case let .deleteCue(_, cue) = catalog.edits[1] {
            #expect(cue.kind == 4)
            #expect(cue.out_ms == 4000)
        } else {
            Issue.record("DeleteCue")
        }
    }
    @Test("a_legacy_cue_save_rbx_cannot_read_still_gets_a_4702")
    func a_legacy_cue_save_rbx_cannot_read_still_gets_a_4702() {
        let catalog = Recording(two_cues())
        let s = session(catalog)
        for request in [
            legacy(1, 4 << 16, 1000, 0),
            Message.new(0x8135, kind.SAVE_CUE, [.number(CTX), .number(TRACK), .number(1)]),
        ] {
            let reply = s.handle(request)
            #expect(reply.count == 1)
            #expect(reply[0].kind == kind.HOT_CUE_BANK_REPLY)
            #expect(reply[0].arguments[1] == .number(0x32))
        }
        #expect(catalog.edits.isEmpty)
    }
}
