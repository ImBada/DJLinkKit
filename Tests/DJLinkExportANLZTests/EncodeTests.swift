// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-anlz/src/encode.rs의 tests
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation
import Testing

@testable import DJLinkExportANLZ

@Suite("encode::tests") struct EncodeTests {
    private func ramp(_ n: Int) -> [BandColumn] {
        (0..<n).map {
            let v = UInt8(exactly: $0 * 255 / max(n - 1, 1)) ?? 255
            return BandColumn(low: v, mid: v / 2, high: v / 4, peak: v)
        }
    }
    private func pwv5_word(_ c: BandColumn) -> UInt16 { anlzBE16(Encode.pwv5([c]), 0) }
    private func pwv5_fields(_ word: UInt16) -> [UInt16] {
        [word >> 13, (word >> 10) & 7, (word >> 7) & 7, (word >> 2) & 0x1f]
    }
    private func tags(_ bytes: [UInt8]) throws -> [String] { try parse(bytes).sections.map { $0.tag.description } }
    private func header_hex(_ bytes: [UInt8], _ tag: String, _ nth: Int) throws -> String {
        let sections = try parse(bytes).sections.filter { $0.tag == Tag(tag) }
        return sections[nth].header.map { String(format: "%02x", $0) }.joined()
    }
    @Test("independent_overview_is_encoded_without_peak_gain") func independent_overview_is_encoded_without_peak_gain()
        throws
    {
        let columns = ramp(1500)
        var overview = [[UInt8]](repeating: [0, 0, 0], count: Encode.OVERVIEW_COLUMNS)
        overview[600] = [59, 42, 70]
        let files = author_with_overview("/track.wav", [], columns, overview, Existing())
        let parsed = try parse(files.two_ex)
        let preview = try #require(parsed.section("PWV6"))
        #expect(Array(preview.payload[1800..<1803]) == [59, 42, 70])
        #expect(preview.payload.prefix(1800).allSatisfy { $0 == 0 })
        #expect(try #require(parsed.section("PWV7")).payload == Encode.pwv7(columns))
    }
    @Test("three_band_preview_uses_rekordbox_framing") func three_band_preview_uses_rekordbox_framing() throws {
        let files = author("/track.wav", [], ramp(1200), Existing())
        let s = try #require(parse(files.two_ex).section("PWV6"))
        #expect(s.header == [0, 0, 0, 3, 0, 0, 4, 176])
        #expect(s.payload.count == 3600)
    }
    @Test("coarser_waveforms_keep_the_loudest_column_of_each_bucket")
    func coarser_waveforms_keep_the_loudest_column_of_each_bucket() {
        var columns = [BandColumn](repeating: BandColumn(), count: 3000)
        columns[1500] = BandColumn(low: 200, mid: 10, high: 10, peak: 200)
        let overview = Encode.resample(columns, 1200)
        #expect(overview.count == 1200)
        #expect(overview[600].peak == 200)
        #expect(Encode.resample([], 4) == [BandColumn](repeating: BandColumn(), count: 4))
        #expect(Encode.resample(columns, 0) == [])
    }
    @Test("the_payloads_have_their_strides_and_ranges") func the_payloads_have_their_strides_and_ranges() {
        let c = ramp(3000)
        let v4 = Encode.pwv4(c)
        let full = BandColumn(low: 255, mid: 255, high: 255, peak: 255)
        #expect(Encode.pwav(c).count == 400)
        #expect(Encode.pwv2(c).count == 100)
        #expect(Encode.pwv3(c).count == 3000)
        #expect(v4.count == 7200)
        #expect(Encode.pwv5(c).count == 6000)
        #expect(Encode.pwv6(c).count == 3600)
        #expect(Encode.pwv7(c).count == 9000)
        #expect(stride(from: 0, to: v4.count, by: 6).allSatisfy { v4[$0] <= 127 })
        #expect(
            stride(from: 0, to: v4.count, by: 6).allSatisfy {
                v4[$0 + 3] <= 127 && v4[$0 + 4] <= 127 && v4[$0 + 5] <= 127
            })
        #expect(Array(Encode.pwv4([full])[3..<6]) == [127, 101, 82])
        #expect(Encode.pwv6(c).allSatisfy { $0 <= 44 })
        #expect(Encode.pwv7(c).allSatisfy { $0 <= 127 })
        #expect(Encode.pwv7([BandColumn(low: 255, mid: 128, high: 64, peak: 255)]) == [127, 64, 32])
        #expect(Encode.band(255) == 44)
        #expect(Encode.band_height(full, Encode.PWAV_CEILING) == 25)
        #expect(Encode.band_height(full, Encode.DETAIL_CEILING) == 31)
        #expect(Encode.pwav(c).map { $0 & 0x1f }.max() == 25)
        #expect(Encode.pwv2(c).max() == 15)
        #expect(Encode.pwv3(c).map { $0 & 0x1f }.max() == 31)
        #expect(Encode.pwav([BandColumn()])[0] & 0x1f == 2)
        #expect(Encode.mono_byte(BandColumn(low: 0, mid: 0, high: 255, peak: 255), Encode.PWAV_CEILING) >> 5 == 7)
        #expect(Encode.mono_byte(BandColumn(low: 255, mid: 0, high: 0, peak: 255), Encode.PWAV_CEILING) >> 5 == 0)
        let word = pwv5_word(full)
        #expect(word >> 7 == 0b101011111)
        #expect((word >> 2) & 0x1f == 31)
    }
    @Test("colour_channels_are_low_mid_and_high") func colour_channels_are_low_mid_and_high() {
        let bass = BandColumn(low: 200, mid: 0, high: 0, peak: 200)
        let body = BandColumn(low: 0, mid: 200, high: 0, peak: 200)
        let hats = BandColumn(low: 0, mid: 0, high: 200, peak: 200)
        #expect(Array(pwv5_fields(pwv5_word(bass)).prefix(3)) == [7, 0, 0])
        #expect(Array(pwv5_fields(pwv5_word(body)).prefix(3)) == [0, 5, 0])
        #expect(Array(pwv5_fields(pwv5_word(hats)).prefix(3)) == [0, 0, 7])
        #expect(Array(Encode.pwv4([bass])[3..<6]) == [100, 0, 0])
        #expect(Array(Encode.pwv4([body])[3..<6]) == [0, 80, 0])
        #expect(Array(Encode.pwv4([hats])[3..<6]) == [0, 0, 65])
    }
    @Test("pwv5_colour_is_normalised_so_a_quiet_column_is_as_saturated_as_a_loud_one")
    func pwv5_colour_is_normalised_so_a_quiet_column_is_as_saturated_as_a_loud_one() {
        let loud = pwv5_fields(pwv5_word(BandColumn(low: 240, mid: 120, high: 40, peak: 250)))
        let quiet = pwv5_fields(pwv5_word(BandColumn(low: 60, mid: 30, high: 10, peak: 80)))
        #expect(loud[0] == 7)
        #expect(Array(loud.prefix(3)) == Array(quiet.prefix(3)))
        #expect(quiet[3] < loud[3])
        #expect(pwv5_word(BandColumn()) == 0)
    }
    @Test("detail_height_is_rekordboxs_squared_peak") func detail_height_is_rekordboxs_squared_peak() {
        let values: [(UInt8, UInt16)] = [
            (0, 0), (56, 1), (104, 5), (136, 9), (168, 13), (200, 19), (232, 26), (255, 31),
        ]
        for (peak, height) in values {
            let column = BandColumn(low: peak / 2, mid: peak / 2, high: peak / 4, peak: peak)
            #expect(UInt16(Encode.pwv3([column])[0] & 0x1f) == height)
            #expect(pwv5_fields(pwv5_word(column))[3] == height)
        }
    }
    @Test("pwv5_matches_rekordboxs_own_words_for_these_columns")
    func pwv5_matches_rekordboxs_own_words_for_these_columns() {
        let rb: [(UInt8, UInt8, UInt8, UInt8, UInt16, UInt8)] = [
            (44, 102, 109, 186, 0x4fc0, 16), (217, 94, 55, 198, 0xe9cc, 19), (189, 45, 35, 222, 0xe55c, 23),
            (179, 112, 106, 252, 0xef78, 30), (233, 76, 21, 253, 0xe8fc, 31), (176, 173, 127, 239, 0xd7ec, 27),
            (162, 90, 57, 190, 0xee44, 17), (41, 68, 149, 182, 0x2bc0, 16), (173, 97, 41, 236, 0xed6c, 27),
            (133, 216, 145, 253, 0x97fc, 31),
        ]
        for (low, mid, high, peak, word, height) in rb {
            let c = BandColumn(low: low, mid: mid, high: high, peak: peak)
            #expect(pwv5_word(c) == word)
            #expect(Encode.pwv3([c])[0] & 0x1f == height)
        }
    }
    @Test("pwv5_matches_a_rekordbox_usb_exports_words_for_these_columns")
    func pwv5_matches_a_rekordbox_usb_exports_words_for_these_columns() {
        let rb: [(UInt8, UInt8, UInt8, UInt8, UInt16, UInt8)] = [
            (205, 230, 93, 255, 0xd67c, 31), (115, 55, 77, 170, 0xebb8, 14), (90, 36, 45, 145, 0xeaa8, 10),
            (77, 111, 152, 231, 0x4be4, 25), (97, 173, 125, 245, 0x97f4, 29), (36, 72, 140, 190, 0x2bc4, 17),
            (95, 74, 120, 243, 0x8bf0, 28), (88, 81, 30, 139, 0xf624, 9), (112, 79, 111, 227, 0xabe4, 25),
        ]
        for (low, mid, high, peak, word, height) in rb {
            let c = BandColumn(low: low, mid: mid, high: high, peak: peak)
            #expect(pwv5_word(c) == word)
            #expect(Encode.pwv3([c])[0] & 0x1f == height)
            #expect(max((word >> 13) & 7, (word >> 10) & 7, (word >> 7) & 7) >= 5)
        }
    }
    @Test("pwv2_carries_the_height_alone_as_rekordbox_does") func pwv2_carries_the_height_alone_as_rekordbox_does() {
        let treble = BandColumn(low: 0, mid: 0, high: 255, peak: 255)
        #expect(Encode.pwv2([treble]) == [UInt8](repeating: 15, count: Encode.TINY_COLUMNS))
        #expect(Encode.pwav([treble])[0] == 0b11111001)
        let columns = ramp(3000)
        #expect(Encode.pwv2(columns).allSatisfy { $0 <= Encode.PWV2_MAX_BYTE })
        #expect(Encode.pwv2(columns).max() == 15)
        #expect(Encode.pwv2([BandColumn()]) == [UInt8](repeating: 1, count: Encode.TINY_COLUMNS))
    }
    @Test("an_export_repairs_old_previews_and_leaves_rekordboxs_alone")
    func an_export_repairs_old_previews_and_leaves_rekordboxs_alone() {
        let ours = Section.new("PWV2", [UInt8](repeating: 0, count: 8), [0x48, 0xef, 0, 0x2f])
        #expect(Encode.with_device_preview(ours).payload == [8, 15, 1, 15])
        #expect(Encode.with_device_preview(ours).header == ours.header)
        let pwav = Section.new("PWAV", [UInt8](repeating: 0, count: 8), [0xa0, 0, 0xe5, 0x21])
        #expect(Encode.with_device_preview(pwav).payload == [0xa2, 2, 0xe5, 0x22])
        let rb2 = Section.new("PWV2", [UInt8](repeating: 0, count: 8), [8, 10, 10, 4, 12, 13, 14, 1])
        let rbA = Section.new("PWAV", [UInt8](repeating: 0, count: 8), [0xa2, 0xa2, 0xa5, 0xa4, 0xa7])
        let v3 = Section.new("PWV3", [UInt8](repeating: 0, count: 12), [0, 0xe0])
        #expect(Encode.with_device_preview(rb2) == rb2)
        #expect(Encode.with_device_preview(rbA) == rbA)
        #expect(Encode.with_device_preview(v3) == v3)
        #expect(Encode.device_tiny_preview_byte(255) == 15)
    }
    @Test("a_real_vbr_table_is_preserved_across_re_analysis_and_never_doubled")
    func a_real_vbr_table_is_preserved_across_re_analysis_and_never_doubled() throws {
        let beats = Encode.beat_grid_of([(UInt16(1), UInt16(12800), UInt32(0))])
        let columns = ramp(600)
        var previous = try parse(author("/Music/track.mp3", beats, columns, Existing()).dat)
        let at = try #require(previous.sections.firstIndex { $0.tag == Tag("PVBR") })
        previous.sections[at].payload = previous.sections[at].payload.indices.map { UInt8($0 % 251) }
        let real_table = try #require(previous.section("PVBR"))
        previous.sections.append(.new("PVDI", [UInt8](repeating: 0, count: 8), [7, 7, 7]))
        let again = author("/Music/track.mp3", beats, columns, Existing(dat: previous))
        let reread = try parse(again.dat)
        #expect(reread.sections.filter { $0.tag == Tag("PVBR") }.count == 1)
        #expect(reread.section("PVBR") == real_table)
        #expect(reread.section("PVDI") != nil)
    }
    @Test("authored_files_parse_and_carry_what_they_cannot_write")
    func authored_files_parse_and_carry_what_they_cannot_write() throws {
        let records: [(UInt16, UInt16, UInt32)] = [(1, 12800, 0), (2, 12800, 469), (3, 12800, 938), (4, 12800, 1406)]
        let beats = Encode.beat_grid_of(records)
        let columns = ramp(600)
        let fresh = author("/Music/track.mp3", beats, columns, Existing())
        let dat = try parse(fresh.dat)
        #expect(dat.path() == "/Music/track.mp3")
        #expect(dat.sections.prefix(3).map(\.tag) == [Tag("PPTH"), Tag("PVBR"), Tag("PQTZ")])
        let pvbr = try #require(dat.section("PVBR"))
        #expect(pvbr.len_header() == 16)
        #expect(pvbr.len_tag() == 1620)
        #expect((pvbr.header + pvbr.payload).allSatisfy { $0 == 0 })
        #expect(dat.beat_grid() == beats)
        #expect(try #require(dat.waveform("PWAV")).1.count == 400)
        #expect(dat.sections.filter { $0.is_cue_list() }.count == 2)
        let ext = try parse(fresh.ext)
        let two = try parse(fresh.two_ex)
        #expect(ext.waveform("PWV5")?.0 == 2)
        #expect(ext.waveform("PWV5")?.1 == Encode.pwv5(columns))
        #expect(ext.waveform("PWV4")?.0 == 6)
        #expect(two.waveform("PWV7")?.0 == 3)
        #expect(two.waveform("PWV7")?.1 == Encode.pwv7(columns))
        var previous = ext
        previous.header_extra = [UInt8](repeating: 9, count: 16)
        previous.sections.append(.new("PSSI", [UInt8](repeating: 0, count: 8), [1, 2, 3]))
        previous.sections.append(.new("PQT2", [UInt8](repeating: 0, count: 32), [UInt8](repeating: 0, count: 8)))
        let again = author("/Music/track.mp3", beats, columns, Existing(ext: previous))
        let reread = try parse(again.ext)
        #expect(reread.section("PSSI") != nil)
        #expect(!reread.has_extended_grid())
        #expect(reread.header_extra == [UInt8](repeating: 9, count: 16))
        #expect(reread.sections.filter { $0.tag == Tag("PWV3") }.count == 1)
    }
    @Test("the_share_tree_path_is_the_file_name_after_a_question_mark")
    func the_share_tree_path_is_the_file_name_after_a_question_mark() {
        #expect(share_tree_ppth("/Users/dj/Music/99 funkytown.mp3") == "?/99 funkytown.mp3")
        #expect(share_tree_ppth("C:/Users/dj/Music/Breaks1.wav") == "?/Breaks1.wav")
        #expect(share_tree_ppth("C:\\Users\\dj\\Music\\House3.wav") == "?/House3.wav")
        #expect(share_tree_ppth("track.flac") == "?/track.flac")
    }
    @Test("fresh_files_have_rekordboxs_share_tree_layout_and_headers")
    func fresh_files_have_rekordboxs_share_tree_layout_and_headers() throws {
        let records: [(UInt16, UInt16, UInt32)] = [(1, 12800, 0), (2, 12800, 469)]
        let fresh = author("?/track.wav", Encode.beat_grid_of(records), ramp(600), Existing())
        #expect(try tags(fresh.dat) == ["PPTH", "PVBR", "PQTZ", "PWAV", "PWV2", "PCOB", "PCOB"])
        #expect(try tags(fresh.ext) == ["PPTH", "PWV3", "PCOB", "PCOB", "PCO2", "PCO2", "PWV5", "PWV4"])
        #expect(try tags(fresh.two_ex) == ["PPTH", "PWV7", "PWV6"])
        for file in [fresh.dat, fresh.ext] {
            #expect(try header_hex(file, "PCOB", 0) == "0000000100000000ffffffff")
            #expect(try header_hex(file, "PCOB", 1) == "0000000000000000ffffffff")
        }
        #expect(try header_hex(fresh.ext, "PCO2", 0) == "0000000100000000")
        #expect(try header_hex(fresh.ext, "PCO2", 1) == "0000000000000000")
        #expect(try parse(fresh.ext).path() == "?/track.wav")
    }
    @Test("re_analysis_repairs_the_old_shape_and_keeps_rekordboxs_sections")
    func re_analysis_repairs_the_old_shape_and_keeps_rekordboxs_sections() throws {
        let beats = Encode.beat_grid_of([(UInt16(1), UInt16(12800), UInt32(0))])
        let columns = ramp(600)
        let old_ext = try parse(
            AnlzBuilder().path("/Music/track.wav").waveform_scroll("PWV3", 1, [0, 0, 0, 0]).waveform_scroll(
                "PWV4", 6, [0, 0, 0, 0, 0, 0]
            ).waveform_scroll("PWV5", 2, [0, 0]).empty_cue_list_of(true, 0).empty_cue_list_of(true, 1).finish())
        let old_dat = try parse(
            AnlzBuilder().path("/Music/track.wav").vbr_table_zero().beat_grid(beats).empty_cue_list_of(false, 0)
                .empty_cue_list_of(false, 1).finish())
        let again = author("?/track.wav", beats, columns, Existing(dat: old_dat, ext: old_ext))
        #expect(again == author("?/track.wav", beats, columns, Existing()))
        var rb_ext = try parse(again.ext)
        var rb_two = try parse(again.two_ex)
        rb_ext.sections.append(.new("PSSI", [UInt8](repeating: 0, count: 20), [1, 2, 3]))
        rb_two.sections.append(.new("PWVC", [0, 0], [0, 0x50, 0, 0xd7, 1, 0xf4]))
        rb_two.sections.append(.new("PVDI", [UInt8](repeating: 0, count: 12), [7]))
        let kept = author("?/track.wav", beats, columns, Existing(ext: rb_ext, two_ex: rb_two))
        #expect(try tags(kept.ext) == ["PPTH", "PWV3", "PCOB", "PCOB", "PCO2", "PCO2", "PWV5", "PWV4", "PSSI"])
        #expect(try tags(kept.two_ex) == ["PPTH", "PWV7", "PWV6", "PWVC", "PVDI"])
        var cued = try parse(again.dat)
        let at = try #require(cued.sections.firstIndex { $0.tag == Tag("PCOB") })
        cued.sections[at].payload = [80, 67, 80, 84, 0, 0, 0, 0x1c]
        let carried = author("?/track.wav", beats, columns, Existing(dat: cued))
        let lists = try parse(carried.dat).sections.filter { $0.tag == Tag("PCOB") }
        #expect(lists.count == 2)
        #expect(lists[0].payload == [80, 67, 80, 84, 0, 0, 0, 0x1c])
    }
}
