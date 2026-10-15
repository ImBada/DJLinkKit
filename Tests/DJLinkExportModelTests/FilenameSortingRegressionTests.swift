// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-index/src/category.rs (자체 회귀)
import DJLinkExportModel
import Testing

@Suite struct FilenameSortingRegressionTests {
    @Test("파일명 정렬이 대소문자·전각 문자와 동률의 행 순서를 유지한다")
    func filename_order() {
        let names = ["z.mp3", "A.mp3", "a.mp3", "Ａ.mp3", "Ａ.mp3", "b.mp3"]
        let library = library_from(names.enumerated().map { TestTrack(id: UInt64($0.offset + 1), path: $0.element) })
        // 원본 fold는 전각 문자를 버린다. 같은 키의 파일명은 행 번호로 정렬한다.
        #expect(library.filename_rows() == [1, 2, 5, 3, 4, 0])
    }
}
