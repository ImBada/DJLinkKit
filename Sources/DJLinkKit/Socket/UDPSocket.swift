// 원본 Node `dgram.Socket`과 src/utils/udp.ts를 옮긴 것.
// 시험은 DJLinkTestSupport의 FakeUDPSocket을, 실제로는 BSDUDPSocket을 쓴다.

/// dgram 'message' 이벤트의 `rinfo`.
public struct RemoteInfo: Equatable, Hashable, Sendable {
    public var address: String
    public var family: String
    public var port: Int
    public var size: Int

    public init(address: String, family: String = "IPv4", port: Int, size: Int) {
        self.address = address
        self.family = family
        self.port = port
        self.size = size
    }
}

/// `socket.address()`의 결과(Node `AddressInfo`).
public struct AddressInfo: Equatable, Hashable, Sendable {
    public var address: String
    public var family: String
    public var port: Int

    public init(address: String, family: String = "IPv4", port: Int) {
        self.address = address
        self.family = family
        self.port = port
    }
}

/// 소켓 이벤트 구독. `off`에 넘긴다.
public struct SocketListener: Hashable, Sendable {
    public let id: UInt64

    public init(id: UInt64) {
        self.id = id
    }
}

/// Node `dgram.Socket`에서 원본이 쓰는 부분.
///
/// 이벤트 콜백은 모두 `DJLinkActor` 위에서 불린다. `send`의 콜백은 Node처럼 늘 나중에(비동기로) 불린다.
@DJLinkActor
public protocol UDPSocket: AnyObject {
    /// `socket.on('message', (msg, rinfo) => …)`
    @discardableResult
    func onMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener

    /// `socket.once('message', …)`
    @discardableResult
    func onceMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener

    /// `socket.on('error', …)`
    @discardableResult
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) -> SocketListener

    /// `socket.on('close', …)`
    @discardableResult
    func onClose(_ handler: @escaping @DJLinkActor () -> Void) -> SocketListener

    /// `socket.off(event, handler)`. 어느 이벤트의 구독이든 받는다.
    func off(_ listener: SocketListener)

    /// `socket.removeAllListeners()`
    func removeAllListeners()

    /// `socket.bind(port, address)`를 기다린다(원본 `udpBind`). 실패하면 던진다.
    func bind(port: Int?, address: String?) async throws -> AddressInfo

    /// `socket.send(msg, port, address, callback)`. 콜백의 인자는 오류(없으면 nil)와 보낸 바이트 수.
    func send(
        _ msg: [UInt8],
        port: Int,
        address: String,
        callback: (@DJLinkActor ((any Error)?, Int) -> Void)?
    )

    /// `socket.setBroadcast(flag)`
    func setBroadcast(_ flag: Bool)

    /// `socket.address()`. 묶이지 않았으면 nil(Node는 던진다).
    func address() -> AddressInfo?

    /// `socket.close(callback)`. 콜백은 'close' 뒤에 불린다.
    func close(_ callback: (@DJLinkActor () -> Void)?) throws
}

extension UDPSocket {
    /// 콜백 없는 `socket.send(msg, port, address)`
    public func send(_ msg: [UInt8], port: Int, address: String) {
        send(msg, port: port, address: address, callback: nil)
    }

    /// `socket.on('message', msg => …)`
    @discardableResult
    public func onMessage(_ handler: @escaping @DJLinkActor ([UInt8]) -> Void) -> SocketListener {
        onMessage { message, _ in handler(message) }
    }

    /// `socket.close()`
    public func close() throws {
        try close(nil)
    }
}

/// 원본 `udpBind(conn, port, address)`
@DJLinkActor
@discardableResult
public func udpBind(_ conn: any UDPSocket, _ port: Int? = nil, _ address: String? = nil) async throws -> AddressInfo {
    try await conn.bind(port: port, address: address)
}

/// 원본 `udpRead(conn)`: 다음 메시지 하나를 기다린다.
@DJLinkActor
public func udpRead(_ conn: any UDPSocket) async -> [UInt8] {
    await withCheckedContinuation { (continuation: CheckedContinuation<[UInt8], Never>) in
        conn.onceMessage { message, _ in continuation.resume(returning: message) }
    }
}

/// 원본 `udpSend(conn, msg, port, address)`: 보낸 바이트 수를 돌려준다.
@DJLinkActor
@discardableResult
public func udpSend(_ conn: any UDPSocket, _ msg: [UInt8], _ port: Int, _ address: String) async throws -> Int {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, any Error>) in
        conn.send(msg, port: port, address: address) { error, sent in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: sent)
            }
        }
    }
}

/// 원본 `udpClose(conn)`
@DJLinkActor
public func udpClose(_ conn: any UDPSocket) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        do {
            try conn.close { continuation.resume() }
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
