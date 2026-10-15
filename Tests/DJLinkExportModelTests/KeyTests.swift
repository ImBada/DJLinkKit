// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbl-index/src/key.rs inline 시험.
import Testing

@testable import DJLinkExportModel

@Suite struct KeyTests {
    @Test("the_wheel_goes_round_from_1a") func wheel() {
        #expect(camelot_rank("Abm") == 0)
        #expect(camelot_rank("B") == 1)
        #expect(camelot_rank("Ebm") == 2)
        #expect(camelot_rank("E") == 23)
        #expect(camelot_rank("G#m") == camelot_rank("Abm"))
        #expect(camelot_rank("8A") == camelot_rank("Am"))
        #expect(camelot_rank("") == UInt32.max)
        #expect(camelot_rank("Unknown") == UInt32.max)
    }
    @Test("the_names_keep_their_sharps_apart") func names() {
        var keys = ["Fm", "F#m", "F", "F#", "", "Ab", "A", "am"]
        keys.sort { cmp_names($0, $1) == .less }
        #expect(keys == ["A", "Ab", "am", "F", "F#", "F#m", "Fm", ""])
    }
}
