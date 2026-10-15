import DJLinkExportProtocol
import DJLinkExportSupport
import DJLinkKit
// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-link/src/beacon.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

public typealias LinkAddress = DJLinkExportProtocol.Address4
public typealias LinkDeviceType = DJLinkExportProtocol.DeviceType
let KEEP_ALIVE_EVERY: Double = 2000
let NETWORK_MONITOR_EVERY: Double = 1000
let STATUS_EVERY: Double = 200
let POLL: Double = 50
let PLAYER_TIMEOUT: Double = 6000
let MASTER_BPM_MIN: UInt16 = 4000
let MASTER_BPM_MAX: UInt16 = 30000
public struct BeaconConfig: Sendable {
    public var interface: String?
    public var address: LinkAddress
    public var netmask: LinkAddress
    public var broadcast: LinkAddress
    public var mac: [UInt8]
    public var mode: ConnectionMode
    public var announce_port: UInt16
    public var status_port: UInt16
    public var player_port: UInt16
    public var beat_port: UInt16
    public var computer_name: String
    public init(
        interface: String?, address: LinkAddress, netmask: LinkAddress, broadcast: LinkAddress, mac: [UInt8],
        mode: ConnectionMode, announce_port: UInt16, status_port: UInt16, player_port: UInt16, beat_port: UInt16,
        computer_name: String
    ) {
        self.interface = interface
        self.address = address
        self.netmask = netmask
        self.broadcast = broadcast
        self.mac = mac
        self.mode = mode
        self.announce_port = announce_port
        self.status_port = status_port
        self.player_port = player_port
        self.beat_port = beat_port
        self.computer_name = computer_name
    }
}
public struct MasterState: Equatable, Sendable {
    public var on: Bool
    public var bpm_x100: UInt16
    public var bar_beat: UInt8
    public init(on: Bool = false, bpm_x100: UInt16 = 12000, bar_beat: UInt8 = 1) {
        self.on = on
        self.bpm_x100 = bpm_x100
        self.bar_beat = bar_beat
    }
}
@DJLinkActor public protocol LibraryFacts: AnyObject {
    func track_count() -> UInt16
    func playlist_count() -> UInt16
    func device_settings() -> DeviceSettings
    func track_loaded(_ track: UInt32)
}
extension LibraryFacts {
    public func device_settings() -> DeviceSettings { DeviceSettings() }
    public func track_loaded(_ track: UInt32) {}
}
public struct Player: Equatable, Sendable {
    public var number: UInt8
    public var name: String
    public var address: LinkAddress
    public var kind: LinkDeviceType
    public var loaded: UInt32?
    public var playing: Bool
    public var master: Bool
    public var sync: Bool
    public var cued: Bool
    public var bpm_x100: UInt32
    public var last_seen: Double
    public init(
        number: UInt8, name: String, address: LinkAddress, kind: LinkDeviceType, loaded: UInt32? = nil,
        playing: Bool = false, master: Bool = false, sync: Bool = false, cued: Bool = false, bpm_x100: UInt32 = 0,
        last_seen: Double
    ) {
        self.number = number
        self.name = name
        self.address = address
        self.kind = kind
        self.loaded = loaded
        self.playing = playing
        self.master = master
        self.sync = sync
        self.cued = cued
        self.bpm_x100 = bpm_x100
        self.last_seen = last_seen
    }
}
public enum LinkState: Equatable, Sendable { case waiting, joining, up(number: UInt8), down(String) }
@DJLinkActor final class BeaconShared {
    var peers = DeviceTable(), players: [UInt8: Player] = [:], greeted: [LinkAddress] = [],
        to_greet: [LinkAddress] = [], master = MasterState(), join: Join?, down: String?
    let assigned: AtomicUInt8
    let clock: any DJLinkClock
    init(clock: any DJLinkClock = MonotonicClock.shared, assigned: AtomicUInt8? = nil) {
        self.clock = clock
        self.assigned = assigned ?? AtomicUInt8()
    }
    func rejected() -> Bool { join?.rejected() ?? false }
    func clear_members() {
        peers = DeviceTable()
        players = [:]
        greeted = []
        to_greet = []
    }
    func forget_greeting(_ address: LinkAddress) {
        greeted.removeAll { $0 == address }
        to_greet.removeAll { $0 == address }
    }
    func remove_member(_ number: UInt8) {
        let peer = peers.remove_number(number)
        let player = players.removeValue(forKey: number)
        for address in [peer?.ip, player?.address].compactMap({ $0 }) {
            if !players.values.contains(where: { $0.address == address })
                && !peers.peers().contains(where: { $0.ip == address })
            {
                forget_greeting(address)
            }
        }
    }
    func expire_peers(_ now_ms: UInt64) {
        let expired = peers.expire_received(now_ms)
        for number in expired where number == 9 || number == 11 {
            remove_member(number)
            remove_member(number + 1)
        }
    }
    func observe_player(_ keep_alive: KeepAlive, _ sender: LinkAddress) {
        let number = keep_alive.device_number
        if players[number] == nil {
            players[number] = Player(
                number: number, name: keep_alive.name, address: sender, kind: keep_alive.device_type,
                last_seen: clock.nowMilliseconds())
        }
        players[number]!.last_seen = clock.nowMilliseconds()
        players[number]!.name = keep_alive.name
        if keep_alive.ip == sender {
            let old = players[number]!.address
            players[number]!.address = keep_alive.ip
            players[number]!.kind = keep_alive.device_type
            if old != keep_alive.ip && !players.values.contains(where: { $0.address == old })
                && !peers.peers().contains(where: { $0.ip == old })
            {
                forget_greeting(old)
            }
        }
    }
    func synthesize_members(_ primary: KeepAlive, _ sender: LinkAddress, _ now_ms: UInt64) {
        guard let join, case .running = join.state(), (1...9).contains(primary.device_type.to_u8()) else { return }
        let numbers: [UInt8] =
            primary.device_number == 9
            ? (primary.name == "OPUS-QUAD" ? [10, 11, 12] : [10]) : primary.device_number == 11 ? [12] : []
        let flags = peers.peers().first { $0.device_number == primary.device_number }?.member_flags
        for number in numbers {
            var logical = primary
            logical.device_number = number
            peers.observe_synthetic(logical, now_ms, flags)
            observe_player(logical, sender)
        }
    }
    func rediscover(_ discovery: Discovery) {
        let leaving = peers.peers().filter { peer in
            let in_range: Bool
            switch discovery.device_type {
            case 1: in_range = (1...4).contains(peer.device_number)
            case 2, 3: in_range = peer.device_number == 33
            case 4: in_range = [UInt8(17), 18, 41, 42, 43, 44].contains(peer.device_number)
            case 6: in_range = (41...44).contains(peer.device_number)
            case 7: in_range = (9...12).contains(peer.device_number)
            default: in_range = false
            }
            return in_range && peer.mac == discovery.mac
        }.map { $0.device_number }
        for number in leaving {
            remove_member(number)
            if discovery.device_type == 7 && (number == 9 || number == 11) { remove_member(number + 1) }
        }
    }
    func expire_silent_players() {
        let now = clock.nowMilliseconds()
        var expired: [LinkAddress] = []
        players = players.filter { number, player in
            let alive = peers.is_synthetic(number) || now - player.last_seen < PLAYER_TIMEOUT
            if !alive { expired.append(player.address) }
            return alive
        }
        for address in expired where !players.values.contains(where: { $0.address == address }) {
            forget_greeting(address)
        }
    }
}
@DJLinkActor public final class Beacon {
    let shared: BeaconShared
    private let config: BeaconConfig
    private let facts: any LibraryFacts
    private let clock: any DJLinkClock
    private let interfaceProvider: any InterfaceProvider
    private let announce: any UDPSocket
    private let commands: any UDPSocket
    private let statusSender: any UDPSocket
    private let beats: (any UDPSocket)?
    private var timers: [TimerHandle] = []
    private let resources: BeaconResources
    private var stopped = false
    private var announce_running = true, status_running = true
    private let started: Double
    private var next_keep_alive: Double?, next_monitor: Double, next_send: Double, next_beat: Double,
        free_beat: UInt8 = 1
    private var pending_status: [([UInt8], RemoteInfo)] = []
    init(
        config: BeaconConfig, facts: any LibraryFacts, clock: any DJLinkClock, interfaceProvider: any InterfaceProvider,
        announce: any UDPSocket, status: any UDPSocket, statusSender: any UDPSocket, beats: (any UDPSocket)?,
        shared: BeaconShared? = nil
    ) {
        self.config = config
        self.facts = facts
        self.clock = clock
        self.interfaceProvider = interfaceProvider
        self.announce = announce
        commands = status
        self.statusSender = statusSender
        self.beats = beats
        resources = BeaconResources(clock, [announce, status, statusSender] + (beats.map { [$0] } ?? []))
        started = clock.nowMilliseconds()
        next_monitor = started + NETWORK_MONITOR_EVERY
        next_send = started
        next_beat = started
        self.shared = shared ?? BeaconShared(clock: clock)
        if shared == nil {
            self.shared.join = Join.new(mac: config.mac, ip: config.address, now_ms: UInt64(max(started, 0))).with_mode(
                config.mode)
        }
    }
    public static func start(
        _ config: BeaconConfig, _ facts: any LibraryFacts,
        socketFactory: any ExportSocketFactory = LiveExportSocketFactory.shared,
        clock: any DJLinkClock = MonotonicClock.shared,
        interfaceProvider: any InterfaceProvider = SystemInterfaceProvider()
    ) async throws -> Beacon {
        let announce = try await shared_udp(config.announce_port, config.interface, socketFactory)
        let status: any UDPSocket
        do { status = try await shared_udp(config.status_port, config.interface, socketFactory) } catch {
            await close_beacon_socket(announce)
            throw error
        }
        do {
            try broadcast(announce)
            try broadcast(status)
        } catch {
            await close_beacon_socket(announce)
            await close_beacon_socket(status)
            throw error
        }
        var config = config
        config.announce_port = UInt16(announce.address()!.port)
        config.status_port = UInt16(status.address()!.port)
        var sender: (any UDPSocket)?
        var beats: (any UDPSocket)?
        do {
            let s = try socketFactory.createUDPSocket(reuseAddr: false)
            do {
                _ = try await s.bind(port: 0, address: "0.0.0.0")
                try? broadcast(s)
                sender = s
            } catch { await close_beacon_socket(s) }
        } catch {}
        do {
            let s = try socketFactory.createUDPSocket(reuseAddr: false)
            do {
                _ = try await s.bind(port: 0, address: "0.0.0.0")
                try broadcast(s)
                beats = s
            } catch { await close_beacon_socket(s) }
        } catch {}
        let beacon = Beacon(
            config: config, facts: facts, clock: clock, interfaceProvider: interfaceProvider, announce: announce,
            status: status, statusSender: sender ?? status, beats: beats)
        beacon.start_announce_loop()
        status.onError { [weak beacon] _ in beacon?.status_running = false }
        status.onMessage { [weak beacon] packet, from in
            guard let beacon, !beacon.stopped, beacon.status_running else { return }
            if beacon.number() == nil {
                beacon.pending_status.append((Array(packet.prefix(2048)), from))
            } else {
                beacon.hear_status(Array(packet.prefix(2048)), from)
            }
        }
        beacon.timers.append(clock.setInterval(.ms(POLL)) { [weak beacon] in beacon?.status_tick() })
        beacon.resources.timers = beacon.timers
        beacon.schedule_beat(POLL)
        return beacon
    }
    func start_announce_loop() {
        announce.onError { [weak self] _ in self?.announce_running = false }
        announce.onMessage { [weak self] packet, from in
            guard let self, !stopped, announce_running else { return }
            if let out = hear_announce(Array(packet.prefix(2048)), from, config, shared, started) {
                send_announce(announce, out, config.broadcast, config.announce_port)
            }
            shared.expire_silent_players()
        }
        timers.append(clock.setInterval(.ms(POLL)) { [weak self] in self?.announce_tick() })
        resources.timers = timers
    }
    public func number() -> UInt8? {
        let n = shared.assigned.load()
        return n == 0 ? nil : n
    }
    public func number_cell() -> AtomicUInt8 { shared.assigned }
    public func link_state() -> LinkState {
        if let down = shared.down { return .down(down) }
        guard let join = shared.join else { return .waiting }
        switch join.state() {
        case .waiting: return .waiting
        case let .running(number): return .up(number: number)
        case let .failed(why): return .down(why)
        default: return .joining
        }
    }
    public func announce_port() -> UInt16 { config.announce_port }
    public func status_port() -> UInt16 { config.status_port }
    public func players() -> [Player] { shared.players.values.sorted { $0.number < $1.number } }
    public func load_track(_ player_number: UInt8, _ track_id: UInt32) async throws {
        guard let n = number() else { throw DJLinkError("not on the link yet: no device number") }
        guard let address = player_address(shared.players, player_number) else {
            throw DJLinkError("player \(player_number) is not on the link")
        }
        try await udpSend(
            commands, load_track_command(REKORDBOX_NAME, n, player_number, track_id), Int(config.player_port),
            address.description)
    }
    public func master_state() -> MasterState { shared.master }
    public func set_master(_ on: Bool) {
        shared.master.on = on
        if on { shared.master.bar_beat = 1 }
    }
    public func set_master_bpm(_ bpm_x100: UInt16) {
        shared.master.bpm_x100 = min(max(bpm_x100, MASTER_BPM_MIN), MASTER_BPM_MAX)
    }
    public func nudge_master(_ delta_x100: Int32) {
        let next = Int32(shared.master.bpm_x100) &+ delta_x100
        shared.master.bpm_x100 = UInt16(min(max(next, Int32(MASTER_BPM_MIN)), Int32(MASTER_BPM_MAX)))
    }
    public func current_player_tempo() -> UInt16? {
        shared.players.values.first { $0.master && $0.bpm_x100 != 0 }.map { UInt16(exactly: $0.bpm_x100) ?? .max }
    }
    public func stop() {
        guard !stopped else { return }
        stopped = true
        resources.close()
        timers = []
    }
    public func shutdown() async {
        stopped = true
        timers = []
        await resources.shutdown()
    }
    deinit {
        let resources = resources
        Task { @DJLinkActor in resources.close() }
    }
    private func announce_tick() {
        guard !stopped, announce_running else { return }
        let now = clock.nowMilliseconds()
        shared.expire_peers(UInt64(max(now - started, 0)))
        let outgoing = shared.join?.tick(UInt64(max(now, 0)))
        let settled = shared.join?.number() ?? 0
        if settled != shared.assigned.load() {
            shared.assigned.store(settled)
            next_keep_alive = settled == 0 ? nil : now
        }
        if settled == 0 { next_keep_alive = nil }
        if let join = shared.join, case let .failed(why) = join.state(), shared.down == nil { shared.down = why }
        if let outgoing { send_announce(announce, outgoing, config.broadcast, config.announce_port) }
        if let due = next_keep_alive, now >= due {
            next_keep_alive = due + KEEP_ALIVE_EVERY
            send(
                announce,
                KeepAlive.rekordbox_as(
                    shared.assigned.load(), config.mac, config.address, UInt8(exactly: shared.peers.len()) ?? .max
                ).encode(), config.broadcast, config.announce_port)
        }
        shared.expire_silent_players()
        if now >= next_monitor {
            next_monitor += NETWORK_MONITOR_EVERY
            if let why = interface_lost(config, interfaceProvider), shared.down == nil {
                shared.down = why
                shared.join?.reset(UInt64(max(now, 0)))
                shared.assigned.store(0)
                next_keep_alive = nil
            }
        }
    }
    private func status_tick() {
        guard !stopped, status_running else { return }
        let now = clock.nowMilliseconds()
        guard let ours = number() else {
            next_send = now
            return
        }
        if now >= next_send {
            next_send += STATUS_EVERY
            send(statusSender, status_packet(shared, ours, free_beat), config.broadcast, config.player_port)
            free_beat = free_beat >= 4 ? 1 : free_beat + 1
        }
        let pending = shared.to_greet
        shared.to_greet = []
        shared.greeted += pending
        for player in pending { send(commands, connect_greeting(REKORDBOX_NAME, ours), player, config.player_port) }
        let packets = pending_status
        pending_status = []
        for (packet, from) in packets { hear_status(packet, from) }
    }
    private func hear_status(_ packet: [UInt8], _ from: RemoteInfo) {
        guard let ours = number(), !shared.rejected(), let address = try? LinkAddress(from.address),
            let kind = try? packet_kind(packet)
        else { return }
        switch kind {
        case DEVICE_IDENTITY_QUERY_KIND:
            send(commands, connect_identity(REKORDBOX_NAME, ours, config.computer_name), address, config.player_port)
        case 5: answer_media_query(commands, packet, config, facts, ours)
        case DEVICE_PROPERTY_QUERY_KIND: answer_device_property_query(commands, packet, address, config, ours)
        case DEVICE_SETTINGS_REQUEST_KIND:
            send(
                commands, device_settings_response(REKORDBOX_NAME, ours, facts.device_settings()), address,
                config.player_port)
        case LOAD_TRACK_ACK_KIND: _ = try? LoadTrackResponse.decode(packet)
        case PLAYER_STATUS_KIND: hear_player_status(packet, address, commands, config, shared, facts, ours)
        default: break
        }
    }
    private func schedule_beat(_ delay: Double) {
        resources.beatTimer = clock.setTimeout(.ms(delay)) { [weak self] in self?.beat_tick() }
    }
    private func beat_tick() {
        guard !stopped, let beats else { return }
        let now = clock.nowMilliseconds()
        let m = shared.master
        guard m.on, let ours = number() else {
            next_beat = now
            schedule_beat(POLL)
            return
        }
        if now < next_beat {
            schedule_beat(min(next_beat - now, POLL))
            return
        }
        send(beats, beat_packet(REKORDBOX_NAME, ours, m.bpm_x100, m.bar_beat), config.broadcast, config.beat_port)
        if !shared.rejected() { shared.master.bar_beat = m.bar_beat >= 4 ? 1 : m.bar_beat + 1 }
        let interval = Double(6_000_000 / UInt64(max(m.bpm_x100, 1)))
        next_beat += interval
        if next_beat < now { next_beat = now + interval }
        schedule_beat(min(max(next_beat - now, 1), POLL))
    }
}
@DJLinkActor func shared_udp(_ port: UInt16, _ interface: String?, _ factory: any ExportSocketFactory) async throws
    -> any UDPSocket
{
    let socket = try factory.createUDPSocket(reuseAddr: true)
    do {
        _ = try await socket.bind(port: Int(port), address: "0.0.0.0")
        if let interface { try socket.setBoundInterface(name: interface) }
        return socket
    } catch {
        await close_beacon_socket(socket)
        throw error
    }
}
@DJLinkActor private func broadcast(_ socket: any UDPSocket) throws {
    if let server = socket as? any ServerUDPSocket {
        try server.setBroadcastChecked(true)
    } else {
        socket.setBroadcast(true)
    }
}
func interface_lost(_ config: BeaconConfig, _ provider: any InterfaceProvider) -> String? {
    guard let name = config.interface else { return nil }
    let present = provider.networkInterfaces().contains {
        $0.name == name && $0.addresses.contains { $0.address == config.address.description }
    }
    return present ? nil : "\(name) no longer has the address \(config.address)"
}
@DJLinkActor func send(_ socket: any UDPSocket, _ packet: [UInt8], _ to: LinkAddress, _ port: UInt16) {
    socket.send(packet, port: Int(port), address: to.description, callback: nil)
}
@DJLinkActor func send_announce(_ socket: any UDPSocket, _ out: Outgoing, _ broadcast: LinkAddress, _ port: UInt16) {
    send(socket, out.packet, out.to ?? broadcast, port)
}
@DJLinkActor func hear_announce(
    _ packet: [UInt8], _ from: RemoteInfo, _ config: BeaconConfig, _ shared: BeaconShared, _ started: Double
) -> Outgoing? {
    guard let sender = try? LinkAddress(from.address) else { return nil }
    let kind = try? packet_kind(packet)
    let now = UInt64(max(shared.clock.nowMilliseconds(), 0))
    guard shared.join?.announcement_sender_allowed(sender, config.netmask) ?? (sender != .unspecified) else {
        return nil
    }
    if kind != 9 && shared.rejected() { return nil }
    let original_model =
        packet.count > 0x21 && packet[0x21] == 0 && ["CDJ-2000", "CDJ-900"].contains((try? device_name(packet)) ?? "")
    let model_gate = config.mode == .unknown ? true : (shared.join?.excludes_original_models() ?? false)
    if model_gate && original_model { return nil }
    switch kind {
    case 0:
        guard let discovery = try? Discovery.decode(packet) else { return nil }
        shared.rediscover(discovery)
        return nil
    case 2:
        if packet.count > 11, packet[11] == PROBE_SUBTYPE_BLOCK {
            guard let block = try? NumberBlock.decode(packet) else { return nil }
            return shared.join?.hear_block(block)
        }
        guard let probe = try? NumberProbe.decode(packet) else { return nil }
        return shared.join?.hear_probe(probe)
    case 3:
        if let reply = try? NumberReply.decode(packet) { shared.join?.hear_reply(reply) }
        return nil
    case 9:
        guard packet.count >= 36, config.mode != .unknown else { return nil }
        if shared.join == nil {
            shared.join = Join.new(mac: config.mac, ip: config.address, now_ms: now).with_mode(config.mode)
        }
        let outgoing = shared.join?.reject(now)
        shared.assigned.store(0)
        shared.clear_members()
        shared.master = MasterState(on: false, bpm_x100: 0, bar_beat: 0)
        shared.down = "announcement rejected; restart Link to recover"
        return outgoing
    case 0x0b:
        guard let join = shared.join, join.state() != .waiting else { return nil }
        shared.clear_members()
        shared.join?.reset(now)
        return nil
    case 7, 8:
        guard packet.count > 0x24, (1...80).contains(packet[0x24]), let join = shared.join else { return nil }
        let active: Bool
        switch join.state() {
        case .discovery, .probing, .assigning, .running: active = true
        default: active = false
        }
        let number = packet[0x24]
        guard active, shared.peers.peers().contains(where: { $0.device_number == number }) else { return nil }
        shared.remove_member(number)
        if number == 9 || number == 11 { shared.remove_member(number + 1) }
        return nil
    case 6: break
    default: return nil
    }
    guard let keep_alive = try? KeepAlive.decode(packet),
        !(keep_alive.ip == config.address && keep_alive.mac == config.mac)
    else { return nil }
    shared.join?.hear_keep_alive(keep_alive, now)
    if config.mode == .wireless && original_model { return nil }
    if let join = shared.join, !join.allows_running_member(keep_alive.device_number) { return nil }
    let elapsed = UInt64(max(shared.clock.nowMilliseconds() - started, 0))
    shared.peers.observe_with_flags(keep_alive, elapsed, [packet[0x25], packet[0x35]])
    shared.observe_player(keep_alive, sender)
    shared.synthesize_members(keep_alive, sender, elapsed)
    if keep_alive.device_type == .cdj && !shared.greeted.contains(sender) && !shared.to_greet.contains(sender) {
        shared.to_greet.append(sender)
    }
    return nil
}
@DJLinkActor func answer_device_property_query(
    _ socket: any UDPSocket, _ packet: [UInt8], _ from: LinkAddress, _ config: BeaconConfig, _ ours: UInt8
) {
    guard (try? DevicePropertyQuery.decode(packet)) != nil else { return }
    send(socket, DevicePropertyResponse(name: REKORDBOX_NAME, device_number: ours).encode(), from, config.player_port)
}
@DJLinkActor func answer_media_query(
    _ socket: any UDPSocket, _ packet: [UInt8], _ config: BeaconConfig, _ facts: any LibraryFacts, _ ours: UInt8
) {
    guard let query = try? MediaQuery.decode(packet), query.device_number == ours,
        [SLOT_REKORDBOX, SLOT_REKORDBOX_LEGACY].contains(query.slot)
    else { return }
    send(
        socket,
        MediaResponse(
            name: REKORDBOX_NAME, device_number: ours, slot: query.slot, tracks: facts.track_count(),
            playlists: facts.playlist_count()
        ).encode(), query.from, config.player_port)
}
// alphatheta-connect-rs b54d9e9c53059f11e04f4de9898f4abae3b46480의 길이 경계와 반올림을 보존한다.
// SDK의 기존 파서를 재사용하며 원본 Rust가 nil로 처리하는 0xc8...0xcb도 nil이다.
func beacon_status_from_packet(_ packet: [UInt8]) throws -> CDJStatus.State? {
    guard packet.starts(with: PROLINK_HEADER) else {
        throw DJLinkError("CDJ status packet does not start with the expected header")
    }
    guard packet.count >= 0xcc, var state = try statusFromPacket(packet) else { return nil }
    func pitch(_ at: Int) -> Double {
        let value = Int(packet[at]) << 16 | Int(packet[at + 1]) << 8 | Int(packet[at + 2])
        let computed = Double(value - 0x100000) / Double(0x100000) * 100
        return (computed * 100).rounded(.toNearestOrAwayFromZero) / 100
    }
    state.effectivePitch = pitch(0x8d)
    state.sliderPitch = pitch(0x99)
    return state
}
@DJLinkActor func hear_player_status(
    _ packet: [UInt8], _ from: LinkAddress, _ socket: any UDPSocket, _ config: BeaconConfig, _ shared: BeaconShared,
    _ facts: any LibraryFacts, _ ours: UInt8
) {
    guard let state = try? beacon_status_from_packet(packet), !shared.rejected() else { return }
    if !shared.greeted.contains(from) {
        shared.greeted.append(from)
        send(socket, connect_greeting(REKORDBOX_NAME, ours), from, config.player_port)
    }
    let from_us =
        state.trackDeviceId == Int(ours) && [MediaSlot.rb, .usb].contains(state.trackSlot) && state.trackId != 0
    let playing = [CDJStatus.PlayState.playing, .looping].contains(state.playState)
    let number = UInt8(truncatingIfNeeded: state.deviceId)
    let kind = peer_kind(shared, number)
    if shared.players[number] == nil {
        shared.players[number] = Player(
            number: number, name: (try? status_device_name(packet)) ?? "", address: from, kind: kind,
            last_seen: shared.clock.nowMilliseconds())
    }
    let loaded: UInt32? = from_us ? UInt32(truncatingIfNeeded: state.trackId) : nil
    if shared.players[number]!.loaded != loaded, let loaded { facts.track_loaded(loaded) }
    shared.players[number]!.kind = kind
    shared.players[number]!.loaded = loaded
    shared.players[number]!.playing = playing
    shared.players[number]!.master = state.isMaster
    shared.players[number]!.sync = state.isSync
    shared.players[number]!.cued = [CDJStatus.PlayState.cued, .cuing].contains(state.playState)
    shared.players[number]!.bpm_x100 = tempo_x100(state.trackBPM, state.effectivePitch)
    shared.players[number]!.last_seen = shared.clock.nowMilliseconds()
}
@DJLinkActor func status_packet(_ shared: BeaconShared, _ ours: UInt8, _ free_beat: UInt8) -> [UInt8] {
    let m = shared.master
    let bpm: UInt16
    let beat: UInt8
    let we_master: Bool
    if m.on {
        bpm = m.bpm_x100
        beat = m.bar_beat
        we_master = true
    } else {
        bpm = shared.players.values.first(where: { $0.master }).map { UInt16(exactly: $0.bpm_x100) ?? .max } ?? 0
        beat = bpm == 0 ? 0 : free_beat
        we_master = false
    }
    return Status(name: REKORDBOX_NAME, device_number: ours, bpm_x100: bpm, beat: beat, master: we_master).encode()
}
@DJLinkActor func peer_kind(_ shared: BeaconShared, _ number: UInt8) -> LinkDeviceType {
    shared.peers.peers().first { $0.device_number == number }?.device_type ?? .cdj
}
func player_address(_ players: [UInt8: Player], _ number: UInt8) -> LinkAddress? { players[number]?.address }
func tempo_x100(_ track_bpm: Double?, _ pitch_percent: Double) -> UInt32 {
    guard let bpm = track_bpm else { return 0 }
    let x100 = (bpm * 100 * (1 + pitch_percent / 100)).rounded(.toNearestOrAwayFromZero)
    return x100.isFinite && x100 > 0 && x100 < Double(UInt32.max) ? UInt32(x100) : 0
}

