import DJLinkExportDBServer
import DJLinkExportModel
import DJLinkExportNFS
import DJLinkExportProtocol
import DJLinkExportSupport
import DJLinkKit
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-link/src/lib.rs (90bfb53).
import Darwin
import Foundation

// 원본 crate의 pub use와 공개 콜백 별칭을 모듈 경계에서도 유지한다.
public typealias UnsupportedCommandReporter = DJLinkExportDBServer.UnsupportedCommandReporter
public typealias ArtistRole = DJLinkExportDBServer.ArtistRole
public typealias Edit = DJLinkExportDBServer.Edit
public typealias HotCueColour = DJLinkExportDBServer.HotCueColour
public typealias PlayerCue = DJLinkExportDBServer.PlayerCue
public typealias RootCategory = DJLinkExportDBServer.RootCategory
public typealias Sort = DJLinkExportDBServer.Sort
public typealias TrackColumn = DJLinkExportDBServer.TrackColumn
public typealias DeviceType = DJLinkExportProtocol.DeviceType

public struct Ports: Equatable, Sendable {
    public var announce, status, query, database, portmap, mount, nfs: UInt16
    public init(
        announce: UInt16, status: UInt16, query: UInt16, database: UInt16, portmap: UInt16, mount: UInt16, nfs: UInt16
    ) {
        self.announce = announce
        self.status = status
        self.query = query
        self.database = database
        self.portmap = portmap
        self.mount = mount
        self.nfs = nfs
    }
    public static let REKORDBOX = Ports(
        announce: PORT_ANNOUNCE, status: PORT_STATUS, query: PORT_QUERY, database: 0, portmap: REKORDBOX_PORTMAP_PORT,
        mount: 0, nfs: NFS_PORT)
    public static let EPHEMERAL = Ports(announce: 0, status: 0, query: 0, database: 0, portmap: 0, mount: 0, nfs: 0)
}
public struct Interface: Equatable, Sendable {
    public var name: String
    public var address, netmask: LinkAddress
    public var mac: [UInt8]
    public init(name: String, address: LinkAddress, netmask: LinkAddress, mac: [UInt8]) {
        precondition(mac.count == 6)
        self.name = name
        self.address = address
        self.netmask = netmask
        self.mac = mac
    }
    public func broadcast() -> LinkAddress {
        try! LinkAddress(zip(address.octets, netmask.octets).map { String($0 | ~$1) }.joined(separator: "."))
    }
    public static func loopback() -> Self {
        Self(
            name: "lo0", address: try! .init("127.0.0.1"), netmask: try! .init("255.0.0.0"),
            mac: [UInt8](repeating: 0, count: 6))
    }
}
public func interfaces(interfaceProvider: any InterfaceProvider = SystemInterfaceProvider()) -> [Interface] {
    interfaceProvider.networkInterfaces().flatMap { entry in
        entry.addresses.compactMap { value in
            guard !value.internal, value.family == "IPv4", let address = try? LinkAddress(value.address),
                let mask = try? LinkAddress(value.netmask), let mac = InterfaceMode.parse_mac(value.mac)
            else { return nil }
            return Interface(name: entry.name, address: address, netmask: mask, mac: mac)
        }
    }
}
/// UDP connect는 송신하지 않는다. 시험은 경로 조회를 주입해 실제 소켓을 열지 않는다.
public func interface_toward(
    _ interfaces: [Interface], _ peer: LinkAddress, routeAddress: ((LinkAddress) -> LinkAddress?)? = nil
) -> Interface? {
    let local: LinkAddress?
    if let routeAddress {
        local = routeAddress(peer)
    } else {
        guard !TestProcess.isRunning else { return nil }
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, Darwin.IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = PORT_STATUS.bigEndian
        guard inet_pton(AF_INET, peer.description, &target.sin_addr) == 1 else { return nil }
        let connected = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard result == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address.sin_addr, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        local = try? LinkAddress(
            String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }
    return interfaces.first { $0.address == local }
}
public enum LinkError: Error, Equatable, Sendable, CustomStringConvertible {
    case bind(String), noLibrary
    public var description: String {
        switch self {
        case let .bind(why): return why
        case .noLibrary: return "the library has not loaded"
        }
    }
}
public struct Snapshot: Equatable, Sendable {
    public var interface: Interface
    public var database_port: UInt16
    public var players: [Player]
    public var master: MasterState
    public var link: LinkState
    public var mounted: [LinkAddress]
}
@DJLinkActor final class Facts: LibraryFacts {
    let source: any Source
    init(_ source: any Source) { self.source = source }
    func track_count() -> UInt16 { UInt16(clamping: source.library()?.len() ?? 0) }
    func playlist_count() -> UInt16 { UInt16(clamping: source.library()?.playlists().len() ?? 0) }
    func device_settings() -> DeviceSettings { source.device_settings() }
}
@DJLinkActor public final class LinkExport {
    private let interface: Interface
    private let beacon: Beacon
    private let database: DJLinkExportDBServer.Net.Bound
    private let files: DJLinkExportNFS.Net.Bound
    private let catalog: IndexCatalog
    private init(
        _ interface: Interface, _ beacon: Beacon, _ database: DJLinkExportDBServer.Net.Bound,
        _ files: DJLinkExportNFS.Net.Bound, _ catalog: IndexCatalog
    ) {
        self.interface = interface
        self.beacon = beacon
        self.database = database
        self.files = files
        self.catalog = catalog
    }
    public static func start(
        _ source: any Source, _ interface: Interface, _ ports: Ports = Ports.REKORDBOX,
        socketFactory: any ExportSocketFactory = LiveExportSocketFactory.shared,
        clock: any DJLinkClock = MonotonicClock.shared,
        interfaceProvider: any InterfaceProvider = SystemInterfaceProvider(), connectionMode: ConnectionMode? = nil
    ) async throws -> LinkExport {
        try await start_with_unsupported_command_reporter(
            source, interface, ports, nil, socketFactory: socketFactory, clock: clock,
            interfaceProvider: interfaceProvider, connectionMode: connectionMode)
    }
    public static func start_with_unsupported_command_reporter(
        _ source: any Source, _ interface: Interface, _ ports: Ports, _ reporter: UnsupportedCommandReporter?,
        socketFactory: any ExportSocketFactory = LiveExportSocketFactory.shared,
        clock: any DJLinkClock = MonotonicClock.shared,
        interfaceProvider: any InterfaceProvider = SystemInterfaceProvider(), connectionMode: ConnectionMode? = nil
    ) async throws -> LinkExport {
        guard let library = source.library() else { throw LinkError.noLibrary }
        let catalog = IndexCatalog(source, Played())
        let loopback = interface.address.octets[0] == 127
        let beacon: Beacon
        do {
            beacon = try await Beacon.start(
                BeaconConfig(
                    interface: loopback ? nil : interface.name, address: interface.address, netmask: interface.netmask,
                    broadcast: interface.broadcast(), mac: interface.mac,
                    mode: connectionMode ?? connection_mode_for(mac: interface.mac), announce_port: ports.announce,
                    status_port: ports.status, player_port: PORT_STATUS, beat_port: PORT_BEAT,
                    computer_name: computer_name()), Facts(source), socketFactory: socketFactory, clock: clock,
                interfaceProvider: interfaceProvider)
        } catch { throw LinkError.bind(explain(error, "UDP", ports.announce)) }
        let number = beacon.number_cell()
        let handler = CatalogHandler(catalog).with_device(number)
        if let reporter { handler.with_unsupported_command_reporter(reporter) }
        let listen_on = service_bind_address(interface)
        let database: DJLinkExportDBServer.Net.Bound
        do {
            database = try await DJLinkExportDBServer.Net.Bound.start(
                handler, listen_on, ports.query, ports.database, socketFactory: socketFactory, clock: clock)
        } catch {
            await beacon.shutdown()
            throw LinkError.bind(explain(error, "TCP", ports.query))
        }
        let files: DJLinkExportNFS.Net.Bound
        do {
            files = try await DJLinkExportNFS.Net.Bound.start(
                Files.exports(library), listen_on, ports.portmap, ports.mount, ports.nfs,
                loopback ? nil : "\(interface.address)/\(interface.netmask)", number, socketFactory: socketFactory,
                clock: clock, interfaceProvider: interfaceProvider)
        } catch {
            await database.shutdown()
            await beacon.shutdown()
            throw LinkError.bind(explain(error, "UDP", ports.portmap))
        }
        return LinkExport(interface, beacon, database, files, catalog)
    }
    public func beacon_ports() -> (UInt16, UInt16) { (beacon.announce_port(), beacon.status_port()) }
    public func snapshot() -> Snapshot {
        Snapshot(
            interface: interface, database_port: UInt16(database.database_address().port), players: beacon.players(),
            master: beacon.master_state(), link: beacon.link_state(),
            mounted: files.mounted_hosts().compactMap { try? LinkAddress($0.address) })
    }
    public func link_state() -> LinkState { beacon.link_state() }
    public func set_master(_ on: Bool) { beacon.set_master(on) }
    public func nudge_master(_ delta_x100: Int32) { beacon.nudge_master(delta_x100) }
    public func take_master_tempo() -> Bool {
        guard let bpm = beacon.current_player_tempo() else { return false }
        beacon.set_master_bpm(bpm)
        return true
    }
    public func query_address() -> AddressInfo { database.query_address() }
    public func database_address() -> AddressInfo { database.database_address() }
    public func portmap_address() -> AddressInfo { files.portmap_address() }
    public func analysis_changed() { catalog.forget_analysis() }
    public func load_track(_ player_number: UInt8, _ track_id: UInt32) async throws {
        if let address = beacon.players().first(where: { $0.number == player_number })?.address,
            !files.is_mounted(try DJLinkKit.Address4(address.description))
        {
            throw DJLinkError("player \(player_number) has not mounted the library yet")
        }
        try await beacon.load_track(player_number, track_id)
    }
    public func stop() async {
        await beacon.shutdown()
        await database.shutdown()
        await files.shutdown()
    }
}
func service_bind_address(_ interface: Interface) -> String { interface.address.description }
@DJLinkActor public final class StaticSource: Source {
    public let snapshot: Library
    public let root: String
    public init(library: Library, share_root: String) {
        snapshot = library
        root = share_root
    }
    public func library() -> Library? { snapshot }
    public func share_root() -> String { root }
    public func details(_ id: String) -> DJLinkExportModel.TrackDetails? { nil }
}
func explain(_ error: any Error, _ protocolName: String, _ port: UInt16) -> String {
    let code: Int
    if let error = error as? SystemCallError { code = Int(error.errno) } else { code = (error as NSError).code }
    switch code {
    case Int(EADDRINUSE):
        return "\(protocolName) port \(port) is already in use — usually by rekordbox itself. Quit it to turn LINK on."
    case Int(EACCES), Int(EPERM): return "Not allowed to bind \(protocolName) port \(port)."
    default: return "Could not bind \(protocolName) port \(port): \(error)"
    }
}
func computer_name() -> String {
    if let value = ProcessInfo.processInfo.environment["COMPUTERNAME"], !value.isEmpty { return value }
    var name = [CChar](repeating: 0, count: 256)
    if gethostname(&name, name.count) == 0 {
        let host =
            String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).trimmingCharacters(
                in: .whitespacesAndNewlines
            ).split(
                separator: ".", omittingEmptySubsequences: false
            ).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !host.isEmpty { return host }
    }
    return REKORDBOX_NAME
}
