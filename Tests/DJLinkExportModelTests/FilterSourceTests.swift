// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbl-index/src/filter.rs inline 시험.
import Testing

@testable import DJLinkExportModel

@Suite struct FilterSourceTests {
    @Test("band_is_inclusive_and_symmetric") func bands() {
        for (centre, pct, low, high) in [
            (UInt32(12800), UInt8(0), UInt32(12800), UInt32(12800)), (12800, 2, 12544, 13056), (100, 6, 94, 106),
            (0, 6, 0, 0),
        ] {
            let b = band(centre, pct)
            #expect(b.0 == low && b.1 == high)
        }
    }
    @Test("whole_bpm_rounds_to_nearest") func whole() {
        #expect(whole_bpm(12798) == 128)
        #expect(whole_bpm(12849) == 128)
        #expect(whole_bpm(12850) == 129)
        #expect(whole_bpm(0) == 0)
        #expect(whole_bpm(UInt32.max) == UInt32.max / 100)
    }
    @Test("camelot_order_matches_the_capture") func camelot() {
        var names = ["Cm", "F#", "B", "Ebm", "Abm", "Db", "Fm", "Ab", "Bbm", "zz", "A"]
        names.sort {
            let a = filter_camelot_rank($0)
            let b = filter_camelot_rank($1)
            return a == b ? $0.lowercased() < $1.lowercased() : a < b
        }
        #expect(names == ["Abm", "B", "Ebm", "F#", "Bbm", "Db", "Fm", "Ab", "Cm", "A", "zz"])
        #expect(filter_camelot_rank("G#m") == filter_camelot_rank("Abm"))
    }
}
