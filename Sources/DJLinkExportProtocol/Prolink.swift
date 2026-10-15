// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbxport/crates/rbl-prolink/src/lib.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 공개 원본의 패킷 코덱과 장치 테이블을 1:1로 옮겼다. 소켓을 열지 않는다.
import Foundation

public let MAGIC: [UInt8] = [0x51, 0x73, 0x70, 0x74, 0x31, 0x57, 0x6d, 0x4a, 0x4f, 0x4c]
public let NAME_LEN: Int = 20
public let NAME_AT: Int = 0x0c
public let PORT_ANNOUNCE: UInt16 = 50_000
public let PORT_BEAT: UInt16 = 50_001
public let PORT_STATUS: UInt16 = 50_002
public let REKORDBOX_DEVICE_NUMBER: UInt8 = 0x11
public let REKORDBOX_NAME: String = "rekordbox"
public let KEEP_ALIVE_INTERVAL_MS: UInt64 = 2_000
public let KEEP_ALIVE_LEN: Int = 0x36
public let STATUS_LEN: Int = 0x38
public let CONNECT_GREETING_LEN: Int = 0x30
public let CONNECT_IDENTITY_LEN: Int = 296
public let DEVICE_IDENTITY_QUERY_KIND: UInt8 = 0x10
public let REKORDBOX_CLAIM_NUMBERS: [UInt8] = [0x11, 0x12, 0x29, 0x2a, 0x2b, 0x2c]
public let PROBE_SUBTYPE_PROBE: UInt8 = 0x00
public let PROBE_SUBTYPE_ASSIGN: UInt8 = 0x01
public let PROBE_SUBTYPE_BLOCK: UInt8 = 0x02
public let NUMBER_PROBE_LEN: Int = 0x32
public let NUMBER_IN_USE_LEN: Int = 0x27
public let NUMBER_REPLY_IN_USE: UInt8 = 0x01
public let MEDIA_QUERY_LEN: Int = 0x30
public let SLOT_REKORDBOX: UInt8 = 0x04
public let SLOT_REKORDBOX_LEGACY: UInt8 = 0x03
public let MEDIA_RESPONSE_LEN: Int = 0xc0
public let DEVICE_PROPERTY_QUERY_KIND: UInt8 = 0x30
public let DEVICE_PROPERTY_QUERY_LEN: Int = 0x24
public let DEVICE_PROPERTY_RESPONSE_KIND: UInt8 = 0x31
public let DEVICE_PROPERTY_RESPONSE_LEN: Int = 0x2c
public let DEVICE_SETTINGS_REQUEST_KIND: UInt8 = 0x46
public let DEVICE_SETTINGS_RESPONSE_KIND: UInt8 = 0x47
public let DEVICE_SETTINGS_RESPONSE_LEN: Int = 0x48
public let PLAYER_STATUS_KIND: UInt8 = 0x0a
public let BEAT_KIND: UInt8 = 0x28
public let MASTER_HANDOFF_REQUEST_KIND: UInt8 = 0x26
public let BEAT_LEN: Int = 0x60
public let LOAD_TRACK_KIND: UInt8 = 0x19
public let LOAD_TRACK_ACK_KIND: UInt8 = 0x1a
public let LOAD_TRACK_LEN: Int = 0x58
public let TRACK_TYPE_REKORDBOX: UInt8 = 0x01
public let PEER_TIMEOUT_MS: UInt64 = KEEP_ALIVE_INTERVAL_MS * 3

public struct KeepAlive: Equatable, Sendable {
    public var name: String
    public var device_number: UInt8
    public var device_type: DeviceType
    public var mac: [UInt8]
    public var ip: Address4
    public var peers: UInt8
    public var generation: UInt8
    public init(
        name: String, device_number: UInt8, device_type: DeviceType, mac: [UInt8], ip: Address4, peers: UInt8,
        generation: UInt8
    ) {
        self.name = name
        self.device_number = device_number
        self.device_type = device_type
        precondition(mac.count == 6)
        self.mac = mac
        self.ip = ip
        self.peers = peers
        self.generation = generation
    }
}

public struct Status: Equatable, Sendable {
    public var name: String
    public var device_number: UInt8
    public var bpm_x100: UInt16
    public var beat: UInt8
    public var master: Bool
    public init(name: String, device_number: UInt8, bpm_x100: UInt16, beat: UInt8, master: Bool) {
        self.name = name
        self.device_number = device_number
        self.bpm_x100 = bpm_x100
        self.beat = beat
        self.master = master
    }
}

public struct Discovery: Equatable, Sendable {
    public var counter: UInt8
    public var device_type: UInt8
    public var mac: [UInt8]
    public init(counter: UInt8, device_type: UInt8, mac: [UInt8]) {
        self.counter = counter
        self.device_type = device_type
        precondition(mac.count == 6)
        self.mac = mac
    }
}

