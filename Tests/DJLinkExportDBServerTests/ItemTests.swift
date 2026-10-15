// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-dbserver/src/item.rs inline tests @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportDBServer

@Suite struct ItemTests {
    @Test("track_columns_use_rekordbox_composite_types") func track_columns_use_rekordbox_composite_types() {
        let columns: [(TrackColumn, UInt32)] = [
            (.title, 0x0004), (.album, 0x0204), (.genre, 0x0604), (.artist, 0x0704), (.rating, 0x0a04),
            (.duration, 0x0b04), (.bpm, 0x0d04), (.label, 0x0e04), (.key, 0x0f04), (.bitrate, 0x1004), (.color, 0x1a04),
            (.comment, 0x2304), (.originalArtist, 0x2804), (.remixer, 0x2904), (.djPlayCount, 0x2a04),
            (.dateAdded, 0x2e04),
        ]
        for (column, expected) in columns { #expect(track_item_type(column, column == .color ? 7 : 0) == expected) }
    }
    @Test("every_track_column_carries_the_raw_database_key_id")
    func every_track_column_carries_the_raw_database_key_id() {
        var row = TrackRow(
            id: 42, title: "Track", secondary_text: "3A - 112.2 bpm", column: .key, column_value: 3_441_880_869, key: 5,
            key_id: 3_441_880_869, key_name: "Ebm", bpm_x100: 11_220)
        var item = Item.track(row, 0, 0)
        #expect(item.a == 3_441_880_869)
        #expect(item.art == 3_441_880_869)
        #expect(item.item_type == 0x0f04)
        #expect(item.text2 == "3A - 112.2 bpm")
        row.column = .comment
        row.column_value = row.id
        row.secondary_text = "note"
        item = Item.track(row, 0, 0)
        #expect(item.a == row.id)
        #expect(item.art == 3_441_880_869)
        #expect(item.item_type == 0x2304)
        row.column = .dateAdded
        row.secondary_text = "2026-10-02"
        item = Item.track(row, 0, 0)
        #expect(item.a == row.id)
        #expect(item.item_type == 0x2e04)
    }
    @Test("rx3_key_and_bpm_sorts_use_opposite_composite_order")
    func rx3_key_and_bpm_sorts_use_opposite_composite_order() {
        var row = TrackRow(
            id: 42, title: "Track", secondary_text: "", column: .bpm, column_value: 13_000, key: 5, key_id: 5001,
            key_name: "3A", bpm_x100: 13_000)
        row.format_sort_column()
        #expect(row.secondary_text == "130.0 bpm - 3A")
        row.column = .key
        row.format_sort_column()
        #expect(row.secondary_text == "3A - 130.0 bpm")
    }
}
