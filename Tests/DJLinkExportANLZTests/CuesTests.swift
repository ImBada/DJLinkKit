// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/src/cues.rs의 tests
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation
import Testing

@testable import DJLinkExportANLZ

@Suite("cues::tests") struct CuesTests {
    @Test("matches_a_rekordbox_hot_cue_record_and_complete_palette")
    func matches_a_rekordbox_hot_cue_record_and_complete_palette() {
        let cue = ExportCue(kind: 1, time_ms: 83032, color_code: 46)
        let entry = Cues.sections([cue], true)[2].payload
        let expected =
            "50435032000000100000005800000001010003e800014458ffffffff000100000000000000000000000000002eff005c00000000000000000000000000000000000000000000000000000000000000000000000000000000"
        #expect(entry.map { String(format: "%02x", $0) }.joined() == expected)
        for (code, rgb) in MEASURED_CUE_COLOURS.dropFirst() { #expect(Cues.export_colour(code, 1) == rgb) }
        #expect(Cues.export_colour(0, 1) == [255, 0, 23])
        #expect(Cues.export_colour(62, 1) == [26, 0, 255])
    }
    @Test("exports_memory_loop_comments_colors_and_the_d_slot")
    func exports_memory_loop_comments_colors_and_the_d_slot() throws {
        let cues = [
            ExportCue(kind: 5, time_ms: 1000, color_code: 8, comment: "Drop 🎵"),
            ExportCue(
                time_ms: 2000, loop_time_ms: 4000, comment: "Loop", active_loop: true, loop_numerator: 4,
                loop_denominator: 1),
        ]
        let dat = Cues.sections(cues, false)
        #expect(dat[0].payload == [])
        #expect(Array(dat[1].payload[16..<20]) == testBE(UInt32(4)))
        let ext = Cues.sections(cues, true)
        let decoded = try #require(ext[2].as_cue_entries())
        #expect(decoded[0].hot_cue == 4)
        #expect(decoded[0].comment == "Drop 🎵")
        #expect(decoded[0].rgb == [0, 196, 255])
        let memory = try #require(ext[3].as_cue_entries())
        #expect(memory[0].kind == 2)
        #expect(memory[0].time_ms == 2000)
        #expect(memory[0].loop_time_ms == 4000)
        #expect(Array(ext[3].payload[36..<40]) == [0, 4, 0, 1])
    }
}