public struct NumberProbe: Equatable, Sendable {
    public var subtype: UInt8
    public var name: String
    public var ip: Address4
    public var mac: [UInt8]
    public var number: UInt8
    public var round: UInt8
    public var device_type: DeviceType
    public var auto_assign: Bool
    public init(
        subtype: UInt8, name: String, ip: Address4, mac: [UInt8], number: UInt8, round: UInt8, device_type: DeviceType,
        auto_assign: Bool
    ) {
        self.subtype = subtype
        self.name = name
        self.ip = ip
        precondition(mac.count == 6)
        self.mac = mac
        self.number = number
        self.round = round
        self.device_type = device_type
        self.auto_assign = auto_assign
    }
}

public struct NumberBlock: Equatable, Sendable {
    public var ip: Address4
    public var mac: [UInt8]
    public var wired_mask: UInt8
    public var wireless_mask: UInt8
    public var counter: UInt8
    public init(ip: Address4, mac: [UInt8], wired_mask: UInt8, wireless_mask: UInt8, counter: UInt8) {
        self.ip = ip
        precondition(mac.count == 6)
        self.mac = mac
        self.wired_mask = wired_mask
        self.wireless_mask = wireless_mask
        self.counter = counter
    }
}

public struct NumberReply: Equatable, Sendable {
    public var subtype: UInt8
    public var name: String
    public var number: UInt8
    public var status: UInt8
    public init(subtype: UInt8, name: String, number: UInt8, status: UInt8) {
        self.subtype = subtype
        self.name = name
        self.number = number
        self.status = status
    }
}

public struct MediaQuery: Equatable, Sendable {
    public var name: String
    public var from: Address4
    public var device_number: UInt8
    public var slot: UInt8
    public init(name: String, from: Address4, device_number: UInt8, slot: UInt8) {
        self.name = name
        self.from = from
        self.device_number = device_number
        self.slot = slot
    }
}

public struct MediaResponse: Equatable, Sendable {
    public var name: String
    public var device_number: UInt8
    public var slot: UInt8
    public var tracks: UInt16
    public var playlists: UInt16
    public init(name: String, device_number: UInt8, slot: UInt8, tracks: UInt16, playlists: UInt16) {
        self.name = name
        self.device_number = device_number
        self.slot = slot
        self.tracks = tracks
        self.playlists = playlists
    }
}

public struct DevicePropertyQuery: Equatable, Sendable {
    public var name: String
    public var requester: UInt8
    public init(name: String, requester: UInt8) {
        self.name = name
        self.requester = requester
    }
}

public struct DevicePropertyResponse: Equatable, Sendable {
    public var name: String
    public var device_number: UInt8
    public init(name: String, device_number: UInt8) {
        self.name = name
        self.device_number = device_number
    }
}

public struct LoadTrackResponse: Equatable, Sendable {
    public var name: String
    public var fields: [UInt8]
    public init(name: String, fields: [UInt8]) {
        self.name = name
        precondition(fields.count == 4)
        self.fields = fields
    }
}

public struct Claim: Equatable, Sendable {
    public var stage: AnnounceKind
    public var name: String
    public var device_number: UInt8
    public var mac: [UInt8]
    public var ip: Address4
    public var `repeat`: UInt8
    public var device_type: DeviceType
    public init(
        stage: AnnounceKind, name: String, device_number: UInt8, mac: [UInt8], ip: Address4, `repeat`: UInt8,
        device_type: DeviceType
    ) {
        self.stage = stage
        self.name = name
        self.device_number = device_number
        precondition(mac.count == 6)
        self.mac = mac
        self.ip = ip
        self.`repeat` = `repeat`
        self.device_type = device_type
    }
}

public struct Announcement: Equatable, Sendable {
    public var name: String
    public var device_type: DeviceType
    public init(name: String, device_type: DeviceType) {
        self.name = name
        self.device_type = device_type
    }
}

public struct Peer: Equatable, Sendable {
    public var name: String
    public var device_number: UInt8
    public var device_type: DeviceType
    public var ip: Address4
    public var mac: [UInt8]
    public var member_flags: [UInt8]?
    public var last_seen_ms: UInt64
    public init(
        name: String, device_number: UInt8, device_type: DeviceType, ip: Address4, mac: [UInt8], member_flags: [UInt8]?,
        last_seen_ms: UInt64
    ) {
        self.name = name
        self.device_number = device_number
        self.device_type = device_type
        self.ip = ip
        precondition(mac.count == 6)
        self.mac = mac
        precondition(member_flags == nil || member_flags?.count == 2)
        self.member_flags = member_flags
        self.last_seen_ms = last_seen_ms
    }
}

