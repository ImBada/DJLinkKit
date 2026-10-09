// 원본 Node `net.Socket`과 `promise-socket`에서 remotedb가 쓰는 부분.
// 시험은 DJLinkTestSupport의 FakeTCPConnection을, 실제로는 NWConnection 구현을 쓴다(3단계).

/// `new PromiseSocket(new net.Socket())`
@DJLinkActor
public protocol TCPConnection: AnyObject {
    /// `await socket.connect(port, host)`
    func connect(port: Int, host: String) async throws

    /// `await socket.write(data)`
    func write(_ data: [UInt8]) async throws

    /// `await socket.read(size)`(promise-readable). `size`만큼 모일 때까지 기다리고, 끝이 먼저 오면
    /// 남은 만큼을 준다. `size`가 nil이면 지금 있는 덩어리를 준다. 이미 끝났으면 nil.
    func read(_ size: Int?) async throws -> [UInt8]?

    /// `socket.stream.setTimeout(ms)`와 `once('timeout', …)`. 0이면 끈다.
    func setTimeout(_ milliseconds: Int, onTimeout: (@DJLinkActor () -> Void)?)

    /// `stream.writable && !stream.closed && !stream.destroyed`
    var isOpen: Bool { get }

    /// CLI 안전을 위한 추가(기본값은 원본 동작). 연결 전에 이름으로 인터페이스를 요구한다.
    func setRequiredInterface(name: String) throws

    /// CLI 안전을 위한 추가(기본값은 원본 동작). 원격 종료를 포함해 닫힌 연결을 알린다.
    func setCloseHandler(_ handler: @escaping @DJLinkActor () -> Void) throws

    /// `socket.destroy(error)`
    func destroy(_ error: (any Error)?)
}

extension TCPConnection {
    public func setCloseHandler(_ handler: @escaping @DJLinkActor () -> Void) throws {
        throw DJLinkError("This connection cannot report closure")
    }

    public func setRequiredInterface(name: String) throws {
        throw DJLinkError("This connection cannot require a network interface")
    }
}
