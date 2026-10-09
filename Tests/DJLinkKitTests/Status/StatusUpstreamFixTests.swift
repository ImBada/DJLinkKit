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
