import DJLinkExportProtocol
// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbxport/crates/rbl-prolink/tests/packets.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 원본 39개 시험의 입력·기대값과 시험명을 그대로 옮겼다.
import Foundation
import Testing

private let CAPTURED_REKORDBOX_KEEP_ALIVE =
    "5173707431576d4a4f4c060072656b6f7264626f78000000000000000000000001030036110100e04ccf632ec0a8010e020100000408"
private let CAPTURED_CDJ_KEEP_ALIVE =
    "5173707431576d4a4f4c060043444a2d333030300000000000000000000000000103003601012497ed0b4043c0a80198030000000164"
private let CAPTURED_REKORDBOX_STATUS =
    "5173707431576d4a4f4c2972656b6f7264626f7800000000000000000000000101110038110000c00010000080001e80001000000009ff01"
private let CAPTURED_MEDIA_QUERY =
    "5173707431576d4a4f4c0543444a2d33303030000000000000000000000000010001000cc0a801980000001100000003"
private let CAPTURED_MEDIA_RESPONSE =
    "5173707431576d4a4f4c0672656b6f7264626f780000000000000000000000010111009c000000110000000300720065006b006f007200640062006f007800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009719000001010000027300000000000000000000000000000000"
private let CAPTURED_DEVICE_SETTINGS_RESPONSE =
    "5173707431576d4a4f4c4772656b6f7264626f7800000000000000000000000101110024110400001234567800000001010104010101000002000000000000000000000000000000"
private let CAPTURED_DEVICE_PROPERTY_QUERY = "5173707431576d4a4f4c3058444a2d5258330000000000000000000000000001030b0000"
private let CAPTURED_DEVICE_PROPERTY_RESPONSE =
    "5173707431576d4a4f4c3172656b6f7264626f78000000000000000000000001031100080600000000000000"
private let CAPTURED_CONNECT_GREETING =
    "5173707431576d4a4f4c1672656b6f7264626f7800000000000000000000000101110000000000000000000000000000"
private let CAPTURED_CONNECT_IDENTITY =
    "5173707431576d4a4f4c1172656b6f7264626f78000000000000000000000001011101041101000000630068007200690073006c00650073002d004d0042005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
private let CAPTURED_MEDIA_QUERY_SLOT_4 =
    "5173707431576d4a4f4c0543444a2d33303030000000000000000000000000010001000cc0a801aa0000001100000004"
private let CAPTURED_MEDIA_RESPONSE_SLOT_4 =
    "5173707431576d4a4f4c0672656b6f7264626f780000000000000000000000010111009c000000110000000400720065006b006f007200640062006f007800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036000001010000000200000000000000000000000000000000"
private let CAPTURED_REKORDBOX_STATUS_IDLE =
    "5173707431576d4a4f4c2972656b6f7264626f7800000000000000000000000101110038110000c00010000000000000001000000009ff00"
private let CAPTURED_MASTER_STATUS_BEAT_1 =
    "5173707431576d4a4f4c2972656b6f7264626f7800000000000000000000000101110038110000e000100000800032c8001000000109ff01"
private let CAPTURED_LOAD_TRACK_PLAYER_1 =
    "5173707431576d4a4f4c1972656b6f7264626f7800000000000000000000000101110034110000001104010001300ad700000032000000000000000000000000000000000000000000000032000000000000000000000000"
private let CAPTURED_LOAD_TRACK_PLAYER_2 =
    "5173707431576d4a4f4c1972656b6f7264626f78000000000000000000000001011100341100000011040100046273df00000032000000000000000000000000010000000000000000000032000000000000000000000000"
private let CAPTURED_LOAD_TRACK_ACK = "5173707431576d4a4f4c1a43444a2d33303030000000000000000000000000010003000403010000"
private let CAPTURED_LOAD_TRACK_ACK_PLAYER_1 =
    "5173707431576d4a4f4c1a43444a2d33303030000000000000000000000000010001000401010000"
