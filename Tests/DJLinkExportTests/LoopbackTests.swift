// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbl-fakecdj/tests/loopback.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
//
// 링크 프로토콜을 끝까지 시험한다: 실제 소켓, 우리 서버, 우리 가짜 플레이어.
// 모두 127.0.0.1의 임시 포트에 묶는다. 이 파일의 시험 8개는 실제 소켓을 여므로 DJLINK_LOOPBACK_TESTS=1
// (scripts/ci.sh --loopback)일 때만 실행하고, 기본 실행에서는 건너뛴다.
import DJLinkExportDBServer
import DJLinkExportNFS
import DJLinkExportSupport
import DJLinkKit
import Foundation
import Testing

private typealias NfsBound = DJLinkExportNFS.Net.Bound
private typealias DbBound = DJLinkExportDBServer.Net.Bound

private let LOOPBACK = "127.0.0.1"

/// 서버가 여는 실제 소켓 공장. 시험 프로세스에서는 Export 전송의 차단이 먼저 걸린다(ExportSockets.swift).
@DJLinkActor
private func serverFactory() -> any ExportSocketFactory { LiveExportSocketFactory.shared }

/// 가짜 플레이어가 여는 실제 소켓 공장. DJLinkKit의 것이라 DJLINK_LOOPBACK_TESTS=1일 때만 열린다.
@DJLinkActor
private func clientFactory() -> any SocketFactory { LiveSocketFactory.shared }

private final class TempDir {
    let path: String
    init() throws {
        path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
    func join(_ name: String) -> String { path + "/" + name }
    deinit { try? FileManager.default.removeItem(atPath: path) }
}

private func writeFile(_ path: String, _ bytes: [UInt8]) throws {
    try Data(bytes).write(to: URL(fileURLWithPath: path))
}

/// 조각 경계의 off-by-one이 드러나도록 내용을 채운, 여러 번 읽어야 할 만큼 큰 곡.
private func trackBytes() -> [UInt8] { (0..<40_000).map { UInt8($0 % 251) } }

/// 실제 파일 둘, 깊은 경로 하나, 아무것도 없는 디렉터리 하나.
private func exports(_ dir: TempDir) throws -> Exports {
    let track = trackBytes()
    try writeFile(dir.join("track.mp3"), track)
    try writeFile(dir.join("export.pdb"), Array("PDB0".utf8))

    let vfs = Vfs("/")
    vfs.add_file("Contents/ARTBAT/The Abyss.mp3", dir.join("track.mp3"), UInt64(track.count), 1_700_000_000)
    vfs.add_file("PIONEER/rekordbox/export.pdb", dir.join("export.pdb"), 4, 1_700_000_001)
    vfs.add_dir("PIONEER/USBANLZ")

    let exports = Exports()
    exports.insert(vfs)
    return exports
}

/// 메뉴 요청에 머리글, 행 몇 개, 바닥글로 답하는 핸들러.
///
/// 행의 내용은 진짜 메뉴가 아니라 우리 것이다. 이 시험이 증명하는 것은 전송이다: 프레이밍, 한 응답에 든 여러
/// 메시지, 재조립. 진짜 메뉴는 DJLinkExportDBServer의 session이며 캡처로 시험한다.
@DJLinkActor
private final class MenuRows {
    let rows: [String]
    // 원본의 AtomicUsize. 직렬 DJLinkActor 위에서만 읽고 쓰므로 일반 정수로 둔다.
    var seen = 0
    init(_ rows: [String]) { self.rows = rows }
}

@DJLinkActor
private final class Menu: DJLinkExportDBServer.Handler {
    let shared: MenuRows
    init(_ shared: MenuRows) { self.shared = shared }
    func open() -> any DJLinkExportDBServer.Session { MenuSession(shared) }
}

@DJLinkActor
private final class MenuSession: DJLinkExportDBServer.Session {
    let shared: MenuRows
    init(_ shared: MenuRows) { self.shared = shared }
    func handle(_ message: DJLinkExportDBServer.Message) -> [DJLinkExportDBServer.Message] {
        shared.seen += 1
        switch message.kind {
        case kind.SETUP:
            return [setup_reply(message.transaction, 0x11)]
        case kind.RENDER:
            var out = [menu_header(message.transaction, UInt32(kind.RENDER), UInt32(shared.rows.count))]
            for (index, row) in shared.rows.enumerated() {
                out.append(.new(message.transaction, kind.MENU_ITEM, [.number(UInt32(index)), .string(row)]))
            }
            out.append(menu_footer(message.transaction))
            return out
        default:
            return [.new(message.transaction, kind.ERROR, [.number(0)])]
        }
    }
}

@Suite("rbl-fakecdj loopback", .serialized, .enabled(if: TestProcess.loopbackTestsEnabled))
@DJLinkActor struct LoopbackTests {
    private func menu_server(_ rows: [String]) async throws -> (MenuRows, DbBound) {
        let shared = MenuRows(rows)
        let handler: any DJLinkExportDBServer.Handler = Menu(shared)
        let bound = try await DbBound.start(handler, LOOPBACK, 0, 0, socketFactory: serverFactory())
        return (shared, bound)
    }

