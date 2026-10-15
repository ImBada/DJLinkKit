// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbl-index/src/view.rs inline 시험.
import Testing

@testable import DJLinkExportModel

@Suite struct ViewSourceTests {
    @Test("parallel_indexes_match_serial_indexes_including_ties") func indexes() {
        let tracks: [TestTrack] = (0..<5000).map { (i: Int) -> TestTrack in
            TestTrack(
                id: UInt64(i), title: i % 2 == 0 ? "Écho" : "echo", artist: i % 3 == 0 ? "A" : "B",
                bpm_x100: 12000 + UInt32(i % 11), key: i % 5 == 0 ? "F#" : "F")
        }
        let lib = library_from(tracks)
        let ranks = lib.ranks
        let search = lib.search
        lib.build_indexes()
        #expect(lib.ranks == ranks)
        for row in 0..<tracks.count { #expect(lib.search.get(row) == search.get(row)) }
    }
}