/// 원본 Ipv4Addr와 같은 네 바이트 주소. 접미사나 서브넷 상태는 갖지 않는다.
public struct Address4: Hashable, Sendable, CustomStringConvertible {
    public let octets: [UInt8]
    public init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) { octets = [a, b, c, d] }
    public init(octets: [UInt8]) {
        precondition(octets.count == 4)
        self.octets = octets
    }
    /// Swift 주소 형과 연결하기 위한 편의 변환. 저장하는 값은 원본처럼 네 바이트뿐이다.
    public init(_ address: String) throws {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
            parts.allSatisfy({
                !$0.isEmpty && ($0.count == 1 || $0.first != "0") && $0.allSatisfy({ $0.isASCII && $0.isNumber })
            }),
            let a = UInt8(parts[0]), let b = UInt8(parts[1]), let c = UInt8(parts[2]), let d = UInt8(parts[3])
        else { throw AddressError.invalid }
        self.init(a, b, c, d)
    }
    public static let unspecified = Self(0, 0, 0, 0)
    public var description: String { octets.map(String.init).joined(separator: ".") }
    public var address: String { description }
    public func toArray() -> [Int] { octets.map(Int.init) }
    public static let localhost = Self(127, 0, 0, 1)
}
public enum AddressError: Error { case invalid }

public enum PacketError: Error, Equatable, Sendable, CustomStringConvertible {
    case tooShort(Int), badMagic, wrongKind(UInt8), wrongSubtype(UInt8), wrongLength(UInt16)
    public var description: String {
        switch self {
        case .tooShort(let count): return "packet is too short: \(count) bytes"
        case .badMagic: return "not a DJ Link packet: wrong magic"
        case .wrongKind(let kind): return String(format: "unexpected packet kind 0x%02x for this port", kind)
        case .wrongSubtype(let subtype): return String(format: "unexpected packet subtype 0x%02x", subtype)
        case .wrongLength(let length): return "unexpected payload length \(length)"
        }
    }
}
public typealias Result<T> = Swift.Result<T, PacketError>

public enum AnnounceKind: Equatable, Sendable {
    case claimStage1, claimStage2, claimFinal, keepAlive, conflict, announce, other(UInt8)
    public static func from_u8(_ v: UInt8) -> Self {
        switch v {
        case 0: return .claimStage1
        case 2: return .claimStage2
        case 4: return .claimFinal
        case 6: return .keepAlive
        case 8: return .conflict
        case 10: return .announce
        default: return .other(v)
        }
    }
    public func to_u8() -> UInt8 {
        switch self {
        case .claimStage1: return 0
        case .claimStage2: return 2
        case .claimFinal: return 4
        case .keepAlive: return 6
        case .conflict: return 8
        case .announce: return 10
        case .other(let v): return v
        }
    }
}
public enum DeviceType: Equatable, Sendable {
    case cdj, mixer, rekordbox, allInOne, other(UInt8)
    public static func from_u8(_ v: UInt8) -> Self {
        switch v {
        case 1: return .cdj
        // 원본은 02와 03 모두 mixer로 읽고, 다시 쓰면 02로 만든다.
        case 2, 3: return .mixer
        case 4: return .rekordbox
        case 7: return .allInOne
        default: return .other(v)
        }
    }
    public func to_u8() -> UInt8 {
        switch self {
        case .cdj: return 1
        case .mixer: return 2
        case .rekordbox: return 4
        case .allInOne: return 7
        case .other(let v): return v
        }
    }
}
public enum ConnectionMode: Equatable, Sendable {
    case wired, wireless, unknown
    public static func `default`() -> Self { .unknown }
}

