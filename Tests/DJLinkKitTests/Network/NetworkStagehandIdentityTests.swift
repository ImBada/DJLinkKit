import DJLinkKit
import DJLinkTestSupport
import Testing

@Suite("Stagehand identity across reconnects")
@DJLinkActor
struct NetworkStagehandIdentityTests {
    private func makeNetwork() -> (ProlinkNetwork, FakeUDPSocket, TestClock) {
        let announceSocket = FakeUDPSocket()
        let beatSocket = FakeUDPSocket()
        let statusSocket = FakeUDPSocket()
        let clock = TestClock()
        let mocks = NetworkDatabaseMocks()
        let network = ProlinkNetwork(
            config: .init(iface: networkTestInterface, connectMethod: .stagehand),
            announceSocket: announceSocket, beatSocket: beatSocket, statusSocket: statusSocket,
            deviceManager: DeviceManager(announceSocket, clock: clock),
            statusEmitter: StatusEmitter(statusSocket, stagehandMode: true, clock: clock),
            positionEmitter: PositionEmitter(beatSocket, stagehandMode: true),
            socketFactory: FakeSocketFactory(), interfaceProvider: FakeInterfaceProvider(),
            clock: clock, dependencies: mocks.dependencies)
        return (network, announceSocket, clock)
    }

    private func sentOfType(_ socket: FakeUDPSocket, _ type: UInt8) -> [[UInt8]] {
        socket.sent.map(\.message).filter { $0[10] == type }
    }

    @Test("claims with a MAC derived from the interface, not a random one")
    func interfaceMAC() throws {
        let (network, announceSocket, clock) = makeNetwork()
        try network.connect()
        clock.advance(ms: Double(STAGEHAND_STARTUP_INTERVAL * 4))
        let claim = try #require(sentOfType(announceSocket, 0x02).first)
        #expect(claim.subarray(40, 46) == getStagehandMac(networkTestInterface))
        try network.disconnect()
    }

    @Test("keeps the same device number and MAC after disconnect/connect")
    func reconnectIdentity() throws {
        let (network, announceSocket, clock) = makeNetwork()
        try network.connect()
        clock.advance(ms: Double(STAGEHAND_STARTUP_INTERVAL * 7))
        let firstKeepAlive = try #require(sentOfType(announceSocket, 0x06).first)
        try network.disconnect()
        announceSocket.clearSent()
        try network.connect()
        clock.advance(ms: Double(STAGEHAND_STARTUP_INTERVAL * 7))
        let secondKeepAlive = try #require(sentOfType(announceSocket, 0x06).first)
        try network.disconnect()
        #expect(secondKeepAlive[36] == firstKeepAlive[36])
        #expect(secondKeepAlive.subarray(38, 44) == firstKeepAlive.subarray(38, 44))
    }
}
