// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/tests/grid_save.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportANLZ

@Suite("grid_save") struct GridSaveTests {
    private func fixture() throws -> (Anlz, [Beat]) {
        let beats = [
            Beat(beat_number: 1, tempo_x100: 12000, time_ms: 0), Beat(beat_number: 2, tempo_x100: 12000, time_ms: 500),
        ]
        var header = [UInt8](repeating: 0, count: 44)
        let words: [(Int, UInt32)] = [
            (4, 0x01000002), (12, (1 << 16) | 0x2ee0), (16, 0), (20, (2 << 16) | 0x2ee0), (24, 500), (28, 2),
            (32, 24503),
        ]
        for (at, value) in words { testPut(&header, at, value) }
        return (try parse(AnlzBuilder().raw(Tag("PQT2"), header, [0x12, 0x34, 0x56, 0x78]).finish()), beats)
    }
    @Test("renumbering_preserves_payload_and_updates_checksum")
    func renumbering_preserves_payload_and_updates_checksum() throws {
        let (file, old) = try fixture()
        var new = old
        new[0].beat_number = 4
        new[1].beat_number = 1
        let saved = try parse(#require(file.with_extended_grid_edit(old, new, 0)))
        let section = try #require(saved.section("PQT2"))
        #expect(section.payload == [0x12, 0x34, 0x56, 0x78])
        #expect(Array(section.header[32..<36]) == testBE(UInt32(24505)))
        #expect(Array(section.header[12..<16]) == testBE((UInt32(4) << 16) | 0x2ee0))
    }
    @Test("retiming_or_an_invalid_old_checksum_clears_payload")
    func retiming_or_an_invalid_old_checksum_clears_payload() throws {
        let (file, old) = try fixture()
        var new = old
        new[1].time_ms += 1
        let saved = try parse(#require(file.with_extended_grid_edit(old, new, 0)))
        #expect(try #require(saved.section("PQT2")).payload == [])
        var bad = file
        bad.sections[0].header[32] = 1
        let badSaved = try parse(#require(bad.with_extended_grid_edit(old, old, 0)))
        #expect(try #require(badSaved.section("PQT2")).payload == [])
    }
}