private func write_header(_ out: inout [UInt8], _ kind: UInt8, _ subtype: UInt8, _ name: String) {
    out += MAGIC
    out += [kind, subtype]
    var padded = Array(name.utf8.prefix(NAME_LEN))
    padded += [UInt8](repeating: 0, count: NAME_LEN - padded.count)
    out += padded
}
private func write_status_header(_ out: inout [UInt8], _ kind: UInt8, _ name: String) {
    out += MAGIC
    out.append(kind)
    var padded = Array(name.utf8.prefix(NAME_LEN))
    padded += [UInt8](repeating: 0, count: NAME_LEN - padded.count)
    out += padded
}
private func be16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(truncatingIfNeeded: value)] }
private func be32(_ value: UInt32) -> [UInt8] {
    [
        UInt8(value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8),
        UInt8(truncatingIfNeeded: value),
    ]
}
private func resize(_ out: inout [UInt8], _ count: Int) {
    if out.count > count {
        out.removeLast(out.count - count)
    } else {
        out += [UInt8](repeating: 0, count: count - out.count)
    }
}
public func device_name(_ packet: [UInt8]) throws(PacketError) -> String {
    guard packet.count >= NAME_AT + NAME_LEN else { throw .tooShort(packet.count) }
    guard Array(packet.prefix(10)) == MAGIC else { throw .badMagic }
    let raw = packet[NAME_AT..<NAME_AT + NAME_LEN]
    return String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
}
public func status_device_name(_ packet: [UInt8]) throws(PacketError) -> String {
    guard packet.count >= NAME_AT - 1 + NAME_LEN else { throw .tooShort(packet.count) }
    guard Array(packet.prefix(10)) == MAGIC else { throw .badMagic }
    let raw = packet[(NAME_AT - 1)..<(NAME_AT - 1 + NAME_LEN)]
    return String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
}
public func packet_kind(_ packet: [UInt8]) throws(PacketError) -> UInt8 {
    guard packet.count > 0x0a else { throw .tooShort(packet.count) }
    guard Array(packet.prefix(10)) == MAGIC else { throw .badMagic }
    return packet[0x0a]
}
public func announce_kind_name(_ kind: UInt8) -> String {
    switch AnnounceKind.from_u8(kind) {
    case .claimStage1: return "number claim 1"
    case .claimStage2: return "number claim 2"
    case .claimFinal: return "number claim 3"
    case .keepAlive: return "keep-alive"
    case .conflict: return "number in use"
    case .announce: return "announce"
    case .other(let v): return String(format: "kind 0x%02x", v)
    }
}
public func status_kind_name(_ kind: UInt8) -> String {
    switch kind {
    case 0x05: return "media query"
    case 0x06: return "media response"
    case PLAYER_STATUS_KIND: return "player status"
    case DEVICE_IDENTITY_QUERY_KIND: return "device identity query"
    case 0x11: return "device identity reply"
    case LOAD_TRACK_KIND: return "load track"
    case LOAD_TRACK_ACK_KIND: return "load track ack"
    case MASTER_HANDOFF_REQUEST_KIND: return "master handoff request"
    case 0x27: return "master handoff reply"
    case BEAT_KIND: return "beat"
    case 0x29: return "mixer status"
    case 0x2a: return "sync control"
    case DEVICE_PROPERTY_QUERY_KIND: return "device property query"
    case DEVICE_PROPERTY_RESPONSE_KIND: return "device property response"
    case DEVICE_SETTINGS_REQUEST_KIND: return "device settings request"
    case DEVICE_SETTINGS_RESPONSE_KIND: return "device settings response"
    default: return String(format: "kind 0x%02x", kind)
    }
}
public func hex(_ packet: [UInt8], _ limit: Int) -> String {
    precondition(limit >= 0)
    let out = packet.prefix(limit).map { String(format: "%02x", $0) }.joined(separator: " ")
    return out + (packet.count > limit ? "…" : "")
}

