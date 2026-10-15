// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/src/phrase.rs의 edit_tests
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportANLZ

@Suite("phrase::edit_tests") struct PhraseSourceTests {
    private func pssi(_ masked: Bool) -> Section {
        var body = testBE(UInt16(2)) + [UInt8](repeating: 0, count: 6) + testBE(UInt16(64)) + [0, 0, 0, 0]
        let entries: [(UInt16, UInt16, UInt16)] = [(1, 1, 1), (2, 17, 2), (3, 33, 3)]
        for (index, beat, kind) in entries {
            var entry = [UInt8](repeating: 0, count: 24)
            testPut(&entry, 0, index)
            testPut(&entry, 2, beat)
            testPut(&entry, 4, kind)
            testPut(&entry, 0x0c, beat + 4)
            body += entry
        }
        if masked { phrase_unmask(&body, 3) }
        let raw = testBE(UInt32(24)) + testBE(UInt16(3)) + body
        return .new("PSSI", Array(raw.prefix(20)), Array(raw.dropFirst(20)))
    }
    private func beats(_ section: Section) throws -> [[UInt16]] {
        try #require(section.as_song_structure()).phrases.map { [$0.index, $0.beat, $0.kind] }
    }
    @Test("a_cut_splits_the_phrase_under_the_beat_and_a_clear_takes_it_out")
    func a_cut_splits_the_phrase_under_the_beat_and_a_clear_takes_it_out() throws {
        let original = pssi(false)
        #expect(try beats(original) == [[1, 1, 1], [2, 17, 2], [3, 33, 3]])
        let cut = try #require(original.with_phrase_edit(.cut(beat: 25)))
        #expect(try beats(cut) == [[1, 1, 1], [2, 17, 2], [3, 25, 2], [4, 33, 3]])
        #expect(cut.header.count == 20)
        let raw = cut.header + cut.payload
        #expect(Array(raw[(20 + 2 * 24 + 0x0c)..<(20 + 2 * 24 + 0x0e)]) == testBE(UInt16(21)))
        #expect(original.with_phrase_edit(.cut(beat: 17)) == nil)
        #expect(original.with_phrase_edit(.cut(beat: 0)) == nil)
        let cleared = try #require(original.with_phrase_edit(.clear(beat: 20)))
        #expect(try beats(cleared) == [[1, 1, 1], [2, 33, 3]])
        let structure = try #require(cleared.as_song_structure())
        #expect(structure.mood == .mid)
        #expect(structure.end_beat == 64)
        let edited = try #require(pssi(true).with_phrase_edit(.cut(beat: 25)))
        #expect(try beats(edited) == beats(cut))
        #expect(anlzBE16(edited.header + edited.payload, 6) == 2)
        #expect(Section.new("PQTZ", [], []).with_phrase_edit(.clear(beat: 1)) == nil)
    }
}
