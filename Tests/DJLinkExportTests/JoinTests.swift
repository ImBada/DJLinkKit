// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
import DJLinkExportProtocol
// 원본: rbl-link/src/join.rs inline 시험. 입력·기대값을 유지한다.
import Testing

@testable import DJLinkExport

@Suite struct JoinTests {
    let MAC: [UInt8] = [0, 0xe0, 0x4c, 0xcf, 0x63, 0x2e]
    let IP = try! DJLinkExportProtocol.Address4("192.168.1.14")
    func player() -> KeepAlive {
        KeepAlive(
            name: "CDJ-3000", device_number: 1, device_type: .cdj, mac: [0x24, 0x97, 0xed, 0x0b, 0x40, 0x43],
            ip: try! .init("192.168.1.152"), peers: 0, generation: 3)
    }
    func run(_ join: inout Join, _ initial: UInt64, _ limit: Int) -> ([Outgoing], UInt64) {
        var out = [Outgoing]()
        var now = initial
        while out.count < limit {
            if let packet = join.tick(now) {
                out.append(packet)
            } else {
                switch join.state() {
                case .running, .failed, .waiting: return (out, now)
                default: now += TICK
                }
            }
        }
        return (out, now)
    }
    @Test("nothing_goes_out_until_a_player_is_heard") func waiting() {
        let now: UInt64 = 0
        var join = Join.new(mac: MAC, ip: IP, now_ms: now)
        #expect(join.tick(now + 5000) == nil)
        #expect(join.state() == .waiting)
        var rekordbox = player()
        rekordbox.device_type = .rekordbox
        join.hear_keep_alive(rekordbox, now)
        #expect(join.state() == .waiting)
        var old = player()
        old.name = "CDJ-2000"
        old.generation = 0
        join.hear_keep_alive(old, now)
        #expect(join.state() == .waiting)
        join.hear_keep_alive(player(), now)
        #expect(join.state() == .discovery(sent: 0))
    }
    @Test("the_join_is_three_claims_then_six_rounds_of_six_probes_then_seventeen") func sequence() {
        let now: UInt64 = 0
        var join = Join.new(mac: MAC, ip: IP, now_ms: now)
        join.hear_keep_alive(player(), now)
        let (out, _) = run(&join, now, 100)
        #expect(out.count == 3 + 36)
        #expect(out[0].packet == rekordbox_claim_stage1(MAC, 1))
        #expect(out[2].packet == rekordbox_claim_stage1(MAC, 3))
        #expect(out[3].packet == rekordbox_claim_stage2(MAC, IP, 0x11, 1))
        #expect(out[8].packet == rekordbox_claim_stage2(MAC, IP, 0x2c, 1))
        #expect(out[9].packet == rekordbox_claim_stage2(MAC, IP, 0x11, 2))
        #expect(out[38].packet == rekordbox_claim_stage2(MAC, IP, 0x2c, 6))
        #expect(out.allSatisfy { $0.to == nil })
        #expect(join.state() == .running(number: 0x11))
        #expect(join.number() == 0x11)
    }
    @Test("a_number_answered_for_is_skipped_and_eighteen_is_taken_when_seventeen_is_held") func skip() throws {
        var join = Join.new(mac: MAC, ip: IP, now_ms: 0)
        join.hear_keep_alive(player(), 0)
        let (out, now) = run(&join, 0, 4)
        #expect(out[3].packet[0x2e] == 0x11)
        let reply = try NumberReply.decode(number_in_use_reply("rekordbox", 0x11))
        join.hear_reply(reply)
        let (rest, _) = run(&join, now, 100)
        #expect(rest.count == 5 + 5 * 5)
        #expect(rest.allSatisfy { $0.packet[0x2e] != 0x11 })
        #expect(join.state() == .running(number: 0x12))
    }
    @Test("with_all_preferred_numbers_held_it_asks_to_be_assigned_and_takes_the_answer") func assigned() throws {
        var join = Join.new(mac: MAC, ip: IP, now_ms: 0)
        join.hear_keep_alive(player(), 0)
        let (_, start) = run(&join, 0, 3)
        for number in [UInt8(17), 18] {
            join.hear_reply(try NumberReply.decode(number_in_use_reply("rekordbox", number)))
        }
        let (out, now) = run(&join, start, 4 * 6 + 1)
        #expect(out.count == 4 * 6 + 1)
        let request = out[24]
        #expect(request.what == "assign request")
        #expect(request.packet[0x0b] == PROBE_SUBTYPE_ASSIGN)
        #expect(request.packet[0x2e] == 0x11)
        #expect(join.state() == .assigning(sent: 1))
        var accepted = number_in_use_reply("DJM-V10", 0x11)
        accepted[0x0b] = PROBE_SUBTYPE_ASSIGN
        accepted[0x26] = 0
        join.hear_reply(try NumberReply.decode(accepted))
        #expect(join.state() == .running(number: 0x11))
        #expect(join.tick(now + TICK) == nil)
    }
    @Test("unanswered_assign_requests_end_in_failure_after_six") func unanswered() throws {
        var join = Join.new(mac: MAC, ip: IP, now_ms: 0)
        join.hear_keep_alive(player(), 0)
        let (_, now) = run(&join, 0, 3)
        for number in [UInt8(17), 18] {
            join.hear_reply(try NumberReply.decode(number_in_use_reply("rekordbox", number)))
        }
        let (out, _) = run(&join, now, 100)
        #expect(out.filter { $0.what == "assign request" }.count == 6)
        if case .failed = join.state() {} else { Issue.record("expected Failed") }
        #expect(join.number() == nil)
    }
    @Test("running_it_answers_a_probe_of_its_number_and_no_other") func answering() throws {
        var join = Join.new(mac: MAC, ip: IP, now_ms: 0)
        join.hear_keep_alive(player(), 0)
        _ = run(&join, 0, 100)
        let other_mac: [UInt8] = [1, 2, 3, 4, 5, 6]
        let other_ip = try DJLinkExportProtocol.Address4("192.168.1.20")
        let probe = try NumberProbe.decode(rekordbox_claim_stage2(other_mac, other_ip, 0x11, 1))
        let answerOptional = join.hear_probe(probe)
        let answer = try #require(answerOptional)
        #expect(answer.to == other_ip)
        #expect(answer.packet == number_in_use_reply_with_counter("rekordbox", 0x11, 1))
        let reply = try NumberReply.decode(answer.packet)
        #expect(reply.number == 0x11 && reply.status == NUMBER_REPLY_IN_USE && reply.subtype == PROBE_SUBTYPE_PROBE)
        let other = try NumberProbe.decode(rekordbox_claim_stage2(other_mac, other_ip, 0x12, 1))
        #expect(join.hear_probe(other) == nil)
        let ours = try NumberProbe.decode(rekordbox_claim_stage2(MAC, IP, 0x11, 1))
        #expect(join.hear_probe(ours) == nil)
        join.reset(0)
        #expect(join.state() == .waiting)
    }
    @Test("occupancy_masks_echo_counters_only_in_the_established_mode_and_state") func masks() throws {
        let other_ip = try DJLinkExportProtocol.Address4("192.168.1.20")
        for (mode, choices) in [(ConnectionMode.wired, [UInt8(17), 18]), (.wireless, [41, 42, 43, 44])] {
            for number in choices {
                for counter in [UInt8(0), 1, 255] {
                    var join = Join.new(mac: MAC, ip: IP, now_ms: 0).with_mode(mode)
                    join.current = .running(number: number)
                    var request = rekordbox_claim_stage2([UInt8](repeating: 1, count: 6), other_ip, 0, 0)
                    request += [UInt8](repeating: 0, count: 68 - request.count)
                    request[11] = PROBE_SUBTYPE_BLOCK
                    request[34] = 0
                    request[35] = 68
                    request[48] = mode == .wired ? UInt8(1) << (number - 17) : 0
                    request[51] = mode == .wireless ? UInt8(1) << (number - 41) : 0
                    request[67] = counter
                    let block = try NumberBlock.decode(request)
                    let before = join.current
                    let responseOptional = join.hear_block(block)
                    let response = try #require(responseOptional)
                    #expect(response.to == other_ip)
                    var expected: [UInt8] =
                        [0x51, 0x73, 0x70, 0x74, 0x31, 0x57, 0x6d, 0x4a, 0x4f, 0x4c, 3, 0] + Array("rekordbox".utf8)
                    expected += [UInt8](repeating: 0, count: 32 - expected.count)
                    expected += [1, 3, 0, 39, number, counter, 1]
                    #expect(response.packet == expected)
                    #expect(join.state() == before)
                    var absent = block
                    absent.wired_mask = 0
                    absent.wireless_mask = 0
                    #expect(join.hear_block(absent) == nil)
                    join.mode = .unknown
                    #expect(join.hear_block(block) == nil)
                    join.mode = mode
                    var echo = block
                    echo.ip = IP
                    echo.mac = MAC
                    #expect(join.hear_block(echo) == nil)
                    for state in [JoinState.waiting, .probing(round: 1, index: 0), .assigning(sent: 1)] {
                        join.current = state
                        #expect(join.hear_block(block) == nil)
                    }
                }
            }
        }
    }
    @Test("probing_keepalives_mark_all_candidates_without_a_probe_reply") func keepalives() throws {
        var join = Join.new(mac: MAC, ip: IP, now_ms: 0).with_mode(.wired)
        join.hear_keep_alive(player(), 0)
        _ = run(&join, 0, 3)
        var packet = player()
        packet.device_type = .rekordbox
        for number in [UInt8(17), 41, 42, 43, 44] {
            packet.device_number = number
            let decoded = try KeepAlive.decode(packet.encode())
            join.hear_keep_alive(decoded, 0)
            join.hear_keep_alive(decoded, 0)
        }
        #expect(join.in_use == [true, false, true, true, true, true])
        packet.device_number = 18
        packet.ip = IP
        packet.mac = MAC
        join.hear_keep_alive(packet, 0)
        #expect(!join.in_use[1])
        packet.ip = player().ip
        packet.mac = player().mac
        packet.device_type = .other(10)
        join.hear_keep_alive(packet, 0)
        #expect(!join.in_use[1])
        let (out, _) = run(&join, 0, 100)
        #expect(out.allSatisfy { $0.packet[46] == 18 })
        #expect(join.number() == 18)
    }
    @Test("original_players_join_only_on_a_known_wired_interface") func originals() throws {
        for name in ["CDJ-2000", "CDJ-900"] {
            for mode in [ConnectionMode.wired, .wireless, .unknown] {
                var join = Join.new(mac: MAC, ip: IP, now_ms: 0).with_mode(mode)
                var packet = player()
                packet.name = name
                packet.generation = 0
                join.hear_keep_alive(try KeepAlive.decode(packet.encode()), 0)
                if mode == .wired {
                    #expect(join.state() == .discovery(sent: 0))
                    let ticked = join.tick(0)
                    #expect(try #require(ticked).packet == rekordbox_claim_stage1(MAC, 1))
                } else {
                    #expect(join.state() == .waiting)
                    packet.generation = 1
                    join.hear_keep_alive(packet, 0)
                    #expect(join.state() == .discovery(sent: 0))
                }
            }
        }
    }
    @Test("single_number_probe_echoes_every_counter_and_does_not_answer_assignment") func counters() throws {
        var join = Join.new(mac: MAC, ip: IP, now_ms: 0).test_state(.running(number: 17))
        let destination = try DJLinkExportProtocol.Address4("192.168.1.20")
        for counter in [UInt8(0), 1, 255] {
            var wire = rekordbox_claim_stage2([UInt8](repeating: 1, count: 6), destination, 17, counter)
            let responseOptional = join.hear_probe(try NumberProbe.decode(wire))
            let response = try #require(responseOptional)
            #expect(response.to == destination)
            #expect(response.packet == number_in_use_reply_with_counter(REKORDBOX_NAME, 17, counter))
            #expect(response.packet[37] == counter)
            #expect(join.state() == .running(number: 17))
            wire[11] = PROBE_SUBTYPE_ASSIGN
            #expect(join.hear_probe(try NumberProbe.decode(wire)) == nil)
        }
    }
    @Test("each_candidate_keepalive_sets_exactly_one_occupancy_bit") func bits() throws {
        for (index, number) in REKORDBOX_CLAIM_NUMBERS.enumerated() {
            var join = Join.new(mac: MAC, ip: IP, now_ms: 0).test_state(.probing(round: 1, index: 0))
            var announcement = player()
            announcement.device_number = number
            join.hear_keep_alive(try KeepAlive.decode(announcement.encode()), 0)
            var expected = [Bool](repeating: false, count: 6)
            expected[index] = true
            #expect(join.in_use == expected)
            announcement.device_number = 33
            join.hear_keep_alive(announcement, 0)
            #expect(join.in_use == expected)
        }
    }
    @Test("terminal_rejection_retains_interface_and_candidate_but_not_runtime_or_occupancy") func terminal() throws {
        for mode in [ConnectionMode.wired, .wireless] {
            let candidate: UInt8 = mode == .wireless ? 41 : 17
            var machine = Join.new(mac: MAC, ip: IP, now_ms: 0).with_mode(mode)
            let unspecified = try DJLinkExportProtocol.Address4("0.0.0.0")
            #expect(machine.configured_number == 17)
            #expect(machine.runtime_ip == unspecified)
            #expect(!machine.network_initialized())
            machine.hear_keep_alive(player(), 0)
            #expect(machine.configured_number == candidate)
            #expect(machine.runtime_ip == IP)
            machine.in_use = [Bool](repeating: true, count: 6)
            machine.current = .running(number: 18)
            let outgoingOptional = machine.reject(0)
            let outgoing = try #require(outgoingOptional)
            #expect(outgoing.packet[36] == 18)
            #expect(Array(outgoing.packet[37...]) == IP.octets)
            #expect(machine.current == .waiting)
            #expect(machine.runtime_ip == unspecified)
            #expect(machine.in_use == [Bool](repeating: false, count: 6))
            #expect(machine.network_ip == IP)
            #expect(machine.configured_number == candidate)
            machine.reset(0)
            machine.hear_keep_alive(player(), 0)
            #expect(machine.tick(60_000) == nil)
            machine.hear_reply(try NumberReply.decode(number_in_use_reply(REKORDBOX_NAME, 17)))
            let probe = try NumberProbe.decode(rekordbox_claim_stage2([UInt8](repeating: 1, count: 6), IP, 18, 3))
            #expect(machine.hear_probe(probe) == nil)
            #expect(machine.in_use == [Bool](repeating: false, count: 6))
            #expect(machine.state() == .waiting)
            let repeatedOptional = machine.reject(0)
            let repeated = try #require(repeatedOptional)
            #expect(repeated.packet[36] == candidate)
            #expect(Array(repeated.packet[37...]) == [UInt8](repeating: 0, count: 4))
            #expect(machine.rejected())
            #expect(!Join.new(mac: MAC, ip: IP, now_ms: 0).with_mode(mode).rejected())
        }
    }
}
