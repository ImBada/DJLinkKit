// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
import DJLinkExportModel
// 원본: rbl-index/tests/categories.rs.
import Testing

@Suite struct CategoriesTests {
    func track(
        _ id: UInt64, _ path: String, _ bpm: UInt32, _ duration: UInt32, _ rating: UInt8, _ color: UInt8, _ year: UInt16
    ) -> TestTrack {
        TestTrack(id: id, bpm_x100: bpm, length_sec: duration, rating: rating, color: color, path: path, year: year)
    }
    @Test("bpm_uses_half_up_buckets_and_raw_percentage_ranges") func bpm() {
        let lib = library_from([
            track(1, "z.mp3", 12749, 0, 0, 0, 0), track(2, "a.mp3", 12750, 0, 0, 0, 0),
            track(3, "b.mp3", 13050, 0, 0, 0, 0), track(4, "c.mp3", 0, 0, 0, 0, 0),
            track(5, "d.mp3", 50000, 0, 0, 0, 0),
        ])
        #expect(lib.bpm_buckets() == [12700, 12800, 13100])
        #expect(lib.bpm_matches(1, 12800, 0))
        #expect(!lib.bpm_matches(0, 12800, 0))
        #expect(lib.bpm_matches(0, 12800, 1))
        #expect(!lib.bpm_matches(2, 12800, 1))
        #expect(!lib.bpm_matches(4, 50000, 0))
    }
    @Test("scalar_categories_have_captured_order_and_boundaries") func scalar() {
        let lib = library_from([
            track(1, "z.mp3", 0, 59, 1, 1, 2024), track(2, "A.mp3", 0, 60, 5, 8, 2020),
            track(3, "a.mp3", 0, 10799, 1, 0, 1999), track(4, "x.mp3", 0, 10800, 0, 9, 0),
            track(5, "y.mp3", 0, 120, 0, 0, 3000),
        ])
        lib.bitrate.replaceSubrange(0..<5, with: [320, 0, 128, 320, 0])
        #expect(lib.bitrates() == [320, 128, 0])
        #expect(lib.bitrate_matches(1, 0))
        #expect(lib.ratings() == [5, 1, 0])
        #expect(lib.rating_matches(2, 1))
        #expect(lib.color_ids() == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(lib.color_matches(1, 8))
        #expect(!lib.color_matches(2, 0))
        #expect(lib.duration_minute_buckets() == [179, 2, 1, 0])
        #expect(lib.duration_minute_matches(1, 1))
        #expect(!lib.duration_minute_matches(3, 180))
        #expect(lib.release_decades() == [2020, 1990])
        #expect(lib.release_years(2020) == [2024, 2020])
        #expect(lib.release_year_matches(0, 2024))
        #expect(!lib.release_year_matches(4, 3000))
        #expect(lib.filename_rows() == [1, 2, 3, 4, 0])
    }
}
