import DJLinkKit
import DJLinkTestSupport
import Testing

private func typedPositionPacket(_ type: UInt8) -> [UInt8] {
    var packet = [UInt8].alloc(0x40)
    packet.set(PROLINK_HEADER, 0)
    packet[0x0a] = type
    packet[0x21] = 3
    packet.writeUInt16BE(0x0038, 0x22)
    packet.writeUInt32BE(180, 0x24)
    packet.writeUInt32BE(45500, 0x28)
    packet.writeInt32BE(326 * 64, 0x2c)
    packet.writeUInt32BE(1202, 0x30)
    return packet
}

@Suite("위치 파서 원본 버그 수정")
struct StatusUpstreamFixTests {
    @Test("위치와 같은 subtype과 길이를 가진 다른 종류 패킷을 버린다", arguments: [UInt8(0x28), 0x00, 0x03, 0x58])
    func rejectsOtherPacketTypes(_ type: UInt8) throws {
        #expect(try positionFromPacket(typedPositionPacket(type)) == nil)
    }

    @Test("0x0b 위치 패킷의 필드를 읽는다")
    func parsesPositionPacket() throws {
        #expect(
            try positionFromPacket(typedPositionPacket(0x0b))
                == .init(deviceId: 3, trackLength: 180, playhead: 45500, pitch: 3.26, bpm: 120.2))
    }

    @Test("0x0b 위치 패킷의 BPM 미상과 음수 pitch와 시작 위치를 읽는다")
    func positionEdgeCases() throws {
        var packet = typedPositionPacket(0x0b)
        packet.writeUInt32BE(0, 0x28)
        packet.writeInt32BE(-200 * 64, 0x2c)
        packet.writeUInt32BE(0xffff_ffff, 0x30)
        let position = try #require(try positionFromPacket(packet))
        #expect(position.playhead == 0)
        #expect(position.pitch == -2)
        #expect(position.bpm == nil)
    }

    @Test("능동 위치 이벤트에서 비트 패킷을 제외한다")
    @DJLinkActor
    func activePositionEvents() {
        let socket = FakeUDPSocket()
        let emitter = PositionEmitter(socket)
        var positions: [CDJStatus.PositionState] = []
        emitter.on(.position) { positions.append($0) }
        socket.emitMessage(typedPositionPacket(0x28))
        #expect(positions.isEmpty)
        socket.emitMessage(typedPositionPacket(0x0b))
        #expect(positions.count == 1)
    }
}

/// DJM-900NXS2가 비트 포트(50001)로 보낸 실제 4채널 on-air 패킷(2026-10-14 실기, 45바이트). 채널 2·3이 on-air다.
private let DJM_900NXS2_ON_AIR: [UInt8] = {
    let hex = "5173707431576d4a4f4c03444a4d2d3930304e5853320000000000000000000102210009000101000000000000"
    return stride(from: 0, to: hex.count, by: 2).map {
        let start = hex.index(hex.startIndex, offsetBy: $0)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
}()

private func expectDJM900NXS2(_ onAir: CDJStatus.OnAirStatus?) {
    #expect(onAir?.deviceId == 33)
    #expect(onAir?.channels == [1: false, 2: true, 3: true, 4: false])
    #expect(onAir?.isSixChannel == false)
}

@Suite("on-air 원본 버그 수정")
@DJLinkActor
struct StatusOnAirUpstreamFixTests {
    @Test("DJM-900NXS2가 보내는 45바이트 4채널 on-air 패킷을 읽는다")
    func parsesDJM900NXS2Packet() throws {
        #expect(DJM_900NXS2_ON_AIR.count == 0x2d)
        expectDJM900NXS2(try onAirFromPacket(DJM_900NXS2_ON_AIR))
    }

    @Test("비트 포트로 온 on-air 패킷을 onAir로 낸다")
    func reportsOnAirFromBeatPort() {
        let beatSocket = FakeUDPSocket()
        let emitter = StatusEmitter(FakeUDPSocket(), beatSocket: beatSocket)
        var received: [CDJStatus.OnAirStatus] = []
        emitter.on(.onAir) { received.append($0) }
        beatSocket.emitMessage(DJM_900NXS2_ON_AIR)
        #expect(received.count == 1)
        expectDJM900NXS2(received.first)
    }

    @Test("비트 포트에서는 종류가 0x03이 아닌 패킷을 on-air로 읽지 않는다", arguments: [UInt8(0x28), 0x0b, 0x02, 0x06])
    func ignoresOtherTypesOnBeatPort(_ type: UInt8) {
        let beatSocket = FakeUDPSocket()
        let emitter = StatusEmitter(FakeUDPSocket(), beatSocket: beatSocket)
        var received = 0
        emitter.on(.onAir) { _ in received += 1 }
        var packet = DJM_900NXS2_ON_AIR
        packet[0x0a] = type
        beatSocket.emitMessage(packet)
        #expect(received == 0)
    }

    @Test("bringOnline은 비트 소켓으로 온 on-air 패킷도 상태 이벤트로 낸다")
    func bringOnlineListensOnBeatSocket() async throws {
        let factory = FakeSocketFactory()
        let network = try await bringOnline(
            socketFactory: factory, interfaceProvider: FakeInterfaceProvider(), clock: TestClock())
        network.configure(
            .init(
                iface: NetworkInterfaceInfo(
                    address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
                    mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24"),
                vcdjId: 7))
        try network.connect()
        let statusEmitter = try #require(network.statusEmitter)
        var received: [CDJStatus.OnAirStatus] = []
        statusEmitter.on(.onAir) { received.append($0) }
        // bringOnline이 만드는 소켓 순서는 announce, beat, status다.
        factory.udpSockets[1].emitMessage(DJM_900NXS2_ON_AIR)
        #expect(received.count == 1)
        expectDJM900NXS2(received.first)
        try await network.close()
    }
}
