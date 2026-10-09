import DJLinkKit
import DJLinkTestSupport
import Testing

@testable import djlink

@Suite("CLI destination boundary")
@DJLinkActor
struct CLIDestinationSafetyTests {
    @Test("out of scope UDP destinations send zero bytes and TCP never connects")
    func outsideDestinations() async throws {
        let factory = FakeSocketFactory()
        let tcp = FakeTCPConnection()
        factory.makeTCPConnection = { tcp }
        let registry = CLISocketRegistry(inner: factory, abort: CLIAbort())
        registry.scope = try CLINetworkScope(name: "en7", info: networkInterface("192.168.1.100"))
        let udp = try registry.createUDPSocket(reuseAddr: false)
        let connection = try registry.createTCPConnection()
        for address in ["10.0.0.1", "255.255.255.255", "example.com", "192.168.1.20/24", "::1"] {
            await #expect(throws: CLIRuntimeError.self) { try await udpSend(udp, [1, 2], 50000, address) }
            await #expect(throws: CLIRuntimeError.self) { try await connection.connect(port: 12523, host: address) }
        }
        #expect(factory.udpSockets[0].sent.isEmpty)
        #expect(tcp.connectCalls.isEmpty)
        try await udpSend(udp, [1], 50000, "192.168.1.255")
        #expect(factory.udpSockets[0].sent.count == 1)
        await registry.closeAll()
    }

    @Test("unselected scope cannot send")
    func noScope() async throws {
        let factory = FakeSocketFactory()
        let registry = CLISocketRegistry(inner: factory, abort: CLIAbort())
        let udp = try registry.createUDPSocket(reuseAddr: false)
        await #expect(throws: CLIRuntimeError.self) { try await udpSend(udp, [1], 111, "192.168.1.20") }
        #expect(factory.udpSockets[0].sent.isEmpty)
        await registry.closeAll()
    }

    @Test("NFS rejects an outside device before the fake reader is called")
    func nfsDeviceGuard() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        try session.lock(session.resolveScope(named: "en7"))
        let device = try cdj(1, "10.0.0.1")
        await #expect(throws: CLIRuntimeError.self) {
            _ = try await session.guardedDBDependencies().fetchFile(device, .usb, "Contents/example.mp3", nil, nil)
        }
        #expect(h.nfs.requestCount == 0)
        await session.cleanup()
    }
}