extension KeepAlive {
    public static func rekordbox(_ mac: [UInt8], _ ip: Address4, _ peers: UInt8) -> Self {
        rekordbox_as(REKORDBOX_DEVICE_NUMBER, mac, ip, peers)
    }
    public static func rekordbox_as(_ device_number: UInt8, _ mac: [UInt8], _ ip: Address4, _ peers: UInt8) -> Self {
        Self(
            name: REKORDBOX_NAME, device_number: device_number, device_type: .rekordbox, mac: mac, ip: ip, peers: peers,
            generation: 3)
    }
    public func encode() -> [UInt8] {
        var out: [UInt8] = []
        write_header(&out, AnnounceKind.keepAlive.to_u8(), 0, name)
        out += [1, generation]
        out += be16(UInt16(KEEP_ALIVE_LEN))
        out += [device_number, 1]
        out += mac
        out += ip.octets
        out.append(peers)
        let (after_peers, last): (UInt8, UInt8) = device_type == .rekordbox ? (1, 8) : (0, 0x64)
        out += [after_peers, 0, 0, device_type.to_u8(), last]
        assert(out.count == KEEP_ALIVE_LEN)
        return out
    }
    public static func decode(_ packet: [UInt8]) throws(PacketError) -> Self {
        guard packet.count >= KEEP_ALIVE_LEN else { throw .tooShort(packet.count) }
        let kind = try packet_kind(packet)
        guard AnnounceKind.from_u8(kind) == .keepAlive else { throw .wrongKind(kind) }
        guard packet[0x0b] == 0 else { throw .wrongSubtype(packet[0x0b]) }
        return Self(
            name: try device_name(packet), device_number: packet[0x24], device_type: DeviceType.from_u8(packet[0x34]),
            mac: Array(packet[0x26..<0x2c]), ip: Address4(octets: Array(packet[0x2c..<0x30])), peers: packet[0x30],
            generation: packet[0x21])
    }
}
extension Status {
    public func encode() -> [UInt8] {
        var out: [UInt8] = []
        write_status_header(&out, 0x29, name)
        out += [1, 1, device_number, 0, 0x38, device_number]
        let flag: UInt8 = master ? 0xe0 : 0xc0
        let tempo_valid: UInt8 = master || bpm_x100 != 0 ? 0x80 : 0
        out += [0, 0, flag, 0, 0x10, 0, 0, tempo_valid, 0]
        out += be16(bpm_x100)
        out += [0, 0x10, 0, 0, master ? 1 : 0, 9, 0xff, beat]
        assert(out.count == STATUS_LEN)
        return out
    }
}
public func connect_greeting(_ name: String, _ device_number: UInt8) -> [UInt8] {
    var out: [UInt8] = []
    write_status_header(&out, 0x16, name)
    out += [1, 1, device_number]
    resize(&out, CONNECT_GREETING_LEN)
    return out
}
public func connect_identity(_ name: String, _ device_number: UInt8, _ computer_name: String) -> [UInt8] {
    var out: [UInt8] = []
    write_status_header(&out, 0x11, name)
    out += [1, 1, device_number, 1, 4, device_number, 1, 0, 0]
    for unit in computer_name.utf16 { out += be16(unit) }
    // 원본 Vec.resize처럼 길이를 넘긴 이름은 바이트 단위로 자른다.
    resize(&out, CONNECT_IDENTITY_LEN)
    return out
}
public func brings_link_up(_ keep_alive: KeepAlive) -> Bool { brings_link_up_on(keep_alive, .unknown) }
public func rejection_disconnect(_ number: UInt8, _ ip: Address4) -> [UInt8] {
    var out: [UInt8] = []
    write_header(&out, 8, 0, REKORDBOX_NAME)
    out += [1, 3, 0, 41, number]
    out += ip.octets
    return out
}
extension Discovery {
    public static func decode(_ packet: [UInt8]) throws(PacketError) -> Self {
        guard packet.count >= 44 else { throw .tooShort(packet.count) }
        let kind = try packet_kind(packet)
        guard kind == 0 else { throw .wrongKind(kind) }
        guard packet[11] == 0 else { throw .wrongSubtype(packet[11]) }
        return Self(counter: packet[36], device_type: packet[37], mac: Array(packet[38..<44]))
    }
}
public func brings_link_up_on(_ keep_alive: KeepAlive, _ mode: ConnectionMode) -> Bool {
    guard [UInt8(1), 2, 3, 7].contains(keep_alive.device_type.to_u8()) else { return false }
    return mode == .wired
        || !(keep_alive.generation == 0 && (keep_alive.name == "CDJ-2000" || keep_alive.name == "CDJ-900"))
}
public func rekordbox_claim_stage1(_ mac: [UInt8], _ counter: UInt8) -> [UInt8] {
    precondition(mac.count == 6)
    var out: [UInt8] = []
    write_header(&out, 0, 0, REKORDBOX_NAME)
    out += [1, 3, 0, 0x2c, counter, 4]
    out += mac
    assert(out.count == 0x2c)
    return out
}
public func rekordbox_claim_stage2(_ mac: [UInt8], _ ip: Address4, _ number: UInt8, _ counter: UInt8) -> [UInt8] {
    precondition(mac.count == 6)
    var out: [UInt8] = []
    write_header(&out, 2, 0, REKORDBOX_NAME)
    out += [1, 3, 0, 0x32]
    out += ip.octets
    out += mac
    out += [number, counter, 4, 1]
    assert(out.count == 0x32)
    return out
}
extension NumberProbe {
    public static func decode(_ packet: [UInt8]) throws(PacketError) -> Self {
        guard packet.count >= NUMBER_PROBE_LEN else { throw .tooShort(packet.count) }
        let kind = try packet_kind(packet)
        guard AnnounceKind.from_u8(kind) == .claimStage2 else { throw .wrongKind(kind) }
        guard [PROBE_SUBTYPE_PROBE, PROBE_SUBTYPE_ASSIGN].contains(packet[0x0b]) else {
            throw .wrongSubtype(packet[0x0b])
        }
        return Self(
            subtype: packet[0x0b], name: try device_name(packet), ip: Address4(octets: Array(packet[0x24..<0x28])),
            mac: Array(packet[0x28..<0x2e]), number: packet[0x2e], round: packet[0x2f],
            device_type: DeviceType.from_u8(packet[0x30]), auto_assign: packet[0x31] == 1)
    }
}
extension NumberBlock {
    public static func decode(_ packet: [UInt8]) throws(PacketError) -> Self {
        guard packet.count >= 68 else { throw .tooShort(packet.count) }
        let kind = try packet_kind(packet)
        guard kind == 2 else { throw .wrongKind(kind) }
        guard packet[11] == PROBE_SUBTYPE_BLOCK else { throw .wrongSubtype(packet[11]) }
        return Self(
            ip: Address4(octets: Array(packet[36..<40])), mac: Array(packet[40..<46]), wired_mask: packet[48],
            wireless_mask: packet[51], counter: packet[67])
    }
    public func names(_ number: UInt8, _ mode: ConnectionMode) -> Bool {
        switch mode {
        case .wired where (17...18).contains(number): return wired_mask & (1 << (number - 17)) != 0
        case .wireless where (41...44).contains(number): return wireless_mask & (1 << (number - 41)) != 0
        default: return false
        }
    }
}
public func rekordbox_assign_request(_ mac: [UInt8], _ ip: Address4, _ number: UInt8, _ counter: UInt8) -> [UInt8] {
    var out = rekordbox_claim_stage2(mac, ip, number, counter)
    out[0x0b] = PROBE_SUBTYPE_ASSIGN
    return out
}
public func number_in_use_reply(_ name: String, _ number: UInt8) -> [UInt8] {
    number_in_use_reply_with_counter(name, number, 0)
}
public func number_in_use_reply_with_counter(_ name: String, _ number: UInt8, _ counter: UInt8) -> [UInt8] {
    var out: [UInt8] = []
    write_header(&out, 3, PROBE_SUBTYPE_PROBE, name)
    out += [1, 3, 0, 0x27, number, counter, NUMBER_REPLY_IN_USE]
    assert(out.count == NUMBER_IN_USE_LEN)
    return out
}
extension NumberReply {
    public static func decode(_ packet: [UInt8]) throws(PacketError) -> Self {
        guard packet.count >= NUMBER_IN_USE_LEN else { throw .tooShort(packet.count) }
        let kind = try packet_kind(packet)
        guard kind == 3 else { throw .wrongKind(kind) }
        return Self(subtype: packet[0x0b], name: try device_name(packet), number: packet[0x24], status: packet[0x26])
    }
}
public func rekordbox_startup_ladder(_ mac: [UInt8], _ ip: Address4) -> [[UInt8]] {
    var ladder: [[UInt8]] = []
    for counter in UInt8(1)...3 { ladder.append(rekordbox_claim_stage1(mac, counter)) }
    // 원본의 counter-major 순서: 각 카운터에서 여섯 번호를 모두 보낸다.
    for counter in UInt8(1)...6 {
        for number in REKORDBOX_CLAIM_NUMBERS { ladder.append(rekordbox_claim_stage2(mac, ip, number, counter)) }
    }
    return ladder
}
extension MediaQuery {
    public static func decode(_ packet: [UInt8]) throws(PacketError) -> Self {
        guard packet.count >= MEDIA_QUERY_LEN else { throw .tooShort(packet.count) }
        let kind = try packet_kind(packet)
        guard kind == 5 else { throw .wrongKind(kind) }
        return Self(
            name: try status_device_name(packet), from: Address4(octets: Array(packet[0x24..<0x28])),
            device_number: packet[0x2b], slot: packet[0x2f])
    }
}
extension MediaResponse {
    public func encode() -> [UInt8] {
        var out: [UInt8] = []
        write_status_header(&out, 6, name)
        out += [1, 1, device_number]
        out += be16(UInt16(MEDIA_RESPONSE_LEN - 0x24))
        out += be32(UInt32(device_number))
        out += be32(UInt32(slot))
        var utf16 = name.utf16.prefix(31).flatMap { be16($0) }
        resize(&utf16, 64)
        out += utf16
        resize(&out, 0xa6)
        out += be16(tracks)
        out += [0, 0, 1, 1, 0, 0]
        out += be16(playlists)
        resize(&out, MEDIA_RESPONSE_LEN)
        assert(out.count == MEDIA_RESPONSE_LEN)
        return out
    }
}
extension DevicePropertyQuery {
    public static func decode(_ packet: [UInt8]) throws(PacketError) -> Self {
        guard packet.count >= DEVICE_PROPERTY_QUERY_LEN else { throw .tooShort(packet.count) }
        let kind = try packet_kind(packet)
        guard kind == DEVICE_PROPERTY_QUERY_KIND else { throw .wrongKind(kind) }
        return Self(name: try status_device_name(packet), requester: packet[0x21])
    }
}
extension DevicePropertyResponse {
    public func encode() -> [UInt8] {
        var out: [UInt8] = []
        write_status_header(&out, DEVICE_PROPERTY_RESPONSE_KIND, name)
        out += [1, 3, device_number, 0, 8, 6, 0, 0, 0, 0, 0, 0, 0]
        assert(out.count == DEVICE_PROPERTY_RESPONSE_LEN)
        return out
    }
}

