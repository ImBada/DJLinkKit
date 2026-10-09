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
