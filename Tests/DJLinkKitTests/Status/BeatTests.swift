import DJLinkKit
import DJLinkTestSupport
import Testing

// CDJ-2000nexus 두 대의 2026-10-14 실기 패킷. 곡 정보·주소는 들어 있지 않다.
private let capturedBeatPackets: [[UInt8]] = [
    "5173707431576d4a4f4c2843444a2d323030306e6578757300000000000000010001003c0000016a000002d3000005a6000005a600000b4c00000b4cffffffffffffffffffffffffffffffffffffffffffffffff000f9ba5000040d801000001",
    "5173707431576d4a4f4c2843444a2d323030306e6578757300000000000000010002003c00000165000002ca000005950000059500000b2900000b29ffffffffffffffffffffffffffffffffffffffffffffffff000ff9db000041a001000002",
].map { hex in
    stride(from: 0, to: hex.count, by: 2).map {
        let start = hex.index(hex.startIndex, offsetBy: $0)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
}

private func beatPositionPacket() -> [UInt8] {
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

private let beatOnAirPacket: [UInt8] = {
    let hex = "5173707431576d4a4f4c03444a4d2d3930304e5853320000000000000000000102210009000101000000000000"
    return stride(from: 0, to: hex.count, by: 2).map {
        let start = hex.index(hex.startIndex, offsetBy: $0)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
}()

@Suite("실기 비트 패킷 해석")
struct BeatPacketTests {
    @Test("두 CDJ의 BPM과 음수 pitch를 실기 값으로 읽는다", arguments: [0, 1])
    func capturedFields(_ index: Int) throws {
        let state = try #require(beatFromPacket(capturedBeatPackets[index]))
        let expectedPitch = [-2.450084686279297, -0.15001296997070312][index]
        let expectedBPM = [166.0, 168.0][index]
        #expect(state.deviceId == index + 1)
        #expect(state.trackBPM == expectedBPM)
        #expect(abs(state.pitch - expectedPitch) < 0.000000001)
        #expect(state.beatInMeasure == 1)
        #expect(abs(state.effectiveBPM - expectedBPM * (1 + expectedPitch / 100)) < 0.000000001)
    }

    @Test("한 마디의 1~4박을 모두 읽는다", arguments: [1, 2, 3, 4])
    func measureBeats(_ beat: Int) throws {
        var packet = capturedBeatPackets[0]
        packet[0x5c] = UInt8(beat)
        let state = try #require(beatFromPacket(packet))
        #expect(state.beatInMeasure == beat)
        #expect(state.deviceId == 1 && state.trackBPM == 166)
    }

    @Test("모든 잘린 패킷과 뒤에 바이트가 붙은 패킷을 안전하게 버린다")
    func rejectsPacketLengths() {
        let packet = capturedBeatPackets[0]
        for length in 0..<96 {
            #expect(beatFromPacket(Array(packet.prefix(length))) == nil)
        }
        #expect(beatFromPacket(packet + [0]) == nil)
    }

    @Test("틀린 머리말·종류·subtype·길이는 비트로 읽지 않는다")
    func rejectsEnvelope() {
        let original = capturedBeatPackets[0]
        for offset in PROLINK_HEADER.indices {
            var packet = original
            packet[offset] ^= 0xff
            #expect(beatFromPacket(packet) == nil)
        }
        for (offset, value) in [(0x0a, UInt8(0x0b)), (0x20, 1), (0x22, 1), (0x23, 0x3b)] {
            var packet = original
            packet[offset] = value
            #expect(beatFromPacket(packet) == nil)
        }
    }

    @Test("1~4 범위 밖의 박 번호는 버린다", arguments: [UInt8(0), 5, 255])
    func rejectsMeasureBeat(_ beat: UInt8) {
        var packet = capturedBeatPackets[0]
        packet[0x5c] = beat
        #expect(beatFromPacket(packet) == nil)
    }
}

@Suite("능동 비트 이벤트 연결과 종료")
@DJLinkActor
struct BeatEmitterTests {
    @Test("공유 비트 소켓에서 비트·위치·on-air를 구분하고 비트만 정지한다")
    func sharedSocket() {
        let socket = FakeUDPSocket()
        let beat = BeatEmitter(socket)
        let position = PositionEmitter(socket)
        let status = StatusEmitter(FakeUDPSocket(), beatSocket: socket, clock: TestClock())
        var beats: [CDJStatus.BeatState] = []
        var positions: [CDJStatus.PositionState] = []
        var onAir: [CDJStatus.OnAirStatus] = []
        beat.on(.beat) { beats.append($0) }
        position.on(.position) { positions.append($0) }
        status.on(.onAir) { onAir.append($0) }
        socket.emitMessage(capturedBeatPackets[0])
        socket.emitMessage(beatPositionPacket())
        socket.emitMessage(beatOnAirPacket)
        #expect(beats.count == 1 && beats.first?.deviceId == 1)
        #expect(positions.count == 1 && positions.first?.playhead == 90000)
        #expect(onAir.count == 1 && onAir.first?.channels == [1: false, 2: true, 3: true, 4: false])
        let listenersBeforeStop = socket.messageListenerCount
        beat.stop()
        beat.stop()
        #expect(socket.messageListenerCount == listenersBeforeStop - 1)
        socket.emitMessage(capturedBeatPackets[1])
        socket.emitMessage(beatPositionPacket())
        socket.emitMessage(beatOnAirPacket)
        #expect(beats.count == 1)
        #expect(positions.count == 2 && onAir.count == 2)
        #expect(!socket.isClosed && socket.sent.isEmpty)
    }

    @Test("잘못된 비트 뒤에도 같은 소켓의 다른 수신자와 정상 비트를 처리한다")
    func malformedDoesNotInterruptListeners() {
        let socket = FakeUDPSocket()
        let emitter = BeatEmitter(socket)
        var beats = 0
        var otherPackets = 0
        emitter.on(.beat) { _ in beats += 1 }
        socket.onMessage { _ in otherPackets += 1 }
        socket.emitMessage(Array(capturedBeatPackets[0].prefix(95)))
        socket.emitMessage(capturedBeatPackets[0])
        #expect(beats == 1 && otherPackets == 2)
        #expect(socket.sent.isEmpty)
        emitter.stop()
    }

    @Test("연결 뒤 공개되고 재연결 때 중복되지 않으며 close 뒤에는 수신하지 않는다")
    func networkLifecycle() async throws {
        let factory = FakeSocketFactory()
        let network = try await bringOnline(
            socketFactory: factory, interfaceProvider: FakeInterfaceProvider(), clock: TestClock(),
            dependencies: NetworkDatabaseMocks().dependencies)
        #expect(network.beatEmitter == nil)
        #expect(factory.udpSockets.count == 3)
        network.configure(.init(iface: networkTestInterface, vcdjId: 7))
        try network.connect()
        let emitter = try #require(network.beatEmitter)
        let socket = factory.udpSockets[1]
        var beats: [CDJStatus.BeatState] = []
        emitter.on(.beat) { beats.append($0) }
        socket.emitMessage(capturedBeatPackets[0])
        #expect(beats.count == 1)
        let initialListeners = socket.messageListenerCount
        _ = try network.disconnect()
        try network.connect()
        #expect(network.beatEmitter === emitter)
        #expect(socket.messageListenerCount == initialListeners)
        socket.emitMessage(capturedBeatPackets[1])
        #expect(beats.map(\.deviceId) == [1, 2])
        _ = try network.disconnect()
        try await network.close()
        socket.emitMessage(capturedBeatPackets[0])
        #expect(beats.count == 2)
        #expect(socket.messageListenerCount == initialListeners - 1)
        #expect(factory.udpSockets.allSatisfy { $0.isClosed })
    }

    @Test("기존 내부 생성자와 명시적 비트 emitter 주입이 단일 구독을 만든다", arguments: [false, true])
    func initializerCompatibility(_ inject: Bool) async throws {
        let announce = FakeUDPSocket()
        let beatSocket = FakeUDPSocket()
        let statusSocket = FakeUDPSocket()
        let clock = TestClock()
        let manager = DeviceManager(announce, clock: clock)
        let status = StatusEmitter(statusSocket, beatSocket: beatSocket, clock: clock)
        let position = PositionEmitter(beatSocket)
        let config = NetworkConfig(iface: networkTestInterface, vcdjId: 7)
        let network: ProlinkNetwork
        let injected: BeatEmitter?
        if inject {
            let emitter = BeatEmitter(beatSocket)
            injected = emitter
            network = ProlinkNetwork(
                config: config, announceSocket: announce, beatSocket: beatSocket, statusSocket: statusSocket,
                deviceManager: manager, statusEmitter: status, positionEmitter: position, beatEmitter: emitter,
                socketFactory: FakeSocketFactory(), clock: clock, dependencies: NetworkDatabaseMocks().dependencies)
        } else {
            injected = nil
            network = ProlinkNetwork(
                config: config, announceSocket: announce, beatSocket: beatSocket, statusSocket: statusSocket,
                deviceManager: manager, statusEmitter: status, positionEmitter: position,
                socketFactory: FakeSocketFactory(), clock: clock, dependencies: NetworkDatabaseMocks().dependencies)
        }
        try network.connect()
        let emitter = try #require(network.beatEmitter)
        if let injected { #expect(emitter === injected) }
        #expect(beatSocket.messageListenerCount == 3)
        var received = 0
        emitter.on(.beat) { _ in received += 1 }
        beatSocket.emitMessage(capturedBeatPackets[0])
        #expect(received == 1)
        _ = try network.disconnect()
        try await network.close()
    }
}
