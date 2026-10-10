import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 대응이 아닌 연결 서비스 통합 시험. 모든 소켓과 시간은 가짜다.
@Suite("ProlinkNetwork flow")
@DJLinkActor
struct NetworkFlowTests {
    @Test("online, configure, connect, disconnect and close preserve upstream lifecycle")
    func lifecycle() async throws {
        let factory = FakeSocketFactory()
        let clock = TestClock()
        let mocks = NetworkDatabaseMocks()
        let network = try await bringOnline(
            socketFactory: factory, interfaceProvider: FakeInterfaceProvider(), clock: clock,
            dependencies: mocks.dependencies)
        #expect(factory.udpSockets.count == 3)
        #expect(factory.udpSockets.map { $0.bindCalls.first?.port } == [ANNOUNCE_PORT, BEAT_PORT, STATUS_PORT])
        #expect(factory.udpSockets.allSatisfy { $0.bindCalls.first?.address == "0.0.0.0" })
        #expect(factory.udpSockets[0].broadcastCalls == [true])
        #expect(factory.udpSockets[1].broadcastCalls.isEmpty)
        #expect(factory.udpSockets[2].broadcastCalls.isEmpty)
        #expect(network.state == .online)
        #expect(!network.isConfigured)
        #expect(!network.isConnected())
        #expect(network.statusEmitter == nil)
        #expect(network.positionEmitter == nil)
        #expect(network.virtualDevice == nil)
        #expect(network.db == nil)
        #expect(network.localdb == nil)
        #expect(network.remotedb == nil)
        #expect(network.mixstatus == nil)
        await network.startupReady
        let help = DJLinkError("Network must be configured. Try using `autoconfigFromPeers` or `configure`")
        #expect(throws: help) { try network.connect() }
        #expect(throws: help) { try network.disconnect() }

        network.configure(
            .init(iface: networkTestInterface, vcdjId: 7, vcdjName: "Network-test", databasePreference: .pdb))
        network.configure(.init(fullStartup: false))
        try network.connect()
        #expect(network.state == .connected)
        #expect(network.isConfigured)
        #expect(network.isConnected())
        #expect(network.virtualDevice?.name == "Network-test")
        #expect(network.virtualDevice?.id == 7)
        #expect(network.statusEmitter != nil)
        #expect(network.positionEmitter != nil)
        #expect(mocks.constructionOrder == ["remote", "local", "database"])
        #expect(mocks.local?.preference == .pdb)
        #expect(mocks.remote?.hostDeviceRef === mocks.local?.hostDeviceRef)
        #expect(mocks.local?.hostDeviceRef === mocks.database?.hostDeviceRef)
        let reference = try #require(mocks.remote?.hostDeviceRef)
        reference.id = 8
        #expect(network.virtualDevice?.id == 8)
        #expect(network.db?.hostDevice.id == 8)
        #expect(network.remotedb?.hostDevice.id == 8)
        await network.startupReady

        let device = mockDevice(ip: try Address4("192.168.1.2"))
        network.deviceManager.devices[device.id] = device
        let close = try network.disconnect()
        await clock.settle()
        #expect(mocks.remote?.disconnected == [device])
        #expect(mocks.local?.disconnected == [device])
        #expect(clock.pendingTimerCount == 0)
        #expect(factory.udpSockets.allSatisfy { !$0.isClosed })
        #expect(network.state == .connected)
        #expect(network.db != nil)
        try await close()
        #expect(factory.udpSockets.allSatisfy { $0.isClosed })
        #expect(network.state == .connected)
        #expect(network.virtualDevice?.id == 8)
    }

    @Test("autoconfig waits for a new peer and overwrites the configured player ID")
    func autoconfig() async throws {
        let factory = FakeSocketFactory()
        let clock = TestClock()
        let network = try await bringOnline(
            .init(vcdjId: 12), socketFactory: factory,
            interfaceProvider: FakeInterfaceProvider([("en0", [networkTestInterface])]), clock: clock,
            dependencies: NetworkDatabaseMocks().dependencies)
        let existing = mockDevice(id: 1, ip: try Address4("192.168.1.1"))
        network.deviceManager.devices[1] = existing
        let task = Task { try await network.autoconfigFromPeers() }
        await clock.settle()
        #expect(network.deviceManager.emitter.listenerCount(.connected) == 1)
        network.deviceManager.emitter.emit(.connected, existing)
        try await task.value
        #expect(network.deviceManager.emitter.listenerCount(.connected) == 0)
        try network.connect()
        #expect(network.virtualDevice?.id == 7)
        #expect(network.virtualDevice?.ip.address == "192.168.1.100")
        try network.disconnect()
        try await network.close()
    }

    @Test("autoconfig reports the upstream error if no interface matches")
    func autoconfigNoInterface() async throws {
        let clock = TestClock()
        let network = try await bringOnline(
            socketFactory: FakeSocketFactory(), interfaceProvider: FakeInterfaceProvider(), clock: clock)
        let task = Task { try await network.autoconfigFromPeers() }
        await clock.settle()
        network.deviceManager.emitter.emit(.connected, mockDevice())
        await #expect(throws: DJLinkError("Unable to determine network interface")) { try await task.value }
        #expect(!network.isConfigured)
        try await network.close()
    }

