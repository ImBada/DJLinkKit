import DJLinkKit
import DJLinkTestSupport
import Testing

@testable import djlink

@Suite("CLI NFS pending read cleanup")
@DJLinkActor
struct CLINFSWaitingSafetyTests {
    @Test("closing during RPC read fails the call and removes subscriptions and timers")
    func closePendingRPC() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        try session.lock(session.resolveScope(named: "en7"))
        let conn = try RpcConnection(address: "192.168.1.20", socketFactory: session.sockets, clock: h.clock)
        let call = Task { try await conn.call(port: 111, program: 1, version: 1, procedure: 1, data: []) }
        await h.clock.waitForTimers(atLeast: 1)
        let socket = h.fakeFactory.udpSockets[0]
        #expect(socket.messageListenerCount == 1)
        await session.sockets.closeAll()
        await #expect(throws: SocketNotRunningError.self) { _ = try await call.value }
        #expect(socket.messageListenerCount == 0)
        #expect(h.clock.pendingTimerCount == 0)
    }

    @Test("cancelling an RPC read removes every pending listener and timer")
    func cancelRead() async throws {
        let socket = FakeUDPSocket()
        let clock = TestClock()
        let read = Task { try await udpReadCancellable(socket, clock: clock, duration: .seconds(10)) }
        await clock.waitForTimers(atLeast: 1)
        read.cancel()
        await #expect(throws: CancellationError.self) { _ = try await read.value }
        #expect(socket.messageListenerCount == 0)
        #expect(clock.pendingTimerCount == 0)
        #expect(Set(socket.offEvents) == ["message", "error", "close"])
    }

    @Test("RPC retry backoff is also released by close")
    func closeDuringBackoff() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        try session.lock(session.resolveScope(named: "en7"))
        let conn = try RpcConnection(
            address: "192.168.1.20", retryConfig: RetryConfig(minTimeout: 5000, transactionTimeout: 100),
            socketFactory: session.sockets, clock: h.clock)
        let call = Task { try await conn.call(port: 111, program: 1, version: 1, procedure: 1, data: []) }
        await h.clock.waitForTimers(atLeast: 1)
        h.clock.advance(ms: 100)
        await h.settle()
        #expect(h.clock.pendingTimerCount == 1)
        await session.sockets.closeAll()
        await #expect(throws: SocketNotRunningError.self) { _ = try await call.value }
        #expect(h.clock.pendingTimerCount == 0)
        #expect(h.fakeFactory.udpSockets[0].sent.count == 1)
    }
}
