import DJLinkExportTestSupport
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-dbserver/tests/corpus.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportDBServer

private func decode_stream(_ stream: [UInt8]) throws -> [Message] {
    #expect(stream.starts(with: GREETING))
    var at = GREETING.count
    var out: [Message] = []
    while at < stream.count {
        let (message, used) = try Message.decode(Array(stream[at...]))
        #expect(message.encode() == Array(stream[at..<(at + used)]))
        at += used
        out.append(message)
    }
    return out
}
private func player() throws -> [UInt8] {
    try UpstreamFixtures.bytes(crate: "rbl-dbserver", path: "tests/corpus/link-export.player.bin")
}
private func rekordbox() throws -> [UInt8] {
    try UpstreamFixtures.bytes(crate: "rbl-dbserver", path: "tests/corpus/link-export.rekordbox.bin")
}
@Suite struct CorpusTests {
    @Test("both_streams_decode_whole_and_re_encode_byte_for_byte")
    func both_streams_decode_whole_and_re_encode_byte_for_byte() throws {
        let requests = try decode_stream(player())
        let replies = try decode_stream(rekordbox())
        #expect(requests.count == 97)
        #expect(replies.count == 388)
    }
    @Test("every_request_is_answered_on_its_own_transaction") func every_request_is_answered_on_its_own_transaction()
        throws
    {
        let requests = try decode_stream(player())
        let decoded = try decode_stream(rekordbox())
        var replies: [UInt32: [Message]] = [:]
        for reply in decoded { replies[reply.transaction, default: []].append(reply) }
        for request in requests {
            let answers = try #require(replies[request.transaction])
            switch request.kind {
            case kind.SETUP: #expect(answers[0].kind == kind.SETUP)
            case kind.RENDER:
                #expect(answers[0].kind == kind.RENDER_HEADER)
                #expect(answers.last?.kind == kind.MENU_FOOTER)
                #expect(answers[1..<(answers.count - 1)].allSatisfy { $0.kind == kind.MENU_ITEM })
            case let k where k >> 12 == 2 && k != kind.METADATA && k != kind.TRACK_INFO:
                #expect(answers.count == 1)
                #expect(answers[0].arguments[0] == .number(UInt32(k)))
            default: #expect(answers[0].kind == kind.MENU_HEADER)
            }
        }
    }
    @Test("a_menu_item_carries_sixteen_arguments") func a_menu_item_carries_sixteen_arguments() throws {
        let items = try decode_stream(rekordbox()).filter { $0.kind == kind.MENU_ITEM }
        #expect(!items.isEmpty)
        for item in items {
            #expect(item.arguments.count == 16)
            for at in [3, 5, 14] { if case .string = item.arguments[at] {} else { Issue.record("String argument") } }
        }
    }
}
