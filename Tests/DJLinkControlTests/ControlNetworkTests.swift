import DJLinkControl
import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 대응이 아닌 별도 Control 타깃 연결 시험.
@Suite("ProlinkNetwork Control extension")
@DJLinkActor
struct ControlNetworkTests {
    private let iface = NetworkInterfaceInfo(
        address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
        mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24")

    @Test("Control requires a connection and sends load commands from the status socket")
    func controlSockets() async throws {
        let factory = FakeSocketFactory()
        let clock = TestClock()
        let network = try await bringOnline(
            socketFactory: factory, interfaceProvider: FakeInterfaceProvider(), clock: clock)
        #expect(network.control == nil)
        network.configure(.init(iface: iface, vcdjId: 7))
        #expect(network.control == nil)
        try network.connect()
        let control = try #require(network.control)
        #expect(network.control === control)
        let reference = try #require(network.connectionDeviceReference)
        // Announcer가 실제 충돌 패킷을 받아 번호를 옮겨도 같은 참조를 쥔 DB와 Control이 따라간다.
        network.deviceManager.devices[7] = mockDevice(id: 7, ip: try Address4("192.168.1.7"))
        var conflict = [UInt8].alloc(0x29)
        conflict.set(PROLINK_HEADER, 0)
        conflict[10] = 0x08
        conflict[0x24] = 7
        factory.udpSockets[0].emitMessage(conflict)
        #expect(reference.id == 8)
        #expect(network.virtualDevice?.id == 8)
        #expect(network.db?.hostDevice.id == 8)
        #expect(network.remotedb?.hostDevice.id == 8)
        let device = mockDevice(ip: try Address4("192.168.1.2"))
        try await control.loadTrack(device, 0x12345678, .init(deviceId: 2, slot: .usb))
        let statusPacket = try #require(factory.udpSockets[2].sent.last)
        #expect(statusPacket.port == STATUS_PORT)
        #expect(statusPacket.address == "192.168.1.2")
        #expect(statusPacket.message[10] == 0x19)
        #expect(statusPacket.message[33] == 8)
        #expect(factory.udpSockets[1].sent.isEmpty)
        try await control.setPlayState(device, .playing)
        let beatPacket = try #require(factory.udpSockets[1].sent.last)
        #expect(beatPacket.port == BEAT_PORT)
        #expect(beatPacket.message[33] == 8)
        try network.disconnect()
        #expect(network.control === control)
        try await network.close()
        #expect(network.control === control)
    }

    @Test("reconnect creates a new Control while retaining the announced Stagehand identity")
    func reconnectControl() async throws {
        let factory = FakeSocketFactory()
        let clock = TestClock()
        let network = try await bringOnlineStagehand(
            .init(iface: iface), socketFactory: factory, interfaceProvider: FakeInterfaceProvider(), clock: clock)
        try network.connect()
        let firstControl = try #require(network.control)
        let firstDevice = network.virtualDevice
        try network.disconnect()
        #expect(network.control === firstControl)
        try network.connect()
        let secondControl = try #require(network.control)
        #expect(firstControl !== secondControl)
        #expect(network.virtualDevice == firstDevice)
        let device = mockDevice(ip: try Address4("192.168.1.2"))
        try await secondControl.play(device)
        #expect(factory.udpSockets[1].sent.count == 2)
        #expect(factory.udpSockets[1].sent.allSatisfy { $0.message[10] == 0x07 && $0.port == BEAT_PORT })
        try network.disconnect()
        try await network.close()
    }
}
