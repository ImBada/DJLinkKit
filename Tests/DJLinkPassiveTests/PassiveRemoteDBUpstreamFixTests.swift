import DJLinkKit
import DJLinkPassive
import DJLinkTestSupport
import Testing

// PLAN §9: 패시브 remotedb도 능동과 같은 연결(`Connection`)을 쓰므로 #46·#47 고침이 같이 적용되는지 본다.
// 시험용 바이트는 코드로 만든 것과, 2026-10-16 실기(CDJ-2000nexus)에서 CDJ가 먼저 보낸 54바이트(이슈 #46)뿐이다.

private let UNSOLICITED_MESSAGE: [UInt8] = hexBytes(
    """
    11 87 23 49 ae 11 03 80 01 22 10 4b 02 0f 04 14 00 00 00 0c 06 06 06 02 00 00 00 00 00 00 00 00
    11 00 00 3e 03 11 00 00 00 00 11 00 00 00 02 26 00 00 00 01 00 00
    """)

private func hexBytes(_ text: String) -> [UInt8] {
    text.split(whereSeparator: \.isWhitespace).map { UInt8($0, radix: 16)! }
}

private func announce(_ id: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 46)
    bytes.replaceSubrange(0..<10, with: PROLINK_HEADER)
    bytes[10] = 6
    let encoded = Array("CDJ-test".utf8)
    bytes.replaceSubrange(12..<(12 + encoded.count), with: encoded)
    bytes[0x24] = UInt8(id)
    bytes.replaceSubrange(0x26..<0x2c, with: [1, 2, 3, 4, 5, 6])
    return bytes
}

@DJLinkActor
private func artworkResponse(_ transactionId: Int, _ bytes: [UInt8]) -> [UInt8] {
    Message(
        transactionId: transactionId, type: .artwork,
        args: [RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(bytes.count), RemoteDBBinary(bytes)]
    ).buffer
}

@Suite("패시브 remotedb 원본 버그 수정") @DJLinkActor
struct PassiveRemoteDBUpstreamFixTests {
    @Test("소개 응답과 질의 응답 앞에 CDJ가 먼저 보낸 메시지가 있어도 건너뛰고 자기 번호의 응답을 읽는다(#46)")
    func skipsUnsolicitedMessages() async throws {
        let adapter = PcapAdapter(
            config: .init(iface: "en0"), backendFactory: { throw DJLinkError("시험에서 pcap을 열지 않는다") })
        let manager = PassiveDeviceManager(adapter)
        let device = mockDevice()
        adapter.emitter.emit(
            .announce, .init(packet: announce(1), info: .init(payload: [], srcAddr: device.ip.address)))
        let factory = FakeSocketFactory()
        let port = FakeTCPConnection()
        port.inject([0x12, 0x34])
        let socket = FakeTCPConnection()
        var step = 0
        socket.onWrite = { data in
            defer { step += 1 }
            switch step {
            case 0: socket.inject(RemoteDBUInt32(1).buffer)
            case 1:
                socket.inject(
                    UNSOLICITED_MESSAGE
                        + Message(
                            transactionId: 0xfffffffe, type: .success, args: [RemoteDBUInt32(0), RemoteDBUInt32(0)]
                        )
                        .buffer)
            default:
                // 첫 질의의 트랜잭션 번호는 1이다. 요청의 번호(0x11 매직 0x11 번호)를 그대로 되돌려 보낸다.
                let transaction = try data.readUInt32BE(6)
                socket.inject(UNSOLICITED_MESSAGE + artworkResponse(transaction, [7, 8]))
            }
        }
        var next = 0
        factory.makeTCPConnection = {
            defer { next += 1 }
            return next == 0 ? port : socket
        }
        let remote = PassiveRemoteDatabase(manager, socketFactory: factory)
        let query = try #require(try await remote.get(1))
        let result = try await query.query(
            queryDescriptor: QueryDescriptor(menuTarget: .main, trackSlot: .usb, trackType: .rb), query: .getArtwork,
            args: RemoteDBQueryArgs(artworkId: 9))
        #expect(result == .artwork([7, 8]))
        manager.stop()
        remote.stop()
    }

    @Test("질의 시간 제한 등으로 닫힌 연결은 다음 get()에서 버리고 새로 연결한다(#47)")
    func reconnectsAfterClosedConnection() async throws {
        let adapter = PcapAdapter(
            config: .init(iface: "en0"), backendFactory: { throw DJLinkError("시험에서 pcap을 열지 않는다") })
        let manager = PassiveDeviceManager(adapter)
        let device = mockDevice()
        adapter.emitter.emit(
            .announce, .init(packet: announce(1), info: .init(payload: [], srcAddr: device.ip.address)))
        let factory = FakeSocketFactory()
        var sockets: [FakeTCPConnection] = []
        factory.makeTCPConnection = {
            let socket = FakeTCPConnection()
            if sockets.count % 2 == 0 {
                // 질의 포트 연결: 데이터베이스 포트를 알려 준다.
                socket.inject([0x12, 0x34])
            } else {
                var step = 0
                socket.onWrite = { _ in
                    defer { step += 1 }
                    if step == 0 { socket.inject(RemoteDBUInt32(1).buffer) }
                    if step == 1 {
                        socket.inject(
                            Message(
                                transactionId: 0xfffffffe, type: .success,
                                args: [RemoteDBUInt32(0), RemoteDBUInt32(0)]
                            ).buffer)
                    }
                }
            }
            sockets.append(socket)
            return socket
        }
        let remote = PassiveRemoteDatabase(manager, socketFactory: factory)
        _ = try #require(try await remote.get(1))
        #expect(sockets.count == 2)
        // 시간 제한이 연결을 닫은 것처럼 데이터베이스 연결을 닫는다.
        sockets[1].destroy(DJLinkError("RemoteDB query to 10.0.0.1 timed out"))
        _ = try #require(try await remote.get(1))
        #expect(sockets.count == 4)
        #expect(sockets[3].isOpen)
        manager.stop()
        remote.stop()
    }
}
