import DJLinkKit
import DJLinkTestSupport
import Darwin
import Testing

@testable import DJLinkKit

// 원본 대응이 아닌 시험. CLI 안전을 위해 더한 opt-in(번호 정책·announce 대상 필터·인터페이스 묶기)이
// 기본값에서는 원본 동작과 같고, 켜면 약속대로 막는지 본다. 모든 소켓과 시간은 가짜다.
@Suite("CLI safety opt-ins")
@DJLinkActor
struct CLISafetyOptInTests {
    let clock = TestClock()

    private func iface(_ cidr: String) -> NetworkInterfaceInfo {
        let address = String(cidr.split(separator: "/")[0])
        return NetworkInterfaceInfo(
            address: address, netmask: "255.255.255.0", family: "IPv4", mac: "00:11:22:33:44:55", internal: false,
            cidr: cidr)
    }

    private func conflictPacket(_ id: Int) -> [UInt8] {
        var packet = [UInt8].alloc(0x29)
        packet.set(PROLINK_HEADER, 0)
        packet[0x0a] = 0x08
        packet[0x24] = UInt8(id)
        return packet
    }

    private struct Rig {
        let announcer: Announcer
        let vcdj: DeviceReference
        let socket: FakeUDPSocket
        let rejected: CallRecorder<DeviceID>
    }

    private func makeRig(
        vcdjId: Int, peers: [(id: Int, ip: String)], fullStartup: Bool,
        allowsDeviceId: (@Sendable (DeviceID) -> Bool)? = nil,
        announceTargetFilter: (@Sendable (Device) -> Bool)? = nil
    ) throws -> Rig {
        let socket = FakeUDPSocket()
        let manager = DeviceManager(FakeUDPSocket(), clock: clock)
        for peer in peers {
            manager.devices[peer.id] = mockDevice(id: peer.id, name: "CDJ-\(peer.id)", ip: try Address4(peer.ip))
        }
        let network = iface("192.168.1.100/24")
        let vcdj = DeviceReference(try getVirtualCDJ(network, vcdjId))
        let rejected = CallRecorder<DeviceID>()
        let announcer = Announcer(
            vcdj, socket, manager, network, fullStartup: fullStartup, clock: clock,
            allowsDeviceId: allowsDeviceId, onDeviceIdRejected: { rejected.record($0) },
            announceTargetFilter: announceTargetFilter)
        return Rig(announcer: announcer, vcdj: vcdj, socket: socket, rejected: rejected)
    }

    /// 7~32번을 모두 쓰는 장치. 충돌이 나면 1~6번만 남는다.
    private var crowdedPeers: [(id: Int, ip: String)] {
        (7...32).map { (id: $0, ip: "192.168.1.\($0 + 10)") }
    }

    @Test("without a policy a conflict still falls back to player numbers like upstream", arguments: [false, true])
    func defaultStillMovesToPlayerNumbers(fullStartup: Bool) throws {
        let rig = try makeRig(vcdjId: 7, peers: crowdedPeers, fullStartup: fullStartup)
        try rig.announcer.start()
        rig.socket.emitMessage(conflictPacket(7))
        rig.announcer.stop()
        #expect(rig.vcdj.id == 6)
        #expect(rig.rejected.calls.isEmpty)
    }

    @Test("a disallowed replacement number stops the announcer before any packet carries it", arguments: [false, true])
    func rejectsReplacementBeforeAnnouncing(fullStartup: Bool) throws {
        let rig = try makeRig(
            vcdjId: 7, peers: crowdedPeers, fullStartup: fullStartup, allowsDeviceId: { $0 >= 7 })
        try rig.announcer.start()
        #expect(!rig.socket.sent.isEmpty)
        rig.socket.clearSent()

        rig.socket.emitMessage(conflictPacket(7))
        // 시작 단계 타이머와 keep-alive가 모두 지나도록 시간을 민다.
        clock.advance(ms: 30_000)

        #expect(rig.socket.sent.isEmpty, "허용하지 않는 번호로도 옛 번호로도 패킷이 나가면 안 된다")
        #expect(rig.vcdj.id == 7, "번호를 바꾸지 않는다")
        #expect(rig.rejected.calls == [6])
        #expect(clock.pendingTimerCount == 0)
        // 멈춘 announcer는 다음 충돌에도 반응하지 않는다.
        rig.socket.emitMessage(conflictPacket(7))
        #expect(rig.rejected.calls == [6])
    }

    @Test("an allowed replacement number moves normally and never reports a rejection")
    func allowedReplacementMoves() throws {
        let rig = try makeRig(
            vcdjId: 7, peers: [(id: 7, ip: "192.168.1.20")], fullStartup: false, allowsDeviceId: { $0 >= 7 })
        try rig.announcer.start()
        rig.socket.emitMessage(conflictPacket(7))
        rig.announcer.stop()
        #expect(rig.vcdj.id == 8)
        #expect(rig.rejected.calls.isEmpty)
    }

    @Test("a disallowed first number never announces", arguments: [false, true])
    func rejectsFirstNumber(fullStartup: Bool) throws {
        let rig = try makeRig(
            vcdjId: 3, peers: [(id: 1, ip: "192.168.1.11")], fullStartup: fullStartup, allowsDeviceId: { $0 >= 7 })
        #expect(throws: DJLinkError("Device ID 3 is not allowed")) { try rig.announcer.start() }
        clock.advance(ms: 10_000)
        #expect(rig.socket.sent.isEmpty)
        #expect(rig.socket.messageListenerCount == 0)
    }