    @Test("a_player_mounts_browses_and_fetches_a_whole_track") func mountsBrowsesAndFetches() async throws {
        let dir = try TempDir()
        let track = trackBytes()
        let offered = try exports(dir)
        let bound = try await NfsBound.start(offered, LOOPBACK, 0, 0, 0, nil, nil, socketFactory: serverFactory())

        let mounted = try await FakeCdj.mount(bound.portmap_address(), "/", clientFactory())
        defer { mounted.close() }

        // 트리는 우리가 내보낸 그대로, 순서도 같다.
        let root = mounted.root()
        #expect(try await mounted.list(root) == ["Contents", "PIONEER"])
        let pioneer = try await mounted.lookup(root, "PIONEER")
        #expect(try await mounted.list(pioneer) == ["rekordbox", "USBANLZ"])

        // 곡 전체가 여러 번의 읽기를 거쳐 바이트 단위로 같게 돌아온다.
        let fetched = try await mounted.read_file("Contents/ARTBAT/The Abyss.mp3")
        #expect(fetched.count == track.count)
        #expect(fetched == track)

        #expect(try await mounted.read_file("PIONEER/rekordbox/export.pdb") == Array("PDB0".utf8))

        await bound.shutdown()
    }

    @Test("a_player_cannot_reach_outside_the_export_over_the_wire") func cannotReachOutside() async throws {
        let dir = try TempDir()
        let offered = try exports(dir)
        let bound = try await NfsBound.start(offered, LOOPBACK, 0, 0, 0, nil, nil, socketFactory: serverFactory())
        let mounted = try await FakeCdj.mount(bound.portmap_address(), "/", clientFactory())
        defer { mounted.close() }
        let root = mounted.root()

        for name in ["..", "../..", "/etc", "etc"] {
            do {
                let handle = try await mounted.lookup(root, name)
                // 루트의 `..`는 루트로 풀리며, 이것은 탈출이 아니다.
                #expect(handle == root, "\(name) must not leave the export")
            } catch FakeCdj.CdjError.nfs(let status) {
                #expect(status == nfs_status.NOENT, "\(name)")
            } catch {
                Issue.record("\(name): \(error)")
            }
        }

        // 그리고 디렉터리는 파일로 읽을 수 없다.
        var notAFile = false
        do {
            _ = try await mounted.read_file("Contents")
        } catch FakeCdj.CdjError.notAFile(_) {
            notAFile = true
        } catch {
            Issue.record("Contents: \(error)")
        }
        #expect(notAFile)

        await bound.shutdown()
    }

    @Test("mounting_an_export_that_is_not_offered_fails_before_any_lookup") func mountingMissingExport() async throws {
        let dir = try TempDir()
        let offered = try exports(dir)
        let bound = try await NfsBound.start(offered, LOOPBACK, 0, 0, 0, nil, nil, socketFactory: serverFactory())
        var noExport = false
        do {
            let mounted = try await FakeCdj.mount(bound.portmap_address(), "/C/", clientFactory())
            mounted.close()
        } catch FakeCdj.CdjError.noExport(_) {
            noExport = true
        } catch {
            Issue.record("/C/: \(error)")
        }
        #expect(noExport)
        await bound.shutdown()
    }

