// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-anlz/tests/parse.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportANLZ

func testBE<T: FixedWidthInteger>(_ v: T) -> [UInt8] {
    (0..<MemoryLayout<T>.size).reversed().map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) }
}
func testPut<T: FixedWidthInteger>(_ bytes: inout [UInt8], _ at: Int, _ v: T) {
    bytes.replaceSubrange(at..<(at + MemoryLayout<T>.size), with: testBE(v))
}
private func build(_ sections: [(String, [UInt8], [UInt8])]) -> [UInt8] {
    let extra = [UInt8](repeating: 0, count: 16)
    var body: [UInt8] = []
    for (tag, header, payload) in sections {
        body += tag.utf8
        body += testBE(UInt32(12 + header.count))
        body += testBE(UInt32(12 + header.count + payload.count))
        body += header
        body += payload
    }
    return Array("PMAI".utf8) + testBE(UInt32(28)) + testBE(UInt32(28 + body.count)) + extra + body
}
private func beat_grid_parts(_ beats: [(UInt16, UInt16, UInt32)]) -> ([UInt8], [UInt8]) {
    (
        testBE(UInt32(0)) + testBE(UInt32(0x80000)) + testBE(UInt32(beats.count)),
        beats.flatMap { testBE($0.0) + testBE($0.1) + testBE($0.2) }
    )
}
private func path_parts(_ text: String) -> ([UInt8], [UInt8]) {
    let raw = text.utf16.flatMap(testBE) + [0, 0]
    return (testBE(UInt32(raw.count)), raw)
}
private func cue_entry(_ hot: UInt32, _ kind: UInt8, _ time: UInt32, _ comment: String, _ colour: (UInt8, [UInt8])?)
    -> [UInt8]
{
    let text = comment.utf16.flatMap(testBE) + (comment.isEmpty ? [] : [0, 0])
    var body =
        testBE(hot) + [kind, 0, 0, 0] + testBE(time) + testBE(UInt32(0)) + [UInt8](repeating: 0, count: 12)
        + testBE(UInt32(text.count)) + text
    if let (code, rgb) = colour { body += [code] + rgb }
    return Array("PCP2".utf8) + testBE(UInt32(12)) + testBE(UInt32(12 + body.count)) + body
}
@Suite("parse") struct ParseTests {
    @Test("rejects_a_file_without_the_pmai_magic") func rejects_a_file_without_the_pmai_magic() {
        #expect(throws: AnlzError.notAnlz) { try parse(Array("NOPE\0\0\0\0\0\0\0\0".utf8)) }
    }
    @Test("rejects_a_truncated_header_without_panicking") func rejects_a_truncated_header_without_panicking() {
        for input in [Array("PMAI".utf8), Array("PMAI\0\0".utf8), []] {
            #expect(throws: (any Error).self) { try parse(input) }
        }
    }
    @Test("reads_a_beat_grid") func reads_a_beat_grid() throws {
        let (h, p) = beat_grid_parts([(1, 12800, 0), (2, 12800, 469), (3, 12800, 938)])
        let beats = try #require(parse(build([("PQTZ", h, p)])).beat_grid())
        #expect(beats.count == 3)
        #expect(beats[0].beat_number == 1)
        #expect(beats[1].tempo_x100 == 12800)
        #expect(beats[2].time_ms == 938)
    }
    @Test("a_truncated_beat_grid_keeps_the_beats_it_could_read")
    func a_truncated_beat_grid_keeps_the_beats_it_could_read() throws {
        var (h, p) = beat_grid_parts([(1, 12800, 0), (2, 12800, 469)])
        testPut(&h, 8, UInt32(4))
        #expect(try #require(parse(build([("PQTZ", h, p)])).beat_grid()).count == 2)
    }
    @Test("reads_a_utf16_path") func reads_a_utf16_path() throws {
        let path = "/Users/dj/Music/Track Ébano.mp3"
        let (h, p) = path_parts(path)
        #expect(try parse(build([("PPTH", h, p)])).path() == path)
    }
    @Test("keeps_unknown_tags_verbatim") func keeps_unknown_tags_verbatim() throws {
        let s = try #require(parse(build([("PZZZ", [7, 7], [1, 2, 3, 4])])).section("PZZZ"))
        #expect(s.tag == Tag("PZZZ"))
        #expect(s.header == [7, 7])
        #expect(s.payload == [1, 2, 3, 4])
    }
    @Test("tag_header_fields_are_not_read_from_the_payload") func tag_header_fields_are_not_read_from_the_payload()
        throws
    {
        let header = testBE(UInt32(6)) + testBE(UInt32(0x10000))
        let payload: [UInt8] = [0x51, 0x4b, 0x52, 0x54, 0x50, 0x55]
        let (stride, data) = try #require(parse(build([("PWAV", header, payload)])).waveform("PWAV"))
        #expect(stride == 1)
        #expect(data == payload)
    }
    @Test("reads_waveform_stride_from_the_tag_header") func reads_waveform_stride_from_the_tag_header() throws {
        let h = testBE(UInt32(2)) + testBE(UInt32(3)) + testBE(UInt32(0))
        let p: [UInt8] = [1, 2, 3, 4, 5, 6]
        let (stride, data) = try #require(parse(build([("PWV5", h, p)])).waveform("PWV5"))
        #expect(stride == 2)
        #expect(data == p)
    }
    @Test("reads_pwv6s_three_byte_stride_from_its_short_header")
    func reads_pwv6s_three_byte_stride_from_its_short_header() throws {
        #expect(
            try parse(build([("PWV6", [0, 0, 0, 3, 0, 0, 0, 2], [UInt8](repeating: 1, count: 6))])).waveform("PWV6")?.0
                == 3)
    }
    @Test("a_section_longer_than_the_file_is_reported") func a_section_longer_than_the_file_is_reported() throws {
        let (h, p) = beat_grid_parts([(1, 12800, 0)])
        var file = build([("PQTZ", h, p)])
        let len = file.count
        testPut(&file, 36, UInt32(len + 500))
        do {
            _ = try parse(file)
            Issue.record("expected section error")
        } catch AnlzError.badSectionLength {}
    }
    @Test("rejects_a_file_whose_declared_length_does_not_match")
    func rejects_a_file_whose_declared_length_does_not_match() {
        var file = build([])
        testPut(&file, 8, UInt32(27))
        #expect(throws: AnlzError.badFileLength(declared: 27, actual: 28)) { try parse(file) }
    }
    @Test("rejects_a_section_header_that_runs_past_its_frame") func rejects_a_section_header_that_runs_past_its_frame()
        throws
    {
        var file = build([("PWAV", [UInt8](repeating: 0, count: 8), [1, 2, 3])])
        testPut(&file, 32, UInt32(24))
        do {
            _ = try parse(file)
            Issue.record("expected section header error")
        } catch AnlzError.badSectionHeaderLength {}
    }
    @Test("a_zero_length_section_does_not_loop_forever") func a_zero_length_section_does_not_loop_forever() {
        let (h, p) = beat_grid_parts([(1, 12800, 0)])
        var file = build([("PQTZ", h, p)])
        testPut(&file, 36, UInt32(0))
        #expect(throws: (any Error).self) { try parse(file) }
    }
    @Test("several_sections_are_all_read") func several_sections_are_all_read() throws {
        let (ph, pp) = path_parts("/a.mp3")
        let (bh, bp) = beat_grid_parts([(1, 12000, 0)])
        let a = try parse(build([("PPTH", ph, pp), ("PQTZ", bh, bp), ("PZZZ", [], [9])]))
        #expect(a.sections.count == 3)
        #expect(a.path() != nil)
        #expect(a.beat_grid() != nil)
    }
    @Test("reading_a_missing_file_is_an_io_error") func reading_a_missing_file_is_an_io_error() throws {
        do {
            _ = try Anlz.read("/definitely/not/here.DAT")
            Issue.record("expected IO")
        } catch AnlzError.io {}
    }
    @Test("resolve_joins_a_share_relative_path") func resolve_joins_a_share_relative_path() {
        let share = "/Users/dj/Library/Pioneer/rekordbox/share"
        let p = resolve(share, "/PIONEER/USBANLZ/abc/def/ANLZ0000.DAT")
        #expect(p.hasSuffix("PIONEER/USBANLZ/abc/def/ANLZ0000.DAT"))
        #expect(p.hasPrefix(share))
    }
    @Test("sibling_swaps_the_extension") func sibling_swaps_the_extension() {
        #expect(sibling("/x/ANLZ0000.DAT", "EXT").hasSuffix("ANLZ0000.EXT"))
        #expect(sibling("/x/ANLZ0000.DAT", "2EX").hasSuffix("ANLZ0000.2EX"))
    }
    @Test("parsing_then_re_emitting_reproduces_the_file_exactly")
    func parsing_then_re_emitting_reproduces_the_file_exactly() throws {
        let (ph, pp) = path_parts("/a.mp3")
        let (bh, bp) = beat_grid_parts([(1, 12800, 0), (2, 12800, 469)])
        let original = build([
            ("PPTH", ph, pp), ("PQTZ", bh, bp), ("PSSI", [1, 2], [3, 4, 5]), ("PVDI", [], [9, 8, 7]),
        ])
        #expect(try parse(original).to_bytes() == original)
    }
    @Test("a_written_beat_grid_reads_back_identically") func a_written_beat_grid_reads_back_identically() throws {
        let beats = (0..<64).map { Beat(beat_number: UInt16($0 % 4 + 1), tempo_x100: 12800, time_ms: UInt32($0) * 469) }
        let a = try parse(AnlzBuilder().path("/Users/dj/Music/Track.mp3").beat_grid(beats).finish())
        #expect(a.path() == "/Users/dj/Music/Track.mp3")
        #expect(a.beat_grid() == beats)
    }
    @Test("written_waveforms_read_back_identically") func written_waveforms_read_back_identically() throws {
        let data = (0..<600).map { UInt8($0 % 256) }
        let a = try parse(AnlzBuilder().waveform_preview("PWAV", data).waveform_scroll("PWV5", 2, data).finish())
        let first = try #require(a.waveform("PWAV"))
        let second = try #require(a.waveform("PWV5"))
        #expect(first.0 == 1)
        #expect(first.1 == data)
        #expect(second.0 == 2)
        #expect(second.1 == data)
    }
    @Test("non_ascii_paths_survive_the_round_trip") func non_ascii_paths_survive_the_round_trip() throws {
        let path = "/Users/dj/Música/Ébano — Tiësto.mp3"
        #expect(try parse(AnlzBuilder().path(path).finish()).path() == path)
    }
    @Test("tags_we_cannot_author_are_carried_through") func tags_we_cannot_author_are_carried_through() throws {
        let (ph, pp) = path_parts("/a.mp3")
        let parsed = try parse(build([("PPTH", ph, pp), ("PSSI", [1], [2, 3, 4, 5]), ("PVDI", [], [9, 8, 7])]))
        let b = AnlzBuilder().header_extra(parsed.header_extra)
        for s in parsed.sections { b.copy_section(s) }
        let reparsed = try parse(b.finish())
        let tags = reparsed.sections.map { $0.tag.description }
        #expect(tags.contains("PSSI"))
        #expect(tags.contains("PVDI"))
        #expect(reparsed.section("PSSI")?.payload == [2, 3, 4, 5])
    }
    @Test("an_empty_cue_list_is_what_the_share_tree_holds") func an_empty_cue_list_is_what_the_share_tree_holds() throws
    {
        let lists = try parse(AnlzBuilder().empty_cue_list(false).empty_cue_list(true).finish()).sections.filter {
            $0.is_cue_list()
        }
        #expect(lists.count == 2)
        #expect(lists.allSatisfy { $0.payload.isEmpty })
    }
    @Test("a_file_with_no_sections_is_still_valid") func a_file_with_no_sections_is_still_valid() throws {
        let a = try parse(AnlzBuilder().finish())
        #expect(a.sections.isEmpty)
        #expect(a.beat_grid() == nil)
    }
    @Test("replacing_the_grid_leaves_every_other_section_alone")
    func replacing_the_grid_leaves_every_other_section_alone() throws {
        let beats = (0..<8).map {
            Beat(beat_number: UInt16($0 % 4 + 1), tempo_x100: 12000, time_ms: 500 + UInt32($0) * 500)
        }
        let original = AnlzBuilder().path("/Music/one.mp3").beat_grid(beats).waveform_preview("PWAV", [1, 2, 3, 4])
            .finish()
        let parsed = try parse(original)
        #expect(parsed.with_beat_grid(beats) == original)
        let nudged = Grid.apply(beats, .nudge(-40))
        let rewritten = try parse(parsed.with_beat_grid(nudged))
        #expect(rewritten.beat_grid() == nudged)
        #expect(rewritten.path() == "/Music/one.mp3")
        #expect(rewritten.waveform("PWAV")?.0 == parsed.waveform("PWAV")?.0)
        #expect(rewritten.waveform("PWAV")?.1 == parsed.waveform("PWAV")?.1)
        #expect(rewritten.sections.count == parsed.sections.count)
    }
    @Test("a_file_with_no_grid_gains_one_after_its_required_prefix")
    func a_file_with_no_grid_gains_one_after_its_required_prefix() throws {
        let parsed = try parse(
            AnlzBuilder().path("/Music/one.mp3").vbr_table_zero().waveform_preview("PWAV", [1, 2, 3]).finish())
        #expect(parsed.beat_grid() == nil)
        let beat = Beat(beat_number: 1, tempo_x100: 12000, time_ms: 500)
        let grown = try parse(parsed.with_beat_grid([beat]))
        #expect(grown.beat_grid() == [beat])
        #expect(grown.sections.prefix(3).map { $0.tag.as_str() } == ["PPTH", "PVBR", "PQTZ"])
        #expect(!grown.has_extended_grid())
    }
    @Test("extended_cues_carry_their_colour") func extended_cues_carry_their_colour() throws {
        let payload =
            cue_entry(1, 1, 4321, "intro", (21, [0, 255, 0])) + cue_entry(2, 2, 90000, "", (36, [255, 140, 0]))
        let entries = try parse(build([("PCO2", [0, 0, 0, 1, 0, 2, 0, 0], payload)])).cue_entries()
        #expect(entries.count == 2)
        #expect(entries[0].hot_cue == 1)
        #expect(entries[0].kind == 1)
        #expect(entries[0].time_ms == 4321)
        #expect(entries[0].comment == "intro")
        #expect(entries[0].color_code == 21)
        #expect(entries[0].rgb == [0, 255, 0])
        #expect(entries[1].hot_cue == 2)
        #expect(entries[1].comment == nil)
        #expect(entries[1].color_code == 36)
    }
    @Test("an_empty_cue_list_reads_as_no_cues") func an_empty_cue_list_reads_as_no_cues() throws {
        #expect(try parse(build([("PCO2", [0, 0, 0, 1, 0, 0, 0, 0], [])])).cue_entries().isEmpty)
    }
    @Test("a_truncated_cue_entry_does_not_run_off_the_end") func a_truncated_cue_entry_does_not_run_off_the_end() throws
    {
        var payload = cue_entry(1, 1, 100, "a", (21, [1, 2, 3]))
        payload.removeLast(6)
        #expect(try parse(build([("PCO2", [0, 0, 0, 1, 0, 1, 0, 0], payload)])).cue_entries().isEmpty)
    }
    @Test("the_cue_palette_answers_for_every_valid_index") func the_cue_palette_answers_for_every_valid_index() {
        #expect(cue_colour(21) == [0, 255, 0])
        #expect(cue_colour(36) == [255, 140, 0])
        #expect(cue_colour(41) == [255, 26, 0])
        #expect(cue_colour(0) == [0, 0, 0])
        #expect(cue_colour(64) == [255, 255, 255])
        #expect(cue_colour(65) == nil)
    }
    @Test("the_drawn_palette_covers_the_same_indices_as_the_stored_one")
    func the_drawn_palette_covers_the_same_indices_as_the_stored_one() {
        let stored = MEASURED_CUE_COLOURS.map(\.0)
        let drawn = DRAWN_CUE_COLOURS.map(\.0)
        #expect(stored == drawn)
        #expect(stored == Array(UInt8(0)...64))
        #expect(cue_colour_drawn(1) == [48, 90, 255])
        #expect(cue_colour_drawn(21) == [60, 235, 80])
        #expect(cue_colour_drawn(41) == [224, 40, 35])
        #expect(cue_colour_drawn(64) == [255, 255, 255])
        #expect(cue_colour_drawn(65) == nil)
    }
    @Test("a_grid_edit_empties_the_extended_grid_and_nothing_else")
    func a_grid_edit_empties_the_extended_grid_and_nothing_else() throws {
        var filled = [UInt8](repeating: 0, count: 44)
        testPut(&filled, 4, UInt32(0x01000002))
        let file = build([
            ("PPTH", [0, 0, 0, 4], [0, 97, 0, 0]), ("PQT2", filled, [1, 2, 3, 4, 5, 6]),
            ("PWV3", [0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0], [7, 8, 9]),
        ])
        let parsed = try parse(file)
        let cleared = try parse(#require(parsed.with_extended_grid_cleared()))
        #expect(cleared.sections.count == 3)
        #expect(cleared.sections[0] == parsed.sections[0])
        #expect(cleared.sections[2] == parsed.sections[2])
        let grid = cleared.sections[1]
        #expect(grid.tag == Tag("PQT2"))
        #expect(grid.payload.isEmpty)
        #expect(grid.header.count == 44)
        #expect(Array(grid.header[4..<8]) == testBE(UInt32(0x01000002)))
        #expect(grid.header.dropFirst(8).allSatisfy { $0 == 0 })
        #expect(cleared.with_extended_grid_cleared() == nil)
        #expect(try parse(build([("PPTH", [0, 0, 0, 4], [0, 97, 0, 0])])).with_extended_grid_cleared() == nil)
    }
}