public enum OverviewWaveform: String, Codable, Sendable {
    case half, full
    public static func `default`() -> Self { .half }
}
public enum WaveformColor: String, Codable, Sendable {
    case blue, rgb, threeBand = "3band"
    public static func `default`() -> Self { .threeBand }
}
public enum KeyDisplay: String, Codable, Sendable {
    case classic, alphanumeric
    public static func `default`() -> Self { .classic }
}
public enum WaveformPosition: String, Codable, Sendable {
    case center, left
    public static func `default`() -> Self { .center }
}
public struct DeviceSettings: Equatable, Codable, Sendable {
    public var overview_waveform: OverviewWaveform
    public var waveform_color: WaveformColor
    public var key_display: KeyDisplay
    public var waveform_position: WaveformPosition
    public init(
        overview_waveform: OverviewWaveform = .half, waveform_color: WaveformColor = .threeBand,
        key_display: KeyDisplay = .classic, waveform_position: WaveformPosition = .center
    ) {
        self.overview_waveform = overview_waveform
        self.waveform_color = waveform_color
        self.key_display = key_display
        self.waveform_position = waveform_position
    }
    public static func `default`() -> Self { Self() }
    private enum CodingKeys: String, CodingKey {
        case overview_waveform = "overviewWaveform", waveform_color = "waveformColor", key_display = "keyDisplay",
            waveform_position = "waveformPosition"
    }
    fileprivate func body() -> [UInt8] {
        var body = [UInt8](repeating: 0, count: 32)
        body.replaceSubrange(0..<4, with: [0x78, 0x56, 0x34, 0x12])
        body.replaceSubrange(4..<8, with: [1, 0, 0, 0])
        body[8] = 1
        body[9] = overview_waveform == .half ? 1 : 2
        switch waveform_color {
        case .blue: body[10] = 1
        case .rgb: body[10] = 3
        case .threeBand: body[10] = 4
        }
        body[11] = 1
        body[12] = key_display == .classic ? 1 : 2
        body[13] = waveform_position == .center ? 1 : 2
        // 의미가 확인되지 않은 원본의 캡처 바이트도 그대로 유지한다.
        body[16] = 2
        return body
    }
}
public func device_settings_response(_ name: String, _ device_number: UInt8, _ settings: DeviceSettings) -> [UInt8] {
    var out: [UInt8] = []
    write_status_header(&out, DEVICE_SETTINGS_RESPONSE_KIND, name)
    out += [1, 1, device_number, 0, 0x24, device_number, 4, 0, 0]
    let body = settings.body()
    out += body[0..<4].reversed()
    out += body[4..<8].reversed()
    out += body[8..<24]
    out += body[24..<26].reversed()
    out += body[26..<28].reversed()
    out += body[28..<32].reversed()
    assert(out.count == DEVICE_SETTINGS_RESPONSE_LEN)
    return out
}
public func beat_packet(_ name: String, _ device_number: UInt8, _ bpm_x100: UInt16, _ bar_beat: UInt8) -> [UInt8] {
    var out: [UInt8] = []
    write_status_header(&out, BEAT_KIND, name)
    out += [1, 1, device_number, 0, 0x3c]
    let beat = min(max(bar_beat, 1), 4)
    let bpm = UInt32(max(bpm_x100, 1))
    for k in [UInt32(1), 2, UInt32(5 - beat), 4, UInt32(9 - beat), 8] { out += be32(k * 6_000_000 / bpm) }
    out += [UInt8](repeating: 0xff, count: 24)
    out += be32(0x0010_0000)
    out += [0, 0]
    out += be16(bpm_x100)
    out += [beat, 0, 0, device_number]
    assert(out.count == BEAT_LEN)
    return out
}
extension LoadTrackResponse {
    public static func decode(_ packet: [UInt8]) throws(PacketError) -> Self {
        guard packet.count >= 40 else { throw .tooShort(packet.count) }
        let kind = try packet_kind(packet)
        guard kind == LOAD_TRACK_ACK_KIND else { throw .wrongKind(kind) }
        let length = UInt16(packet[34]) << 8 | UInt16(packet[35])
        guard length == 4 else { throw .wrongLength(length) }
        return Self(name: try status_device_name(packet), fields: Array(packet[36..<40]))
    }
}
public func load_track_command(_ name: String, _ from_device: UInt8, _ to_device: UInt8, _ track_id: UInt32) -> [UInt8]
{
    var out: [UInt8] = []
    write_status_header(&out, LOAD_TRACK_KIND, name)
    out += [1, 1, from_device, 0, 0x34]
    out += [from_device, 0, 0, 0, from_device, SLOT_REKORDBOX, TRACK_TYPE_REKORDBOX, 0]
    out += be32(track_id)
    resize(&out, LOAD_TRACK_LEN)
    out[0x33] = 0x32
    out[0x40] = to_device == 0 ? 0 : to_device - 1
    out[0x4b] = 0x32
    assert(out.count == LOAD_TRACK_LEN)
    return out
}
extension Claim {
    public func encode() -> [UInt8] {
        var out: [UInt8] = []
        write_header(&out, stage.to_u8(), 0, name)
        out += [`repeat`, device_type.to_u8()]
        // 원본의 실제 길이(42/48)와 선언 길이(44/50)가 다른 동작을 유지한다.
        if stage == .claimStage1 {
            out += be16(0x002c)
            out += mac
        } else {
            out += be16(0x0032)
            out += ip.octets
            out += mac
            out += [device_number, 1]
        }
        return out
    }
}
extension Announcement {
    public func encode() -> [UInt8] {
        var out: [UInt8] = []
        write_header(&out, AnnounceKind.announce.to_u8(), 0, name)
        out += [1, device_type.to_u8()]
        out += be16(0x0025)
        out.append(1)
        return out
    }
}