    @Test("the target filter limits who receives announce packets", arguments: [false, true])
    func targetFilter(fullStartup: Bool) throws {
        let rig = try makeRig(
            vcdjId: 7,
            peers: [(id: 1, ip: "192.168.1.11"), (id: 2, ip: "10.9.0.2"), (id: 3, ip: "192.168.1.13")],
            fullStartup: fullStartup,
            announceTargetFilter: { $0.ip.address.hasPrefix("192.168.1.") })
        try rig.announcer.start()
        clock.advance(ms: 6000)
        rig.announcer.stop()
        let addresses = Set(rig.socket.sent.map(\.address))
        #expect(addresses == ["192.168.1.11", "192.168.1.13"])
    }

    @Test("without a filter every discovered device still receives packets")
    func defaultTargetsEveryDevice() throws {
        let rig = try makeRig(
            vcdjId: 7, peers: [(id: 1, ip: "192.168.1.11"), (id: 2, ip: "10.9.0.2")], fullStartup: false)
        try rig.announcer.start()
        rig.announcer.stop()
        #expect(Set(rig.socket.sent.map(\.address)) == ["192.168.1.11", "10.9.0.2"])
    }

    @Test("the network passes the policy and the filter from its config to the announcer")
    func networkPassesPolicy() async throws {
        let factory = FakeSocketFactory()
        let mocks = NetworkDatabaseMocks()
        let network = try await bringOnline(
            socketFactory: factory, interfaceProvider: FakeInterfaceProvider(), clock: clock,
            dependencies: mocks.dependencies)
        let announce = factory.udpSockets[0]
        announce.clearSent()
        let rejected = CallRecorder<DeviceID>()
        network.configure(
            NetworkConfig(
                iface: networkTestInterface, vcdjId: 3, allowsDeviceId: { $0 >= 7 },
                onDeviceIdRejected: { rejected.record($0) }))
        #expect(throws: DJLinkError("Device ID 3 is not allowed")) { try network.connect() }
        clock.advance(ms: 10_000)
        #expect(announce.sent.isEmpty)

        network.configure(NetworkConfig(vcdjId: 9))
        try network.connect()
        #expect(network.virtualDevice?.id == 9)
    }

    @Test("a socket that does not support interface binding refuses instead of silently ignoring it")
    func defaultBindingThrows() throws {
        @DJLinkActor final class PlainSocket: UDPSocket {
            func onMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
                .init(id: 0)
            }
            func onceMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
                .init(id: 0)
            }
            func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) -> SocketListener { .init(id: 0) }
            func onClose(_ handler: @escaping @DJLinkActor () -> Void) -> SocketListener { .init(id: 0) }
            func off(_ listener: SocketListener) {}
            func removeAllListeners() {}
            func bind(port: Int?, address: String?) async throws -> AddressInfo { AddressInfo(address: "", port: 0) }
            func send(_ msg: [UInt8], port: Int, address: String, callback: (@DJLinkActor ((any Error)?, Int) -> Void)?)
            {}
            func setBroadcast(_ flag: Bool) {}
            func address() -> AddressInfo? { nil }
            func close(_ callback: (@DJLinkActor () -> Void)?) throws {}
        }
        #expect(throws: DJLinkError("This socket cannot be bound to a network interface")) {
            try PlainSocket().setBoundInterface(name: "en7")
        }
    }

    // MARK: IP_BOUND_IF

    private final class SetSockOptLog: @unchecked Sendable {
        var calls: [(fd: Int32, level: Int32, name: Int32, index: UInt32, length: socklen_t)] = []
        var result: Int32 = 0
    }

    @Test("binding to an interface sets IP_BOUND_IF to the interface index")
    func boundIfCall() throws {
        let log = SetSockOptLog()
        try bindSocketToInterface(
            fd: 42, name: "en7", nameToIndex: { $0 == "en7" ? 17 : 0 },
            setsockopt: { fd, level, name, value, length in
                log.calls.append((fd, level, name, value!.load(as: UInt32.self), length))
                return log.result
            })
        #expect(log.calls.count == 1)
        let call = try #require(log.calls.first)
        #expect(call.fd == 42)
        #expect(call.level == IPPROTO_IP)
        #expect(call.name == IP_BOUND_IF)
        #expect(call.index == 17)
        #expect(call.length == 4)
    }

    @Test("binding fails without calling setsockopt when the interface name is unknown")
    func boundIfUnknownName() {
        let log = SetSockOptLog()
        #expect(throws: SystemCallError.self) {
            try bindSocketToInterface(
                fd: 42, name: "nope0", nameToIndex: { _ in 0 },
                setsockopt: { _, _, _, _, _ in
                    log.calls.append((0, 0, 0, 0, 0))
                    return 0
                })
        }
        #expect(log.calls.isEmpty)
    }

    @Test("binding fails when setsockopt fails")
    func boundIfSetsockoptFailure() {
        #expect(throws: SystemCallError.self) {
            try bindSocketToInterface(fd: 42, name: "en7", nameToIndex: { _ in 5 }, setsockopt: { _, _, _, _, _ in -1 })
        }
    }

    @Test("the fake socket records bound interfaces and can be told to fail")
    func fakeRecordsBinding() throws {
        let socket = FakeUDPSocket()
        try socket.setBoundInterface(name: "en7")
        #expect(socket.boundInterfaces == ["en7"])
        socket.boundInterfaceError = DJLinkError("boom")
        #expect(throws: DJLinkError("boom")) { try socket.setBoundInterface(name: "en8") }
        #expect(socket.boundInterfaces == ["en7"])
    }
}
