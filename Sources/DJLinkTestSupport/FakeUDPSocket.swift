import DJLinkKit

/// 시험용 UDP 소켓. 보낸 바이트를 기록하고, 받은 패킷은 `emitMessage`로 넣는다.
/// 원본 시험의 `new EventEmitter() as Socket`이나 `{send: jest.fn(), on: jest.fn(), off: jest.fn()}`를 대신한다.
@DJLinkActor
public final class FakeUDPSocket: UDPSocket {
    /// `send`로 보낸 것 하나.
    public struct Sent: Equatable, Sendable {
        public var message: [UInt8]
        public var port: Int
        public var address: String

        public init(message: [UInt8], port: Int, address: String) {
            self.message = message
            self.port = port
            self.address = address
        }
    }

    private enum Handler {
        case message(@DJLinkActor ([UInt8], RemoteInfo) -> Void, once: Bool)
        case error(@DJLinkActor (any Error) -> Void)
        case close(@DJLinkActor () -> Void)
    }

    private var handlers: [(id: UInt64, handler: Handler)] = []
    private var nextID: UInt64 = 0

    /// 보낸 순서대로.
    public private(set) var sent: [Sent] = []
    /// `bind` 호출 기록(port, address).
    public private(set) var bindCalls: [(port: Int?, address: String?)] = []
    /// `setBroadcast` 호출 기록.
    public private(set) var broadcastCalls: [Bool] = []
    /// `on(…)` 호출 수(이벤트 이름: "message", "error", "close").
    public private(set) var onCalls: [String] = []
    /// `off(…)` 호출 수.
    public private(set) var offCount = 0
    /// `off(…)`로 실제로 풀린 구독의 이벤트 이름("message", "error", "close"). 원본 `off('message', fn)` 검사용.
    public private(set) var offEvents: [String] = []
    public private(set) var isClosed = false
    /// `setBoundInterface` 호출 기록(CLI 안전을 위한 추가).
    public private(set) var boundInterfaces: [String] = []
    /// 넣으면 `setBoundInterface`가 이 오류를 던진다.
    public var boundInterfaceError: (any Error)?

    /// `bind`가 돌려줄 주소. nil이면 받은 값으로 만든다.
    public var boundAddress: AddressInfo?
    /// 넣으면 `bind`가 이 오류를 던진다.
    public var bindError: (any Error)?
    /// 넣으면 `send` 콜백에 이 오류를 넘긴다.
    public var sendError: (any Error)?
    /// true면 `send` 콜백을 바로(동기로) 부른다. 기본은 Node처럼 다음 차례(Task)에 부른다.
    public var callsSendCallbackSynchronously = true

    public nonisolated init() {}

    // MARK: 시험에서 쓰는 것

    /// 패킷이 온 것처럼 'message' 구독자를 동기로 부른다(원본 `mockSocket.emit('message', buf)`).
    public func emitMessage(
        _ message: [UInt8], from rinfo: RemoteInfo = RemoteInfo(address: "10.0.0.1", port: 50000, size: 0)
    ) {
        var info = rinfo
        if info.size == 0 { info.size = message.count }
        let snapshot = handlers
        handlers.removeAll {
            if case .message(_, once: true) = $0.handler { return true }
            return false
        }
        for entry in snapshot {
            if case let .message(handler, _) = entry.handler { handler(message, info) }
        }
    }

    /// 'error' 구독자를 부른다.
    public func emitError(_ error: any Error) {
        for entry in handlers {
            if case let .error(handler) = entry.handler { handler(error) }
        }
    }

    /// 'message' 구독자 수(`socket.listenerCount('message')`).
    public var messageListenerCount: Int {
        handlers.filter {
            if case .message = $0.handler { return true }
            return false
        }.count
    }

    /// 보낸 기록을 지운다(`mockClear`).
    public func clearSent() {
        sent.removeAll()
    }

    // MARK: UDPSocket

    @discardableResult
    public func onMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        onCalls.append("message")
        return add(.message(handler, once: false))
    }

    @discardableResult
    public func onceMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        onCalls.append("message")
        return add(.message(handler, once: true))
    }

    @discardableResult
    public func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) -> SocketListener {
        onCalls.append("error")
        return add(.error(handler))
    }

    @discardableResult
    public func onClose(_ handler: @escaping @DJLinkActor () -> Void) -> SocketListener {
        onCalls.append("close")
        return add(.close(handler))
    }

    public func off(_ listener: SocketListener) {
        offCount += 1
        if let entry = handlers.first(where: { $0.id == listener.id }) {
            switch entry.handler {
            case .message: offEvents.append("message")
            case .error: offEvents.append("error")
            case .close: offEvents.append("close")
            }
        }
        handlers.removeAll { $0.id == listener.id }
    }

    public func removeAllListeners() {
        handlers.removeAll()
    }

    public func bind(port: Int?, address: String?) async throws -> AddressInfo {
        bindCalls.append((port, address))
        if let bindError { throw bindError }
        return boundAddress ?? AddressInfo(address: address ?? "0.0.0.0", port: port ?? 0)
    }

    public func send(
        _ msg: [UInt8],
        port: Int,
        address: String,
        callback: (@DJLinkActor ((any Error)?, Int) -> Void)?
    ) {
        sent.append(Sent(message: msg, port: port, address: address))
        guard let callback else { return }
        let error = sendError
        let count = error == nil ? msg.count : 0
        if callsSendCallbackSynchronously {
            callback(error, count)
        } else {
            Task { @DJLinkActor in callback(error, count) }
        }
    }

    public func setBoundInterface(name: String) throws {
        if let boundInterfaceError { throw boundInterfaceError }
        boundInterfaces.append(name)
    }

    public func setBroadcast(_ flag: Bool) {
        broadcastCalls.append(flag)
    }

    public func address() -> AddressInfo? {
        boundAddress ?? bindCalls.last.map { AddressInfo(address: $0.address ?? "0.0.0.0", port: $0.port ?? 0) }
    }

    public func close(_ callback: (@DJLinkActor () -> Void)?) {
        isClosed = true
        for entry in handlers {
            if case let .close(handler) = entry.handler { handler() }
        }
        callback?()
    }

    private func add(_ handler: Handler) -> SocketListener {
        nextID += 1
        handlers.append((nextID, handler))
        return SocketListener(id: nextID)
    }
}

/// 시험용 소켓 공장. 만든 소켓을 차례로 기록한다.
@DJLinkActor
public final class FakeSocketFactory: SocketFactory {
    public private(set) var udpSockets: [FakeUDPSocket] = []
    /// TCP 연결을 만들 때 부른다. 3단계에서 FakeTCPConnection을 넣는다.
    public var makeTCPConnection: (@DJLinkActor () throws -> any TCPConnection)?

    public nonisolated init() {}

    public func createUDPSocket(reuseAddr: Bool) throws -> any UDPSocket {
        let socket = FakeUDPSocket()
        udpSockets.append(socket)
        return socket
    }

    public func createTCPConnection() throws -> any TCPConnection {
        guard let makeTCPConnection else {
            throw DJLinkError("FakeSocketFactory.makeTCPConnection is not set")
        }
        return try makeTCPConnection()
    }
}
