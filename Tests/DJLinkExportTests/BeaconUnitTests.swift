// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
import DJLinkExportDBServer
import DJLinkExportProtocol
import DJLinkExportSupport
import DJLinkExportTestSupport
import DJLinkKit
import DJLinkTestSupport
// 원본: crates/rbl-link/src/beacon.rs inline all_in_one_tests @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation
import Testing

@testable import DJLinkExport

private func testClock() -> TestClock { TestClock(start: Date(timeIntervalSince1970: 0)) }
private func config() -> BeaconConfig {
    BeaconConfig(
        interface: nil, address: .localhost, netmask: LinkAddress(255, 0, 0, 0), broadcast: .localhost,
        mac: Array(repeating: 0, count: 6), mode: .wired, announce_port: 50000, status_port: 50002, player_port: 50002,
        beat_port: 50001, computer_name: "fixture")
}
private func rejection_config(_ mode: ConnectionMode) -> BeaconConfig {
    var c = config()
    c.address = LinkAddress(192, 168, 50, 2)
    c.netmask = LinkAddress(255, 255, 255, 0)
    c.broadcast = LinkAddress(192, 168, 50, 255)
    c.mode = mode
    return c
}
private func keep_alive(_ number: UInt8, _ ip: LinkAddress) -> KeepAlive {
    var p = KeepAlive.rekordbox_as(number, [1, 2, 3, 4, 5, 6], ip, 0)
    p.name = "CDJ-3000"
    p.device_type = .cdj
    return p
}
private func player(_ number: UInt8, _ address: LinkAddress, _ kind: LinkDeviceType, _ now: Double = 0) -> Player {
    Player(number: number, name: "device \(number)", address: address, kind: kind, last_seen: now)
}
@DJLinkActor private func members(_ numbers: [UInt8], _ clock: TestClock = testClock()) -> BeaconShared {
    let ip = LinkAddress(169, 254, 20, 2)
    let s = BeaconShared(clock: clock)
    s.greeted = [ip]
    s.to_greet = [ip]
    s.join = Join.new(mac: Array(repeating: 0, count: 6), ip: .localhost, now_ms: 0)
    for number in numbers {
        let p = keep_alive(number, ip)
        s.peers.observe(p, 0)
        s.players[number] = player(number, ip, .cdj)
        s.join?.hear_keep_alive(p, 0)
    }
    return s
}
@DJLinkActor @discardableResult private func hear(
    _ packet: [UInt8], _ sender: LinkAddress, _ s: BeaconShared, _ cfg: BeaconConfig = config(), _ started: Double = 0
) -> Outgoing? {
    hear_announce(packet, RemoteInfo(address: sender.description, port: 50000, size: packet.count), cfg, s, started)
}
@DJLinkActor private func acquired(_ cfg: BeaconConfig, _ first: KeepAlive) -> BeaconShared {
    let s = BeaconShared(clock: testClock())
    s.join = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(cfg.mode)
    _ = hear(first.encode(), first.ip, s, cfg)
    if case .discovery = s.join!.state() {} else { Issue.record("Discovery") }
    for tick: UInt64 in 0..<50 {
        _ = s.join?.tick(tick * TICK)
        if s.join?.number() != nil { break }
    }
    #expect(s.join?.number() == 17)
    return s
}
@DJLinkActor private func numbers(_ s: BeaconShared) -> [UInt8] { s.peers.peers().map { $0.device_number } }
private func rejection_frame() -> [UInt8] {
    var p = keep_alive(1, LinkAddress(192, 168, 50, 10)).encode()
    p[10] = 9
    p[11] = 0x7f
    p[34] = 255
    p[35] = 255
    return Array(p.prefix(36))
}
private func disconnect_bytes(_ number: UInt8, _ ip: LinkAddress) -> [UInt8] {
    [
        0x51, 0x73, 0x70, 0x74, 0x31, 0x57, 0x6d, 0x4a, 0x4f, 0x4c, 8, 0, 114, 101, 107, 111, 114, 100, 98, 111, 120, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 0, 41, number,
    ] + ip.octets
}
@DJLinkActor private final class Loads: LibraryFacts {
    var loads = 0
    func track_count() -> UInt16 { 1 }
    func playlist_count() -> UInt16 { 0 }
    func track_loaded(_ track: UInt32) { loads += 1 }
}
@DJLinkActor private final class EmptyCatalog: Catalog {
    func list(_ q: DJLinkExportDBServer.Query) -> [DJLinkExportDBServer.Row] { [] }
    func track_row(_ id: UInt32, _ c: TrackColumn?) -> TrackRow? { nil }
    func track(_ id: UInt32) -> TrackDetails? { nil }
    func artwork(_ id: UInt32) -> [UInt8]? { nil }
    func item_artwork(_ id: UInt32) -> [UInt8]? { nil }
    func analysis(_ track: UInt32, _ what: DJLinkExportDBServer.Analysis) -> [UInt8]? { nil }
}
@Suite @DJLinkActor struct BeaconUnitTests {
    @Test("logical_decks_at_one_address_remain_separate_load_destinations")
    func logical_decks_at_one_address_remain_separate_load_destinations() {
        let ip = LinkAddress(169, 254, 20, 2)
        let p = [UInt8(1): player(1, ip, .cdj), 2: player(2, ip, .cdj), 33: player(33, ip, .mixer)]
        for n: UInt8 in [1, 2, 33] { #expect(player_address(p, n) == ip) }
        #expect(player_address(p, 3) == nil)
    }
    @Test("an_all_in_one_can_be_greeted_again_after_every_identity_times_out")
    func an_all_in_one_can_be_greeted_again_after_every_identity_times_out() {
        let ip = LinkAddress(169, 254, 20, 2)
        let s = BeaconShared(clock: testClock())
        s.greeted = [ip]
        s.players = [1: player(1, ip, .cdj), 2: player(2, ip, .cdj)]
        s.players[1]!.last_seen = -PLAYER_TIMEOUT - 1
        s.expire_silent_players()
        #expect(s.greeted.contains(ip))
        #expect(s.players.count == 1)
        s.players[2]!.last_seen = -PLAYER_TIMEOUT - 1
        s.expire_silent_players()
        #expect(s.players.isEmpty)
        #expect(!s.greeted.contains(ip))
    }
    @Test("goodbye_preserves_the_other_logical_identity_and_shared_greeting")
    func goodbye_preserves_the_other_logical_identity_and_shared_greeting() {
        let ip = LinkAddress(169, 254, 20, 2)
        let s = BeaconShared(clock: testClock())
        s.greeted = [ip]
        s.to_greet = [ip]
        s.players = [1: player(1, ip, .cdj), 2: player(2, ip, .cdj)]
        s.remove_member(1)
        #expect(s.players.count == 1)
        #expect(s.players[2] != nil)
        #expect(s.greeted.contains(ip))
        #expect(s.to_greet.contains(ip))
        s.remove_member(2)
        #expect(s.players.isEmpty)
        #expect(!s.greeted.contains(ip))
        #expect(!s.to_greet.contains(ip))
    }
    @Test("numbered_disconnect_covers_both_kinds_pairs_sender_and_state_guards")
    func numbered_disconnect_covers_both_kinds_pairs_sender_and_state_guards() {
        let ip = LinkAddress(169, 254, 20, 2)
        let sender = LinkAddress(10, 1, 2, 3)
        let all: [UInt8] = [1, 2, 9, 10, 11, 12]
        for kind: UInt8 in [7, 8] {
            for (leaving, remaining): (UInt8, [UInt8]) in [
                (1, [2, 9, 10, 11, 12]), (9, [1, 2, 11, 12]), (10, [1, 2, 9, 11, 12]), (11, [1, 2, 9, 10]),
                (12, [1, 2, 9, 10, 11]),
            ] {
                let s = members(all)
                var wire = keep_alive(leaving, ip).encode()
                wire[10] = kind
                wire[34] = 0
                wire[35] = 41
                wire = Array(wire.prefix(41))
                for cut in 0..<37 {
                    #expect(hear(Array(wire.prefix(cut)), sender, s) == nil)
                    #expect(s.peers.len() == 6)
                }
                #expect(hear(wire, sender, s) == nil)
                #expect(s.players.keys.sorted() == remaining)
                #expect(numbers(s) == remaining)
                #expect(s.greeted.contains(ip))
            }
        }
        let s = members([9, 10])
        var wire = keep_alive(9, ip).encode()
        wire[10] = 7
        for n: UInt8 in [0, 81, 255, 1] {
            wire[36] = n
            _ = hear(wire, sender, s)
            #expect(s.peers.len() == 2)
        }
        wire[36] = 9
        s.join?.reset(0)
        _ = hear(wire, sender, s)
        #expect(s.peers.len() == 2)
        s.join?.hear_keep_alive(keep_alive(9, ip), 0)
        _ = hear(wire, sender, s)
        #expect(s.players.isEmpty)
        #expect(s.peers.is_empty())
        #expect(s.greeted.isEmpty)
        #expect(s.to_greet.isEmpty)
    }
    @Test("matching_sender_address_change_updates_command_destination_and_peer_mac")
    func matching_sender_address_change_updates_command_destination_and_peer_mac() {
        let old = LinkAddress(169, 254, 20, 2)
        let new = LinkAddress(169, 254, 20, 3)
        let s = members([1, 2])
        var a = keep_alive(1, new)
        a.mac = [6, 5, 4, 3, 2, 1]
        for _ in 0..<2 {
            _ = hear(a.encode(), new, s)
            #expect(player_address(s.players, 1) == new)
            #expect(player_address(s.players, 2) == old)
            let p = s.peers.peers().first { $0.device_number == 1 }
            #expect(p?.ip == new)
            #expect(p?.mac == a.mac)
            #expect(s.greeted.contains(old))
        }
        a.device_number = 2
        _ = hear(a.encode(), new, s)
        #expect(!s.greeted.contains(old))
    }
    @Test("periodic_peer_expiry_needs_no_input_and_keeps_player_activity_separate")
    func periodic_peer_expiry_needs_no_input_and_keeps_player_activity_separate() throws {
        let s = members([1, 2])
        let ip = LinkAddress(169, 254, 20, 2)
        s.peers.observe(keep_alive(2, ip), 1000)
        s.expire_peers(PEER_TIMEOUT_MS)
        #expect(s.peers.len() == 2)
        s.expire_peers(PEER_TIMEOUT_MS + 1)
        #expect(s.peers.peers()[0].device_number == 2)
        s.players[2]!.last_seen = 0
        s.expire_peers(PEER_TIMEOUT_MS + 1001)
        #expect(s.peers.is_empty())
        #expect(s.players.count == 2)
        #expect(
            try KeepAlive.decode(
                KeepAlive.rekordbox_as(17, Array(repeating: 0, count: 6), .localhost, UInt8(s.peers.len())).encode()
            ).peers == 0)
    }
    @Test("idle_compatibility_response_does_not_destroy_members_or_greetings")
    func idle_compatibility_response_does_not_destroy_members_or_greetings() {
        let s = members([1])
        s.join?.reset(0)
        var wire = keep_alive(1, LinkAddress(169, 254, 20, 2)).encode()
        wire[10] = 0xb
        #expect(hear(wire, LinkAddress(10, 0, 0, 1), s) == nil)
        #expect(s.peers.len() == 1)
        #expect(s.players.count == 1)
        #expect(s.greeted.count == 1)
        #expect(s.to_greet.count == 1)
        #expect(s.join?.state() == .waiting)
    }
    @Test("xdj_az_usb_two_slot_survives_status_parsing") func xdj_az_usb_two_slot_survives_status_parsing() throws {
        var p = Array(repeating: UInt8(0), count: 0xcd)
        p.replaceSubrange(0..<DJLinkExportProtocol.MAGIC.count, with: DJLinkExportProtocol.MAGIC)
        p[0x29] = 7
        #expect(try beacon_status_from_packet(p)?.trackSlot == .unknown07)
    }
    @Test("numbered_disconnect_state_guards_cover_the_whole_join_machine")
    func numbered_disconnect_state_guards_cover_the_whole_join_machine() {
        let ip = LinkAddress(169, 254, 20, 2)
        var wire = keep_alive(1, ip).encode()
        wire[10] = 7
        for (state, accepted): (JoinState, Bool) in [
            (.waiting, false), (.discovery(sent: 0), true), (.probing(round: 1, index: 0), true),
            (.assigning(sent: 1), true), (.running(number: 17), true), (.failed("fixture"), false),
        ] {
            let s = members([1, 2])
            s.join = Join.new(mac: Array(repeating: 0, count: 6), ip: .localhost, now_ms: 0).test_state(state)
            #expect(hear(wire, ip, s) == nil)
            #expect((s.players[1] != nil) == !accepted)
            #expect(s.players.count == (accepted ? 1 : 2))
        }
        let s = members([1])
        s.join = nil
        _ = hear(wire, ip, s)
        #expect(s.players.count == 1)
    }
    @Test("changed_address_is_used_by_the_actual_load_command_socket")
    func changed_address_is_used_by_the_actual_load_command_socket() async throws {
        let clock = testClock()
        let factory = FakeExportSocketFactory(clock: clock)
        let s = members([1], clock)
        let receiver = try factory.createUDPSocket(reuseAddr: false) as! FakeExportUDPSocket
        let commands = try factory.createUDPSocket(reuseAddr: false)
        _ = try await receiver.bind(port: 0, address: "127.0.0.1")
        _ = try await commands.bind(port: 0, address: "127.0.0.1")
        var cfg = config()
        cfg.announce_port = 0
        cfg.status_port = UInt16(commands.address()!.port)
        cfg.player_port = UInt16(receiver.address()!.port)
        s.assigned.store(17)
        let beacon = Beacon(
            config: cfg, facts: Loads(), clock: clock, interfaceProvider: FakeInterfaceProvider(), announce: commands,
            status: commands, statusSender: commands, beats: nil, shared: s)
        var received: [([UInt8], RemoteInfo)] = []
        receiver.onMessage { received.append(($0, $1)) }
        #expect(hear(keep_alive(1, .localhost).encode(), .localhost, s) == nil)
        try await beacon.load_track(1, 0x1234)
        #expect(received.first?.1.port == commands.address()?.port)
        #expect(received.first?.0 == load_track_command(REKORDBOX_NAME, 17, 1, 0x1234))
        await beacon.shutdown()
    }
    @Test("wireless_original_model_gate_applies_before_announcement_dispatch")
    func wireless_original_model_gate_applies_before_announcement_dispatch() {
        let ip = LinkAddress(127, 0, 0, 2)
        for mode: ConnectionMode in [.wired, .wireless, .unknown] {
            for name in ["CDJ-2000", "CDJ-900"] {
                let s = members([1])
                var cfg = config()
                cfg.mode = mode
                var j = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(mode)
                j.hear_keep_alive(keep_alive(1, ip), 0)
                s.join = j
                var wire = rekordbox_claim_stage1([1, 2, 3, 4, 5, 6], 1)
                wire.replaceSubrange(12..<32, with: Array(repeating: 0, count: 20))
                wire.replaceSubrange(12..<(12 + name.utf8.count), with: Array(name.utf8))
                wire[33] = 0
                wire[37] = 1
                _ = hear(wire, ip, s, cfg)
                #expect(s.peers.is_empty() == (mode == .wired))
            }
        }
    }
    @Test("rediscovery_removes_only_the_matching_mac_in_its_evidenced_type_range")
    func rediscovery_removes_only_the_matching_mac_in_its_evidenced_type_range() {
        let ip = LinkAddress(169, 254, 20, 2)
        let all: [UInt8] = [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 17, 18, 33, 41, 42, 43, 44]
        for (kind, removed): (UInt8, [UInt8]) in [
            (1, [1, 2, 3, 4]), (2, [33]), (3, [33]), (4, [17, 18, 41, 42, 43, 44]), (6, [41, 42, 43, 44]),
            (7, [9, 10, 11, 12]), (5, []),
        ] {
            let s = members(all)
            var wire = rekordbox_claim_stage1([1, 2, 3, 4, 5, 6], 1)
            wire[37] = kind
            for cut in 0..<44 {
                _ = hear(Array(wire.prefix(cut)), ip, s)
                #expect(s.peers.len() == all.count)
            }
            let before = s.join?.state()
            #expect(hear(wire, ip, s) == nil)
            let remaining = all.filter { !removed.contains($0) }
            #expect(numbers(s) == remaining)
            #expect(s.players.count == remaining.count)
            #expect(s.join?.state() == before)
            #expect(s.greeted.contains(ip))
            let n = removed.first ?? 1
            _ = hear(keep_alive(n, ip).encode(), ip, s)
            wire[38] ^= 0xff
            _ = hear(wire, ip, s)
            #expect(s.players[n] != nil)
            wire[11] = 1
            wire[38] ^= 0xff
            _ = hear(wire, ip, s)
            #expect(s.players[n] != nil)
        }
    }
    @Test("running_multideck_keepalives_add_only_the_established_identities_and_flags")
    func running_multideck_keepalives_add_only_the_established_identities_and_flags() throws {
        let ip = LinkAddress(169, 254, 20, 2)
        for (number, name, expected): (UInt8, String, [UInt8]) in [
            (9, "XDJ-RX3", [9, 10]), (11, "XDJ-RX3", [11, 12]), (9, "OPUS-QUAD", [9, 10, 11, 12]),
            (9, "OPUS-QUAD-X", [9, 10]), (11, "OPUS-QUAD", [11, 12]),
        ] {
            let s = members([1, 2])
            s.join = Join.new(mac: Array(repeating: 0, count: 6), ip: .localhost, now_ms: 0).test_state(
                .running(number: 17))
            var p = keep_alive(number, ip)
            p.name = name
            p.device_type = .allInOne
            var wire = p.encode()
            wire[0x25] = 0xa5
            wire[0x35] = 0x5a
            for _ in 0..<2 { #expect(hear(wire, ip, s) == nil) }
            let all: [UInt8] = [1, 2] + expected
            #expect(numbers(s) == all)
            #expect(s.players.count == all.count)
            #expect(s.join?.state() == .running(number: 17))
            #expect(
                try KeepAlive.decode(
                    KeepAlive.rekordbox_as(17, Array(repeating: 0, count: 6), .localhost, UInt8(s.peers.len())).encode()
                ).peers == UInt8(all.count))
            for n in expected {
                let peer = try #require(s.peers.peers().first { $0.device_number == n })
                #expect(peer.name == p.name)
                #expect(peer.ip == ip)
                #expect(peer.mac == p.mac)
                #expect(peer.device_type == p.device_type)
                #expect(peer.member_flags == [0xa5, 0x5a])
                #expect(s.players[n]?.address == ip)
                #expect(s.peers.is_synthetic(n) == (n != number))
            }
            #expect(s.greeted.contains(ip))
        }
    }
    @Test("multideck_synthesis_is_inert_before_running_and_for_malformed_keepalives")
    func multideck_synthesis_is_inert_before_running_and_for_malformed_keepalives() {
        let ip = LinkAddress(169, 254, 20, 2)
        var p = keep_alive(9, ip)
        p.name = "OPUS-QUAD"
        let wire = p.encode()
        for state: JoinState in [
            .waiting, .discovery(sent: 1), .probing(round: 1, index: 0), .assigning(sent: 1), .failed("fixture"),
        ] {
            let s = members([])
            s.join = Join.new(mac: Array(repeating: 0, count: 6), ip: .localhost, now_ms: 0).test_state(state)
            _ = hear(wire, ip, s)
            #expect(numbers(s) == [9])
        }
        let s = members([])
        s.join = Join.new(mac: Array(repeating: 0, count: 6), ip: .localhost, now_ms: 0).test_state(
            .running(number: 17))
        for cut in 0..<wire.count {
            _ = hear(Array(wire.prefix(cut)), ip, s)
            #expect(s.peers.is_empty())
        }
        var invalid = wire
        invalid[11] = 1
        _ = hear(invalid, ip, s)
        #expect(s.peers.is_empty())
    }
    @Test("multideck_expiry_uses_received_timers_and_only_the_proven_pairs")
    func multideck_expiry_uses_received_timers_and_only_the_proven_pairs() {
        let ip = LinkAddress(169, 254, 20, 2)
        let s = members([])
        s.join = Join.new(mac: Array(repeating: 0, count: 6), ip: .localhost, now_ms: 0).test_state(
            .running(number: 17))
        var p = keep_alive(9, ip)
        p.name = "OPUS-QUAD"
        s.peers.observe_with_flags(p, 0, [0xa5, 0x5a])
        s.observe_player(p, ip)
        s.synthesize_members(p, ip, 0)
        for n: UInt8 in [10, 11, 12] { s.players[n]!.last_seen = -PLAYER_TIMEOUT - 1000 }
        s.expire_silent_players()
        #expect(s.players.count == 4)
        s.expire_peers(PEER_TIMEOUT_MS)
        #expect(s.peers.len() == 4)
        s.expire_peers(PEER_TIMEOUT_MS + 1)
        #expect(numbers(s) == [11, 12])
        #expect(s.players.count == 2)
        #expect(s.greeted.contains(ip))
        s.expire_peers(.max)
        #expect(s.peers.len() == 2)
        p.device_number = 11
        s.peers.observe_with_flags(p, 10000, [1, 2])
        s.observe_player(p, ip)
        s.synthesize_members(p, ip, 10000)
        s.expire_peers(16001)
        #expect(s.peers.is_empty())
        #expect(s.players.isEmpty)
        #expect(s.greeted.isEmpty)
        #expect(s.to_greet.isEmpty)
    }
    @Test("multideck_identity_refresh_preserves_existing_received_timer_and_unrelated_peers")
    func multideck_identity_refresh_preserves_existing_received_timer_and_unrelated_peers() throws {
        let old = LinkAddress(169, 254, 20, 2)
        let new = LinkAddress(169, 254, 20, 3)
        let s = members([1, 11])
        s.join = Join.new(mac: Array(repeating: 0, count: 6), ip: .localhost, now_ms: 0).test_state(
            .running(number: 17))
        var p = keep_alive(9, new)
        p.name = "OPUS-QUAD"
        p.mac = Array(repeating: 7, count: 6)
        s.peers.observe_with_flags(p, 5000, [0xa5, 0x5a])
        s.observe_player(p, new)
        s.synthesize_members(p, new, 5000)
        let eleven = try #require(s.peers.peers().first { $0.device_number == 11 })
        #expect(eleven.ip == new)
        #expect(eleven.mac == Array(repeating: 7, count: 6))
        #expect(eleven.last_seen_ms == 0)
        #expect(s.players[1]?.address == old)
        #expect(s.players[11]?.address == new)
        s.peers.observe(keep_alive(1, old), 5000)
        s.expire_peers(6001)
        #expect(s.players[11] == nil)
        #expect(s.players[12] == nil)
        #expect(s.players[9] != nil)
        #expect(s.players[10] != nil)
        #expect(s.greeted.contains(old))
    }
    @Test("synthesized_opus_members_follow_numbered_rediscovery_and_reset_removal_paths")
    func synthesized_opus_members_follow_numbered_rediscovery_and_reset_removal_paths() {
        let ip = LinkAddress(169, 254, 20, 2)
        for removal: UInt8 in [7, 0, 0xb] {
            let s = members([])
            s.join = Join.new(mac: Array(repeating: 0, count: 6), ip: .localhost, now_ms: 0).test_state(
                .running(number: 17))
            var p = keep_alive(9, ip)
            p.name = "OPUS-QUAD"
            p.device_type = .allInOne
            _ = hear(p.encode(), ip, s)
            #expect(s.peers.len() == 4)
            var packet: [UInt8]
            if removal == 0 {
                packet = rekordbox_claim_stage1(p.mac, 1)
                packet[37] = 7
            } else {
                packet = p.encode()
                packet[10] = removal
            }
            #expect(hear(packet, ip, s) == nil)
            if removal == 7 {
                #expect(numbers(s) == [11, 12])
                #expect(s.players.count == 2)
                #expect(s.greeted.contains(ip))
                packet[36] = 11
                _ = hear(packet, ip, s)
            }
            #expect(s.peers.is_empty())
            #expect(s.players.isEmpty)
            #expect(s.greeted.isEmpty)
            #expect(s.to_greet.isEmpty)
        }
    }
    @Test("acquired_session_classification_gates_coexistence_before_membership_and_synthesis")
    func acquired_session_classification_gates_coexistence_before_membership_and_synthesis() {
        for mode: ConnectionMode in [.wired, .wireless, .unknown] {
            let cfg = rejection_config(mode)
            for all_in_one in [false, true] {
                let ip = LinkAddress(192, 168, 50, 10)
                var first = keep_alive(all_in_one ? 9 : 1, ip)
                if all_in_one {
                    first.device_type = .allInOne
                    first.name = "XDJ-RX3"
                }
                let s = acquired(cfg, first)
                let before = s.peers.peers()
                let greetings = s.to_greet
                for n: UInt8 in all_in_one ? Array(1...4) : Array(9...12) {
                    var other = keep_alive(n, LinkAddress(192, 168, 50, 20))
                    if !all_in_one {
                        other.device_type = .allInOne
                        other.name = "OPUS-QUAD"
                    }
                    _ = hear(other.encode(), other.ip, s, cfg)
                    #expect(s.peers.peers() == before)
                    #expect(s.players.count == before.count)
                    #expect(s.to_greet == greetings)
                    #expect(s.join?.number() == 17)
                }
                var accepted = first
                if all_in_one { accepted.name = "OPUS-QUAD" }
                _ = hear(accepted.encode(), ip, s, cfg)
                #expect(numbers(s) == (all_in_one ? [9, 10, 11, 12] : [1]))
            }
        }
    }
    @Test("initialized_netif_guards_all_announcement_dispatch_not_member_ownership")
    func initialized_netif_guards_all_announcement_dispatch_not_member_ownership() throws {
        let cfg = rejection_config(.wired)
        let first = keep_alive(1, LinkAddress(192, 168, 50, 10))
        var discovery = rekordbox_claim_stage1(first.mac, 1)
        discovery[37] = 1
        var disconnect = disconnect_bytes(1, first.ip)
        disconnect[10] = 7
        var conflict = disconnect
        conflict[10] = 8
        var compatibility = first.encode()
        compatibility[10] = 0xb
        var block = rekordbox_claim_stage2(Array(repeating: 9, count: 6), first.ip, 17, 1)
        block[11] = 2
        block += Array(repeating: 0, count: 68 - block.count)
        block[34] = 0
        block[35] = 68
        block[48] = 1
        block[67] = 0xa5
        #expect(try NumberBlock.decode(block).names(17, cfg.mode))
        let probe = rekordbox_claim_stage2(Array(repeating: 9, count: 6), first.ip, 17, 1)
        let new_member = keep_alive(2, LinkAddress(192, 168, 50, 20))
        let changed = keep_alive(1, new_member.ip)
        let frames = [
            discovery, disconnect, conflict, compatibility, new_member.encode(), changed.encode(), block, probe,
            rejection_frame(),
        ]
        for sender in [cfg.address, LinkAddress(192, 168, 51, 10)] {
            for frame in frames {
                let s = acquired(cfg, first)
                let before = s.peers.peers()
                #expect(hear(frame, sender, s, cfg) == nil)
                #expect(s.peers.peers() == before)
                #expect(s.players.count == 1)
                #expect(s.join?.number() == 17)
                #expect(!s.rejected())
            }
        }
        let s = acquired(cfg, first)
        _ = hear(disconnect, LinkAddress(192, 168, 50, 99), s, cfg)
        #expect(s.peers.is_empty())
        #expect(s.players.isEmpty)
        for (frame, counter): ([UInt8], UInt8) in [(block, 0xa5), (probe, 1)] {
            let s = acquired(cfg, first)
            let out = try #require(hear(frame, LinkAddress(192, 168, 50, 99), s, cfg))
            #expect(out.packet == number_in_use_reply_with_counter(REKORDBOX_NAME, 17, counter))
            #expect(out.to == first.ip)
            #expect(s.peers.len() == 1)
        }
        let updated = acquired(cfg, first)
        _ = hear(changed.encode(), changed.ip, updated, cfg)
        #expect(updated.peers.peers()[0].ip == changed.ip)
        #expect(updated.players[1]?.address == changed.ip)
    }
    @Test("netif_guard_preserves_fresh_unknown_and_cached_after_reset_boundaries")
    func netif_guard_preserves_fresh_unknown_and_cached_after_reset_boundaries() {
        for mode: ConnectionMode in [.wired, .wireless, .unknown] {
            let cfg = rejection_config(mode)
            let first = keep_alive(1, LinkAddress(192, 168, 50, 10))
            let disconnect = disconnect_bytes(1, first.ip)
            for sender in [cfg.address, LinkAddress(10, 1, 2, 3)] {
                let s = members([1])
                s.join = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(mode).test_state(
                    .discovery(sent: 0))
                _ = hear(disconnect, sender, s, cfg)
                #expect(s.peers.is_empty())
            }
            let s = acquired(cfg, first)
            s.join?.reset(0)
            let other = keep_alive(2, LinkAddress(10, 1, 2, 3))
            _ = hear(other.encode(), other.ip, s, cfg)
            if mode == .unknown {
                #expect(s.peers.len() == 2)
                if case .discovery? = s.join?.state() {} else { Issue.record("Discovery") }
            } else {
                #expect(s.peers.len() == 1)
                #expect(s.join?.state() == .waiting)
            }
        }
    }
    @Test("netif_guard_filters_number_replies_and_keepalive_occupancy_during_real_probing")
    func netif_guard_filters_number_replies_and_keepalive_occupancy_during_real_probing() {
        let cfg = rejection_config(.wired)
        let first = keep_alive(1, LinkAddress(192, 168, 50, 10))
        let reply = number_in_use_reply_with_counter("rekordbox", 17, 0xa5)
        #expect(reply.count == 39)
        let occupied = KeepAlive.rekordbox_as(17, Array(repeating: 9, count: 6), LinkAddress(192, 168, 50, 99), 0)
            .encode()
        for frame in [reply, occupied] {
            for (sender, number): (LinkAddress, UInt8) in [
                (cfg.address, 17), (LinkAddress(192, 168, 51, 10), 17), (LinkAddress(192, 168, 50, 99), 18),
            ] {
                let s = BeaconShared(clock: testClock())
                s.join = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(cfg.mode)
                _ = hear(first.encode(), first.ip, s, cfg)
                for tick: UInt64 in 0..<3 { _ = s.join?.tick(tick * TICK) }
                if case .probing? = s.join?.state() {} else { Issue.record("Probing") }
                _ = hear(frame, sender, s, cfg)
                for tick: UInt64 in 3..<50 { _ = s.join?.tick(tick * TICK) }
                #expect(s.join?.number() == number)
                let admitted = number == 18 && frame[10] == 6
                #expect(s.peers.len() == (admitted ? 2 : 1))
                #expect((s.players[17] != nil) == admitted)
            }
        }
    }
    @Test("session_classification_allows_eleven_pair_and_reclassifies_only_on_next_successful_linkup")
    func session_classification_allows_eleven_pair_and_reclassifies_only_on_next_successful_linkup() throws {
        for mode: ConnectionMode in [.wired, .wireless, .unknown] {
            let cfg = rejection_config(mode)
            let ip = LinkAddress(192, 168, 50, 10)
            var first = keep_alive(9, ip)
            first.device_type = .allInOne
            first.name = "XDJ-RX3"
            let s = acquired(cfg, first)
            let second = keep_alive(11, LinkAddress(192, 168, 50, 20))
            var wire = second.encode()
            wire[0x25] = 0xa5
            wire[0x35] = 0x5a
            _ = hear(wire, second.ip, s, cfg)
            #expect(numbers(s) == [9, 11, 12])
            for n: UInt8 in [11, 12] {
                let peer = try #require(s.peers.peers().first { $0.device_number == n })
                #expect(peer.member_flags == [0xa5, 0x5a])
                #expect(peer.ip == second.ip)
                #expect(s.players[n]?.address == second.ip)
            }
            _ = hear(keep_alive(1, ip).encode(), ip, s, cfg)
            #expect(s.players[1] == nil)
            var reset = first.encode()
            reset[10] = 0xb
            _ = hear(reset, ip, s, cfg)
            #expect(s.peers.is_empty())
            #expect(s.join?.state() == .waiting)
            _ = hear(keep_alive(1, ip).encode(), ip, s, cfg)
            for tick: UInt64 in 0..<50 { _ = s.join?.tick(tick * TICK) }
            #expect(s.join?.number() == 17)
            _ = hear(first.encode(), ip, s, cfg)
            #expect(numbers(s) == [1])
            #expect(s.players.count == 1)
        }
    }
    @Test("failed_wireless_original_attempt_does_not_classify_the_later_successful_session")
    func failed_wireless_original_attempt_does_not_classify_the_later_successful_session() {
        let cfg = rejection_config(.wireless)
        let ip = LinkAddress(192, 168, 50, 10)
        let s = BeaconShared(clock: testClock())
        s.join = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(cfg.mode)
        var first = keep_alive(1, ip)
        first.name = "CDJ-2000"
        first.generation = 0
        _ = hear(first.encode(), ip, s, cfg)
        #expect(s.join?.state() == .waiting)
        #expect(s.peers.is_empty())
        first = keep_alive(9, ip)
        first.device_type = .allInOne
        first.name = "OPUS-QUAD"
        _ = hear(first.encode(), ip, s, cfg)
        for tick: UInt64 in 0..<50 { _ = s.join?.tick(tick * TICK) }
        #expect(s.join?.number() == 17)
        _ = hear(keep_alive(1, ip).encode(), ip, s, cfg)
        #expect(s.players[1] == nil)
        #expect(numbers(s) == [9])
    }
    @Test("slot_deadlines_survive_disconnect_rediscovery_and_paired_removal_before_recreation")
    func slot_deadlines_survive_disconnect_rediscovery_and_paired_removal_before_recreation() throws {
        let cfg = rejection_config(.wired)
        let ip = LinkAddress(192, 168, 50, 10)
        var primary = keep_alive(9, ip)
        primary.device_type = .allInOne
        primary.name = "XDJ-RX3"
        var secondary = primary
        secondary.device_number = 10
        for removal in ["disconnect", "rediscovery", "paired_disconnect", "paired_expiry"] {
            let s = acquired(cfg, primary)
            let secondary_seen: UInt64 = removal == "paired_expiry" ? 1000 : 0
            s.peers.observe_with_flags(primary, 0, [1, 2])
            s.peers.observe_with_flags(secondary, secondary_seen, [0xa5, 0x5a])
            s.observe_player(secondary, ip)
            s.greeted.append(ip)
            switch removal {
            case "rediscovery":
                var w = rekordbox_claim_stage1(primary.mac, 1)
                w[37] = 7
                #expect(try Discovery.decode(w).device_type == 7)
                _ = hear(w, ip, s, cfg)
            case "paired_expiry": s.expire_peers(6001)
            default: _ = hear(disconnect_bytes(removal == "disconnect" ? 10 : 9, ip), ip, s, cfg)
            }
            #expect(!numbers(s).contains(10))
            #expect(s.players[10] == nil)
            #expect(s.greeted.contains(ip) == (removal == "disconnect"))
            let recreated_at: UInt64 = removal == "paired_expiry" ? 6500 : 1000
            s.peers.observe_with_flags(primary, recreated_at, [1, 2])
            s.observe_player(primary, ip)
            s.synthesize_members(primary, ip, recreated_at)
            let recreated = try #require(s.peers.peers().first { $0.device_number == 10 })
            #expect(recreated.last_seen_ms == secondary_seen)
            #expect(recreated.member_flags == [1, 2])
            #expect(!s.peers.is_synthetic(10))
            let deadline = secondary_seen + PEER_TIMEOUT_MS
            s.expire_peers(deadline)
            #expect(numbers(s).contains(10))
            s.expire_peers(deadline + 1)
            #expect(!numbers(s).contains(10))
            s.players[10]!.last_seen = -PLAYER_TIMEOUT - 1
            s.expire_silent_players()
            #expect(s.players[10] == nil)
            #expect(s.players[9] != nil)
            #expect(s.greeted.contains(ip) == (removal == "disconnect"))
        }
    }
    @Test("inactive_primary_deadline_does_not_remove_a_new_secondary_and_session_clear_stops_all_timers")
    func inactive_primary_deadline_does_not_remove_a_new_secondary_and_session_clear_stops_all_timers() {
        let s = members([])
        let ip = LinkAddress(169, 254, 20, 2)
        let primary = keep_alive(9, ip)
        let secondary = keep_alive(10, ip)
        s.peers.observe(primary, 0)
        s.remove_member(9)
        s.peers.observe_synthetic(secondary, 1000, nil)
        s.observe_player(secondary, ip)
        s.expire_peers(6001)
        #expect(numbers(s) == [10])
        #expect(s.players[10] != nil)
        s.peers.observe(secondary, 10000)
        s.remove_member(10)
        s.clear_members()
        s.peers.observe_synthetic(secondary, 11000, nil)
        #expect(s.peers.is_synthetic(10))
        #expect(s.peers.expire_received(.max) == [])
    }
    @Test("rejection_clears_every_store_and_database_readiness_in_all_known_mode_states")
    func rejection_clears_every_store_and_database_readiness_in_all_known_mode_states() throws {
        let sender = LinkAddress(192, 168, 50, 10)
        for mode: ConnectionMode in [.wired, .wireless] {
            let cfg = rejection_config(mode)
            let candidate: UInt8 = mode == .wireless ? 41 : 17
            let running: UInt8 = mode == .wireless ? 44 : 18
            for state: JoinState in [
                .waiting, .discovery(sent: 2), .probing(round: 4, index: 2), .assigning(sent: 3),
                .running(number: running), .failed("fixture"),
            ] {
                let assigned: UInt8
                if case .running = state { assigned = running } else { assigned = 0 }
                let s = members([1, 9, 10, 11, 12, 33])
                var j = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(mode)
                j.hear_keep_alive(keep_alive(1, sender), 0)
                s.join = j.test_state(state)
                s.master = MasterState(on: true, bpm_x100: 12300, bar_beat: 3)
                s.assigned.store(assigned)
                let cell = s.assigned
                let handler = CatalogHandler(EmptyCatalog()).with_device(cell)
                #expect((handler.open_ready() != nil) == (assigned != 0))
                let out = try #require(hear(rejection_frame(), sender, s, cfg))
                #expect(out.packet == disconnect_bytes(assigned == 0 ? candidate : running, cfg.address))
                #expect(out.to == nil)
                #expect(cell.load() == 0)
                #expect(handler.open_ready() == nil)
                #expect(s.rejected())
                #expect(s.down?.contains("rejected") == true)
                #expect(s.join?.state() == .waiting)
                #expect(s.peers.is_empty())
                #expect(s.players.isEmpty)
                #expect(s.greeted.isEmpty)
                #expect(s.to_greet.isEmpty)
                #expect(s.master == MasterState(on: false, bpm_x100: 0, bar_beat: 0))
                #expect(
                    try #require(hear(rejection_frame(), sender, s, cfg)).packet
                        == disconnect_bytes(candidate, .unspecified))
                var frames = [
                    keep_alive(1, sender).encode(), rekordbox_claim_stage1(Array(repeating: 1, count: 6), 1),
                    rekordbox_claim_stage2(Array(repeating: 1, count: 6), sender, running, 5),
                    number_in_use_reply(REKORDBOX_NAME, running),
                ]
                for k: UInt8 in [4, 7, 8, 0xb] {
                    var f = keep_alive(1, sender).encode()
                    f[10] = k
                    frames.append(f)
                }
                for f in frames { #expect(hear(f, sender, s, cfg) == nil) }
                s.join?.reset(0)
                #expect(s.join?.tick(60000) == nil)
                #expect(s.rejected())
                #expect(s.peers.is_empty() && s.players.isEmpty)
                #expect(s.greeted.isEmpty && s.to_greet.isEmpty)
                #expect(cell.load() == 0)
            }
        }
    }
    @Test("fresh_rejection_is_terminal_without_an_outgoing_datagram_and_unknown_is_unchanged")
    func fresh_rejection_is_terminal_without_an_outgoing_datagram_and_unknown_is_unchanged() {
        let sender = LinkAddress(10, 9, 8, 7)
        for mode: ConnectionMode in [.wired, .wireless, .unknown] {
            let cfg = rejection_config(mode)
            let s = members([1])
            s.join = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(mode)
            #expect(hear(rejection_frame(), sender, s, cfg) == nil)
            let known = mode != .unknown
            #expect(s.rejected() == known)
            #expect(s.peers.is_empty() == known)
            #expect(s.players.isEmpty == known)
            #expect((s.down != nil) == known)
            #expect(s.join?.tick(60000) == nil)
            #expect(hear(rejection_frame(), sender, s, cfg) == nil)
            let r = BeaconShared(clock: testClock())
            r.join = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(mode)
            _ = hear(keep_alive(1, sender).encode(), sender, r, cfg)
            #expect(!r.rejected())
            if case .discovery? = r.join?.state() {} else { Issue.record("Discovery") }
        }
    }
    @Test("rejection_header_and_network_sender_guards_are_scoped_and_preserve_state")
    func rejection_header_and_network_sender_guards_are_scoped_and_preserve_state() {
        let cfg = rejection_config(.wired)
        let on = LinkAddress(192, 168, 50, 10)
        for initialized in [false, true] {
            for sender in [LinkAddress.unspecified, cfg.address, LinkAddress(192, 168, 51, 10), on] {
                var j = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(cfg.mode)
                if initialized { j.hear_keep_alive(keep_alive(1, on), 0) }
                let s = BeaconShared(clock: testClock())
                s.join = j
                for cut in 0..<36 {
                    #expect(hear(Array(rejection_frame().prefix(cut)), sender, s, cfg) == nil)
                    #expect(!s.rejected())
                }
                var invalid = rejection_frame()
                invalid[0] ^= 0xff
                #expect(hear(invalid, sender, s, cfg) == nil)
                #expect(!s.rejected())
                let accepted = initialized ? sender == on : sender != .unspecified
                let out = hear(rejection_frame(), sender, s, cfg)
                #expect(s.rejected() == accepted)
                #expect((out != nil) == (initialized && accepted))
            }
        }
    }
    @Test("wireless_original_failed_linkup_retains_pre_rejection_identity_without_membership")
    func wireless_original_failed_linkup_retains_pre_rejection_identity_without_membership() throws {
        let cfg = rejection_config(.wireless)
        let sender = LinkAddress(192, 168, 50, 10)
        for name in ["CDJ-2000", "CDJ-900"] {
            let s = BeaconShared(clock: testClock())
            s.join = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(cfg.mode)
            var original = keep_alive(1, sender)
            original.name = name
            original.generation = 0
            _ = hear(original.encode(), sender, s, cfg)
            #expect(s.join?.state() == .waiting)
            #expect(s.join?.network_initialized() == true)
            #expect(s.peers.is_empty() && s.players.isEmpty)
            #expect(s.greeted.isEmpty && s.to_greet.isEmpty)
            #expect(s.assigned.load() == 0)
            #expect(try #require(hear(rejection_frame(), sender, s, cfg)).packet == disconnect_bytes(41, cfg.address))
            #expect(try #require(hear(rejection_frame(), sender, s, cfg)).packet == disconnect_bytes(41, .unspecified))
        }
    }
    @Test("rejection_disconnect_output_uses_configured_broadcast_destination")
    func rejection_disconnect_output_uses_configured_broadcast_destination() async throws {
        let clock = testClock()
        let factory = FakeExportSocketFactory(clock: clock)
        let receiver = try factory.createUDPSocket(reuseAddr: false) as! FakeExportUDPSocket
        let sender = try factory.createUDPSocket(reuseAddr: false)
        _ = try await receiver.bind(port: 0, address: "127.0.0.1")
        _ = try await sender.bind(port: 0, address: "127.0.0.1")
        var cfg = config()
        cfg.announce_port = UInt16(receiver.address()!.port)
        let remote = LinkAddress(127, 0, 0, 2)
        let s = BeaconShared(clock: clock)
        var j = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(cfg.mode)
        j.hear_keep_alive(keep_alive(1, remote), 0)
        s.join = j.test_state(.running(number: 18))
        let out = try #require(hear(rejection_frame(), remote, s, cfg))
        #expect(out.to == nil)
        var received: [([UInt8], RemoteInfo)] = []
        receiver.onMessage { received.append(($0, $1)) }
        send_announce(sender, out, cfg.broadcast, cfg.announce_port)
        #expect(received.first?.0 == disconnect_bytes(18, cfg.address))
        #expect(received.first?.1.port == sender.address()?.port)
    }
    @Test("fresh_known_mode_rejection_sends_no_udp_in_the_real_announce_loop")
    func fresh_known_mode_rejection_sends_no_udp_in_the_real_announce_loop() async throws {
        for mode: ConnectionMode in [.wired, .wireless] {
            let clock = testClock()
            let factory = FakeExportSocketFactory(clock: clock)
            let receiver = try factory.createUDPSocket(reuseAddr: false) as! FakeExportUDPSocket
            _ = try await receiver.bind(port: 0, address: "127.0.0.1")
            var cfg = rejection_config(mode)
            cfg.broadcast = .localhost
            cfg.announce_port = UInt16(receiver.address()!.port)
            // 원본의 announce_loop 단독 구동을 같은 수신·타이머 경계로 연결한다.
            let announce = try factory.createUDPSocket(reuseAddr: false) as! FakeExportUDPSocket
            _ = try await announce.bind(port: 0, address: "127.0.0.1")
            let s = BeaconShared(clock: clock)
            s.join = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(cfg.mode)
            var observed: [[UInt8]] = []
            receiver.onMessage { packet, _ in observed.append(packet) }
            let beacon = Beacon(
                config: cfg, facts: Loads(), clock: clock, interfaceProvider: FakeInterfaceProvider(),
                announce: announce, status: announce, statusSender: announce, beats: nil, shared: s)
            beacon.start_announce_loop()
            func transmit(_ bytes: [UInt8]) {
                receiver.send(bytes, port: announce.address()!.port, address: "127.0.0.1", callback: nil)
            }
            transmit(rejection_frame())
            transmit(keep_alive(1, .localhost).encode())
            transmit(rejection_frame())
            clock.advance(ms: 100)
            #expect(s.rejected())
            #expect(s.down != nil)
            #expect(s.assigned.load() == 0)
            #expect(observed.isEmpty)
            await beacon.shutdown()
            try receiver.close(nil)
        }
    }
    @Test("a_late_player_status_cannot_revive_terminal_membership_or_report_a_load")
    func a_late_player_status_cannot_revive_terminal_membership_or_report_a_load() async throws {
        let clock = testClock()
        let factory = FakeExportSocketFactory(clock: clock)
        let receiver = try factory.createUDPSocket(reuseAddr: false) as! FakeExportUDPSocket
        let socket = try factory.createUDPSocket(reuseAddr: false)
        _ = try await receiver.bind(port: 0, address: "127.0.0.1")
        _ = try await socket.bind(port: 0, address: "127.0.0.1")
        var cfg = config()
        cfg.player_port = UInt16(receiver.address()!.port)
        let sender = LinkAddress(127, 0, 0, 2)
        let s = BeaconShared(clock: clock)
        var j = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(cfg.mode)
        j.hear_keep_alive(keep_alive(1, sender), 0)
        s.join = j.test_state(.running(number: 17))
        s.assigned.store(17)
        s.greeted = [.localhost]
        let facts = Loads()
        var packet = try UpstreamFixtures.bytes(crate: "rbl-link", path: "tests/fixtures/cdj-status-playing-ours.bin")
        packet[0x28] = 17
        #expect(try beacon_status_from_packet(packet) != nil)
        #expect(hear(rejection_frame(), sender, s, cfg) != nil)
        var received: [[UInt8]] = []
        receiver.onMessage { packet, _ in received.append(packet) }
        hear_player_status(packet, .localhost, socket, cfg, s, facts, 17)
        #expect(s.players.isEmpty && s.peers.is_empty())
        #expect(s.greeted.isEmpty && s.to_greet.isEmpty)
        #expect(received.isEmpty)
        #expect(facts.loads == 0)
        let replacement = BeaconShared(clock: clock)
        hear_player_status(packet, .localhost, socket, cfg, replacement, facts, 17)
        #expect(facts.loads == 1)
        #expect(replacement.players.count == 1)
    }
    @Test("rejection_runtime_model_gate_is_distinct_from_selected_mode_and_cached_candidate")
    func rejection_runtime_model_gate_is_distinct_from_selected_mode_and_cached_candidate() throws {
        let sender = LinkAddress(192, 168, 50, 10)
        for name in ["CDJ-2000", "CDJ-900"] {
            var original = rejection_frame()
            original.replaceSubrange(12..<32, with: Array(repeating: 0, count: 20))
            original.replaceSubrange(12..<(12 + name.utf8.count), with: Array(name.utf8))
            original[33] = 0
            for mode: ConnectionMode in [.wired, .wireless] {
                let cfg = rejection_config(mode)
                let fresh = BeaconShared(clock: testClock())
                fresh.join = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(mode)
                #expect(fresh.join?.excludes_original_models() == false)
                #expect(hear(original, sender, fresh, cfg) == nil)
                #expect(fresh.rejected())
                #expect(fresh.join?.excludes_original_models() == true)
                var j = Join.new(mac: cfg.mac, ip: cfg.address, now_ms: 0).with_mode(mode)
                j.hear_keep_alive(keep_alive(1, sender), 0)
                let active = BeaconShared(clock: testClock())
                active.join = j
                let out = hear(original, sender, active, cfg)
                #expect((out != nil) == (mode == .wired))
                if mode == .wireless {
                    #expect(!active.rejected())
                    #expect(hear(rejection_frame(), sender, active, cfg) != nil)
                }
                #expect(active.rejected())
                #expect(hear(original, sender, active, cfg) == nil)
                let modern = try #require(hear(rejection_frame(), sender, active, cfg))
                let candidate: UInt8 = mode == .wireless ? 41 : 17
                #expect(modern.packet == disconnect_bytes(candidate, .unspecified))
            }
        }
    }
}
