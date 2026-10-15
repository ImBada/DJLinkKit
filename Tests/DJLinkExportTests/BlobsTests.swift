// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
import DJLinkExportANLZ
import DJLinkExportModel
import DJLinkExportTestSupport
// 원본: crates/rbl-link/tests/blobs.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExport

@Suite("blobs") struct BlobsTests {
    private func fixture(_ name: String) throws -> [UInt8] {
        try UpstreamFixtures.bytes(crate: "rbl-link", path: "tests/fixtures/" + name)
    }
    private func analysis() throws -> Analysis {
        try Analysis(
            dat: DJLinkExportANLZ.parse(fixture("ANLZ0001.DAT")), ext: DJLinkExportANLZ.parse(fixture("ANLZ0001.EXT")))
    }
    @Test("the_beat_grid_matches_the_capture") func the_beat_grid_matches_the_capture() throws {
        #expect(try #require(analysis().beat_grid()) == fixture("captured-beat-grid.bin"))
    }
    @Test("the_waveform_preview_matches_the_capture") func the_waveform_preview_matches_the_capture() throws {
        #expect(try #require(analysis().waveform_preview()) == fixture("captured-waveform-preview.bin"))
    }
    @Test("the_waveform_detail_matches_the_capture") func the_waveform_detail_matches_the_capture() throws {
        #expect(try #require(analysis().waveform_detail()) == fixture("captured-waveform-detail.bin"))
    }
    @Test("analysis_tags_match_the_capture_including_the_padding")
    func analysis_tags_match_the_capture_including_the_padding() throws {
        let a = try analysis()
        #expect(try #require(a.tag("PWV4", "EXT")) == fixture("captured-tag-PWV4.bin"))
        #expect(try #require(a.tag("PQT2", "EXT")) == fixture("captured-tag-PQT2.bin"))
        #expect(a.tag("PWV6", "2EX") == nil)
        #expect(a.tag("PSSI", "EXT") == nil)
    }
    @Test("the_vbr_compatibility_placeholder_keeps_its_existing_bytes")
    func the_vbr_compatibility_placeholder_keeps_its_existing_bytes() {
        #expect(vbr_compatibility_blob() == [UInt8](repeating: 0, count: 1604))
    }
    @Test("the_extended_cue_list_matches_the_capture") func the_extended_cue_list_matches_the_capture() throws {
        func cue(_ slot: UInt8, _ ms: UInt32) -> ExtendedCue {
            ExtendedCue(position_ms: ms, hot_slot: slot, comment: "CUE(Auto)", colour: slot == 0 ? 0 : 21)
        }
        let cues = [
            cue(0, 2004), cue(0, 467), cue(0, 23521), cue(0, 201803), cue(1, 467), cue(2, 83), cue(3, 23521),
            cue(4, 201803),
        ]
        let (blob, count) = extended_cues_blob(cues)
        #expect(count == 8)
        #expect(try blob == fixture("captured-extended-cues.bin"))
    }
    @Test("an_index_cue_becomes_an_extended_cue_by_its_hot_letter")
    func an_index_cue_becomes_an_extended_cue_by_its_hot_letter() {
        let hot_d = DJLinkExportModel.Cue(id: 1, position_ms: 100, out_ms: 0, kind: 5, colour: 0)
        #expect(ExtendedCue.from(hot_d).hot_slot == 4)
        let memory = DJLinkExportModel.Cue(id: 2, position_ms: 200, out_ms: 900, kind: 0, colour: 0)
        let e = ExtendedCue.from(memory)
        #expect(e.hot_slot == 0)
        #expect(e.out_ms == 900)
        let (blob, _) = extended_cues_blob([e])
        #expect(blob[6] == 2)
        #expect(Array(blob[16..<20]) == [0x84, 3, 0, 0])
    }
    @Test("the_waveform_preview_sends_pwv2_as_height_alone") func the_waveform_preview_sends_pwv2_as_height_alone() {
        let blob = waveform_preview_blob([0xa3, 0x20], [0x48, 0xef, 0, 0x0f])
        #expect(Array(blob[0..<4]) == [3, 5, 2, 1])
        #expect(Array(blob[4..<8]) == [8, 15, 1, 15])
    }
    private func colour_of(_ blob: [UInt8]) -> [UInt8] {
        let comment = Int(UInt16(blob[0x48]) | UInt16(blob[0x49]) << 8)
        return Array(blob[(0x4e + comment)..<(0x52 + comment)])
    }
    @Test("a_hot_cue_carries_its_own_colour") func a_hot_cue_carries_its_own_colour() {
        func hot(_ kind: UInt8, _ colour: UInt8) -> ExtendedCue {
            .from(DJLinkExportModel.Cue(id: 1, position_ms: 100, out_ms: 0, kind: kind, colour: colour))
        }
        let entries: [(UInt8, UInt8, [UInt8])] = [
            (1, 42, [42, 255, 0, 0]), (2, 9, [9, 0, 224, 255]), (3, 30, [30, 230, 255, 0]), (5, 56, [56, 179, 0, 255]),
        ]
        for (kind, colour, expected) in entries {
            #expect(colour_of(extended_cues_blob([hot(kind, colour)]).0) == expected)
        }
        #expect(colour_of(extended_cues_blob([hot(1, 0)]).0) == [0, 255, 0, 23])
        #expect(colour_of(extended_cues_blob([hot(1, 65)]).0) == [0, 255, 0, 23])
    }
    @Test("a_memory_cue_carries_no_colour") func a_memory_cue_carries_no_colour() {
        let memory = ExtendedCue.from(DJLinkExportModel.Cue(id: 2, position_ms: 200, out_ms: 0, kind: 0, colour: 42))
        #expect(colour_of(extended_cues_blob([memory]).0) == [0, 0, 0, 0])
    }
}
