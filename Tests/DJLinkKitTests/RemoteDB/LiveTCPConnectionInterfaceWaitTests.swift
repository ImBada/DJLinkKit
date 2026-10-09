import Testing

@testable import DJLinkKit

// 원본 시험 대응이 아니다(CLI 안전을 위한 추가). 소켓을 열지 않는다: 경로 감시를 시작하지 않고 대기 상태만 만든다.
@Suite("LiveTCPConnectionInterfaceWait") @DJLinkActor
struct LiveTCPConnectionInterfaceWaitTests {
    private func startConnect(_ client: LiveTCPConnection) async -> Task<Void, any Error> {
        client.startsPathMonitor = false
        try? client.setRequiredInterface(name: "djlink-test-interface")
        let connect = Task { @DJLinkActor in try await client.connect(port: 12345, host: "192.0.2.1") }
        for _ in 0..<1000 where !client.isResolvingInterface { await Task.yield() }
        return connect
    }

    @Test("destroy releases the interface lookup immediately instead of waiting for its 3 second timer")
    func destroyReleasesLookup() async throws {
        let client = LiveTCPConnection()
        let connect = await startConnect(client)
        #expect(client.isResolvingInterface)
        let started = ContinuousClock.now
        client.destroy(DJLinkError("closed by test"))
        #expect(!client.isResolvingInterface)
        await #expect(throws: DJLinkError("closed by test")) { try await connect.value }
        #expect(ContinuousClock.now - started < .seconds(1))
        #expect(!client.isOpen)
    }

    @Test("destroy without an error reports a closed socket")
    func destroyWithoutError() async throws {
        let client = LiveTCPConnection()
        let connect = await startConnect(client)
        client.destroy(nil)
        await #expect(throws: DJLinkError("Socket closed")) { try await connect.value }
    }

    @Test("a connection destroyed before connecting never starts an interface lookup")
    func destroyedBeforeConnect() async throws {
        let client = LiveTCPConnection()
        client.startsPathMonitor = false
        try client.setRequiredInterface(name: "djlink-test-interface")
        client.destroy(nil)
        await #expect(throws: DJLinkError("Socket closed")) {
            try await client.connect(port: 12345, host: "192.0.2.1")
        }
        #expect(!client.isResolvingInterface)
    }
}
