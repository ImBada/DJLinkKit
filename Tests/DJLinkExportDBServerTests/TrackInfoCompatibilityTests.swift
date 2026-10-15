// SPDX-License-Identifier: GPL-2.0-or-later
// 원본에 없는 실기 회귀: CDJ-2000nexus의 0x2102/0x3000 왕복과 합성 음원 비교(2026-10-15).
import DJLinkKit
import Testing

@testable import DJLinkExportDBServer

private typealias Message = DJLinkExportDBServer.Message
private typealias Query = DJLinkExportDBServer.Query

@DJLinkActor private final class FormatCatalog: Catalog {
    let value: TrackDetails
    init(_ type: UInt32, _ suffix: String) {
        value = TrackDetails(
            row: TrackRow(id: 10003, title: "Synthetic Signal", bpm_x100: 12000), duration_s: 60,
            path: "/tmp/DJLinkKit-Live/Audio/Synthetic Signal." + suffix, file_size: 10584078, file_type: type)
    }
    func list(_ query: Query) -> [Row] { [] }
    func track_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? { id == 10003 ? value.row : nil }
    func track(_ id: UInt32) -> TrackDetails? { id == 10003 ? value : nil }
    func artwork(_ id: UInt32) -> [UInt8]? { nil }
    func item_artwork(_ id: UInt32) -> [UInt8]? { nil }
    func analysis(_ id: UInt32, _ what: Analysis) -> [UInt8]? { nil }
}
@Suite @DJLinkActor struct TrackInfoCompatibilityTests {
    private func render(_ type: UInt32, _ suffix: String) throws -> [Message] {
        let session = LinkSession(FormatCatalog(type, suffix))
        // 실물 CDJ의 인자 하나짜리 소개와 menu=8/slot=4 문맥을 그대로 쓴다.
        _ = session.handle(Message.new(0xfffffffe, kind.SETUP, [.number(2)]))
        _ = session.handle(Message.new(1, kind.TRACK_INFO, [.number(0x02080401), .number(10003)]))
        let replies = session.handle(Message.new(2, kind.RENDER, [0x02080401, 0, 7, 0, 7, 0].map { .number($0) }))
        return try replies.map { try Message.decode($0.encode()).0 }
    }
    @Test("WAV 곡 정보가 실기에서 확인한 형식 ID를 보낸다")
    func wav_track_info_selects_pcm_decoder() throws {
        let replies = try render(11, "wav")
        let items = replies.filter { $0.kind == kind.MENU_ITEM }
        #expect(items.count == 7)
        // 이 첫 항목의 id만 1→11로 바꾸자 실물의 NFS 읽기가 RIFF/PCM 경로로 전환됐다.
        #expect(
            items[0].arguments == [
                .number(1), .number(11), .number(2), .string(""), .number(2), .string(""), .number(4), .number(0),
                .number(0), .number(0), .number(0x100), .number(0),
            ])
        #expect(items[4].arguments[1] == .number(10003))
        #expect(items[4].arguments[3] == .string("/tmp/DJLinkKit-Live/Audio/Synthetic Signal.wav"))
        #expect(replies.last?.kind == kind.MENU_FOOTER)
    }
    @Test("MP3 곡 정보와 형식 미지정 입력의 기존 값이 유지된다")
    func mp3_and_unspecified_track_info_preserve_decoder() throws {
        for type: UInt32 in [0, 1] {
            let items = try render(type, "mp3").filter { $0.kind == kind.MENU_ITEM }
            #expect(
                items[0].arguments == [
                    .number(1), .number(1), .number(2), .string(""), .number(2), .string(""), .number(4), .number(0),
                    .number(0), .number(0), .number(0x100), .number(0),
                ])
            #expect(items[4].arguments[1] == .number(10003))
        }
    }
}
