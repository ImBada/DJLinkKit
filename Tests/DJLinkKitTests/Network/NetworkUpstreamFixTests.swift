import DJLinkKit
import DJLinkTestSupport
import Testing

@DJLinkActor
private final class CleanupSocket: UDPSocket {
    let socket = FakeUDPSocket()
    var closeError: (any Error)?
    var closeCount = 0

    func onMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        socket.onMessage(handler)
    }
    func onceMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        socket.onceMessage(handler)
    }
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) -> SocketListener {
        socket.onError(handler)
    }
    func onClose(_ handler: @escaping @DJLinkActor () -> Void) -> SocketListener {
        socket.onClose(handler)
    }
    func off(_ listener: SocketListener) { socket.off(listener) }
    func removeAllListeners() { socket.removeAllListeners() }
    func bind(port: Int?, address: String?) async throws -> AddressInfo {
        try await socket.bind(port: port, address: address)
    }
    func send(
        _ msg: [UInt8], port: Int, address: String,
        callback: (@DJLinkActor ((any Error)?, Int) -> Void)?
    ) {
        socket.send(msg, port: port, address: address, callback: callback)
    }
    func setBroadcast(_ flag: Bool) { socket.setBroadcast(flag) }
    func address() -> AddressInfo? { socket.address() }
    func close(_ callback: (@DJLinkActor () -> Void)?) throws {
        closeCount += 1
        if let closeError { throw closeError }
        socket.close(callback)
    }
}

@DJLinkActor
private final class CleanupSocketFactory: SocketFactory {
    let sockets = [CleanupSocket(), CleanupSocket(), CleanupSocket()]
    var createdCount = 0
    var creationFailureIndex: Int?
    let creationError = DJLinkError("create failed")

    func createUDPSocket(reuseAddr: Bool) throws -> any UDPSocket {
        #expect(reuseAddr)
        if createdCount == creationFailureIndex { throw creationError }
        defer { createdCount += 1 }
        return sockets[createdCount]
    }
    func createTCPConnection() throws -> any TCPConnection { throw DJLinkError("unused") }
}

@Suite("network 원본 버그 수정")
@DJLinkActor
struct NetworkUpstreamFixTests {
    private func online(_ factory: CleanupSocketFactory, stagehand: Bool) async throws -> ProlinkNetwork {
        if stagehand {
            return try await bringOnlineStagehand(
                socketFactory: factory, interfaceProvider: FakeInterfaceProvider(), clock: TestClock())
        }
        return try await bringOnline(
            socketFactory: factory, interfaceProvider: FakeInterfaceProvider(), clock: TestClock())
    }

    @Test("각 bind 실패에서 만든 세 소켓을 모두 닫는다", arguments: [0, 1, 2], [false, true])
    func closesSocketsOnBindFailure(_ failureIndex: Int, _ stagehand: Bool) async {
        let factory = CleanupSocketFactory()
        let failure = DJLinkError("bind failed")
        factory.sockets[failureIndex].socket.bindError = failure
        await #expect(throws: failure) { try await online(factory, stagehand: stagehand) }
        #expect(factory.createdCount == 3)
        #expect(factory.sockets.map(\.closeCount) == [1, 1, 1])
        #expect(factory.sockets.allSatisfy { $0.socket.isClosed && $0.socket.broadcastCalls.isEmpty })
        #expect(factory.sockets.map { $0.socket.bindCalls.count } == (0..<3).map { $0 <= failureIndex ? 1 : 0 })
    }

    @Test("닫기 하나가 실패해도 나머지를 닫고 원래 bind 오류를 던진다", arguments: [false, true])
    func preservesBindErrorDuringCleanup(_ stagehand: Bool) async {
        let factory = CleanupSocketFactory()
        let failure = DJLinkError("bind failed")
        factory.sockets[1].socket.bindError = failure
        factory.sockets[0].closeError = DJLinkError("close failed")
        await #expect(throws: failure) { try await online(factory, stagehand: stagehand) }
        #expect(factory.sockets.map(\.closeCount) == [1, 1, 1])
        #expect(factory.sockets[1].socket.isClosed)
        #expect(factory.sockets[2].socket.isClosed)
    }

    @Test("소켓 생성 도중 실패해도 앞서 만든 소켓을 닫는다", arguments: [1, 2], [false, true])
    func closesSocketsOnCreationFailure(_ failureIndex: Int, _ stagehand: Bool) async {
        let factory = CleanupSocketFactory()
        factory.creationFailureIndex = failureIndex
        await #expect(throws: factory.creationError) { try await online(factory, stagehand: stagehand) }
        #expect(factory.createdCount == failureIndex)
        #expect(factory.sockets.map(\.closeCount) == (0..<3).map { $0 < failureIndex ? 1 : 0 })
    }
}
