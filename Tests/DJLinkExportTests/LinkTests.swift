// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
import DJLinkExportANLZ
import DJLinkExportDBServer
import DJLinkExportModel
import DJLinkExportTestSupport
import DJLinkKit
import DJLinkTestSupport
// 원본: rbl-link/tests/link.rs. TCP/UDP 바이트는 가짜 전송으로 왕복한다.
import Foundation
import Testing

@testable import DJLinkExport

@Suite @DJLinkActor struct LinkTests {
    let CTX: UInt32 = 0x01010301
    let LINK_DEVICE_NUMBER: UInt8 = 0x11
    final class Served {
        let dir: URL, link: LinkExport, audio: [UInt8], track: UInt32, path: String, clock: TestClock,
            factory: FakeExportSocketFactory
        init(
            _ dir: URL, _ link: LinkExport, _ audio: [UInt8], _ track: UInt32, _ path: String, _ clock: TestClock,
            _ factory: FakeExportSocketFactory
        ) {
            self.dir = dir
            self.link = link
            self.audio = audio
            self.track = track
            self.path = path
            self.clock = clock
            self.factory = factory
        }
        deinit { try? FileManager.default.removeItem(at: dir) }
    }
    func fixture(_ name: String) throws -> [UInt8] {
        try UpstreamFixtures.bytes(crate: "rbl-link", path: "tests/fixtures/" + name)
    }
    func serve() async throws -> Served {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let audio = (0..<100000).map { UInt8($0 % 253) }
        let audioDir = dir.appendingPathComponent("Music/Crate")
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        // 원본 시험의 곡명 문자열도 공개 저장소에 복사하지 않고 고정 원본에서 읽는다.
        let original = try UpstreamFixtures.text(crate: "rbl-link", path: "tests/link.rs")
        let prefix = "audio_dir.join(\""
        let start = try #require(original.range(of: prefix)).upperBound
        let end = try #require(original[start...].firstIndex(of: "\""))
        let path = audioDir.appendingPathComponent(String(original[start..<end]))
        try Data(audio).write(to: path)
        let lib = fixture_library(tracks: 3, playlists: 1, tracks_per_playlist: 2, histories: 1)
        lib.folder_path = replace_first(lib.folder_path, path.path)
        lib.file_name = replace_first(lib.file_name, path.lastPathComponent)
        lib.title = replace_first(lib.title, path.deletingPathExtension().lastPathComponent)
        lib.title_folded = replace_first(lib.title_folded, fold(path.deletingPathExtension().lastPathComponent))
        lib.length_sec[0] = 290
        let shareRoot = dir.appendingPathComponent("share")
        try FileManager.default.createDirectory(at: shareRoot, withIntermediateDirectories: true)
        let analysis = "/PIONEER/USBANLZ/P001/0000ABCD/ANLZ0000.DAT"
        lib.analysis_path = replace_first(lib.analysis_path, analysis)
        lib.build_indexes()
        let dat = DJLinkExportANLZ.resolve(shareRoot.path, analysis)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: dat).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(fixture("ANLZ0001.DAT")).write(to: URL(fileURLWithPath: dat))
        try Data(fixture("ANLZ0001.EXT")).write(to: URL(fileURLWithPath: DJLinkExportANLZ.sibling(dat, "EXT")))
        let clock = TestClock()
        let factory = FakeExportSocketFactory(clock: clock)
        let source = StaticSource(library: lib, share_root: shareRoot.path)
        let link = try await LinkExport.start(
            source, .loopback(), .EPHEMERAL, socketFactory: factory, clock: clock, connectionMode: .wired)
        #expect(link.link_state() == .waiting)
        await #expect(throws: (any Error).self) {
            try await FakePlayerDatabase.database_port(link.query_address(), factory)
        }
        let player = try factory.createUDPSocket(reuseAddr: false)
        _ = try await player.bind(port: 0, address: "127.0.0.1")
        let wire =
            "5173707431576d4a4f4c060043444a2d333030300000000000000000000000000103003601012497ed0b4043c0a80198030000000164"
        let bytes = stride(from: 0, to: wire.count, by: 2).map { offset -> UInt8 in
            let index = wire.index(wire.startIndex, offsetBy: offset)
            return UInt8(wire[index..<wire.index(index, offsetBy: 2)], radix: 16)!
        }
        try await udpSend(player, bytes, Int(link.beacon_ports().0), "127.0.0.1")
        for _ in 0..<200 {
            if link.link_state() == .up(number: LINK_DEVICE_NUMBER) { break }
            clock.advance(ms: 50)
            await clock.settle()
        }
        #expect(link.link_state() == .up(number: LINK_DEVICE_NUMBER))
        try await udpClose(player)
        return Served(dir, link, audio, UInt32(lib.ids[0]), path.path, clock, factory)
    }
    func replace_first(_ old: StrColumn, _ text: String) -> StrColumn {
        var value = StrColumn()
        for at in 0..<old.len() { value.push(at == 0 ? text : old.get(at)) }
        return value
    }
    @Test("a_player_browses_loads_and_reads_a_track_as_the_capture_shows") func browseRead() async throws {
        let served = try await serve()
        let port = try await FakePlayerDatabase.database_port(served.link.query_address(), served.factory)
        #expect(port == UInt16(served.link.database_address().port))
        let db = try await FakePlayerDatabase.connect(served.link.database_address(), 1, served.factory)
        let root = try await db.browse(kind.ROOT_MENU, [CTX, 0, 0x5cfffff])
        #expect(root.count == 9)
        #expect(root[0][6] == .number(0x81))
        let tracks = try await db.browse(kind.TRACK_MENU, [CTX, 0])
        #expect(tracks.count == 3)
        #expect(tracks[0][1] == .number(served.track))
        let lists = try await db.browse(kind.PLAYLIST_MENU, [CTX, 0, 0, 1])
        #expect(lists.count == 1)
        guard case let .number(playlist) = lists[0][1] else { throw DJLinkError("missing playlist") }
        let members = try await db.browse(kind.PLAYLIST_MENU, [CTX, 0, playlist, 0])
        #expect(members.count == 2)
        #expect(members[0][9] == .number(1))
        let info = try await db.browse(kind.TRACK_INFO, [CTX, served.track])
        #expect(info.count == 7)
        #expect(info[4][3] == .string(served.path))
        #expect(info[4][0] == .number(UInt32(served.audio.count)))
        let grid = try await db.request(kind.BEAT_GRID, [CTX, served.track].map { .number($0) })
        #expect(grid[0].kind == kind.BEAT_GRID_REPLY)
        #expect(try grid[0].arguments[3] == .blob(fixture("captured-beat-grid.bin")))
        let preview = try await db.request(kind.WAVEFORM_PREVIEW, [CTX, 0, served.track, 0].map { .number($0) })
        #expect(try preview[0].arguments[3] == .blob(fixture("captured-waveform-preview.bin")))
        let fourcc = Array("PWV4".utf8).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
        let tag = try await db.request(kind.ANLZ_TAG, [CTX, served.track, fourcc, 0x00545845].map { .number($0) })
        #expect(try tag[0].arguments[3] == .blob(fixture("captured-tag-PWV4.bin")))
        guard case let .number(other) = tracks[1][1] else { throw DJLinkError("missing track") }
        let none = try await db.request(kind.BEAT_GRID, [CTX, other].map { .number($0) })
        #expect(none[0].arguments[1] == .number(0x32))
        let (export, relative) = try #require(Files.split(served.path))
        let mounted = try await FakePlayerRPC.connect(served.link.portmap_address(), served.factory)
        let handle = try await mounted.mount(export)
        #expect(try await mounted.read_file(handle, relative) == served.audio)
        #expect(served.link.snapshot().database_port == port)
        db.stream.destroy(nil)
        try await udpClose(mounted.socket)
        await stop_link(served.link, served.clock)
    }
    @Test("a_second_player_only_sees_its_own_list") func isolatedLists() async throws {
        let served = try await serve()
        let one = try await FakePlayerDatabase.connect(served.link.database_address(), 1, served.factory)
        let two = try await FakePlayerDatabase.connect(served.link.database_address(), 2, served.factory)
        let artists = try await one.browse(kind.ARTIST_MENU, [CTX, 0])
        let tracks = try await two.browse(kind.TRACK_MENU, [CTX, 0])
        #expect(artists.isEmpty)
        #expect(tracks.count == 3)
        let again = try await one.request(kind.RENDER, [CTX, 0, 25, 0, 25, 0xc, 1, 0].map { .number($0) })
        #expect(again.allSatisfy { $0.kind != kind.MENU_ITEM })
        one.stream.destroy(nil)
        two.stream.destroy(nil)
        await stop_link(served.link, served.clock)
    }
    @Test("alphatheta_connects_client_reads_metadata_and_analysis_from_us") func client() async throws {
        let served = try await serve()
        let socket = try served.factory.createTCPConnection()
        try await socket.connect(
            port: served.link.database_address().port, host: served.link.database_address().address)
        try await socket.write(RemoteDBUInt32(1).buffer)
        let hello = try await readField(socket, .uint32)
        #expect((hello as? RemoteDBUInt32)?.value == 1)
        try await socket.write(
            DJLinkKit.Message(transactionId: 0xfffffffe, type: .introduce, args: [RemoteDBUInt32(3)]).buffer)
        let reply = try await DJLinkKit.Message.fromStream(socket, .success)
        #expect(reply.type.rawValue == 0x4000)
        #expect((reply.args[1] as? RemoteDBUInt32)?.value == Int(LINK_DEVICE_NUMBER))
        let rekordbox = Device(
            name: "rekordbox", id: Int(LINK_DEVICE_NUMBER), type: .rekordbox, macAddr: [UInt8](repeating: 0, count: 6),
            ip: try .init("127.0.0.1"))
        let host = Device(
            name: "CDJ-3000", id: 3, type: .cdj, macAddr: [UInt8](repeating: 0, count: 6), ip: try .init("127.0.0.1"))
        let conn = Connection(device: rekordbox, socket: socket)
        let query = QueryInterface(conn: conn, lock: AsyncMutex(), hostDevice: host)
        let descriptor = QueryDescriptor(menuTarget: .main, trackSlot: .rb, trackType: .rb)
        let track = try await query.query(
            queryDescriptor: descriptor, query: .getMetadata, args: .init(trackId: Int(served.track)))
        guard case let .track(metadata) = track else { throw DJLinkError("expected metadata") }
        let original = try UpstreamFixtures.text(crate: "rbl-link", path: "tests/link.rs")
        let expectationPrefix = "assert_eq!(track.title, \""
        let expectationStart = try #require(original.range(of: expectationPrefix)).upperBound
        let expectationEnd = try #require(original[expectationStart...].firstIndex(of: "\""))
        let expectedTitle = String(original[expectationStart..<expectationEnd])
        #expect(metadata.title == expectedTitle)
        #expect(Double(metadata.duration) == 290.0)
        #expect(abs(metadata.tempo - 128.0) < 0.01)
        #expect(metadata.comment == "")
        #expect(
            try await query.query(
                queryDescriptor: descriptor, query: .getTrackInfo, args: .init(trackId: Int(served.track)))
                == .path(served.path))
        let grid = try await query.query(
            queryDescriptor: descriptor, query: .getBeatGrid, args: .init(trackId: Int(served.track)))
        guard case let .beatGrid(beats) = grid else { throw DJLinkError("expected beat grid") }
        #expect(!beats.isEmpty)
        #expect(abs(beats[0].bpm - 78.08) < 0.01)
        let preview = try await query.query(
            queryDescriptor: descriptor, query: .getWaveformPreview, args: .init(trackId: Int(served.track)))
        guard case let .waveformPreview(waveform) = preview else { throw DJLinkError("expected waveform preview") }
        #expect(waveform.count == 400)
        let detailed = try await query.query(
            queryDescriptor: descriptor, query: .getWaveformDetailed, args: .init(trackId: Int(served.track)))
        guard case let .waveformDetailed(detail) = detailed else { throw DJLinkError("expected waveform detail") }
        #expect(!detail.isEmpty)
        let missing = try await query.query(
            queryDescriptor: descriptor, query: .getMetadata, args: .init(trackId: 0xdeadbeef))
        guard case let .track(empty) = missing else { throw DJLinkError("expected empty metadata") }
        #expect(Double(empty.duration) == 0.0)
        conn.close()
        await stop_link(served.link, served.clock)
    }
}
