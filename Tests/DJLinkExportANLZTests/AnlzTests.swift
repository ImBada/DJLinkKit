// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/src/lib.rs의 grid_offset_tests
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportANLZ

@Suite("grid_offset_tests") struct AnlzTests {
    @Test("offset_edits_preserve_every_other_byte_and_the_original_beats")
    func offset_edits_preserve_every_other_byte_and_the_original_beats() throws {
        let beats = [Beat(beat_number: 1, tempo_x100: 12800, time_ms: 1000)]
        let original = Anlz(header_extra: [UInt8](repeating: 0, count: 16), sections: [Write.beat_grid_section(beats)])
        let before = original.to_bytes()
        for offset in [Int16(234), -467, .min, .max, 0] {
            let changed = try #require(original.with_grid_offset(offset))
            let parsed = try parse(changed)
            #expect(parsed.grid_offset() == offset)
            #expect(parsed.beat_grid() == beats)
            #expect(parsed.with_grid_offset(0) == before)
        }
        #expect(Anlz().with_grid_offset(1) == nil)
    }
}
