// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-anlz/src/grid.rs의 tests
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportANLZ

@Suite("grid::tests") struct GridTests {
    private func grid() -> [Beat] {
        (0..<9).map { Beat(beat_number: UInt16($0 % 4 + 1), tempo_x100: 12000, time_ms: UInt32($0) * 500) }
    }
    private func times(_ beats: [Beat]) -> [UInt32] { beats.map(\.time_ms) }
    @Test("recovered_stretch_uses_target_distance_and_even_rounding")
    func recovered_stretch_uses_target_distance_and_even_rounding() {
        let out = Grid.apply_with_duration(grid(), nil, .stretch(by_ms: 1, time_ms: 1000), 4000)
        #expect(Array(times(out).prefix(5)) == [0, 500, 1001, 1502, 2002])
        #expect(Grid.tempo_x100(out) == 11988)
    }
    @Test("downbeat_aligns_and_renumbers") func downbeat_aligns_and_renumbers() {
        let out = Grid.apply_with_duration(grid(), nil, .downbeat(time_ms: 1600), 4000)
        #expect(times(out) == [100, 600, 1100, 1600, 2100, 2600, 3100, 3600])
        #expect(out.first { $0.time_ms == 1600 }?.beat_number == 1)
    }
    @Test("double_includes_final_midpoint") func double_includes_final_midpoint() {
        #expect(times(Grid.apply_with_duration(grid(), nil, .double, 4250)) == (0..<18).map { UInt32($0) * 250 })
    }
    @Test("halve_obeys_original_bar_phase") func halve_obeys_original_bar_phase() {
        let beats = grid().map { b in
            var next = b
            next.beat_number = b.beat_number % 4 + 1
            return next
        }
        let out = Grid.apply_with_duration(beats, nil, .halve, 4000)
        #expect(times(out) == [500, 1500, 2500, 3500])
        #expect(out.first?.beat_number == 4)
    }
    @Test("typed_tempo_anchors_the_scope_start") func typed_tempo_anchors_the_scope_start() {
        #expect(
            times(Grid.apply_with_duration(grid(), 2000, .tempo(bpm_x100: 10000, anchor_ms: 999), 4000)) == [
                0, 500, 1000, 1500, 2000, 2600, 3200, 3800,
            ])
    }
    @Test("singleton_normalizes_using_its_distance_from_zero") func singleton_normalizes_using_its_distance_from_zero()
    {
        let beat = Beat(beat_number: 1, tempo_x100: 12000, time_ms: 500)
        #expect(times(Grid.apply_with_duration([beat], nil, .nudge(0), 2000)) == [500, 1000, 1500, 2000])
    }
    @Test("nearest_ties_choose_the_earlier_beat") func nearest_ties_choose_the_earlier_beat() {
        #expect(Grid.nearest_index(grid(), 750) == 1)
    }
    @Test("invalid_tempo_is_rejected_without_clamping") func invalid_tempo_is_rejected_without_clamping() {
        #expect(throws: (any Error).self) { try Grid.validate(grid(), nil, .tempo(bpm_x100: 3999, anchor_ms: 0)) }
        let fast = grid().map { b in
            var next = b
            next.tempo_x100 = 25000
            return next
        }
        #expect(throws: (any Error).self) { try Grid.validate(fast, nil, .double) }
        #expect(Grid.apply([], .double) == [])
    }
}
