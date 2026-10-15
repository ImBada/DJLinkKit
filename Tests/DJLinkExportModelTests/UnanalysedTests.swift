// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-index/tests/unanalysed.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportModel

@Suite("unanalysed") struct UnanalysedTests {
    @Test("only_unanalysed_tracks_with_a_file_are_offered") func only_unanalysed_tracks_with_a_file_are_offered() {
        let library = library_from([
            TestTrack(id: 1, title: "Analysed", bpm_x100: 12_800, path: "/music/a.mp3"),
            TestTrack(id: 2, title: "Fresh", path: "/music/b.mp3"),
            TestTrack(id: 3, title: "No file"),
            TestTrack(id: 4, title: "Locked", path: "/music/d.mp3"),
            TestTrack(id: 5, title: "Also fresh", path: "/music/e.mp3"),
        ])
        // 잠긴 곡은 `Analysed`에 0x80 비트를 지니며, 로더는 BPM이 0이어도 분석된 것으로 둔다.
        if library.analysed.indices.contains(3) { library.analysed[3] = 1 }

        #expect(library.unanalysed_rows(0) == [1, 4])
        // 뒤쪽 쪽은 자기 행에서 시작하고 앞의 행을 건너뛴다.
        #expect(library.unanalysed_rows(2) == [4])
        #expect(library.unanalysed_rows(5).count == 0)
    }
}
