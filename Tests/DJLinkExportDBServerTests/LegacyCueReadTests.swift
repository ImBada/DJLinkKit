// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본 밖 회귀: #20, 공개 클라이언트의 0x2104/0x4702 계약과 관측된 CDJ 요청.
import DJLinkKit
import Testing

@testable import DJLinkExportDBServer

private typealias Message = DJLinkExportDBServer.Message
private typealias Query = DJLinkExportDBServer.Query
private enum CueReadFixtureError: Error { case notBlob }

@DJLinkActor private final class CueReadCatalog: Catalog {
    var values: [UInt32: [UsbCue]] = [:]
    var reads: [UInt32] = []
    var edits: [Edit] = []
    func list(_ query: Query) -> [Row] { [] }
    func track_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? { nil }
    func track(_ id: UInt32) -> TrackDetails? { nil }
    func artwork(_ id: UInt32) -> [UInt8]? { nil }
    func item_artwork(_ id: UInt32) -> [UInt8]? { nil }
    func analysis(_ id: UInt32, _ what: Analysis) -> [UInt8]? { nil }
    func usb_cues(_ id: UInt32) -> [UsbCue] {
        reads.append(id)
        return values[id] ?? []
    }
    func edit(_ edit: Edit) -> Bool {
        edits.append(edit)
        return false
    }
}
@Suite @DJLinkActor struct LegacyCueReadTests {
    private let context: UInt32 = 0x02080401
    private let track: UInt32 = 10001
    private func request(_ id: UInt32, transaction: UInt32 = 0x12345678) -> Message {
        .new(transaction, kind.CUES, [.number(context), .number(id)])
    }
    private func wireReply(_ replies: [Message]) throws -> Message {
        #expect(replies.count == 1)
        let original = try #require(replies.first)
        let bytes = original.encode()
        let (decoded, used) = try Message.decode(bytes)
        #expect(used == bytes.count)
        #expect(decoded.arguments.count == 11)
        return decoded
    }
    private func blob(_ reply: Message, _ index: Int) throws -> [UInt8] {
        guard case let .blob(bytes) = reply.arguments[index] else { throw CueReadFixtureError.notBlob }
        return bytes
    }
    @Test("레거시 큐 읽기가 메모리와 A·B·C 및 루프의 개수와 레코드를 반환한다")
    func reads_memory_hot_cues_and_loops() throws {
        let catalog = CueReadCatalog()
        catalog.values[track] = [
            UsbCue(slot: 0, in_ms: 1000), UsbCue(slot: 0, in_ms: 2000, out_ms: 4000),
            UsbCue(slot: 1, in_ms: 5000, color_table_index: 21),
            UsbCue(slot: 2, in_ms: 6000, out_ms: 8000, color_table_index: 22),
            UsbCue(slot: 3, in_ms: 9000, color_table_index: 23),
        ]
        var unsupported: [UInt16] = []
        let session = CatalogHandler(catalog).with_unsupported_command_reporter { _, command, _ in
            unsupported.append(command)
        }.open()
        _ = session.handle(.new(0xfffffffe, kind.SETUP, [.number(2)]))
        let reply = try wireReply(session.handle(request(track)))
        #expect(reply.transaction == 0x12345678)
        #expect(reply.kind == 0x4702)
        #expect(reply.arguments[0] == .number(0x2104))
        #expect(reply.arguments[1] == .number(0))
        #expect(reply.arguments[2] == .number(180))
        #expect(reply.arguments[4] == .number(36))
        #expect(reply.arguments[5] == .number(3))
        #expect(reply.arguments[6] == .number(2))
        #expect(reply.arguments[7] == .number(40))
        #expect(reply.arguments[9] == .number(0))
        #expect(reply.arguments[10] == .blob([]))
        let records = try blob(reply, 3)
        let sidecars = try blob(reply, 8)
        #expect(records.count == 180)
        #expect(sidecars.count == 40)
        let flags: [UInt32] = [0x100, 0x101, 0x10100, 0x20101, 0x30100]
        let frames: [UInt32] = [150, 300, 750, 900, 1350]
        for i in 0..<5 {
            #expect(try records.readUInt32LE(i * 36) == Int(flags[i]))
            #expect(try records.readUInt32LE(i * 36 + 12) == Int(frames[i]))
        }
        #expect(try records.readUInt32LE(36 + 16) == 600)
        #expect(try records.readUInt32LE(3 * 36 + 16) == 1200)
        #expect(try records.readUInt32LE(4 * 36 + 24) == 23)
        #expect(try sidecars.readUInt32LE(8) == 2000)
        #expect(try sidecars.readUInt32LE(12) == 4000)
        #expect(catalog.reads == [track])
        #expect(catalog.edits.isEmpty)
        #expect(unsupported.isEmpty)
    }
    @Test("시간순으로 섞인 메모리 큐와 핫큐도 메모리 큐를 앞에, 핫큐를 뒤에 보낸다")
    func orders_memory_cues_before_hot_cues() throws {
        // CDJ-2000nexus 실기(2026-10-15): 시간순으로 섞어 보내면 앞의 memory 개수만큼을 메모리 큐로 읽어
        // Hot Cue A가 메모리 목록에 들어가 A 버튼이 꺼지고, CALL ▶가 A로 이동했다.
        let catalog = CueReadCatalog()
        catalog.values[track] = [
            UsbCue(slot: 0, in_ms: 0), UsbCue(slot: 1, in_ms: 5000, color_table_index: 21),
            UsbCue(slot: 0, in_ms: 10000), UsbCue(slot: 2, in_ms: 15000, color_table_index: 22),
            UsbCue(slot: 0, in_ms: 20000, out_ms: 24000),
            UsbCue(slot: 3, in_ms: 30000, out_ms: 34000, color_table_index: 23),
        ]
        let session = CatalogHandler(catalog).open()
        _ = session.handle(.new(0xfffffffe, kind.SETUP, [.number(2)]))
        let reply = try wireReply(session.handle(request(track)))
        #expect(reply.arguments[5] == .number(3))
        #expect(reply.arguments[6] == .number(3))
        let records = try blob(reply, 3)
        let sidecars = try blob(reply, 8)
        #expect(records.count == 216)
        // 앞 3개는 메모리(버튼 0), 뒤 3개는 A·B·C(버튼 1~3). 각 그룹 안은 시간순이다.
        let buttons = try (0..<6).map { try records.readUInt32LE($0 * 36) >> 16 }
        #expect(buttons == [0, 0, 0, 1, 2, 3])
        let positions = try (0..<6).map { try sidecars.readUInt32LE($0 * 8) }
        #expect(positions == [0, 10000, 20000, 5000, 15000, 30000])
        #expect(catalog.edits.isEmpty)
    }
    @Test("빈 목록과 알 수 없는 곡도 빈 큐 응답으로 왕복한다")
    func empty_and_unknown_tracks_are_empty() throws {
        let catalog = CueReadCatalog()
        let session = LinkSession(catalog)
        catalog.values[track] = []
        for id: UInt32 in [track, 0xdeadbeef] {
            let reply = try wireReply(session.handle(request(id)))
            #expect(reply.kind == kind.CUES_REPLY)
            #expect(
                reply.arguments == [
                    .number(0x2104), .number(0), .number(0), .blob([]), .number(36), .number(0), .number(0), .number(0),
                    .blob([]), .number(0), .blob([]),
                ])
        }
        #expect(catalog.reads == [track, 0xdeadbeef])
        #expect(catalog.edits.isEmpty)
    }
    @Test("반복 조회가 요청한 곡 ID와 트랜잭션을 구분한다")
    func keeps_track_and_transaction_identity() throws {
        let catalog = CueReadCatalog()
        let session = LinkSession(catalog)
        catalog.values[10001] = [UsbCue(in_ms: 1000)]
        catalog.values[10002] = [UsbCue(in_ms: 9000)]
        for (tx, id, frames): (UInt32, UInt32, Int) in [(7, 10001, 150), (8, 10002, 1350), (9, 10001, 150)] {
            let reply = try wireReply(session.handle(request(id, transaction: tx)))
            #expect(reply.transaction == tx)
            #expect(try blob(reply, 3).readUInt32LE(12) == frames)
        }
        #expect(catalog.reads == [10001, 10002, 10001])
        #expect(catalog.edits.isEmpty)
    }
    @Test("잘못된 조회 인자는 읽기나 편집 없이 사용 불가 응답을 보낸다")
    func rejects_malformed_read_arguments() throws {
        let catalog = CueReadCatalog()
        let session = LinkSession(catalog)
        let cases: [[Argument]] = [
            [], [.number(context)], [.string("context"), .number(track)], [.number(context), .string("track")],
            [.number(context), .blob([])],
        ]
        for args in cases {
            let reply = try wireReply(session.handle(.new(99, kind.CUES, args)))
            #expect(reply.transaction == 99)
            #expect(reply.kind == kind.CUES_REPLY)
            #expect(reply.arguments[0] == .number(0x2104))
            #expect(reply.arguments[1] == .number(0x32))
            #expect(try blob(reply, 3).isEmpty)
        }
        #expect(catalog.reads.isEmpty)
        #expect(catalog.edits.isEmpty)
    }
    @Test("프레임 반올림과 별개로 sidecar가 밀리초 위치를 보존한다")
    func preserves_millisecond_sidecar() throws {
        let catalog = CueReadCatalog()
        let session = LinkSession(catalog)
        catalog.values[track] = [UsbCue(slot: 3, in_ms: 1001, out_ms: 2002, color_table_index: 21)]
        let reply = try wireReply(session.handle(request(track)))
        let record = try blob(reply, 3)
        let sidecar = try blob(reply, 8)
        #expect(try record.readUInt32LE(12) == 150)
        #expect(try record.readUInt32LE(16) == 300)
        #expect(try sidecar.readUInt32LE(0) == 1001)
        #expect(try sidecar.readUInt32LE(4) == 2002)
        #expect(reply.arguments[5] == .number(1))
        #expect(reply.arguments[6] == .number(0))
    }
}
