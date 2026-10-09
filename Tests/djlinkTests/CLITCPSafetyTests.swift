import DJLinkKit
import DJLinkTestSupport
import Testing

@testable import djlink

@Suite("CLI TCP interface requirement")
@DJLinkActor
struct CLITCPSafetyTests {
    @Test("both port query and DB connections require the selected interface")
    func bothConnections() async throws {
        let factory = FakeSocketFactory()
        var connections: [FakeTCPConnection] = []
        factory.makeTCPConnection = {
            let connection = FakeTCPConnection()
            connections.append(connection)
            return connection
        }
        let registry = CLISocketRegistry(inner: factory, abort: CLIAbort())
        try registry.bindInterface(name: "en7")
        registry.scope = try CLINetworkScope(name: "en7", info: networkInterface("192.168.1.100"))
        for port in [12523, 1051] {
            let connection = try registry.createTCPConnection()
            try await connection.connect(port: port, host: "192.168.1.20")
        }
        #expect(connections.count == 2)
        #expect(connections.allSatisfy { $0.requiredInterfaces == ["en7"] })
        await registry.closeAll()
    }

    @Test("an unresolved interface prevents connect")
    func missingInterface() async throws {
        let factory = FakeSocketFactory()
        let tcp = FakeTCPConnection()
        tcp.interfaceError = DJLinkError("Network interface not found")
        factory.makeTCPConnection = { tcp }
        let registry = CLISocketRegistry(inner: factory, abort: CLIAbort())
        try registry.bindInterface(name: "missing")
        #expect(throws: DJLinkError.self) { _ = try registry.createTCPConnection() }
        #expect(tcp.connectCalls.isEmpty)
        await registry.closeAll()
    }
}
