import DJLinkKit
import DJLinkTestSupport
import Testing

@testable import djlink

@Suite("CLI TCP ownership cleanup")
@DJLinkActor
struct CLITCPRegistrySafetyTests {
    @Test("destroy and remote FIN remove TCP connections immediately")
    func removedWhenClosed() async throws {
        let factory = FakeSocketFactory()
        let tcp = FakeTCPConnection()
        factory.makeTCPConnection = { tcp }
        let registry = CLISocketRegistry(inner: factory, abort: CLIAbort())
        let connection = try registry.createTCPConnection()
        #expect(registry.openTCPConnectionCount == 1)
        connection.destroy(nil)
        #expect(registry.openTCPConnectionCount == 0)
        let remote = FakeTCPConnection()
        factory.makeTCPConnection = { remote }
        _ = try registry.createTCPConnection()
        #expect(registry.openTCPConnectionCount == 1)
        remote.end()
        #expect(registry.openTCPConnectionCount == 0)
    }

    @Test("a real remotedb handshake through fake sockets binds both connections and closes the port query first")
    func handshakeBound() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let network = try await session.openNetwork(options: CLICommonOptions(iface: "en7"))
        let port = FakeTCPConnection(clock: h.clock)
        port.onWrite = { _ in port.inject([0x04, 0x1b]) }
        let database = FakeTCPConnection(clock: h.clock)
        var writes = 0
        database.onConnect = { _, _ in #expect(!port.isOpen) }
        database.onWrite = { _ in
            if writes == 0 {
                database.inject(RemoteDBUInt32(1).buffer)
            } else if writes == 1 {
                database.inject(
                    Message(
                        transactionId: 0xfffffffe, type: .success,
                        args: [RemoteDBUInt32(0), RemoteDBUInt32(0)]
                    ).buffer)
            }
            writes += 1
        }
        var count = 0
        h.fakeFactory.makeTCPConnection = {
            defer { count += 1 }
            return count == 0 ? port : database
        }
        let db = RemoteDatabase(
            deviceManager: network.deviceManager, hostDevice: mockDevice(id: 7), socketFactory: session.sockets,
            closesPortQueryConnection: true)
        try await db.connectToDevice(cdj(1, "192.168.1.20"))
        #expect(port.requiredInterfaces == ["en7"])
        #expect(database.requiredInterfaces == ["en7"])
        #expect(session.sockets.openTCPConnectionCount == 1)
        await session.cleanup()
        #expect(session.sockets.openTCPConnectionCount == 0)
    }

    @Test("port query closes after a response even if that response is invalid")
    func portQueryClosed() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let network = try await session.openNetwork(options: CLICommonOptions(iface: "en7"))
        let tcp = FakeTCPConnection()
        tcp.inject([0])
        h.fakeFactory.makeTCPConnection = { tcp }
        let db = RemoteDatabase(
            deviceManager: network.deviceManager, hostDevice: mockDevice(id: 7), socketFactory: session.sockets,
            closesPortQueryConnection: true)
        await #expect(throws: DJLinkError("Expected 2 bytes, got 1")) {
            try await db.connectToDevice(cdj(1, "192.168.1.20"))
        }
        #expect(!tcp.isOpen)
        #expect(session.sockets.openTCPConnectionCount == 0)
        await session.cleanup()
    }
}
