import DJLinkExportDBServer
import DJLinkExportModel
import DJLinkExportNFS
import DJLinkExportTestSupport
import DJLinkKit
import DJLinkTestSupport
// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbl-db/src/fixture.rs, rbl-fakecdj/src/lib.rs의 서버 시험 준비 경로.
import Foundation
import Testing

@testable import DJLinkExport

@DJLinkActor func fixture_library(tracks: Int, playlists: Int, tracks_per_playlist: Int, histories: Int) -> Library {
    // 원본과 다름: 서버 범위 밖 SQL fixture 생성/색인 적재 대신 같은 메모리 컬럼을 직접 준비한다.
    let lib = library_from(
        (0..<tracks).map { i in
            TestTrack(
                id: UInt64(10000 + i), title: String(format: "Track %03d", i), bpm_x100: UInt32(12800 + i),
                length_sec: 300, path: String(format: "/fixture/audio/track%03d.mp3", i))
        })
    lib.analysed = [UInt8](repeating: 1, count: tracks)
    // 원본 DB fixture의 NULL lookup은 빈 문자열의 intern ID가 아닌 NO_ID로 읽힌다.
    lib.artist = [UInt32](repeating: NO_ID, count: tracks)
    lib.album = lib.artist
    lib.genre = lib.artist
    lib.label = lib.artist
    lib.key = lib.artist
    lib.artists = Interner()
    lib.albums = Interner()
    lib.genres = Interner()
    lib.labels = Interner()
    lib.keys = Interner()
    lib.artist_ids = []
    lib.album_ids = []
    lib.genre_ids = []
    lib.label_ids = []
    lib.set_my_tags([TagCategory(name: "Situation", tags: ["Peak", "Warm-up"])])
    for p in 0..<playlists {
        let at = add_playlist(
            lib, "Playlist \(p)",
            (0..<tracks_per_playlist).map { UInt32((p * tracks_per_playlist + $0) % max(tracks, 1)) })
        var lists = lib.playlists()
        lists.ids[at] = UInt64(900000 + p)
        lib.set_playlists(lists)
    }
    if histories > 0 {
        // 원본 read_lists의 ORDER BY Seq와 fixture의 연도·월 폴더를 보존한다.
        var nodes:
            [(id: UInt64, name: String, parent: UInt64?, seq: UInt32, folder: Bool, rows: [DJLinkExportModel.Row])] = [
                (2026, "2026", nil, 1, true, []), (202609, "9", 2026, 9, true, []), (202608, "8", 2026, 10, true, []),
            ]
        for h in 0..<histories {
            nodes.append(
                (
                    UInt64(800000 + h), "HISTORY 2026-09-0\(h+1)", 202609, UInt32(h + 1), false,
                    (0..<tracks_per_playlist).map { UInt32((h * tracks_per_playlist + $0) % max(tracks, 1)) }
                ))
        }
        nodes = nodes.enumerated().sorted {
            $0.element.seq == $1.element.seq ? $0.offset < $1.offset : $0.element.seq < $1.element.seq
        }.map(\.element)
        var lists = Playlists()
        for node in nodes {
            lists.ids.append(node.id)
            lists.names.push(node.name)
            lists.parent.append(
                node.parent.flatMap { parent in nodes.firstIndex { $0.id == parent }.map { UInt32($0) } } ?? NO_ID)
            lists.seq.append(node.seq)
            lists.attribute.append(node.folder ? 1 : 0)
            lists.smart.push("")
            lists.members.append(node.rows)
        }
        lib.set_histories(lists)
    }
    lib.build_indexes()
    return lib
}
@DJLinkActor func stop_link(_ link: LinkExport, _ clock: TestClock) async {
    let done = Task { @DJLinkActor in await link.stop() }
    await clock.settle()
    clock.advance(ms: 200)
    await clock.settle()
    await done.value
}
@DJLinkActor final class FakePlayerDatabase {
    let stream: any TCPConnection
    var transaction: UInt32 = 0, pending: [UInt8] = []
    init(_ stream: any TCPConnection) { self.stream = stream }
    static func database_port(_ query: AddressInfo, _ factory: FakeExportSocketFactory) async throws -> UInt16 {
        let stream = try factory.createTCPConnection()
        defer { stream.destroy(nil) }
        try await stream.connect(port: query.port, host: query.address)
        try await stream.write(PORT_QUERY_REQUEST)
        guard let bytes = try await stream.read(2), bytes.count == 2 else {
            throw DJLinkError("the database server did not answer the port query")
        }
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }
    static func connect(_ address: AddressInfo, _ device: UInt8, _ factory: FakeExportSocketFactory) async throws
        -> FakePlayerDatabase
    {
        let stream = try factory.createTCPConnection()
        try await stream.connect(port: address.port, host: address.address)
        let db = FakePlayerDatabase(stream)
        try await stream.write(GREETING)
        #expect(try await stream.read(5) == GREETING)
        try await stream.write(setup_request(device).encode())
        _ = try await db.receive()
        return db
    }
    func request(_ request: UInt16, _ args: [DJLinkExportDBServer.Argument]) async throws -> [DJLinkExportDBServer
        .Message]
    {
        transaction &+= 1
        try await stream.write(DJLinkExportDBServer.Message.new(transaction, request, args).encode())
        return try await receive()
    }
    func receive() async throws -> [DJLinkExportDBServer.Message] {
        while true {
            let (messages, used) = DJLinkExportDBServer.Message.decode_all(pending)
            if !messages.isEmpty {
                pending.removeFirst(used)
                return messages
            }
            guard let chunk = try await stream.read(nil), !chunk.isEmpty else { return [] }
            pending += chunk
        }
    }
    func browse(_ request: UInt16, _ numbers: [UInt32]) async throws -> [[DJLinkExportDBServer.Argument]] {
        let header = try await self.request(request, numbers.map { .number($0) })
        #expect(header.first?.kind == kind.MENU_HEADER)
        guard case let .number(count) = try #require(header.first).arguments[1] else {
            throw DJLinkError("missing menu count")
        }
        var messages = try await self.request(
            kind.RENDER, [0x01010301, 0, count, 0, count, 0xc, 1, 0].map { .number($0) })
        var items: [[DJLinkExportDBServer.Argument]] = []
        while true {
            for message in messages {
                if message.kind == kind.MENU_FOOTER { return items }
                if message.kind == kind.MENU_ITEM { items.append(message.arguments) }
            }
            messages = try await receive()
            guard !messages.isEmpty else { throw DJLinkError("missing menu footer") }
        }
    }
}
@DJLinkActor final class FakePlayerRPC {
    var socket: any UDPSocket
    let factory: FakeExportSocketFactory
    var target: AddressInfo
    var xid: UInt32 = 1
    init(_ socket: any UDPSocket, _ target: AddressInfo, _ factory: FakeExportSocketFactory) {
        self.socket = socket
        self.target = target
        self.factory = factory
    }
    static func connect(_ target: AddressInfo, _ factory: FakeExportSocketFactory) async throws -> FakePlayerRPC {
        let socket = try factory.createUDPSocket(reuseAddr: false)
        _ = try await socket.bind(port: 0, address: "0.0.0.0")
        return FakePlayerRPC(socket, target, factory)
    }
    func call(_ program: UInt32, _ version: UInt32, _ procedure: UInt32, _ arguments: [UInt8]) async throws -> [UInt8] {
        xid &+= 1
        let credential = Xdr.Writer().u32(Rpc.CDJ_AUTH_STAMP).string("").u32(0).u32(0).u32(0).into_bytes()
        let wire = Rpc.Call(
            xid: xid, program: program, version: version, procedure: procedure,
            credential: Rpc.Auth(flavor: Rpc.AUTH_UNIX, body: credential), verifier: .null(), arguments: arguments
        ).encode()
        // 가짜 UDP 버스도 응답이 송신 호출 중 도착할 수 있으므로 수신을 먼저 건다.
        var reply: [UInt8]?
        let listener = socket.onMessage { bytes, _ in
            if let decoded = try? Rpc.Reply.decode(bytes), decoded.xid == self.xid { reply = bytes }
        }
        defer { socket.off(listener) }
        try await udpSend(socket, wire, target.port, target.address)
        let decoded = try Rpc.Reply.decode(#require(reply))
        #expect(decoded.is_success())
        return decoded.results
    }
    func port(_ program: UInt32, _ version: UInt32) async throws -> UInt16 {
        let result = try await call(
            PROGRAM_PORTMAP, VERSION_PORTMAP, portmap_proc.GETPORT,
            Xdr.Writer().u32(program).u32(version).u32(DJLinkExportNFS.IPPROTO_UDP).u32(0).into_bytes())
        return UInt16(try Xdr.Reader(result).u32())
    }
    func mount(_ export: String) async throws -> [UInt8] {
        let mountPort = try await port(PROGRAM_MOUNT, VERSION_MOUNT)
        let nfsPort = try await port(PROGRAM_NFS, VERSION_NFS)
        // 원본 mount는 portmap·mountd·NFS마다 새 UDP 클라이언트와 xid=1을 사용한다.
        let mountClient = try await Self.connect(AddressInfo(address: target.address, port: Int(mountPort)), factory)
        defer { try? mountClient.socket.close(nil) }
        let listed = try await mountClient.call(PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.EXPORT, [])
        let exports = Xdr.Reader(listed)
        var names: [String] = []
        while try exports.u32() == 1 {
            names.append(try exports.utf16())
            while try exports.u32() == 1 { try exports.skip_opaque() }
        }
        #expect(names.contains(export))
        let result = try await mountClient.call(
            PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.MNT, Xdr.Writer().utf16(export).into_bytes())
        let reader = Xdr.Reader(result)
        #expect(try reader.u32() == nfs_status.OK)
        let root = try reader.opaque_fixed(HANDLE_LEN)
        let nfsClient = try await Self.connect(AddressInfo(address: target.address, port: Int(nfsPort)), factory)
        try await udpClose(socket)
        socket = nfsClient.socket
        target = nfsClient.target
        xid = 1
        return root
    }
    func read_file(_ root: [UInt8], _ path: String) async throws -> [UInt8] {
        var at = root
        for name in path.split(separator: "/") {
            let result = try await call(
                PROGRAM_NFS, VERSION_NFS, nfs_proc.LOOKUP,
                Xdr.Writer().opaque_fixed(at).utf16(String(name)).into_bytes())
            let reader = Xdr.Reader(result)
            #expect(try reader.u32() == nfs_status.OK)
            at = try reader.opaque_fixed(HANDLE_LEN)
        }
        var out: [UInt8] = []
        while true {
            let result = try await call(
                PROGRAM_NFS, VERSION_NFS, nfs_proc.READ,
                Xdr.Writer().opaque_fixed(at).u32(UInt32(out.count)).u32(UInt32(MAX_READ)).u32(0).into_bytes())
            let reader = Xdr.Reader(result)
            #expect(try reader.u32() == nfs_status.OK)
            var size: UInt32 = 0
            for field in 0..<17 {
                let value = try reader.u32()
                if field == 5 { size = value }
            }
            let chunk = try reader.opaque()
            out += chunk
            if chunk.isEmpty || out.count >= Int(size) { return out }
        }
    }
}
