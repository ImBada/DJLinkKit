// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
import DJLinkExportModel
import DJLinkExportTestSupport
import DJLinkKit
// 원본: rbl-link/src/files.rs inline 시험.
import Foundation
import Testing

@testable import DJLinkExport

@Suite @DJLinkActor struct FilesTests {
    @Test("paths_split_into_an_export_and_a_relative_path") func split() {
        func check(_ path: String, _ expected: (String, String)?) {
            let actual = Files.split(path)
            #expect(actual?.0 == expected?.0 && actual?.1 == expected?.1)
        }
        check("/Users/me/Music/a.mp3", ("/", "Users/me/Music/a.mp3"))
        check("C:/Users/me/a.mp3", ("/C/", "Users/me/a.mp3"))
        check(#"d:\Music\b.flac"#, ("/D/", "Music/b.flac"))
        check("relative/path.mp3", nil)
        check("", nil)
    }
    @Test("a_track_is_allowed_under_its_first_three_folders") func roots() throws {
        func root(_ path: String) throws -> (String, String)? {
            let relative = try #require(Files.split(path)).1
            return Files.root_of(path, relative)
        }
        for (path, folder, host) in [
            ("/Volumes/SD/RB/Artist/Album/one.mp3", "Volumes/SD/RB", "/Volumes/SD/RB"),
            ("/Users/me/Music/one.mp3", "Users/me/Music", "/Users/me/Music"),
            (#"C:\Users\me\Music\one.mp3"#, "Users/me/Music", #"C:\Users/me/Music"#),
        ] {
            let value = try root(path)
            #expect(value?.0 == folder && value?.1 == host)
        }
        #expect(try root("/Users/me/one.mp3") == nil)
        #expect(try root("/one.mp3") == nil)
        #expect(try root("/Users/me/Music/") == nil)
    }
    @Test("a_shallow_track_does_not_hide_the_library_folders_beside_it") func shallow() throws {
        // 원본 캡처에서 온 경로 문자열은 고정 원본에서 읽어 공개 저장소에 재복사하지 않는다.
        let source = try UpstreamFixtures.text(crate: "rbl-link", path: "src/files.rs")
        func literal(_ name: String) throws -> String {
            let marker = "let \(name) = \""
            let start = try #require(source.range(of: marker)).upperBound
            let end = try #require(source[start...].firstIndex(of: "\""))
            return String(source[start..<end])
        }
        let sd = try literal("sd")
        let transcend = try literal("transcend")
        let loose = try literal("loose")
        for order in [[loose, sd, transcend], [sd, loose, transcend], [sd, transcend, loose]] {
            let library = library_from(
                order.enumerated().map { TestTrack(id: UInt64($0.offset + 1), title: "t", path: $0.element) })
            let root = try #require(Files.exports(library).get("/"))
            for (folder, host) in [
                ("Volumes/SD/Music", "/Volumes/SD/Music"), ("Volumes/Transcend/Music", "/Volumes/Transcend/Music"),
            ] {
                let node = try #require(root.resolve(folder))
                #expect(root.source(node) == host)
            }
            #expect(try root.source(#require(root.resolve("Volumes/SD/loose.mp3"))) == loose)
            func names(_ path: String) throws -> [String] {
                let at = try #require(root.resolve(path))
                return root.children(at).compactMap { root.name($0) }.sorted()
            }
            #expect(try names("Volumes") == ["SD", "Transcend"])
            #expect(try names("Volumes/SD") == ["Music", "loose.mp3"])
            #expect(root.resolve("Volumes/Other") == nil)
            #expect(root.resolve("Volumes/SD/Other") == nil)
        }
    }
    @Test("the_tree_reaches_the_library_folders_and_shallow_tracks_only") func reachable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let music = dir.appendingPathComponent("Music")
        try FileManager.default.createDirectory(
            at: music.appendingPathComponent("A"), withIntermediateDirectories: true)
        try Data("one".utf8).write(to: music.appendingPathComponent("A/one.mp3"))
        try Data("two".utf8).write(to: music.appendingPathComponent("A/two.mp3"))
        try Data("not in the library, but in its folder".utf8).write(to: music.appendingPathComponent("stray.wav"))
        let one = music.appendingPathComponent("A/one.mp3").path
        let two = music.appendingPathComponent("A/two.mp3").path
        let library = library_from([
            TestTrack(id: 1, title: "t", path: one), TestTrack(id: 2, title: "t", path: two),
            TestTrack(id: 3, title: "t", path: "/Users/me/three.mp3"),
            TestTrack(id: 4, title: "t", path: "not absolute.mp3"),
        ])
        let exports = Files.exports(library)
        #expect(exports.names() == ["/"])
        let root = try #require(exports.get("/"))
        let relative = try #require(Files.split(one)).1
        let folder = try #require(Files.root_of(one, relative)).0
        #expect(root.len() == 1 + 3)
        let a_dir = String(relative.prefix(upTo: try #require(relative.lastIndex(of: "/"))))
        #expect(a_dir.hasPrefix(folder))
        let a = try #require(root.resolve(a_dir))
        #expect(root.children(a).count == 2)
        #expect(try root.source(#require(root.resolve(relative))) == one)
        let parent = String(a_dir.prefix(upTo: try #require(a_dir.lastIndex(of: "/"))))
        #expect(root.resolve(parent + "/stray.wav") != nil)
        #expect(root.resolve("etc/hosts") == nil)
        #expect(root.resolve("Users/me/Music/other.mp3") == nil)
        let top = root.children(root.root()).compactMap { root.name($0) }
        #expect(top.contains("Users"))
        #expect(try root.source(#require(root.resolve("Users/me/three.mp3"))) == "/Users/me/three.mp3")
    }
    @Test("a_tracks_symlinked_folder_resolves_and_other_links_do_not") func symlinks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let music = dir.appendingPathComponent("Music")
        let disk = dir.appendingPathComponent("disk")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        for name in ["Artist", "Other"] {
            try FileManager.default.createDirectory(
                at: disk.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data("one".utf8).write(to: disk.appendingPathComponent("Artist/one.mp3"))
        try Data("two".utf8).write(to: disk.appendingPathComponent("Other/two.mp3"))
        for name in ["Artist", "Other"] {
            try FileManager.default.createSymbolicLink(
                at: music.appendingPathComponent(name), withDestinationURL: disk.appendingPathComponent(name))
        }
        let one = music.appendingPathComponent("Artist/one.mp3").path
        let library = library_from([TestTrack(id: 1, title: "t", path: one)])
        let root = try #require(Files.exports(library).get("/"))
        let relative = try #require(Files.split(one)).1
        let node = try #require(root.resolve(relative))
        #expect(root.source(node) == one)
        let music_rel = try #require(relative.range(of: "/Artist/")).lowerBound
        let base = String(relative[..<music_rel])
        #expect(root.resolve(base + "/Other/two.mp3") == nil)
        #expect(root.resolve(base + "/Other") == nil)
    }
}
