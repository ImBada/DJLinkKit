// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Bada
// 원본에 없는 입구: 플레이어가 파일을 찾거나 처음부터 읽을 때 알린다. 원본 파일 대신 다른 파일을 내어 준다(PLAN §9 Link Export).
import DJLinkKit
import Foundation
import Testing

@testable import DJLinkExportNFS

@DJLinkActor
@Suite("NFS 파일 요청 알림·바꿔 내기")
struct NFSFileObserverTests {
    private final class TempDir {
        let path: String
        init() throws {
            path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        func join(_ name: String) -> String { path + "/" + name }
        deinit { try? FileManager.default.removeItem(atPath: path) }
    }
    private final class Seen {
        var requests: [(String, String)] = []
    }
    private static let player = try! Address4("169.254.10.2")
    private final class Counter { var xid: UInt32 = 0x5000 }
    private let counter = Counter()

    private func fixture() throws -> (TempDir, Server, Seen) {
        let dir = try TempDir()
        try Data(repeating: 7, count: 40000).write(to: URL(fileURLWithPath: dir.join("track.flac")))
        let vfs = Vfs("/")
        vfs.add_file("Contents/Artist/track.flac", dir.join("track.flac"), 40000, 1700000000)
        let exports = Exports()
        exports.insert(vfs)
        let seen = Seen()
        let server = Server(exports, 12049, 12005).with_file_observer { path, from in
            seen.requests.append((path, from.address))
        }
        return (dir, server, seen)
    }
    private func call(_ program: UInt32, _ version: UInt32, _ procedure: UInt32, _ arguments: [UInt8]) -> [UInt8] {
        defer { counter.xid &+= 1 }
        return Rpc.Call(
            xid: counter.xid, program: program, version: version, procedure: procedure,
            credential: Rpc.Auth(flavor: Rpc.AUTH_UNIX, body: Array(repeating: 0, count: 8)), verifier: .null(),
            arguments: arguments
        ).encode()
    }
    private func ask(_ server: Server, _ program: UInt32, _ version: UInt32, _ procedure: UInt32, _ args: [UInt8])
        throws -> Xdr.Reader
    {
        let reply = try #require(server.handle_from(call(program, version, procedure, args), Self.player, 1023))
        let parsed = try Rpc.Reply.decode(reply)
        #expect(parsed.is_success())
        return parsed.reader()
    }
    private func root(_ server: Server) throws -> Handle {
        let reader = try ask(server, PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.MNT, Xdr.Writer().utf16("/").into_bytes())
        #expect(try reader.u32() == nfs_status.OK)
        return try #require(Handle.from_slice(reader.opaque_fixed(HANDLE_LEN)))
    }
    private func lookup(_ server: Server, _ parent: Handle, _ name: String) throws -> Handle {
        let reader = try ask(
            server, PROGRAM_NFS, VERSION_NFS, nfs_proc.LOOKUP,
            Xdr.Writer().opaque_fixed(parent.as_bytes()).utf16(name).into_bytes())
        #expect(try reader.u32() == nfs_status.OK)
        return try #require(Handle.from_slice(reader.opaque_fixed(HANDLE_LEN)))
    }
    @discardableResult
    private func read(_ server: Server, _ file: Handle, at offset: UInt32) throws -> (size: UInt32, data: [UInt8]) {
        let args = Xdr.Writer().opaque_fixed(file.as_bytes()).u32(offset).u32(32768).u32(0)
        let reader = try ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.READ, args.into_bytes())
        #expect(try reader.u32() == nfs_status.OK)
        // 파일 속성 17칸 중 여섯째가 크기다
        var attributes: [UInt32] = []
        for _ in 0..<17 { attributes.append(try reader.u32()) }
        return (attributes[5], try reader.opaque())
    }

    @Test("파일을 찾으면 호스트 경로와 보낸 주소를 알리고 폴더를 찾을 때는 알리지 않는다")
    func lookupOfAFileIsReported() throws {
        let (dir, server, seen) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try root(server)
        let contents = try lookup(server, root, "Contents")
        let artist = try lookup(server, contents, "Artist")
        #expect(seen.requests.isEmpty)
        _ = try lookup(server, artist, "track.flac")
        #expect(seen.requests.map(\.0) == [dir.join("track.flac")])
        #expect(seen.requests.map(\.1) == ["169.254.10.2"])
    }

    @Test("허락한 폴더 아래에서도 폴더를 찾을 때는 알리지 않는다")
    func folderUnderAnAllowedRootIsNotReported() throws {
        // 실제 내보내기(`Files.exports`)는 곡 경로 앞 세 단계를 `allow_folder`로 열어 폴더 노드에도 원본 경로가 붙는다
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        try FileManager.default.createDirectory(atPath: dir.join("Music/Artist"), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 100).write(to: URL(fileURLWithPath: dir.join("Music/Artist/track.flac")))
        let vfs = Vfs("/")
        vfs.allow_folder("Users/dj/Music", dir.join("Music"))
        vfs.allow_track(dir.join("Music/Artist/track.flac"))
        let exports = Exports()
        exports.insert(vfs)
        let seen = Seen()
        let server = Server(exports, 12049, 12005).with_file_observer { path, from in seen.requests.append((path, from.address)) }
        var at = try root(server)
        for part in ["Users", "dj", "Music", "Artist"] { at = try lookup(server, at, part) }
        #expect(seen.requests.isEmpty)
        _ = try lookup(server, at, "track.flac")
        #expect(seen.requests.map(\.0) == [dir.join("Music/Artist/track.flac")])
    }

