import DJLinkKit
import DJLinkTestSupport
import Testing

@DJLinkActor
private final class FakePlayer: RemoteDBDeviceSource {
    let device = mockDevice(ip: try! Address4("127.0.0.1"))
    var devices: [DeviceID: Device] { [device.id: device] }
    let factory = FakeSocketFactory()
    var connections: [FakeTCPConnection] = []
    var received: [[[UInt8]]] = []
    init() {
        factory.makeTCPConnection = { [unowned self] in
            let socket = FakeTCPConnection()
            socket.onConnect = { port, _ in
                if port == 0 {
                    socket.onWrite = { _ in
                        socket.inject([0x12, 0x34])
                        socket.end()
                    }
                } else {
                    let index = self.connections.count
                    self.connections.append(socket)
                    self.received.append([])
                    var step = 0
                    socket.onWrite = { data in
                        defer { step += 1 }
                        switch step {
                        case 0: socket.inject(RemoteDBUInt32(0x01).buffer)
                        case 1:
                            socket.inject(
                                Message(
                                    transactionId: 0xfffffffe, type: .success,
                                    args: [RemoteDBUInt32(0), RemoteDBUInt32(0)]
                                ).buffer)
                        default: self.received[index].append(data)
                        }
                    }
                }
            }
            return socket
        }
    }
    func hangUp() { connections.filter(\.isOpen).forEach { $0.end() } }
    func database() -> RemoteDatabase {
        RemoteDatabase(deviceManager: self, hostDevice: mockDevice(id: 5), socketFactory: factory, serverQueryPort: 0)
    }
}

@Suite("RemoteDatabase connections") @DJLinkActor
struct RemoteDBConnectionTests {
    func goodbye(_ transactionId: Int) -> [UInt8] {
        Message(transactionId: transactionId, type: .disconnect, args: []).buffer
    }
    @Test("reuses the connection to a player while it stays open") func reuses() async throws {
        let player = FakePlayer()
        let remotedb = player.database()
        _ = try await remotedb.get(player.device.id)
        _ = try await remotedb.get(player.device.id)
        #expect(player.connections.count == 1)
    }
    @Test("opens a new connection once the player has closed the old one") func reconnects() async throws {
        let player = FakePlayer()
        let remotedb = player.database()
        _ = try await remotedb.get(player.device.id)
        player.hangUp()
        _ = try await remotedb.get(player.device.id)
        #expect(player.connections.count == 2)
        await remotedb.disconnectFromDevice(player.device)
        #expect(!player.connections[1].isOpen)
        #expect(player.received[1].flatMap { $0 } == goodbye(1))
    }
    @Test("disconnects from a player that has already closed the connection") func disconnectsClosed() async throws {
        let player = FakePlayer()
        let remotedb = player.database()
        _ = try await remotedb.get(player.device.id)
        player.hangUp()
        await remotedb.disconnectFromDevice(player.device)
        _ = try await remotedb.get(player.device.id)
        #expect(player.connections.count == 2)
    }
    @Test("says goodbye to a player before closing the connection") func goodbyeBeforeClosing() async throws {
        let player = FakePlayer()
        let remotedb = player.database()
        _ = try await remotedb.get(player.device.id)
        await remotedb.disconnectFromDevice(player.device)
        #expect(!player.connections[0].isOpen)
        #expect(player.received[0].flatMap { $0 } == goodbye(1))
    }
}
