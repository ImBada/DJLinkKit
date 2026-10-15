// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-index/tests/file_created.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import DJLinkExportModel
import Foundation
import Testing

@Suite("file_created") struct FileCreatedTests {
    private func temporary_directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // 플랫폼이 파일에 기록한 생성 시각을 초 단위로 읽는다.
    private func platform_created(_ path: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
            let created = attributes[.creationDate] as? Date, created.timeIntervalSince1970 >= 0
        else { return nil }
        return Int64(created.timeIntervalSince1970)
    }

    private func track(_ id: UInt64, _ path: String) -> TestTrack {
        TestTrack(id: id, title: "t", path: path)
    }

    private func spec(_ descending: Bool) -> ViewSpec {
        ViewSpec(source: .collection, sort: .fileCreated, descending: descending, query: "", filter: TrackFilter())
    }

    @Test("a_files_creation_time_is_what_the_platform_reports")
    func a_files_creation_time_is_what_the_platform_reports() throws {
        let dir = try temporary_directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.mp3")
        try Data("x".utf8).write(to: file)
        #expect(created_secs(file.path) == platform_created(file))
        if let secs = created_secs(file.path) {
            let now = Int64(Date().timeIntervalSince1970)
            #expect(abs(now - secs) < 300, "created \(secs), now \(now)")
        }
    }

    @Test("a_missing_or_empty_path_has_no_creation_time")
    func a_missing_or_empty_path_has_no_creation_time() throws {
        let dir = try temporary_directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(created_secs(dir.appendingPathComponent("gone.mp3").path) == nil)
        #expect(created_secs("") == nil)
    }

    @Test("a_track_reads_its_own_files_creation_time")
    func a_track_reads_its_own_files_creation_time() throws {
        let dir = try temporary_directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.mp3")
        try Data("x".utf8).write(to: file)
        let library = library_from([track(1, file.path), track(2, "/no/such/file.mp3")])
        #expect(library.file_created(0) == platform_created(file))
        #expect(library.file_created(1) == nil)
        #expect(library.file_created(99) == nil, "a row past the end is blank, not a panic")
    }

    @Test("sorting_by_creation_puts_unknown_first_then_oldest_to_newest")
    func sorting_by_creation_puts_unknown_first_then_oldest_to_newest() async throws {
        let dir = try temporary_directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let older = dir.appendingPathComponent("older.mp3")
        let newer = dir.appendingPathComponent("newer.mp3")
        try Data("x".utf8).write(to: older)
        // 생성 시각 열은 초 단위다. 원본처럼 파일 생성을 1100ms 간격으로 둔다.
        try await Task.sleep(for: .milliseconds(1100))
        try Data("x".utf8).write(to: newer)
        if platform_created(older) == nil {
            print("this file system records no creation time; only the blank case is checked")
        }
        let library = library_from([
            track(1, newer.path), track(2, "/no/such/file.mp3"), track(3, older.path),
        ])
        func ids(_ descending: Bool) -> [UInt64] {
            library.open_view(spec(descending)).rows.map { library.ids[Int($0)] }
        }
        if platform_created(older) != nil {
            #expect(ids(false) == [2, 3, 1])
            #expect(ids(true) == [1, 3, 2])
        } else {
            // 생성 시각이 모두 없으면 동률인 행 순서를 유지한다.
            #expect(ids(false) == [1, 2, 3])
        }
        #expect(library.file_created(0) == platform_created(newer))
    }

    @Test("moving_the_files_forgets_the_creation_times_read_before")
    func moving_the_files_forgets_the_creation_times_read_before() throws {
        let dir = try temporary_directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.mp3")
        try Data("x".utf8).write(to: file)
        let library = library_from([track(1, file.path)])
        _ = library.open_view(spec(false))
        library.map_folder_paths { _ in "/no/such/mount/a.mp3" }
        #expect(library.file_created(0) == nil)
    }

    @Test("a_large_library_reads_on_worker_threads_to_the_same_result")
    func a_large_library_reads_on_worker_threads_to_the_same_result() throws {
        let dir = try temporary_directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.mp3")
        try Data("x".utf8).write(to: file)
        let present = file.path
        // 원본과 다름: Swift는 직렬로 읽지만 원본의 5000개 입력과 행별 기대값은 유지한다.
        let tracks = (UInt64(0)..<5000).map { i in track(i + 1, i % 3 == 0 ? "/no/such/file.mp3" : present) }
        let library = library_from(tracks)
        let view = library.open_view(spec(false))
        let expected = platform_created(file)
        for row in tracks.indices {
            let want = row % 3 == 0 ? nil : expected
            #expect(library.file_created(UInt32(row)) == want, "row \(row)")
        }
        if expected != nil {
            // 생성 시각이 없는 행을 먼저 놓고 각 묶음 안에서는 행 순서를 유지한다.
            let blanks = (tracks.count + 2) / 3
            let blank_rows = view.rows.prefix(blanks)
            #expect(blank_rows.allSatisfy { $0 % 3 == 0 })
            #expect(zip(blank_rows, blank_rows.dropFirst()).allSatisfy { $0.0 < $0.1 })
            #expect(view.rows.dropFirst(blanks).allSatisfy { $0 % 3 != 0 })
        }
    }

    @Test(
        "a_folder_sorts_its_tracks_and_loose_files_by_creation_together",
        .disabled("폴더 브라우저(rbl_index::folder)는 서버 범위 밖이라 옮기지 않았다"))
    func a_folder_sorts_its_tracks_and_loose_files_by_creation_together() {}
}