    @Test("처음부터 읽을 때만 알리고 이어 읽을 때는 알리지 않는다")
    func onlyTheFirstReadIsReported() throws {
        let (dir, server, seen) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try root(server)
        var at = root
        for part in ["Contents", "Artist", "track.flac"] { at = try lookup(server, at, part) }
        seen.requests.removeAll()
        try read(server, at, at: 0)
        try read(server, at, at: 32768)
        #expect(seen.requests.map(\.0) == [dir.join("track.flac")])
    }

    @Test("다시 보낸 같은 요청은 앞 답을 다시 보내고 또 알리지 않는다")
    func retransmissionIsNotReportedTwice() throws {
        let (dir, server, seen) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try root(server)
        var at = root
        for part in ["Contents", "Artist"] { at = try lookup(server, at, part) }
        let request = call(
            PROGRAM_NFS, VERSION_NFS, nfs_proc.LOOKUP, Xdr.Writer().opaque_fixed(at.as_bytes()).utf16("track.flac").into_bytes())
        _ = server.handle_from(request, Self.player, 1023)
        _ = server.handle_from(request, Self.player, 1023)
        #expect(seen.requests.count == 1)
    }

    @Test("바꿔 낸 원본을 처음 찾으면 원본 이름으로 다른 파일의 크기와 내용을 준다")
    func redirectBeforeLookupServesTheReplacement() throws {
        // 실제 내보내기처럼 허락한 폴더 아래에서 이름으로 찾는다. 바꾼 WAV는 같은 뿌리 폴더 안 다른 곳에 있다
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        try FileManager.default.createDirectory(atPath: dir.join("Music/Artist"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: dir.join("Music/LINK"), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 100).write(to: URL(fileURLWithPath: dir.join("Music/Artist/track.flac")))
        try Data(repeating: 9, count: 60).write(to: URL(fileURLWithPath: dir.join("Music/LINK/track.wav")))
        let vfs = Vfs("/")
        vfs.allow_folder("Users/dj/Music", dir.join("Music"))
        vfs.allow_track(dir.join("Music/Artist/track.flac"))
        let exports = Exports()
        exports.insert(vfs)
        let seen = Seen()
        let server = Server(exports, 12049, 12005).with_file_observer { path, from in seen.requests.append((path, from.address)) }
        server.exports().redirect(dir.join("Music/Artist/track.flac"), to: dir.join("Music/LINK/track.wav"))
        var at = try root(server)
        for part in ["Users", "dj", "Music", "Artist", "track.flac"] { at = try lookup(server, at, part) }
        let read = try read(server, at, at: 0)
        #expect(read.size == 60)
        #expect(read.data == [UInt8](repeating: 9, count: 60))
        #expect(seen.requests.map(\.0) == [dir.join("Music/LINK/track.wav"), dir.join("Music/LINK/track.wav")])
    }

    @Test("이미 찾은 원본도 바꿔 내면 기억한 핸들로 다른 파일을 읽는다")
    func redirectAfterLookupSwitchesTheRememberedHandle() throws {
        // CDJ-2000nexus는 곡 번호별로 처음 받은 경로를 기억해, 바꾼 뒤에도 원본 이름과 핸들로 찾는다.
        // 핸들이 바뀌면 싣는 도중 옛 핸들과 섞어 써서 멈췄으므로(실기) 같은 핸들로 바꾼 파일을 준다
        let (dir, server, _) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        try Data(repeating: 9, count: 60).write(to: URL(fileURLWithPath: dir.join("track.wav")))
        var folder = try root(server)
        for part in ["Contents", "Artist"] { folder = try lookup(server, folder, part) }
        let open = try lookup(server, folder, "track.flac")
        #expect(try read(server, open, at: 0).size == 40000)
        server.exports().redirect(dir.join("track.flac"), to: dir.join("track.wav"))
        let read = try read(server, open, at: 0)
        #expect(read.size == 60)
        #expect(read.data == [UInt8](repeating: 9, count: 60))
        #expect(try lookup(server, folder, "track.flac") == open)
    }

    @Test("바꿔 낸 뒤 폴더 목록을 읽어도 원본 이름으로 다른 파일을 준다")
    func redirectSurvivesDirectoryListing() throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        try FileManager.default.createDirectory(atPath: dir.join("Music/Artist"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: dir.join("Music/LINK"), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 100).write(to: URL(fileURLWithPath: dir.join("Music/Artist/track.flac")))
        try Data(repeating: 9, count: 60).write(to: URL(fileURLWithPath: dir.join("Music/LINK/track.wav")))
        let vfs = Vfs("/")
        vfs.allow_folder("Users/dj/Music", dir.join("Music"))
        vfs.allow_track(dir.join("Music/Artist/track.flac"))
        let exports = Exports()
        exports.insert(vfs)
        let server = Server(exports, 12049, 12005)
        server.exports().redirect(dir.join("Music/Artist/track.flac"), to: dir.join("Music/LINK/track.wav"))
        var at = try root(server)
        for part in ["Users", "dj", "Music", "Artist"] { at = try lookup(server, at, part) }
        let served = try #require(server.exports().get("/"))
        let folder = try #require(served.node_of(at))
        _ = served.children(folder)
        let read = try read(server, try lookup(server, at, "track.flac"), at: 0)
        #expect(read.size == 60)
    }
}
