// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-dbserver/tests/messages.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportDBServer

private let HEADER_LEN = 20
private let CAPTURED_SETUP = "11872349ae11fffffffe1000000f021400000002060611000000011100000014"
private let CAPTURED_SETUP_REPLY = "11872349ae11fffffffe1000000f021400000002060611000000111100000014"
private let CAPTURED_ROOT_MENU = "11872349ae110000017f1010000f031400000003060606110101030111000000001105cfffff"
private let CAPTURED_NO_ARTWORK = "11872349ae11000001871040020f04140000000406060603110000200311000000321100000000"
private func hex(_ s: String) -> [UInt8] {
    stride(from: 0, to: s.count, by: 2).map {
        let a = s.index(s.startIndex, offsetBy: $0)
        let b = s.index(a, offsetBy: 2)
        return UInt8(s[a..<b], radix: 16)!
    }
}
private func header_declaring(_ k: UInt16, _ tags: [UInt8]) -> [UInt8] {
    var b = Message.new(1, k, []).encode()
    b[14] = UInt8(tags.count)
    b.replaceSubrange(16..<20, with: dbBE(UInt32(tags.count)))
    b += tags
    return b
}
private func error(_ b: [UInt8]) -> DbError? {
    do {
        _ = try Message.decode(b)
        return nil
    } catch { return error as? DbError }
}
private func truncated(_ b: [UInt8]) -> Bool {
    if case .truncated? = error(b) { return true }
    return false
}
private func no_messages(_ b: [UInt8]) -> Bool {
    let (m, n) = Message.decode_all(b)
    return m.isEmpty && n == 0
}
@Suite struct MessagesTests {
    @Test("header_layout_is_exact") func header_layout_is_exact() {
        let bytes = Message.new(0x1234_5678, kind.ROOT_MENU, []).encode()
        #expect(bytes.count == HEADER_LEN)
        #expect(bytes[0] == 0x11)
        #expect(Array(bytes[1..<5]) == dbBE(MAGIC))
        #expect(bytes[5] == 0x11)
        #expect(Array(bytes[6..<10]) == dbBE(UInt32(0x1234_5678)))
        #expect(bytes[10] == 0x10)
        #expect(Array(bytes[11..<13]) == dbBE(kind.ROOT_MENU))
        #expect(bytes[13] == 0x0f)
        #expect(bytes[14] == 0)
        #expect(bytes[15] == 0x14)
        #expect(Array(bytes[16..<20]) == dbBE(UInt32(0)))
    }
    @Test("the_captured_setup_exchange_decodes_and_re_encodes_byte_for_byte")
    func the_captured_setup_exchange_decodes_and_re_encodes_byte_for_byte() throws {
        let (setup, used) = try Message.decode(hex(CAPTURED_SETUP))
        #expect(used == hex(CAPTURED_SETUP).count)
        #expect(setup == setup_request(1))
        #expect(setup.encode() == hex(CAPTURED_SETUP))
        let (reply, _) = try Message.decode(hex(CAPTURED_SETUP_REPLY))
        #expect(reply == setup_reply(SETUP_TXID, 0x11))
        #expect(reply.encode() == hex(CAPTURED_SETUP_REPLY))
    }
    @Test("the_captured_root_menu_request_decodes_and_re_encodes_byte_for_byte")
    func the_captured_root_menu_request_decodes_and_re_encodes_byte_for_byte() throws {
        let (request, used) = try Message.decode(hex(CAPTURED_ROOT_MENU))
        #expect(used == hex(CAPTURED_ROOT_MENU).count)
        #expect(request.transaction == 0x17f)
        #expect(request.kind == kind.ROOT_MENU)
        #expect(request.arguments == [.number(0x0101_0301), .number(0), .number(0x05cf_ffff)])
        #expect(request.encode() == hex(CAPTURED_ROOT_MENU))
    }
    @Test("an_empty_trailing_blob_is_absent_on_the_wire_and_present_when_decoded")
    func an_empty_trailing_blob_is_absent_on_the_wire_and_present_when_decoded() throws {
        let bytes = hex(CAPTURED_NO_ARTWORK)
        let (reply, used) = try Message.decode(bytes)
        #expect(used == bytes.count)
        #expect(reply.arguments == [.number(0x2003), .number(0x32), .number(0), .blob([])])
        #expect(reply.encode() == bytes)
        let two = bytes + bytes
        let (messages, consumed) = Message.decode_all(two)
        #expect(messages.count == 2)
        #expect(consumed == two.count)
    }
    @Test("argument_tags_differ_between_the_header_list_and_the_value")
    func argument_tags_differ_between_the_header_list_and_the_value() {
        let bytes = Message.new(7, kind.SEARCH, [.string("a"), .blob([9]), .number(5)]).encode()
        #expect(bytes[14] == 3)
        #expect(Array(bytes[16..<20]) == dbBE(UInt32(3)))
        #expect(Array(bytes[20..<23]) == [2, 3, 6])
        #expect(bytes[HEADER_LEN + 3] == 0x26)
    }
    @Test("round_trips_every_argument_kind") func round_trips_every_argument_kind() throws {
        let message = Message.new(
            42, kind.METADATA,
            [.number(0x0102_0304), .string("Take Me Home"), .blob([0, 1, 2, 253, 254, 255]), .string("")])
        let bytes = message.encode()
        let (back, used) = try Message.decode(bytes)
        #expect(back == message)
        #expect(used == bytes.count)
    }
    @Test("strings_are_utf16be_with_a_trailing_nul_counted_in_the_length")
    func strings_are_utf16be_with_a_trailing_nul_counted_in_the_length() {
        let bytes = Message.new(1, kind.SEARCH, [.string("Hi")]).encode()
        let field = Array(bytes[(HEADER_LEN + 1)...])
        #expect(field[0] == 0x26)
        #expect(Array(field[1..<5]) == dbBE(UInt32(3)))
        #expect(Array(field[5..<11]) == [0, 72, 0, 105, 0, 0])
    }
    @Test("non_ascii_survives_the_utf16_round_trip") func non_ascii_survives_the_utf16_round_trip() throws {
        for text in ["Björk", "とんかつ", "Ø", "emoji 🎧 here"] {
            let message = Message.new(1, kind.SEARCH, [.string(text)])
            let (back, _) = try Message.decode(message.encode())
            #expect(back == message)
        }
    }
    @Test("decodes_the_narrow_number_tags_a_player_may_send") func decodes_the_narrow_number_tags_a_player_may_send()
        throws
    {
        let bytes = header_declaring(kind.RENDER, [6, 6]) + [0x0f, 0x7b, 0x10, 1, 0]
        let (message, used) = try Message.decode(bytes)
        #expect(message.arguments == [.number(123), .number(256)])
        #expect(used == bytes.count)
    }
    @Test("several_messages_in_one_segment_are_all_decoded") func several_messages_in_one_segment_are_all_decoded() {
        let sent = [
            menu_header(3, 0x1105, 128), Message.new(3, kind.MENU_ITEM, [.string("Melodic Vox")]), menu_footer(3),
        ]
        let wire = sent.flatMap { $0.encode() }
        let (got, used) = Message.decode_all(wire)
        #expect(got == sent)
        #expect(used == wire.count)
    }
    @Test("the_extended_menu_footer_has_no_arguments") func the_extended_menu_footer_has_no_arguments() throws {
        let footer = menu_footer(3)
        #expect(footer.kind == kind.MENU_FOOTER)
        #expect(footer.arguments.isEmpty)
        #expect(try Message.decode(footer.encode()).0 == footer)
    }
    @Test("a_message_split_across_segments_is_left_for_the_next_read")
    func a_message_split_across_segments_is_left_for_the_next_read() {
        let whole = Message.new(9, kind.MENU_ITEM, [.string("Tech House")])
        let wire = menu_header(9, 0x1105, 1).encode() + whole.encode()
        let first = menu_header(9, 0x1105, 1).encode().count
        for cut in (first + 1)..<wire.count {
            let (got, used) = Message.decode_all(Array(wire[..<cut]))
            #expect(got.count == 1)
            #expect(used == first)
            #expect(Message.decode_all(Array(wire[used...])).0 == [whole])
        }
    }
    @Test("truncation_is_an_error_rather_than_a_panic") func truncation_is_an_error_rather_than_a_panic() {
        let bytes = Message.new(1, kind.METADATA, [.string("Angels")]).encode()
        for cut in 0..<bytes.count { #expect(truncated(Array(bytes[..<cut]))) }
    }
    @Test("malformed_unsupported_requests_are_not_decoded_as_dispatchable_commands")
    func malformed_unsupported_requests_are_not_decoded_as_dispatchable_commands() {
        let wire = hex("11872349ae1100008123102fff0f021400000002060611010103011100000000")
        for cut in 0..<wire.count {
            let b = Array(wire[..<cut])
            #expect(truncated(b))
            #expect(no_messages(b))
        }
        var foreign = wire
        foreign[1] = 0x51
        if case .badMagic? = error(foreign) {} else { Issue.record("BadMagic") }
        #expect(no_messages(foreign))
        var invalid_field = wire
        invalid_field[22] = 0x99
        #expect(error(invalid_field) == .unknownTag(0x99))
        #expect(no_messages(invalid_field))
    }
    @Test("a_blob_length_beyond_the_buffer_is_rejected") func a_blob_length_beyond_the_buffer_is_rejected() {
        let bytes = header_declaring(kind.ANLZ_TAG, [6, 3]) + [0x11] + dbBE(UInt32.max) + [0x14] + dbBE(UInt32.max)
        #expect(truncated(bytes))
    }
    @Test("a_string_length_beyond_the_buffer_is_rejected") func a_string_length_beyond_the_buffer_is_rejected() {
        #expect(truncated(header_declaring(kind.SEARCH, [2]) + [0x26] + dbBE(UInt32(0x4000_0000))))
    }
    @Test("a_foreign_packet_is_not_mistaken_for_a_message") func a_foreign_packet_is_not_mistaken_for_a_message() {
        var bytes = Message.new(1, kind.ROOT_MENU, []).encode()
        bytes[1] = 0x51
        if case .badMagic? = error(bytes) {} else { Issue.record("BadMagic") }
    }
    @Test("an_impossible_argument_count_is_rejected") func an_impossible_argument_count_is_rejected() {
        #expect(error(header_declaring(kind.ROOT_MENU, Array(repeating: 6, count: 33))) == .tooManyArguments(33))
    }
    @Test("an_unknown_field_tag_is_reported_not_guessed") func an_unknown_field_tag_is_reported_not_guessed() {
        #expect(error(header_declaring(kind.ROOT_MENU, [6]) + [0x99]) == .unknownTag(0x99))
    }
    @Test("decode_all_stops_at_garbage_rather_than_looping") func decode_all_stops_at_garbage_rather_than_looping() {
        let wire = menu_header(1, 0x1000, 0).encode() + [0xde, 0xad, 0xbe, 0xef, 0, 0x11, 0x22]
        let (got, used) = Message.decode_all(wire)
        #expect(got.count == 1)
        #expect(used == menu_header(1, 0x1000, 0).encode().count)
    }
    @Test("setup_uses_the_reserved_transaction_id") func setup_uses_the_reserved_transaction_id() {
        let m = setup_request(2)
        #expect(m.transaction == SETUP_TXID)
        #expect(m.kind == kind.SETUP)
        #expect(m.arguments == [.number(2), .number(SETUP_MAGIC)])
        #expect(SETUP_TXID == 0xffff_fffe)
    }
    @Test("only_device_numbers_one_to_six_are_answerable") func only_device_numbers_one_to_six_are_answerable() {
        for device: UInt8 in 1...6 { #expect(is_answerable_device(device)) }
        for device: UInt8 in [0, 7, 8, 17, 255] { #expect(!is_answerable_device(device)) }
    }
    @Test("the_port_query_string_is_nul_terminated") func the_port_query_string_is_nul_terminated() {
        #expect(PORT_QUERY_REQUEST == [0, 0, 0, 15] + Array("RemoteDBServer\0".utf8))
        #expect(PORT_QUERY == 12_523)
    }
    @Test("a_twelve_byte_zero_padded_tag_list_is_accepted_too")
    func a_twelve_byte_zero_padded_tag_list_is_accepted_too() throws {
        var bytes = Message.new(1, kind.ROOT_MENU, []).encode()
        bytes[14] = 2
        bytes.replaceSubrange(16..<20, with: dbBE(UInt32(12)))
        bytes += [6, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x11, 0, 0, 0, 7, 0x11, 0, 0, 0, 9]
        let (m, used) = try Message.decode(bytes)
        #expect(m.arguments == [.number(7), .number(9)])
        #expect(used == bytes.count)
    }
}
