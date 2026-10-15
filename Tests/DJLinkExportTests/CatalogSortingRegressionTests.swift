// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-link/src/catalog.rs (자체 회귀)
import DJLinkExportDBServer
import DJLinkExportModel
import DJLinkKit
import Testing

@testable import DJLinkExport

@DJLinkActor private final class SortingSource: Source {
    let value: Library
    init(_ value: Library) { self.value = value }
    func library() -> Library? { value }
    func share_root() -> String { "/nonexistent" }
    func details(_ id: String) -> DJLinkExportModel.TrackDetails? { nil }
}

@Suite @DJLinkActor struct CatalogSortingRegressionTests {
    private func library() -> Library {
        let names = ["Zulu", "Alpha", "alpha", "Ａｌｐｈａ", "Ａｌｐｈａ", "", "Unknown", "unknown", ""]
        let library = library_from(
            names.enumerated().map {
                TestTrack(
                    id: UInt64($0.offset + 1), artist: $0.element, album: $0.element, label: $0.element,
                    genre: $0.element)
            })
        // wire id 순서가 밀집 id 순서와 반대여도 동률은 밀집 id로 정한다.
        let ids: [UInt32] = [800, 700, 600, 500, 400, 300, 200, 100, 50]
        library.artist_ids = ids
        library.album_ids = ids
        library.genre_ids = ids
        library.label_ids = ids
        return library
    }

    @Test("이름 메뉴 정렬이 대소문자·전각 문자와 동률의 밀집 id 순서를 유지한다")
    func named_order() {
        let catalog = IndexCatalog(SortingSource(library()), Played())
        let expected: [DJLinkExportDBServer.Row] = [
            .named(id: 500, name: "Ａｌｐｈａ"), .named(id: 400, name: "Ａｌｐｈａ"),
            .named(id: 700, name: "Alpha"), .named(id: 600, name: "alpha"),
            .named(id: 200, name: "Unknown"), .named(id: 100, name: "unknown"), .named(id: 800, name: "Zulu"),
        ]
        for query in [Query.artists(.default), .albums(.default), .genres(.default), .labels(.default)] {
            #expect(catalog.list(query) == expected)
        }
    }

    @Test("앨범 메뉴 정렬이 중복·빈 이름·Unknown과 동률의 밀집 id 순서를 유지한다")
    func album_order() {
        let library = library()
        library.artist = [UInt32](repeating: 0, count: library.count)
        library.album[4] = library.album[3]
        library.album[8] = NO_ID
        let catalog = IndexCatalog(SortingSource(library), Played())
        #expect(
            catalog.list(.artistAlbums(800)) == [
                .named(id: 500, name: "Ａｌｐｈａ"), .named(id: 700, name: "Alpha"),
                .named(id: 600, name: "alpha"), .named(id: 200, name: "Unknown"),
                .named(id: 100, name: "unknown"), .named(id: 0, name: "Unknown"), .named(id: 800, name: "Zulu"),
            ])
    }
}
