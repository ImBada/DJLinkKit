// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본 밖 회귀: 메모리 라이브러리 → 실제 서버 세션 → 기존 클라이언트의 레거시 큐 읽기.
import DJLinkExportDBServer
import DJLinkExportModel
import DJLinkExportTestSupport
import DJLinkKit
import DJLinkTestSupport
import Testing

@testable import DJLinkExport

@Suite @DJLinkActor struct LegacyCueClientTests {
    private func withClient(
        _ cues: [DJLinkExportModel.Cue],
        _ body: @DJLinkActor (QueryInterface) async throws -> Void
    ) async throws {
        let library = library_from([TestTrack(id: 10001, title: "Synthetic Cue Test", bpm_x100: 12000, cues: cues)])
        let source = StaticSource(library: library, share_root: "/nonexistent")
        let handler = CatalogHandler(IndexCatalog(source, Played()))
        let clock = TestClock()
        let factory = FakeExportSocketFactory(clock: clock)
        let bound = try await DJLinkExportDBServer.Net.Bound.start(
            handler, "127.0.0.1", 0, 0, socketFactory: factory, clock: clock)
        let socket = try factory.createTCPConnection()
        do {
            let target = bound.database_address()
            try await socket.connect(port: target.port, host: target.address)
            try await socket.write(RemoteDBUInt32(1).buffer)
            let greeting = try await readField(socket, .uint32)
            #expect((greeting as? RemoteDBUInt32)?.value == 1)
            try await socket.write(
                DJLinkKit.Message(transactionId: 0xfffffffe, type: .introduce, args: [RemoteDBUInt32(2)]).buffer)
            let introduced = try await DJLinkKit.Message.fromStream(socket, .success)
            #expect((introduced.args[1] as? RemoteDBUInt32)?.value == 17)
            let remote = Device(
                name: "rekordbox", id: 17, type: .rekordbox, macAddr: [UInt8](repeating: 0, count: 6),
                ip: try .init("127.0.0.1"))
            let host = Device(
                name: "CDJ-2000nexus", id: 2, type: .cdj, macAddr: [UInt8](repeating: 0, count: 6),
                ip: try .init("127.0.0.1"))
            let client = QueryInterface(
                conn: Connection(device: remote, socket: socket), lock: AsyncMutex(), hostDevice: host)
            try await body(client)
            socket.destroy(nil)
            await bound.shutdown()
        } catch {
            socket.destroy(error)
            await bound.shutdown()
            clock.advance(ms: 250)
            await clock.settle()
            throw error
        }
        clock.advance(ms: 250)
        await clock.settle()
    }
    @Test("기존 클라이언트가 메모리 큐·A/B/C·루프를 가짜 TCP에서 읽는다")
    func client_reads_indexed_cues_and_loops() async throws {
        let cues: [DJLinkExportModel.Cue] = [
            .init(id: 1, position_ms: 1000, kind: 0),
            .init(id: 2, position_ms: 2000, out_ms: 4000, kind: 4),
            .init(id: 3, position_ms: 5000, kind: 1, colour: 21),
            .init(id: 4, position_ms: 6000, out_ms: 8000, kind: 2, colour: 22),
            .init(id: 5, position_ms: 9000, kind: 3, colour: 23),
            .init(id: 6, position_ms: 12000, kind: 5),
        ]
        try await withClient(cues) { client in
            let descriptor = QueryDescriptor(menuTarget: .main, trackSlot: .rb, trackType: .rb)
            let result = try await client.query(
                queryDescriptor: descriptor, query: .getCueAndLoops, args: .init(trackId: 10001))
            // 레거시 경계는 메모리와 A/B/C를 내보내고 D 이후는 기존 어댑터처럼 제외한다.
            #expect(
                result
                    == .cueAndLoops([
                        .cuePoint(CuePoint(offset: 1000)), .loop(Loop(offset: 2000, length: 2000)),
                        .hotCue(Hotcue(offset: 5000, button: .A)),
                        .hotLoop(Hotloop(offset: 6000, button: .B, length: 2000)),
                        .hotCue(Hotcue(offset: 9000, button: .C)),
                    ]))
        }
    }
    @Test("빈 레거시 큐 응답을 기존 클라이언트가 대기 없이 해석한다")
    func client_reads_empty_and_missing_tracks() async throws {
        try await withClient([]) { client in
            let descriptor = QueryDescriptor(menuTarget: .main, trackSlot: .rb, trackType: .rb)
            for track in [10001, 0xdeadbeef] {
                let result = try await client.query(
                    queryDescriptor: descriptor, query: .getCueAndLoops, args: .init(trackId: track))
                #expect(result == .cueAndLoops([]))
            }
        }
    }
}
