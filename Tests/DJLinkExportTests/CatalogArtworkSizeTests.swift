// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-link/src/catalog.rs (자체 회귀)
import DJLinkExportDBServer
import DJLinkExportModel
import DJLinkKit
import Foundation
import Testing

@testable import DJLinkExport

@DJLinkActor private final class ArtworkSource: Source {
    let value: Library, root: String
    init(_ value: Library, _ root: String) {
        self.value = value
        self.root = root
    }
    func library() -> Library? { value }
    func share_root() -> String { root }
    func details(_ id: String) -> DJLinkExportModel.TrackDetails? { nil }
}

/// 2026-10-16 캡처: CDJ-2000nexus가 목록 썸네일을 인자 둘인 `ARTWORK`(0x2003)로 물으면
/// rekordbox는 작은 파일 `_s`(80×80, 약 3KB)를 보냈다. rekordbox 7은 그림마다 원본(500~800px)·`_m`(240px)·`_s`(80px)를 둔다.
/// 원본은 `_m`(약 17KB)을 먼저 보내 목록 썸네일이 늦고 밀려 떴다.
@Suite @DJLinkActor struct CatalogArtworkSizeTests {
    private func catalog() throws -> (IndexCatalog, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "djlink-artwork-\(UUID().uuidString)")
        let folder = root.appending(path: "PIONEER/Artwork/00a")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: folder.appending(path: "a1.jpg"))
        try Data("small".utf8).write(to: folder.appending(path: "a1_s.jpg"))
        try Data("medium".utf8).write(to: folder.appending(path: "a1_m.jpg"))
        let library = library_from([TestTrack(id: 1)])
        var paths = StrColumn()
        paths.push("/PIONEER/Artwork/00a/a1.jpg")
        library.artwork_path = paths
        return (IndexCatalog(ArtworkSource(library, root.path), Played()), root)
    }

    @Test("목록 썸네일 요청에는 rekordbox처럼 _s를 보낸다")
    func list_artwork_is_the_small_file() throws {
        let (catalog, root) = try catalog()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(catalog.artwork(1) == Array("small".utf8))
        // 같은 줄을 큰 그림으로 물어도 캐시가 섞이지 않는다
        #expect(catalog.item_artwork(1) == Array("medium".utf8))
        #expect(catalog.artwork(1) == Array("small".utf8))
    }

    @Test("목록 썸네일은 그 줄의 곡 id로 묻는다")
    func list_artwork_is_asked_by_track_id() throws {
        // 2026-10-16 캡처: rekordbox 목록 줄과 CDJ의 ARTWORK 요청이 같은 곡 id를 썼다. 줄 번호+2로 읽으면 앞 곡 그림이 나왔다
        let root = FileManager.default.temporaryDirectory.appending(path: "djlink-artwork-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "PIONEER/Artwork")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: folder.appending(path: "a_s.jpg"))
        try Data("second".utf8).write(to: folder.appending(path: "b_s.jpg"))
        let library = library_from([TestTrack(id: 1), TestTrack(id: 2)])
        var paths = StrColumn()
        paths.push("/PIONEER/Artwork/a.jpg")
        paths.push("/PIONEER/Artwork/b.jpg")
        library.artwork_path = paths
        let catalog = IndexCatalog(ArtworkSource(library, root.path), Played())
        #expect(catalog.artwork(1) == Array("first".utf8))
        #expect(catalog.artwork(2) == Array("second".utf8))
        #expect(catalog.artwork(3) == nil)
    }

    @Test("_s가 없으면 _m을, 그것도 없으면 원본을 보낸다")
    func falls_back_to_larger_files() throws {
        let (catalog, root) = try catalog()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "PIONEER/Artwork/00a")
        try FileManager.default.removeItem(at: folder.appending(path: "a1_s.jpg"))
        #expect(catalog.artwork(1) == Array("medium".utf8))
        let (fresh, other) = try self.catalog()
        defer { try? FileManager.default.removeItem(at: other) }
        let second = other.appending(path: "PIONEER/Artwork/00a")
        for name in ["a1_s.jpg", "a1_m.jpg"] { try FileManager.default.removeItem(at: second.appending(path: name)) }
        #expect(fresh.artwork(1) == Array("original".utf8))
        #expect(fresh.item_artwork(1) == Array("original".utf8))
    }
}