private let CAPTURED_DJM_V5_KEEP_ALIVE =
    "5173707431576d4a4f4c0600444a4d2d56350000000000000000000000000000010200362102c83dfc1dfea2c0a80142040000000331"
private let CAPTURED_BEATS: [(String, UInt8)] = [
    (
        "5173707431576d4a4f4c2872656b6f7264626f780000000000000000000000010111003c000001cd0000039b000007360000073600000e6c00000e6cffffffffffffffffffffffffffffffffffffffffffffffff00100000000032c801000011",
        1
    ),
    (
        "5173707431576d4a4f4c2872656b6f7264626f780000000000000000000000010111003c000001cd0000039b000005680000073600000c9e00000e6cffffffffffffffffffffffffffffffffffffffffffffffff00100000000032c802000011",
        2
    ),
    (
        "5173707431576d4a4f4c2872656b6f7264626f780000000000000000000000010111003c000001cd0000039b0000039b0000073600000ad100000e6cffffffffffffffffffffffffffffffffffffffffffffffff00100000000032c803000011",
        3
    ),
    (
        "5173707431576d4a4f4c2872656b6f7264626f780000000000000000000000010111003c000001cd0000039b000001cd000007360000090300000e6cffffffffffffffffffffffffffffffffffffffffffffffff00100000000032c804000011",
        4
    ),
]

private func sample() -> KeepAlive {
    KeepAlive.rekordbox([0x00, 0x1e, 0x1d, 0x11, 0x22, 0x33], Address4(192, 168, 1, 42), 2)
}
private func hex(_ s: String) -> [UInt8] {
    let chars = Array(s)
    return stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0..<$0 + 2]), radix: 16)! }
}