/// 수신된 슬롯 타이머와 합성 장치의 회원 상태를 원본처럼 따로 보관한다.
public struct DeviceTable: Sendable {
    private var members: [Peer] = []
    private var received_at: [UInt8: UInt64] = [:]
    public init() {}
    public static func new() -> Self { Self() }
    public static func `default`() -> Self { Self() }
    public mutating func observe(_ keep_alive: KeepAlive, _ now_ms: UInt64) {
        record(keep_alive, now_ms, true, nil)
        received_at[keep_alive.device_number] = now_ms
    }
    public mutating func observe_with_flags(_ keep_alive: KeepAlive, _ now_ms: UInt64, _ flags: [UInt8]) {
        precondition(flags.count == 2)
        record(keep_alive, now_ms, true, flags)
        received_at[keep_alive.device_number] = now_ms
    }
    public mutating func observe_synthetic(_ keep_alive: KeepAlive, _ now_ms: UInt64, _ flags: [UInt8]?) {
        precondition(flags == nil || flags?.count == 2)
        record(keep_alive, now_ms, false, flags)
    }
    private mutating func record(_ keep_alive: KeepAlive, _ now_ms: UInt64, _ received: Bool, _ flags: [UInt8]?) {
        if let index = members.firstIndex(where: { $0.device_number == keep_alive.device_number }) {
            members[index].name = keep_alive.name
            members[index].device_type = keep_alive.device_type
            members[index].ip = keep_alive.ip
            members[index].mac = keep_alive.mac
            members[index].member_flags = flags
            if received || received_at[keep_alive.device_number] == nil { members[index].last_seen_ms = now_ms }
            return
        }
        members.append(
            Peer(
                name: keep_alive.name, device_number: keep_alive.device_number, device_type: keep_alive.device_type,
                ip: keep_alive.ip, mac: keep_alive.mac, member_flags: flags,
                last_seen_ms: received ? now_ms : received_at[keep_alive.device_number] ?? now_ms))
    }
    public mutating func expire(_ now_ms: UInt64) -> Int { expire_received(now_ms).count }
    public mutating func expire_received(_ now_ms: UInt64) -> [UInt8] {
        // 원본처럼 비활성 슬롯의 지난 타이머도 소비한다.
        let expired_slots = received_at.compactMap { entry -> UInt8? in
            let number = entry.key
            let seen = entry.value
            let elapsed = now_ms >= seen ? now_ms - seen : 0
            return elapsed > PEER_TIMEOUT_MS ? number : nil
        }
        for number in expired_slots { received_at.removeValue(forKey: number) }
        let expired = members.filter { expired_slots.contains($0.device_number) }.map(\.device_number)
        for number in expired { _ = remove_number(number) }
        return expired
    }
    public func is_synthetic(_ number: UInt8) -> Bool {
        members.contains { $0.device_number == number } && received_at[number] == nil
    }
    public func peers() -> [Peer] { members }
    @discardableResult public mutating func remove_number(_ number: UInt8) -> Peer? {
        guard let index = members.firstIndex(where: { $0.device_number == number }) else { return nil }
        return members.remove(at: index)
    }
    public func len() -> Int { members.count }
    public func is_empty() -> Bool { members.isEmpty }
    public func free_device_number(_ preferred: UInt8) -> UInt8 {
        if !members.contains(where: { $0.device_number == preferred }) { return preferred }
        return (UInt8(0x11)...0x20).first(where: { candidate in !members.contains { $0.device_number == candidate } })
            ?? preferred
    }
}
