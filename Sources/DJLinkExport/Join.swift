// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-link/src/join.rs (90bfb53). Instant는 주입 시계의 밀리초로 옮긴다.
import DJLinkExportProtocol

public let TICK: UInt64 = 100
public enum JoinState: Equatable, Sendable {
    case waiting, discovery(sent: UInt8), probing(round: UInt8, index: Int)
    case assigning(sent: UInt8), running(number: UInt8), failed(String)
}
public struct Outgoing: Equatable, Sendable {
    public var packet: [UInt8]
    public var to: DJLinkExportProtocol.Address4?
    public var what: String
}
public struct Join: Sendable {
    var mode: ConnectionMode = .unknown
    let mac: [UInt8]
    let ip: DJLinkExportProtocol.Address4
    var current: JoinState = .waiting
    var in_use = [Bool](repeating: false, count: 6)
    var next_at: UInt64
    var configured_number: UInt8 = 17
    var runtime_ip = try! DJLinkExportProtocol.Address4("0.0.0.0")
    var network_ip: DJLinkExportProtocol.Address4?
    var rejection = false
    var exclude_original_models = false
    var all_in_one_session: Bool?
    public init(mac: [UInt8], ip: DJLinkExportProtocol.Address4, now_ms: UInt64) {
        precondition(mac.count == 6)
        self.mac = mac
        self.ip = ip
        next_at = now_ms
    }
    public static func new(mac: [UInt8], ip: DJLinkExportProtocol.Address4, now_ms: UInt64) -> Self {
        Self(mac: mac, ip: ip, now_ms: now_ms)
    }
    public func state() -> JoinState { current }
    public func with_mode(_ mode: ConnectionMode) -> Self {
        var copy = self
        copy.mode = mode
        return copy
    }
    public func test_state(_ state: JoinState) -> Self {
        var copy = self
        copy.current = state
        return copy
    }
    public func number() -> UInt8? {
        if case let .running(number) = current { return number }
        return nil
    }
    public func rejected() -> Bool { rejection }
    public func network_initialized() -> Bool { network_ip != nil }
    public func excludes_original_models() -> Bool { exclude_original_models }
    public func announcement_sender_allowed(
        _ sender: DJLinkExportProtocol.Address4, _ mask: DJLinkExportProtocol.Address4
    ) -> Bool {
        let own = network_ip ?? (try! DJLinkExportProtocol.Address4("0.0.0.0"))
        return sender != own
            && (own.octets[0] == 0
                || zip(sender.octets, mask.octets).map { $0 & $1 } == zip(own.octets, mask.octets).map { $0 & $1 })
    }
    public func allows_running_member(_ number: UInt8) -> Bool {
        guard case .running = current else { return true }
        switch all_in_one_session {
        case false?: return !(9...12).contains(number)
        case true?: return !(1...4).contains(number)
        case nil: return true
        }
    }
    public mutating func reject(_ now_ms: UInt64) -> Outgoing? {
        guard mode != .unknown else { return nil }
        let packet = rejection_disconnect(number() ?? configured_number, runtime_ip)
        let can_send = network_ip.map { $0.octets[0] != 0 } ?? false
        rejection = true
        exclude_original_models = true
        current = .waiting
        runtime_ip = try! DJLinkExportProtocol.Address4("0.0.0.0")
        in_use = [Bool](repeating: false, count: 6)
        next_at = now_ms
        return can_send ? Outgoing(packet: packet, to: nil, what: "rejection disconnect") : nil
    }
    public mutating func reset(_ now_ms: UInt64) {
        guard !rejection else { return }
        current = .waiting
        in_use = [Bool](repeating: false, count: 6)
        all_in_one_session = nil
        next_at = now_ms
    }
    public mutating func hear_keep_alive(_ keep_alive: KeepAlive, _ now_ms: UInt64) {
        guard !rejection, !(keep_alive.ip == ip && keep_alive.mac == mac), (1...80).contains(keep_alive.device_number),
            (1...9).contains(keep_alive.device_type.to_u8())
        else { return }
        if case .probing = current, let index = REKORDBOX_CLAIM_NUMBERS.firstIndex(of: keep_alive.device_number) {
            in_use[index] = true
        }
        if current == .waiting && brings_link_up_on(keep_alive, .wired) && mode != .unknown {
            network_ip = ip
            runtime_ip = ip
            configured_number = mode == .wireless ? 41 : 17
            exclude_original_models = mode == .wireless
        }
        if current == .waiting && brings_link_up_on(keep_alive, mode) {
            current = .discovery(sent: 0)
            all_in_one_session = keep_alive.device_type == .allInOne
            next_at = now_ms
        }
    }
    public mutating func hear_reply(_ reply: NumberReply) {
        guard !rejection else { return }
        switch current {
        case .probing where reply.subtype == PROBE_SUBTYPE_PROBE && reply.status == NUMBER_REPLY_IN_USE:
            if let index = REKORDBOX_CLAIM_NUMBERS.firstIndex(of: reply.number) { in_use[index] = true }
        case .assigning where reply.subtype == PROBE_SUBTYPE_ASSIGN && reply.status == 0:
            current = .running(number: reply.number)
        default: break
        }
    }
    public mutating func hear_probe(_ probe: NumberProbe) -> Outgoing? {
        guard !rejection, let number = number(), !(probe.ip == ip && probe.mac == mac),
            probe.subtype == PROBE_SUBTYPE_PROBE, probe.number == number
        else { return nil }
        return Outgoing(
            packet: number_in_use_reply_with_counter(REKORDBOX_NAME, number, probe.round), to: probe.ip,
            what: "number in use")
    }
    public mutating func hear_block(_ block: NumberBlock) -> Outgoing? {
        guard !rejection, let number = number(), !(block.ip == ip && block.mac == mac), block.names(number, mode) else {
            return nil
        }
        return Outgoing(
            packet: number_in_use_reply_with_counter(REKORDBOX_NAME, number, block.counter), to: block.ip,
            what: "number in use")
    }
    public mutating func tick(_ now_ms: UInt64) -> Outgoing? {
        guard !rejection, now_ms >= next_at else { return nil }
        switch current {
        case .waiting, .running, .failed: return nil
        case let .discovery(sent):
            next_at = now_ms + TICK
            let counter = sent + 1
            current = counter >= 3 ? .probing(round: 1, index: 0) : .discovery(sent: counter)
            return Outgoing(packet: rekordbox_claim_stage1(mac, counter), to: nil, what: "first-stage claim")
        case .probing(var round, var index):
            next_at = now_ms + TICK
            while true {
                if round > 6 { return choose(now_ms) }
                if index >= REKORDBOX_CLAIM_NUMBERS.count {
                    round += 1
                    index = 0
                    continue
                }
                if in_use[index] {
                    index += 1
                    continue
                }
                break
            }
            let number = REKORDBOX_CLAIM_NUMBERS[index]
            current = .probing(round: round, index: index + 1)
            return Outgoing(packet: rekordbox_claim_stage2(mac, ip, number, round), to: nil, what: "number probe")
        case let .assigning(sent):
            guard sent < 6 else {
                current = .failed("every device number rekordbox reserves is in use, and nothing assigned one")
                return nil
            }
            next_at = now_ms + TICK
            current = .assigning(sent: sent + 1)
            return Outgoing(packet: rekordbox_assign_request(mac, ip, 17, sent + 1), to: nil, what: "assign request")
        }
    }
    private mutating func choose(_ now_ms: UInt64) -> Outgoing? {
        if let number = ([UInt8](arrayLiteral: 17, 18)).first(where: { choice in
            REKORDBOX_CLAIM_NUMBERS.firstIndex(of: choice).map { !in_use[$0] } ?? false
        }) {
            current = .running(number: number)
            return nil
        }
        current = .assigning(sent: 0)
        next_at = now_ms
        return tick(now_ms)
    }
}
