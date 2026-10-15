// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbl-index/src/related.rs inline 시험.
import Testing

@testable import DJLinkExportModel

@Suite struct RelatedTests {
    @Test("a_key_goes_with_itself_its_relative_and_its_neighbours") func keys() {
        let a1 = camelot_rank("Abm")
        let b1 = camelot_rank("B")
        let a2 = camelot_rank("Ebm")
        let a12 = camelot_rank("Dbm")
        let a3 = camelot_rank("Bbm")
        #expect(keys_go_together(a1, a1))
        #expect(keys_go_together(a1, b1))
        #expect(keys_go_together(a1, a2))
        #expect(keys_go_together(a1, a12))
        #expect(!keys_go_together(a1, a3))
        #expect(!keys_go_together(a1, camelot_rank("F#")))
        #expect(!keys_go_together(UInt32.max, a1))
    }
    @Test("the_bpm_window_is_five_percent_either_side_rounded_ties_to_even") func window() {
        for (bpm, pct, low, high)
            in ([(12800, 5, 12160, 13440), (12810, 5, 12170, 13450), (12800, 0, 12800, 12800), (0, 5, 0, 0)]
            as [(UInt32, UInt32, UInt32, UInt32)])
        {
            let value = bpm_window(bpm, pct)
            #expect(value.0 == low && value.1 == high)
        }
    }
    @Test("a_bpm_matches_inside_the_window_at_its_own_half_or_double_tempo") func bpm() {
        for (centre, theirs, half, expected)
            in ([
                (12800, 12160, true, true), (12800, 13440, true, true), (12800, 12159, true, false),
                (12800, 13441, true, false), (17000, 8500, true, true), (17000, 8075, true, true),
                (17000, 8074, true, false), (17000, 34000, true, true), (17000, 35700, true, true),
                (17000, 35701, true, false), (17000, 8500, false, false), (17000, 34000, false, false),
                (12801, 6080, true, true), (12800, 0, true, false),
            ] as [(UInt32, UInt32, Bool, Bool)])
        { #expect(related_bpm_matches(centre, theirs, 5, half) == expected) }
    }
    func track(_ id: UInt64, _ bpm: UInt32, _ key: String) -> TestTrack {
        TestTrack(id: id, title: "t", artist: "a", bpm_x100: bpm, key: key)
    }
    @Test("bpm_and_key_takes_half_and_double_tempo_tracks_in_a_related_key") func related() {
        let lib = library_from([
            track(1, 17400, "Am"), track(2, 8700, "Am"), track(3, 34800, "C"), track(4, 17400, "Em"),
            track(5, 8700, "F#"), track(6, 12800, "Am"), track(7, 18270, "Dm"), track(8, 18271, "Am"),
        ])
        #expect(lib.related_rows(0, .bpmAndKey) == [1, 2, 3, 6])
    }
    @Test("a_suggestion_is_what_followed_the_track_in_past_sets_or_its_bpm_and_key_matches") func suggestion() {
        let lib = library_from([
            track(1, 12800, "Am"), track(2, 12800, "Am"), track(3, 12800, "Em"), track(4, 17000, "C"),
            track(5, 12800, "Am"),
        ])
        add_history(lib, "one", [0, 3, 4])
        add_history(lib, "two", [2, 0, 1])
        add_history(lib, "three", [0, 3])
        #expect(lib.related_rows(0, .suggestion) == [3, 1])
        let fallback = lib.related_rows(1, .suggestion)
        #expect(fallback == lib.related_rows(1, .bpmAndKey))
        #expect(fallback == [0, 2, 4])
    }
}