private final class BeaconResources: @unchecked Sendable {
    let clock: any DJLinkClock
    let sockets: [any UDPSocket]
    var timers: [TimerHandle] = []
    var beatTimer: TimerHandle?
    @DJLinkActor init(_ clock: any DJLinkClock, _ sockets: [any UDPSocket]) {
        self.clock = clock
        self.sockets = sockets
    }
    var closing: Task<Void, Never>?
    @DJLinkActor func close() {
        guard closing == nil else { return }
        for timer in timers { clock.clearTimer(timer) }
        timers = []
        clock.clearTimeout(beatTimer)
        beatTimer = nil
        let sockets = sockets
        closing = Task { @DJLinkActor in
            var seen: Set<ObjectIdentifier> = []
            for socket in sockets where seen.insert(ObjectIdentifier(socket)).inserted {
                if let server = socket as? any ServerUDPSocket {
                    try? await server.shutdown()
                } else {
                    try? await udpClose(socket)
                }
            }
        }
    }
    @DJLinkActor func shutdown() async {
        close()
        await closing?.value
    }

}

@DJLinkActor private func close_beacon_socket(_ socket: any UDPSocket) async {
    if let server = socket as? any ServerUDPSocket { try? await server.shutdown() } else { try? await udpClose(socket) }
}