    @Test("a_player_finds_the_database_port_then_browses_a_menu") func findsDatabasePortThenBrowses() async throws {
        let rows = (0..<40).map { String(format: "Playlist %02d", $0) }
        let (handler, bound) = try await menu_server(rows)

        // 포트 질의는 진짜 장비처럼 별도 서비스다.
        let port = try await FakeCdj.database_port(bound.query_address(), clientFactory())
        #expect(port == UInt16(bound.database_address().port))

        let session = try await FakeCdj.Database.connect(
            AddressInfo(address: LOOPBACK, port: Int(port)), 2, clientFactory())
        defer { session.close() }

        // 메뉴 전체가 여러 메시지로 오고 순서대로 재조립된다.
        var received = try await session.request(kind.RENDER, [.number(0)])
        while received.count < rows.count + 2 {
            let more = try await session.receive()
            try #require(!more.isEmpty, "the server stopped mid-menu")
            received += more
        }

        #expect(received.count == rows.count + 2)
        #expect(received.first?.kind == kind.MENU_HEADER)
        #expect(received.last?.kind == kind.MENU_FOOTER)

        let names: [String] =
            received
            .filter { $0.kind == kind.MENU_ITEM }
            .compactMap { message -> String? in
                if message.arguments.count > 1, case let .string(name) = message.arguments[1] { return name }
                return nil
            }
        #expect(names == rows)

        // setup과 render: 보낸 메시지는 모두 해석됐고, 두 번 해석된 것은 없다.
        #expect(handler.seen == 2)

        await bound.shutdown()
    }

    @Test("a_menu_row_with_non_ascii_text_survives_the_wire") func nonAsciiRowSurvives() async throws {
        let rows = ["Björk", "とんかつ", "🎧 Set"]
        let (_, bound) = try await menu_server(rows)
        let port = try await FakeCdj.database_port(bound.query_address(), clientFactory())
        let session = try await FakeCdj.Database.connect(
            AddressInfo(address: LOOPBACK, port: Int(port)), 1, clientFactory())
        defer { session.close() }

        var received = try await session.request(kind.RENDER, [])
        while received.count < rows.count + 2 {
            // 원본과 다름: 서버가 끊어 빈 응답만 오면 원본은 끝없이 돈다. 여기서는 실패로 끝낸다.
            let more = try await session.receive()
            try #require(!more.isEmpty, "the server stopped mid-menu")
            received += more
        }
        let names: [String] = received.compactMap { message -> String? in
            if message.arguments.count > 1, case let .string(name) = message.arguments[1] { return name }
            return nil
        }
        #expect(names == rows)

        await bound.shutdown()
    }

    @Test("two_players_are_served_at_the_same_time") func twoPlayersAtOnce() async throws {
        let (_, bound) = try await menu_server(["One"])
        let port = try await FakeCdj.database_port(bound.query_address(), clientFactory())
        let address = AddressInfo(address: LOOPBACK, port: Int(port))

        let first = try await FakeCdj.Database.connect(address, 1, clientFactory())
        defer { first.close() }
        let second = try await FakeCdj.Database.connect(address, 2, clientFactory())
        defer { second.close() }

        // 번갈아 요청한다. 세션을 직렬로 처리하는 서버라면 여기서 멈춘다.
        let a = try await first.request(kind.RENDER, [])
        let b = try await second.request(kind.RENDER, [])
        #expect(!a.isEmpty)
        #expect(!b.isEmpty)

        await bound.shutdown()
    }

    @Test("an_unknown_request_is_answered_with_an_error_not_silence") func unknownRequestGetsError() async throws {
        let (_, bound) = try await menu_server([])
        let port = try await FakeCdj.database_port(bound.query_address(), clientFactory())
        let session = try await FakeCdj.Database.connect(
            AddressInfo(address: LOOPBACK, port: Int(port)), 1, clientFactory())
        defer { session.close() }

        let received = try await session.request(kind.ARTWORK, [.number(1)])
        #expect(received.first?.kind == kind.ERROR)

        await bound.shutdown()
    }

    @Test("the_servers_stop_cleanly_and_release_their_ports") func serversReleasePorts() async throws {
        let dir = try TempDir()
        let offered = try exports(dir)
        let nfs = try await NfsBound.start(offered, LOOPBACK, 0, 0, 0, nil, nil, socketFactory: serverFactory())
        let addresses = [nfs.portmap_address(), nfs.mount_address(), nfs.nfs_address()]
        await nfs.shutdown()

        // 같은 포트에 다시 묶이면 소켓이 정말 풀렸다는 증거다.
        for address in addresses {
            let socket = try clientFactory().createUDPSocket(reuseAddr: false)
            do {
                _ = try await socket.bind(port: address.port, address: address.address)
            } catch {
                Issue.record("\(address.address):\(address.port) was not released: \(error)")
            }
            try? socket.close()
        }

        let (_, db) = try await menu_server([])
        let query = db.query_address()
        let database = db.database_address()
        await db.shutdown()
        for address in [query, database] {
            let listener = try serverFactory().createTCPListener()
            do {
                try await listener.bind(port: address.port, address: address.address)
            } catch {
                Issue.record("\(address.address):\(address.port) was not released: \(error)")
            }
            try? await listener.shutdown()
        }
    }
}