@Suite("Packet encoding, decoding, and the device table’s expiry rules")
struct PacketsTests {
    @Test("rekordboxs_keep_alive_is_reproduced_byte_for_byte")
    func rekordboxs_keep_alive_is_reproduced_byte_for_byte() throws {
        let alive = KeepAlive.rekordbox([0x00, 0xe0, 0x4c, 0xcf, 0x63, 0x2e], Address4(192, 168, 1, 14), 2)
        #expect(alive.encode() == hex(CAPTURED_REKORDBOX_KEEP_ALIVE))
        #expect(try KeepAlive.decode(hex(CAPTURED_REKORDBOX_KEEP_ALIVE)) == alive)
    }
    @Test("a_cdj_3000s_keep_alive_decodes_to_a_player")
    func a_cdj_3000s_keep_alive_decodes_to_a_player() throws {
        let deck = try KeepAlive.decode(hex(CAPTURED_CDJ_KEEP_ALIVE))
        #expect(deck.name == "CDJ-3000")
        #expect(deck.device_number == 1)
        #expect(deck.device_type == .cdj)
        #expect(deck.ip == Address4(192, 168, 1, 152))
        #expect(deck.peers == 3)
        #expect(deck.generation == 3)
        #expect(deck.encode() == hex(CAPTURED_CDJ_KEEP_ALIVE))
    }
    @Test("the_status_beacon_and_the_connect_greeting_match_the_capture")
    func the_status_beacon_and_the_connect_greeting_match_the_capture() {
        let status = Status(
            name: REKORDBOX_NAME, device_number: REKORDBOX_DEVICE_NUMBER, bpm_x100: 0x1e80, beat: 1, master: false)
        #expect(status.encode() == hex(CAPTURED_REKORDBOX_STATUS))
        #expect(connect_greeting(REKORDBOX_NAME, REKORDBOX_DEVICE_NUMBER) == hex(CAPTURED_CONNECT_GREETING))
    }
    @Test("the_identity_reply_matches_the_capture")
    func the_identity_reply_matches_the_capture() {
        let identity = connect_identity(REKORDBOX_NAME, REKORDBOX_DEVICE_NUMBER, "chrisles-MBP")
        #expect(identity.count == CONNECT_IDENTITY_LEN)
        #expect(identity == hex(CAPTURED_CONNECT_IDENTITY))
    }
    @Test("the_rx3_device_property_exchange_matches_the_capture")
    func the_rx3_device_property_exchange_matches_the_capture() throws {
        let query = try DevicePropertyQuery.decode(hex(CAPTURED_DEVICE_PROPERTY_QUERY))
        #expect(query.name == "XDJ-RX3")
        #expect(query.requester == 0x0b)
        let response = DevicePropertyResponse(name: REKORDBOX_NAME, device_number: REKORDBOX_DEVICE_NUMBER)
        #expect(response.encode() == hex(CAPTURED_DEVICE_PROPERTY_RESPONSE))
    }
    @Test("a_keep_alive_round_trips")
    func a_keep_alive_round_trips() throws {
        let original = sample()
        let bytes = original.encode()
        #expect(bytes.count == KEEP_ALIVE_LEN)
        #expect(try KeepAlive.decode(bytes) == original)
    }
    @Test("every_packet_starts_with_the_dj_link_magic")
    func every_packet_starts_with_the_dj_link_magic() {
        for bytes in [
            sample().encode(),
            Announcement(name: "rekordbox", device_type: .rekordbox).encode(),
            Claim(
                stage: .claimStage1, name: "rekordbox", device_number: 17, mac: [1, 2, 3, 4, 5, 6], ip: .localhost,
                repeat: 1, device_type: .rekordbox
            ).encode(),
        ] {
            #expect(Array(bytes.prefix(10)) == MAGIC, "magic missing")
        }
    }
    @Test("the_device_name_sits_at_a_fixed_offset_and_is_nul_padded")
    func the_device_name_sits_at_a_fixed_offset_and_is_nul_padded() throws {
        let bytes = sample().encode()
        #expect(try device_name(bytes) == "rekordbox")
        #expect(Array(bytes[0x0c..<0x0c + 9]) == Array("rekordbox".utf8))
        #expect(bytes[0x15..<0x20].allSatisfy { $0 == 0 }, "name must be NUL-padded")
    }
    @Test("a_long_name_is_truncated_to_the_field_rather_than_overflowing")
    func a_long_name_is_truncated_to_the_field_rather_than_overflowing() throws {
        var alive = sample()
        alive.name = "a-very-long-device-name-that-will-not-fit"
        let bytes = alive.encode()
        #expect(bytes.count == KEEP_ALIVE_LEN, "the packet must stay a fixed size")
        #expect(try device_name(bytes).utf8.count == 20)
    }
    @Test("keep_alive_fields_land_where_the_protocol_says")
    func keep_alive_fields_land_where_the_protocol_says() {
        let bytes = sample().encode()
        #expect(bytes[0x0a] == 0x06, "kind: keep-alive")
        #expect(bytes[0x21] == 0x03, "generation")
        #expect(bytes[0x34] == DeviceType.rekordbox.to_u8())
        #expect(Int(UInt16(bytes[0x22]) << 8 | UInt16(bytes[0x23])) == KEEP_ALIVE_LEN)
        #expect(bytes[0x24] == REKORDBOX_DEVICE_NUMBER)
        #expect(Array(bytes[0x26..<0x2c]) == [0x00, 0x1e, 0x1d, 0x11, 0x22, 0x33])
        #expect(Array(bytes[0x2c..<0x30]) == [192, 168, 1, 42])
        #expect(bytes[0x30] == 2, "peer count")
    }
    @Test("rubbish_is_rejected_rather_than_misread")
    func rubbish_is_rejected_rather_than_misread() {
        #expect(throws: PacketError.tooShort(0)) { try KeepAlive.decode([]) }
        #expect(throws: PacketError.tooShort(4)) { try packet_kind([0, 0, 0, 0]) }
        var wrong = sample().encode()
        wrong[0] = 0xff
        #expect(throws: PacketError.badMagic) { try packet_kind(wrong) }
        #expect(throws: PacketError.badMagic) { try device_name(wrong) }
    }
    @Test("a_packet_of_the_wrong_kind_is_refused")
    func a_packet_of_the_wrong_kind_is_refused() {
        var bytes = sample().encode()
        bytes[0x0a] = AnnounceKind.announce.to_u8()
        #expect(throws: PacketError.wrongKind(0x0a)) { try KeepAlive.decode(bytes) }
    }
    @Test("announce_kinds_round_trip")
    func announce_kinds_round_trip() {
        for kind in [
            AnnounceKind.claimStage1, .claimStage2, .claimFinal, .keepAlive, .conflict, .announce, .other(0x7f),
        ] {
            #expect(AnnounceKind.from_u8(kind.to_u8()) == kind)
        }
    }
    @Test("device_types_round_trip")
    func device_types_round_trip() {
        for kind in [DeviceType.cdj, .mixer, .rekordbox, .allInOne, .other(9)] {
            #expect(DeviceType.from_u8(kind.to_u8()) == kind)
        }
    }
    @Test("the_first_claim_stage_is_shorter_than_the_later_ones")
    func the_first_claim_stage_is_shorter_than_the_later_ones() {
        let base = Claim(
            stage: .claimStage1, name: "rekordbox", device_number: 17, mac: [1, 2, 3, 4, 5, 6],
            ip: Address4(10, 0, 0, 5), repeat: 1, device_type: .rekordbox)
        let first = base.encode()
        var later = base
        later.stage = .claimStage2
        let second = later.encode()
        #expect(second.count > first.count, "later stages carry the IP and number")
        #expect(first[0x0a] == 0x00)
        #expect(second[0x0a] == 0x02)
        #expect(second.contains(17))
    }
    @Test("the_table_records_and_updates_a_peer")
    func the_table_records_and_updates_a_peer() {
        var table = DeviceTable.new()
        table.observe(sample(), 1_000)
        #expect(table.len() == 1)
        #expect(table.peers()[0].name == "rekordbox")
        var moved = sample()
        moved.ip = Address4(192, 168, 1, 99)
        table.observe(moved, 2_000)
        #expect(table.len() == 1)
        #expect(table.peers()[0].ip == Address4(192, 168, 1, 99))
        #expect(table.peers()[0].last_seen_ms == 2_000)
    }
    @Test("occupancy_block_has_distinct_masks_counter_and_truncation_boundary")
    func occupancy_block_has_distinct_masks_counter_and_truncation_boundary() throws {
        var wire = rekordbox_claim_stage2([1, 2, 3, 4, 5, 6], Address4(192, 168, 1, 20), 99, 7)
        wire += [UInt8](repeating: 0, count: 68 - wire.count)
        wire[11] = 2
        wire.replaceSubrange(34..<36, with: [0, 68])
        wire[48] = 0b10
        wire[51] = 0b0101
        wire[67] = 255
        let block = try NumberBlock.decode(wire)
        #expect(block.ip == Address4(192, 168, 1, 20))
        #expect(block.mac == [1, 2, 3, 4, 5, 6])
        #expect(block.counter == 255)
        #expect(!block.names(17, .wired))
        #expect(block.names(18, .wired))
        #expect(block.names(41, .wireless))
        #expect(!block.names(42, .wireless))
        #expect(block.names(43, .wireless))
        #expect(!block.names(44, .wireless))
        for number in UInt8(0)...255 { #expect(!block.names(number, .unknown)) }
        #expect(throws: PacketError.wrongSubtype(2)) { try NumberProbe.decode(wire) }
        for cut in 0..<68 {
            #expect(throws: PacketError.tooShort(cut)) { try NumberBlock.decode(Array(wire[..<cut])) }
        }
        wire[11] = 0
        #expect(throws: PacketError.wrongSubtype(0)) { try NumberBlock.decode(wire) }
        wire[11] = 2
        wire[10] = 6
        #expect(throws: PacketError.wrongKind(6)) { try NumberBlock.decode(wire) }
        wire[0] = 0
        #expect(throws: PacketError.badMagic) { try NumberBlock.decode(wire) }
    }
    @Test("a_wrong_keepalive_subtype_cannot_mark_probing_occupancy")
    func a_wrong_keepalive_subtype_cannot_mark_probing_occupancy() {
        var wire = hex(CAPTURED_CDJ_KEEP_ALIVE)
        wire[11] = 1
        #expect(throws: PacketError.wrongSubtype(1)) { try KeepAlive.decode(wire) }
    }
    @Test("a_peer_that_goes_quiet_is_dropped")
    func a_peer_that_goes_quiet_is_dropped() {
        var table = DeviceTable.new()
        table.observe(sample(), 0)
        #expect(table.expire(PEER_TIMEOUT_MS) == 0, "still within the timeout")
        #expect(table.len() == 1)
        #expect(table.expire(PEER_TIMEOUT_MS + 1) == 1, "a player unplugged mid-set stops announcing")
        #expect(table.is_empty())
    }
    @Test("several_devices_are_tracked_separately")
    func several_devices_are_tracked_separately() {
        var table = DeviceTable.new()
        for number in [UInt8(1), 2, 17] {
            var alive = sample()
            alive.device_number = number
            alive.name = "device-\(number)"
            table.observe(alive, 0)
        }
        #expect(table.len() == 3)
        #expect(table.free_device_number(17) == 18, "17 is taken, so pick the next free one")
        #expect(table.free_device_number(20) == 20, "20 is free")
    }
    @Test("an_empty_table_hands_back_the_preferred_number")
    func an_empty_table_hands_back_the_preferred_number() {
        #expect(DeviceTable.new().free_device_number(REKORDBOX_DEVICE_NUMBER) == REKORDBOX_DEVICE_NUMBER)
    }
    @Test("the_media_query_decodes_and_the_response_matches_the_capture")
    func the_media_query_decodes_and_the_response_matches_the_capture() throws {
        let query = try MediaQuery.decode(hex(CAPTURED_MEDIA_QUERY))
        #expect(query.name == "CDJ-3000")
        #expect(query.from == Address4(192, 168, 1, 152))
        #expect(query.device_number == REKORDBOX_DEVICE_NUMBER)
        #expect(query.slot == SLOT_REKORDBOX_LEGACY)
        let response = MediaResponse(
            name: REKORDBOX_NAME, device_number: REKORDBOX_DEVICE_NUMBER, slot: query.slot, tracks: 38_681,
            playlists: 627)
        #expect(response.encode() == hex(CAPTURED_MEDIA_RESPONSE))
    }
    @Test("a_current_cdj_3000_asks_about_slot_4_and_the_answer_names_it_back")
    func a_current_cdj_3000_asks_about_slot_4_and_the_answer_names_it_back() throws {
        let query = try MediaQuery.decode(hex(CAPTURED_MEDIA_QUERY_SLOT_4))
        #expect(query.name == "CDJ-3000")
        #expect(query.from == Address4(192, 168, 1, 170))
        #expect(query.device_number == REKORDBOX_DEVICE_NUMBER)
        #expect(query.slot == SLOT_REKORDBOX)
        #expect(query.slot != SLOT_REKORDBOX_LEGACY)
        let response = MediaResponse(
            name: REKORDBOX_NAME, device_number: REKORDBOX_DEVICE_NUMBER, slot: query.slot, tracks: 54, playlists: 2)
        #expect(response.encode() == hex(CAPTURED_MEDIA_RESPONSE_SLOT_4))
    }
    @Test("the_device_settings_response_matches_the_capture")
    func the_device_settings_response_matches_the_capture() {
        #expect(
            device_settings_response(REKORDBOX_NAME, REKORDBOX_DEVICE_NUMBER, DeviceSettings.default())
                == hex(CAPTURED_DEVICE_SETTINGS_RESPONSE))
    }
    @Test("device_settings_response_encodes_each_decoded_field")
    func device_settings_response_encodes_each_decoded_field() {
        let response = device_settings_response(
            REKORDBOX_NAME, REKORDBOX_DEVICE_NUMBER,
            DeviceSettings(
                overview_waveform: .full, waveform_color: .rgb, key_display: .alphanumeric, waveform_position: .left))
        #expect(Array(response[0x30..<0x36]) == [1, 2, 3, 1, 2, 2])
    }
    @Test("device_settings_deserialize_from_the_dj_system_values")
    func device_settings_deserialize_from_the_dj_system_values() throws {
        // 원본과 다름: serde_json::Value 대신 같은 키·값의 JSON을 Foundation 경계에서 읽는다.
        let settings = try JSONDecoder().decode(
            DeviceSettings.self,
            from: Data(
                #"{"waveformColor":"3band","waveformPosition":"left","overviewWaveform":"full","keyDisplay":"alphanumeric"}"#
                    .utf8))
        #expect(
            settings
                == DeviceSettings(
                    overview_waveform: .full, waveform_color: .threeBand, key_display: .alphanumeric,
                    waveform_position: .left))
    }
    @Test("alphanumeric_device_settings_change_only_the_key_display_byte")
    func alphanumeric_device_settings_change_only_the_key_display_byte() {
        var expected = hex(CAPTURED_DEVICE_SETTINGS_RESPONSE)
        expected[0x34] = 2
        let response = device_settings_response(
            REKORDBOX_NAME, REKORDBOX_DEVICE_NUMBER, DeviceSettings(key_display: .alphanumeric))
        #expect(response == expected)
    }
    @Test("the_rekordbox_startup_ladder_matches_the_capture")
    func the_rekordbox_startup_ladder_matches_the_capture() {
        let mac: [UInt8] = [0x00, 0xe0, 0x4c, 0xcf, 0x63, 0x2e]
        let ip = Address4(192, 168, 1, 14)
        #expect(
            rekordbox_claim_stage1(mac, 1)
                == hex("5173707431576d4a4f4c000072656b6f7264626f7800000000000000000000000103002c010400e04ccf632e"))
        #expect(
            rekordbox_claim_stage2(mac, ip, 0x11, 1)
                == hex(
                    "5173707431576d4a4f4c020072656b6f7264626f78000000000000000000000001030032c0a8010e00e04ccf632e11010401"
                ))
        #expect(
            rekordbox_claim_stage2(mac, ip, 0x2c, 6)
                == hex(
                    "5173707431576d4a4f4c020072656b6f7264626f78000000000000000000000001030032c0a8010e00e04ccf632e2c060401"
                ))
        #expect(rekordbox_startup_ladder(mac, ip).count == 3 + 36)
    }
    @Test("the_idle_status_matches_the_capture")
    func the_idle_status_matches_the_capture() {
        let status = Status(
            name: REKORDBOX_NAME, device_number: REKORDBOX_DEVICE_NUMBER, bpm_x100: 0, beat: 0, master: false)
        #expect(status.encode() == hex(CAPTURED_REKORDBOX_STATUS_IDLE))
    }
    @Test("the_master_status_matches_the_capture")
    func the_master_status_matches_the_capture() {
        let status = Status(
            name: REKORDBOX_NAME, device_number: REKORDBOX_DEVICE_NUMBER, bpm_x100: 13_000, beat: 1, master: true)
        #expect(status.encode() == hex(CAPTURED_MASTER_STATUS_BEAT_1))
        var mirrored = status
        mirrored.master = false
        let mirror = mirrored.encode()
        let master = status.encode()
        let differing = master.indices.filter { master[$0] != mirror[$0] }
        #expect(differing == [0x27, 0x34])
    }
    @Test("the_beat_packet_is_rekordboxs_byte_for_byte_across_a_bar")
    func the_beat_packet_is_rekordboxs_byte_for_byte_across_a_bar() throws {
        for (captured, beat) in CAPTURED_BEATS {
            let packet = beat_packet(REKORDBOX_NAME, REKORDBOX_DEVICE_NUMBER, 13_000, beat)
            #expect(packet.count == BEAT_LEN)
            #expect(packet == hex(captured), "beat \(beat)")
            #expect(try packet_kind(packet) == BEAT_KIND)
        }
    }
    @Test("the_load_track_command_is_rekordboxs_byte_for_byte")
    func the_load_track_command_is_rekordboxs_byte_for_byte() {
        let to_player_1 = load_track_command(REKORDBOX_NAME, REKORDBOX_DEVICE_NUMBER, 1, 19_925_719)
        #expect(to_player_1.count == LOAD_TRACK_LEN)
        #expect(to_player_1 == hex(CAPTURED_LOAD_TRACK_PLAYER_1))
        let to_player_2 = load_track_command(REKORDBOX_NAME, REKORDBOX_DEVICE_NUMBER, 2, 73_561_055)
        #expect(to_player_2 == hex(CAPTURED_LOAD_TRACK_PLAYER_2))
    }
    @Test("the_load_track_command_names_the_track_and_the_player")
    func the_load_track_command_names_the_track_and_the_player() throws {
        let packet = load_track_command(REKORDBOX_NAME, REKORDBOX_DEVICE_NUMBER, 0x02, 0x1234_5678)
        #expect(packet[0x0a] == LOAD_TRACK_KIND)
        #expect(try status_device_name(packet) == REKORDBOX_NAME)
        #expect(packet[0x21] == REKORDBOX_DEVICE_NUMBER, "our device number")
        #expect(packet[0x28] == REKORDBOX_DEVICE_NUMBER, "the track's source device")
        #expect(packet[0x29] == SLOT_REKORDBOX, "the rekordbox slot")
        #expect(packet[0x2a] == TRACK_TYPE_REKORDBOX, "a rekordbox track")
        #expect(Array(packet[0x2c..<0x30]) == [0x12, 0x34, 0x56, 0x78], "the track id")
        #expect(packet[0x40] == 0x01, "the player to load onto, counted from zero")
    }
    @Test("a_cdj_3000_acknowledges_a_load_track_command")
    func a_cdj_3000_acknowledges_a_load_track_command() throws {
        for (captured, player) in [
            (CAPTURED_LOAD_TRACK_ACK, UInt8(0x03)), (CAPTURED_LOAD_TRACK_ACK_PLAYER_1, UInt8(0x01)),
        ] {
            let bytes = hex(captured)
            #expect(try packet_kind(bytes) == LOAD_TRACK_ACK_KIND)
            #expect(try status_device_name(bytes) == "CDJ-3000")
            #expect(bytes[0x21] == player, "the player that accepted it")
        }
    }
    @Test("load_track_response_preserves_raw_fields_and_rejects_malformed_frames")
    func load_track_response_preserves_raw_fields_and_rejects_malformed_frames() throws {
        var wire = hex(CAPTURED_LOAD_TRACK_ACK)
        let response = try LoadTrackResponse.decode(wire)
        #expect(response.name == "CDJ-3000")
        #expect(response.fields == [3, 1, 0, 0])
        for cut in 0..<40 {
            #expect(throws: PacketError.tooShort(cut)) { try LoadTrackResponse.decode(Array(wire[..<cut])) }
        }
        wire.replaceSubrange(36..<40, with: [255, 0, 17, 42])
        #expect(try LoadTrackResponse.decode(wire).fields == [255, 0, 17, 42])
        wire[35] = 5
        #expect(throws: PacketError.wrongLength(5)) { try LoadTrackResponse.decode(wire) }
        wire[35] = 4
        wire[10] = 0x19
        #expect(throws: PacketError.wrongKind(0x19)) { try LoadTrackResponse.decode(wire) }
        wire[0] = 0
        #expect(throws: PacketError.badMagic) { try LoadTrackResponse.decode(wire) }
    }
    @Test("a_djm_v5_is_read_as_a_mixer")
    func a_djm_v5_is_read_as_a_mixer() throws {
        let bytes = hex(CAPTURED_DJM_V5_KEEP_ALIVE)
        let mixer = try KeepAlive.decode(bytes)
        #expect(mixer.name == "DJM-V5")
        #expect(mixer.device_number == 33)
        #expect(mixer.device_type == .mixer)
        #expect(DeviceType.from_u8(0x02) == .mixer)
    }
    @Test("synthetic_members_do_not_own_or_refresh_received_keepalive_timers")
    func synthetic_members_do_not_own_or_refresh_received_keepalive_timers() {
        var table = DeviceTable.new()
        var primary = sample()
        primary.device_number = 9
        table.observe_with_flags(primary, 1_000, [0xa5, 0x5a])
        var secondary = primary
        secondary.device_number = 10
        table.observe_synthetic(secondary, 1_000, [0xa5, 0x5a])
        #expect(table.is_synthetic(10))
        #expect(table.peers()[1].member_flags == [0xa5, 0x5a])
        #expect(table.expire_received(7_000).isEmpty)
        #expect(table.expire_received(7_001) == [9])
        #expect(table.peers()[0].device_number == 10)
        table.observe_with_flags(secondary, 8_000, [1, 2])
        #expect(!table.is_synthetic(10))
        secondary.ip = Address4(192, 168, 1, 99)
        table.observe_synthetic(secondary, 13_999, [3, 4])
        #expect(table.peers()[0].ip == secondary.ip)
        #expect(table.peers()[0].member_flags == [3, 4])
        #expect(table.peers()[0].last_seen_ms == 8_000)
        #expect(table.expire_received(14_000).isEmpty)
        #expect(table.expire_received(14_001) == [10])
        table.observe_synthetic(secondary, 15_000, [5, 6])
        #expect(table.is_synthetic(10))
        #expect(table.expire_received(UInt64.max).isEmpty)
    }
    @Test("pending_slot_timer_survives_removal_and_synthetic_recreation")
    func pending_slot_timer_survives_removal_and_synthetic_recreation() {
        var table = DeviceTable.new()
        var secondary = sample()
        secondary.device_number = 10
        table.observe(secondary, 0)
        table.remove_number(10)
        table.observe_synthetic(secondary, 1_000, nil)
        #expect(!table.is_synthetic(10))
        #expect(table.peers()[0].last_seen_ms == 0)
        #expect(table.expire_received(6_000).isEmpty)
        #expect(table.expire_received(6_001) == [10])
        #expect(table.is_empty())
        table.observe(secondary, 10_000)
        table.remove_number(10)
        #expect(table.expire_received(16_001).isEmpty)
        table.observe_synthetic(secondary, 17_000, nil)
        #expect(table.is_synthetic(10))
        #expect(table.peers()[0].last_seen_ms == 17_000)
        #expect(table.expire_received(UInt64.max).isEmpty)
        table.observe(secondary, 20_000)
        table.remove_number(10)
        table.observe(secondary, 25_000)
        #expect(table.expire_received(26_001).isEmpty)
        #expect(table.expire_received(31_000).isEmpty)
        #expect(table.expire_received(31_001) == [10])
    }
    @Test("rejection_disconnect_is_the_complete_pre_clear_41_byte_frame")
    func rejection_disconnect_is_the_complete_pre_clear_41_byte_frame() {
        #expect(
            rejection_disconnect(18, Address4(192, 168, 50, 2))
                == hex("5173707431576d4a4f4c080072656b6f7264626f7800000000000000000000000103002912c0a83202"))
        #expect(
            rejection_disconnect(41, .unspecified)
                == hex("5173707431576d4a4f4c080072656b6f7264626f780000000000000000000000010300292900000000"))
    }
}