    @Test("Stagehand entrypoint enables packet parsing and autoconfig picks a stable Stagehand ID")
    func stagehandEntrypoint() async throws {
        let factory = FakeSocketFactory()
        let clock = TestClock()
        let network = try await bringOnlineStagehand(
            .init(connectMethod: .active), socketFactory: factory,
            interfaceProvider: FakeInterfaceProvider([("en0", [networkTestInterface])]), clock: clock,
            dependencies: NetworkDatabaseMocks().dependencies)
        #expect(network.isConfigured)
        let task = Task { try await network.autoconfigFromPeers() }
        await clock.settle()
        network.deviceManager.emitter.emit(.connected, mockDevice(ip: try Address4("192.168.1.2")))
        try await task.value
        try network.connect()
        let device = try #require(network.virtualDevice)
        #expect(device.type == .stagehand)
        #expect(device.name == "Stagehand")
        #expect((141...211).contains(device.id))
        var seen = 0
        network.statusEmitter?.on(.mixerState) { _ in seen += 1 }
        var packet = [UInt8].alloc(266)
        packet.set(PROLINK_HEADER, 0)
        packet[10] = 0x39
        factory.udpSockets[2].emitMessage(packet)
        #expect(seen == 1)
        let ready = Task { await network.startupReady }
        await clock.settle()
        clock.advance(ms: Double(STAGEHAND_STARTUP_INTERVAL * 7))
        await ready.value
        try network.disconnect()
        #expect(clock.pendingTimerCount == 0)
        try network.connect()
        #expect(network.virtualDevice?.id == device.id)
        try network.disconnect()
        try await network.close()
    }

    @Test("full startup readiness follows the injected clock and mixer status gating stays fixed at online time")
    func activeStartup() async throws {
        let factory = FakeSocketFactory()
        let clock = TestClock()
        let mocks = NetworkDatabaseMocks()
        let network = try await bringOnline(
            .init(iface: networkTestInterface, vcdjId: 7, fullStartup: true),
            socketFactory: factory, interfaceProvider: FakeInterfaceProvider(), clock: clock,
            dependencies: mocks.dependencies)
        network.configure(.init(connectMethod: .stagehand))
        try network.connect()
        var seen = 0
        network.statusEmitter?.on(.mixerState) { _ in seen += 1 }
        var packet = [UInt8].alloc(266)
        packet.set(PROLINK_HEADER, 0)
        packet[10] = 0x39
        factory.udpSockets[2].emitMessage(packet)
        #expect(seen == 0)
        try network.disconnect()
        network.configure(.init(connectMethod: .active))
        try network.connect()
        var ready = false
        let task = Task {
            await network.startupReady
            ready = true
        }
        await clock.settle()
        #expect(!ready)
        clock.advance(ms: 10_000)
        await task.value
        #expect(ready)
        try network.disconnect()
        try await network.close()
    }

    @Test("mixstatus subscribes once and survives reconnects like upstream")
    func mixstatusLifetime() async throws {
        let clock = TestClock()
        let network = try await bringOnline(
            .init(iface: networkTestInterface, vcdjId: 7), socketFactory: FakeSocketFactory(),
            interfaceProvider: FakeInterfaceProvider(), clock: clock,
            dependencies: NetworkDatabaseMocks().dependencies)
        try network.connect()
        let emitter = try #require(network.statusEmitter)
        let initialListeners = emitter.emitter.listenerCount(.status)
        let processor = try #require(network.mixstatus)
        #expect(network.mixstatus === processor)
        #expect(emitter.emitter.listenerCount(.status) == initialListeners + 1)
        try network.disconnect()
        try network.connect()
        #expect(network.mixstatus === processor)
        #expect(emitter.emitter.listenerCount(.status) == initialListeners + 1)
        try network.disconnect()
        try await network.close()
    }

    @Test("default database factories receive the shared device and fake socket factory")
    func liveDatabaseConstruction() async throws {
        let clock = TestClock()
        let factory = FakeSocketFactory()
        let network = try await bringOnline(
            .init(iface: networkTestInterface, vcdjId: 7), socketFactory: factory,
            interfaceProvider: FakeInterfaceProvider(), clock: clock)
        try network.connect()
        #expect(network.db is Database)
        #expect(network.localdb is LocalDatabase)
        #expect(network.remotedb is RemoteDatabase)
        let reference = try #require(network.connectionDeviceReference)
        reference.id = 9
        #expect(network.db?.hostDevice.id == 9)
        #expect(network.remotedb?.hostDevice.id == 9)
        let device = mockDevice()
        await #expect(throws: DJLinkError("FakeSocketFactory.makeTCPConnection is not set")) {
            try await network.remotedb?.connectToDevice(device)
        }
        try network.disconnect()
        try await network.close()
    }

    @Test("bind failure leaves sockets open and does not enable broadcast like upstream")
    func bindFailure() async throws {
        let sockets = [FakeUDPSocket(), FakeUDPSocket(), FakeUDPSocket()]
        let failure = DJLinkError("bind failed")
        sockets[1].bindError = failure
        let factory = NetworkFailingSocketFactory(sockets)
        await #expect(throws: failure) {
            try await bringOnline(
                socketFactory: factory, interfaceProvider: FakeInterfaceProvider(), clock: TestClock())
        }
        #expect(factory.reuseCalls == [true, true, true])
        #expect(sockets[0].bindCalls.count == 1)
        #expect(sockets[1].bindCalls.count == 1)
        #expect(sockets[2].bindCalls.isEmpty)
        #expect(sockets.allSatisfy { !$0.isClosed && $0.broadcastCalls.isEmpty })
    }
}

@DJLinkActor
private final class NetworkFailingSocketFactory: SocketFactory {
    let sockets: [FakeUDPSocket]
    var reuseCalls: [Bool] = []
    init(_ sockets: [FakeUDPSocket]) { self.sockets = sockets }
    func createUDPSocket(reuseAddr: Bool) throws -> any UDPSocket {
        let socket = sockets[reuseCalls.count]
        reuseCalls.append(reuseAddr)
        return socket
    }
    func createTCPConnection() throws -> any TCPConnection { throw DJLinkError("unused") }
}
