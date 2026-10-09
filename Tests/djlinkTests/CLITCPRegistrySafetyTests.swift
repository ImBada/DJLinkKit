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

    /// 가짜 TCP로 remotedb 인사까지 끝낸다. 이름 소개(introduce) 메시지를 `introductions`에 모은다.
    private func connectRemoteDB(
        _ h: CLIHarness, session: CLISession, network: ProlinkNetwork, host: Device, target: Device
    ) async throws -> [[UInt8]] {
        let port = FakeTCPConnection(clock: h.clock)
        port.onWrite = { _ in port.inject([0x04, 0x1b]) }
        let database = FakeTCPConnection(clock: h.clock)
        var introductions: [[UInt8]] = []
        var writes = 0
        database.onWrite = { data in
            if writes == 0 {
                database.inject(RemoteDBUInt32(1).buffer)
            } else if writes == 1 {
                introductions.append(data)
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
        let remote = session.guardedNetworkDependencies().makeRemoteDatabase(
            network.deviceManager, DeviceReference(host), session.sockets)
        let db = try #require(remote as? RemoteDatabase)
        try await db.connectToDevice(target)
        return introductions
    }

    @Test("a virtual CDJ above the player range logs the query number it puts in remotedb messages")
    func logsQueryNumber() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let target = try cdj(2, "192.168.1.20")
        let network = try await session.openNetwork(options: CLICommonOptions(iface: "en7"))
        let introductions = try await connectRemoteDB(
            h, session: session, network: network, host: mockDevice(id: 7), target: target)
        // 원본 동작: 다른 CDJ가 없으면 대상이 아닌 1~6 중 가장 작은 번호(1)를 쓴다.
        #expect(introductions.count == 1)
        #expect(introductions[0].last == 1, "remotedb 메시지의 장치 번호 칸")
        let lines = h.output.lines.filter { $0.contains("remotedb 질의 번호") }
        #expect(lines.count == 1)
        #expect(lines.first?.contains("1번") == true)
        #expect(lines.first?.contains("announce 번호 7번") == true)
        await session.cleanup()
    }

    @Test("the logged query number follows the original choice when another CDJ is on the network")
    func logsOtherPlayerNumber() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let target = try cdj(2, "192.168.1.20")
        let network = try await session.openNetwork(options: CLICommonOptions(iface: "en7"))
        try h.announce(try cdj(3, "192.168.1.21"))
        await h.settle()
        #expect(network.deviceManager.devices[3] != nil)
        _ = try await connectRemoteDB(h, session: session, network: network, host: mockDevice(id: 7), target: target)
        let lines = h.output.lines.filter { $0.contains("remotedb 질의 번호") }
        #expect(lines.count == 1)
        #expect(lines.first?.contains("3번") == true)
        await session.cleanup()
    }
}
