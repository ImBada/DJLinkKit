// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/tests/phrase.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportANLZ

private let maskBase: [UInt8] = [
    0xcb, 0xe1, 0xee, 0xfa, 0xe5, 0xee, 0xad, 0xee, 0xe9, 0xd2, 0xe9, 0xeb, 0xe1, 0xe9, 0xf3, 0xe8, 0xe9, 0xf4, 0xe1,
]
private func entry(
    _ index: UInt16, _ beat: UInt16, _ kind: UInt16, _ k1: UInt8, _ k2: UInt8, _ k3: UInt8, _ fill: UInt16?
) -> [UInt8] {
    var e = [UInt8](repeating: 0, count: 24)
    testPut(&e, 0, index)
    testPut(&e, 2, beat)
    testPut(&e, 4, kind)
    e[7] = k1
    e[9] = k2
    e[0x13] = k3
    if let fill {
        e[0x15] = 1
        testPut(&e, 0x16, fill)
    }
    return e
}
private func body(_ mood: UInt16, _ end: UInt16, _ bank: UInt8, _ entries: [[UInt8]]) -> [UInt8] {
    var b = [UInt8](repeating: 0, count: 14)
    testPut(&b, 0, mood)
    testPut(&b, 8, end)
    b[0x0c] = bank
    return b + entries.flatMap { $0 }
}
private func mask(_ body: inout [UInt8], _ count: UInt16) {
    for at in body.indices { body[at] ^= maskBase[at % 19] &+ UInt8(truncatingIfNeeded: count) }
}
private func pssi_local(_ mood: UInt16, _ end: UInt16, _ bank: UInt8, _ entries: [[UInt8]], _ masked: Bool) -> [UInt8] {
    let count = UInt16(truncatingIfNeeded: entries.count)
    var b = body(mood, end, bank, entries)
    if masked { mask(&b, count) }
    let all = testBE(UInt32(24)) + testBE(count) + b
    return AnlzBuilder().raw(Tag("PSSI"), Array(all.prefix(20)), Array(all.dropFirst(20))).finish()
}
private func pssi_exported(_ mood: UInt16, _ entries: [[UInt8]], _ masked: Bool) -> [UInt8] {
    let count = UInt16(truncatingIfNeeded: entries.count)
    var b = body(mood, 0, 0, entries)
    if masked { mask(&b, count) }
    return AnlzBuilder().raw(Tag("PSSI"), testBE(UInt32(24)) + testBE(count), b).finish()
}
private func labels(_ bytes: [UInt8]) throws -> [String] { try #require(parse(bytes).phrases()).map(\.label) }
private func pvdi(_ declared: UInt32, _ payload: [UInt8]) -> [UInt8] {
    AnlzBuilder().raw(Tag("PVDI"), testBE(UInt32(1024)) + testBE(UInt32(0x56220001)) + testBE(declared), payload)
        .finish()
}
@Suite("phrase") struct PhraseTests {
    @Test("reads_an_unmasked_song_structure") func reads_an_unmasked_song_structure() throws {
        let entries = [entry(1, 1, 1, 0, 0, 0, nil), entry(2, 65, 5, 1, 0, 0, nil), entry(3, 129, 3, 0, 0, 0, nil)]
        let s = try #require(parse(pssi_local(1, 721, 0, entries, false)).song_structure())
        #expect(s.mood == .high)
        #expect(s.end_beat == 721)
        #expect(s.bank == 0)
        #expect(s.phrases.count == 3)
        #expect(s.phrases[1].index == 2)
        #expect(s.phrases[1].beat == 65)
        #expect(s.phrases[1].kind == 5)
        #expect(s.phrases[2].label == "DOWN")
    }
    @Test("unmasks_a_masked_song_structure_to_the_same_phrases")
    func unmasks_a_masked_song_structure_to_the_same_phrases() throws {
        let e = [entry(1, 1, 1, 0, 0, 0, nil), entry(2, 65, 5, 1, 0, 0, nil), entry(3, 129, 2, 0, 1, 0, nil)]
        let plain = try parse(pssi_local(1, 400, 3, e, false))
        let masked = try parse(pssi_local(1, 400, 3, e, true))
        #expect(masked.song_structure() == plain.song_structure())
        #expect(try labels(pssi_local(1, 400, 3, e, true)) == ["INTRO 2", "CHORUS 1", "UP 3"])
    }
    @Test("a_masked_tag_is_not_mistaken_for_a_plain_one") func a_masked_tag_is_not_mistaken_for_a_plain_one() throws {
        let e = (0..<53).map { entry(UInt16($0 + 1), UInt16($0 * 16), 9, 0, 0, 0, nil) }
        let s = try #require(parse(pssi_local(2, 900, 0, e, true)).song_structure())
        #expect(s.mood == .mid)
        #expect(s.phrases.count == 53)
        #expect(s.phrases.allSatisfy { $0.label == "CHORUS" })
    }
    @Test("reads_the_exported_header_split_as_well_as_the_local_one")
    func reads_the_exported_header_split_as_well_as_the_local_one() throws {
        let e = [entry(1, 1, 1, 1, 0, 0, nil), entry(2, 33, 6, 0, 0, 0, nil)]
        #expect(try labels(pssi_exported(1, e, true)) == ["INTRO 1", "OUTRO 2"])
        #expect(try labels(pssi_exported(1, e, false)) == ["INTRO 1", "OUTRO 2"])
    }
    @Test("high_mood_labels_come_from_the_flag_bytes_not_the_kind")
    func high_mood_labels_come_from_the_flag_bytes_not_the_kind() throws {
        let e = [
            entry(1, 0, 1, 1, 0, 0, nil), entry(2, 0, 1, 0, 0, 0, nil), entry(3, 0, 2, 0, 0, 0, nil),
            entry(4, 0, 2, 0, 0, 1, nil), entry(5, 0, 2, 0, 1, 0, nil), entry(6, 0, 3, 0, 0, 0, nil),
            entry(7, 0, 5, 1, 0, 0, nil), entry(8, 0, 5, 0, 0, 0, nil), entry(9, 0, 6, 1, 0, 0, nil),
            entry(10, 0, 6, 0, 0, 0, nil),
        ]
        #expect(
            try labels(pssi_local(1, 0, 0, e, false)) == [
                "INTRO 1", "INTRO 2", "UP 1", "UP 2", "UP 3", "DOWN", "CHORUS 1", "CHORUS 2", "OUTRO 1", "OUTRO 2",
            ])
    }
    @Test("the_same_kind_means_different_things_in_each_mood") func the_same_kind_means_different_things_in_each_mood()
        throws
    {
        let e = [entry(1, 0, 5, 1, 0, 0, nil)]
        #expect(try labels(pssi_local(1, 0, 0, e, false)) == ["CHORUS 1"])
        #expect(try labels(pssi_local(2, 0, 0, e, false)) == ["VERSE 4"])
        #expect(try labels(pssi_local(3, 0, 0, e, false)) == ["VERSE 2"])
    }
    @Test("the_low_moods_three_ids_for_a_verse_collapse_to_one_label")
    func the_low_moods_three_ids_for_a_verse_collapse_to_one_label() throws {
        let e = (UInt16(2)...7).map { entry($0, 0, $0, 0, 0, 0, nil) }
        #expect(
            try labels(pssi_local(3, 0, 0, e, false)) == [
                "VERSE 1", "VERSE 1", "VERSE 1", "VERSE 2", "VERSE 2", "VERSE 2",
            ])
    }
    @Test("an_unknown_kind_gets_no_label_rather_than_an_invented_one")
    func an_unknown_kind_gets_no_label_rather_than_an_invented_one() throws {
        let e = [entry(1, 8, 4, 0, 0, 0, nil), entry(2, 16, 99, 0, 0, 0, nil)]
        #expect(try labels(pssi_local(1, 0, 0, e, false)) == ["", ""])
    }
    @Test("reads_a_fill_in") func reads_a_fill_in() throws {
        let e = [entry(1, 545, 2, 0, 0, 0, 575), entry(2, 577, 5, 1, 0, 0, nil)]
        let p = try #require(parse(pssi_local(1, 0, 0, e, false)).phrases())
        #expect(p[0].fill_in)
        #expect(p[0].fill_in_beat == 575)
        #expect(!p[1].fill_in)
        #expect(p[1].fill_in_beat == 0)
    }
    @Test("a_count_the_payload_cannot_back_yields_the_phrases_that_are_there")
    func a_count_the_payload_cannot_back_yields_the_phrases_that_are_there() throws {
        let e = [entry(1, 1, 1, 1, 0, 0, nil), entry(2, 33, 3, 0, 0, 0, nil)]
        var bytes = pssi_local(1, 0, 0, e, false)
        let at = try #require((0..<(bytes.count - 3)).first { Array(bytes[$0..<($0 + 4)]) == Array("PSSI".utf8) })
        testPut(&bytes, at + 16, UInt16(10))
        #expect(try labels(bytes) == ["INTRO 1", "DOWN"])
    }
    @Test("a_truncated_or_nonsense_song_structure_returns_none_rather_than_panicking")
    func a_truncated_or_nonsense_song_structure_returns_none_rather_than_panicking() throws {
        let full = pssi_local(1, 0, 0, [entry(1, 1, 1, 0, 0, 0, nil)], false)
        let at = try #require((0..<(full.count - 3)).first { Array(full[$0..<($0 + 4)]) == Array("PSSI".utf8) })
        let tail = Array(full.dropFirst(at + 12))
        for cut in 0..<full.count {
            let take = min(cut, tail.count)
            let header = min(take, 20)
            let bytes = AnlzBuilder().raw(Tag("PSSI"), Array(tail.prefix(header)), Array(tail[header..<take])).finish()
            _ = try parse(bytes).song_structure()
        }
        #expect(
            try parse(
                AnlzBuilder().raw(
                    Tag("PSSI"), testBE(UInt32(24)) + testBE(UInt16(1)), [UInt8](repeating: 0xab, count: 40)
                ).finish()
            ).song_structure() == nil)
        #expect(
            try parse(
                AnlzBuilder().raw(
                    Tag("PSSI"), testBE(UInt32(8)) + testBE(UInt16(2)) + testBE(UInt16(1)),
                    [UInt8](repeating: 0, count: 32)
                ).finish()
            ).song_structure() == nil)
    }
    @Test("a_file_without_a_song_structure_has_no_phrases") func a_file_without_a_song_structure_has_no_phrases() throws
    {
        #expect(
            try parse(AnlzBuilder().path("/Music/one.mp3").waveform_preview("PWAV", [1, 2, 3]).finish()).phrases()
                == nil)
    }
    @Test("reads_the_vocal_strip") func reads_the_vocal_strip() throws {
        let strip: [UInt8] = [0, 0, 1, 2, 3, 4, 4, 4, 3, 1, 0]
        #expect(try parse(pvdi(UInt32(strip.count), strip)).vocals() == strip)
        #expect(strip.allSatisfy { $0 <= VOCAL_MAX })
    }
    @Test("a_vocal_strip_whose_count_disagrees_with_its_payload_is_refused")
    func a_vocal_strip_whose_count_disagrees_with_its_payload_is_refused() throws {
        #expect(try parse(pvdi(50, [0, 1, 2])).vocals() == nil)
        #expect(try parse(pvdi(0, [0, 1, 2])).vocals() == nil)
    }
    @Test("a_truncated_vocal_tag_returns_none_rather_than_panicking")
    func a_truncated_vocal_tag_returns_none_rather_than_panicking() throws {
        for length in 0..<12 {
            #expect(
                try parse(AnlzBuilder().raw(Tag("PVDI"), [UInt8](repeating: 0, count: length), [1, 2, 3]).finish())
                    .vocals() == nil)
        }
        #expect(try parse(AnlzBuilder().path("/Music/one.mp3").finish()).vocals() == nil)
    }
    @Test("one_vocal_entry_covers_the_measured_frame") func one_vocal_entry_covers_the_measured_frame() {
        #expect(abs(VOCAL_FRAME_MS - 46.44) < 0.01)
    }
}
