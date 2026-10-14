import DJLinkKit
import DJLinkPassive
import DJLinkTestSupport
import Testing

// CDJ-2000nexus의 2026-10-14 실기 값만 사용하며 곡 정보·주소는 포함하지 않는다.
private let passiveCapturedBeats: [[UInt8]] = [
    "5173707431576d4a4f4c2843444a2d323030306e6578757300000000000000010001003c0000016a000002d3000005a6000005a600000b4c00000b4cffffffffffffffffffffffffffffffffffffffffffffffff000f9ba5000040d801000001",
    "5173707431576d4a4f4c2843444a2d323030306e6578757300000000000000010002003c00000165000002ca000005950000059500000b2900000b29ffffffffffffffffffffffffffffffffffffffffffffffff000ff9db000041a001000002",
].map { hex in
    stride(from: 0, to: hex.count, by: 2).map {
        let start = hex.index(hex.startIndex, offsetBy: $0)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
}

@DJLinkActor
private final class BeatPcapBackend: PcapBackend {
    var packetHandler: (@DJLinkActor ([UInt8], Bool) -> Void)?
    var openCount = 0
    var closeCount = 0
    func deviceList() throws -> [CapDeviceListEntry] { [] }
    func open(device: String, filter: String, bufSize: Int, bufferSize: Int) throws { openCount += 1 }
    func onPacket(_ handler: @escaping @DJLinkActor ([UInt8], Bool) -> Void) { packetHandler = handler }
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) {}
    func close() {
        closeCount += 1
        packetHandler = nil
    }
}

/// 가짜 Ethernet/IPv4/UDP 프레임. 실제 소켓이나 BPF를 열지 않는다.
private func passiveBeatFrame(_ payload: [UInt8], port: Int = BEAT_PORT) -> [UInt8] {
    var bytes = [UInt8].alloc(42)
    bytes.writeUInt16BE(0x0800, 12)
    bytes[14] = 0x45
    bytes.writeUInt16BE(28 + payload.count, 16)
    bytes[23] = 17
    bytes.writeUInt32BE(0x0a000001, 26)
    bytes.writeUInt32BE(0x0a000002, 30)
    bytes.writeUInt16BE(BEAT_PORT, 34)
    bytes.writeUInt16BE(port, 36)
    bytes.writeUInt16BE(payload.count + 8, 38)
    return bytes + payload
}

private func passiveBeatPositionPacket() -> [UInt8] {
    var packet = [UInt8].alloc(0x34)
    packet.set(PROLINK_HEADER, 0)
    packet[0x0a] = 0x0b
    packet[0x21] = 1
    packet.writeUInt16BE(0x0c, 0x22)
    packet.writeUInt32BE(180, 0x24)
    packet.writeUInt32BE(90000, 0x28)
    packet.writeUInt32BE(6400, 0x2c)
    packet.writeUInt32BE(1280, 0x30)
    return packet
}

@Suite("패시브 비트 이벤트 연결과 종료")
@DJLinkActor
struct PassiveBeatTests {
    @Test("두 실기 비트가 프레임 경로를 지나 능동 파서와 같은 상태로 나온다", arguments: [0, 1])
    func capturedPackets(_ index: Int) throws {
        let backend = BeatPcapBackend()
        let adapter = PcapAdapter(config: .init(iface: "en0", bufferSize: 2048), backend: backend)
        let emitter = PassiveBeatEmitter(adapter)
        var states: [CDJStatus.BeatState] = []
        emitter.on(.beat) { states.append($0) }
        try adapter.start()
        let packet = passiveCapturedBeats[index]
        backend.packetHandler?(passiveBeatFrame(packet), false)
        let expected = try #require(beatFromPacket(packet))
        #expect(states == [expected])
        #expect(states.first?.deviceId == index + 1)
        #expect(states.first?.trackBPM == [166.0, 168.0][index])
        // 같은 내용도 상태·announce 포트로 들어오면 비트 이벤트를 내지 않는다.
        backend.packetHandler?(passiveBeatFrame(packet, port: STATUS_PORT), false)
        backend.packetHandler?(passiveBeatFrame(packet, port: ANNOUNCE_PORT), false)
        #expect(states.count == 1)
        emitter.stop()
        adapter.stop()
    }

    @Test("잘못된 비트가 뒤 리스너를 막지 않고 stop은 자신의 구독만 해제한다")
    func malformedAndOwnStop() throws {
        let backend = BeatPcapBackend()
        let adapter = PcapAdapter(config: .init(iface: "en0", bufferSize: 2048), backend: backend)
        let emitter = PassiveBeatEmitter(adapter)
        var beats: [CDJStatus.BeatState] = []
        var errors = 0
        var laterPackets = 0
        emitter.on(.beat) { beats.append($0) }
        adapter.on(.error) { _ in errors += 1 }
        let laterSubscription = adapter.on(.beat) { _ in laterPackets += 1 }
        try adapter.start()
        let packet = passiveCapturedBeats[0]
        // 빈 UDP payload는 adapter가 버리므로, 전달 가능한 모든 짧은 길이를 확인한다.
        for length in 1..<96 {
            backend.packetHandler?(passiveBeatFrame(Array(packet.prefix(length))), false)
        }
        var invalidBeat = packet
        invalidBeat[0x5c] = 0
        backend.packetHandler?(passiveBeatFrame(invalidBeat), false)
        backend.packetHandler?(passiveBeatFrame(packet + [0]), false)
        #expect(beats.isEmpty && errors == 0 && laterPackets == 97)
        backend.packetHandler?(passiveBeatFrame(packet), false)
        #expect(beats.count == 1 && laterPackets == 98)
        let beforeStop = adapter.emitter.listenerCount(.beat)
        emitter.stop()
        emitter.stop()
        #expect(adapter.emitter.listenerCount(.beat) == beforeStop - 1)
        backend.packetHandler?(passiveBeatFrame(passiveCapturedBeats[1]), false)
        #expect(beats.count == 1 && laterPackets == 99 && errors == 0)
        #expect(adapter.isCapturing)
        adapter.off(laterSubscription)
        adapter.stop()
    }

    @Test("패시브 네트워크가 비트와 위치를 구분하고 stop에서 새 비트 구독을 정리한다")
    func networkIntegration() throws {
        let backend = BeatPcapBackend()
        let factory = FakeSocketFactory()
        let network = try bringOnlinePassive(
            .init(iface: "en0", bufferSize: 2048), backend: backend,
            socketFactory: factory, clock: TestClock())
        var beats: [CDJStatus.BeatState] = []
        var positions: [CDJStatus.PositionState] = []
        network.beatEmitter.on(.beat) { beats.append($0) }
        network.positionEmitter.on(.position) { positions.append($0) }
        backend.packetHandler?(passiveBeatFrame(passiveCapturedBeats[0]), false)
        backend.packetHandler?(passiveBeatFrame(passiveBeatPositionPacket()), false)
        #expect(beats.count == 1 && beats.first?.deviceId == 1)
        #expect(positions.count == 1 && positions.first?.playhead == 90000)
        network.stop()
        network.stop()
        #expect(!network.isCapturing && backend.closeCount == 1)
        #expect(network.adapter.emitter.listenerCount(.beat) == 0)
        let packet = passiveCapturedBeats[1]
        network.adapter.emitter.emit(.beat, .init(packet: packet, info: .init(payload: packet, srcAddr: "10.0.0.1")))
        #expect(beats.count == 1 && positions.count == 1)
        #expect(factory.udpSockets.isEmpty)
    }
}
