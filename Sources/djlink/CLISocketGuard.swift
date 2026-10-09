import DJLinkKit
import Foundation

// 이 실행이 만든 모든 소켓(UDP·TCP, NFS의 별도 RPC 소켓 포함)을 한 곳에서 만들고 추적한다.
// - 선택한 인터페이스에 UDP 소켓을 묶는다(`--iface`).
// - 중단된 뒤에는 새 소켓을 만들지 않고, 열린 소켓이 보내지도 연결하지도 않는다.
// - 끝날 때 남은 소켓을 모두 닫는다.

/// 중단 토큰이 선 뒤에는 보내지 않고 오류로 알리는 UDP 소켓. 나머지는 안쪽 소켓에 맡긴다.
@DJLinkActor
final class GuardedUDPSocket: UDPSocket {
    let inner: any UDPSocket
    private let abort: CLIAbort
    private let requireDestination: @DJLinkActor (String) throws -> Void
    private(set) var isCloseRequested = false
    var cancelsPendingReads: Bool { true }

    init(_ inner: any UDPSocket, abort: CLIAbort, requireDestination: @escaping @DJLinkActor (String) throws -> Void) {
        self.inner = inner
        self.abort = abort
        self.requireDestination = requireDestination
    }

    @discardableResult
    func onMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        inner.onMessage(handler)
    }

    @discardableResult
    func onceMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        inner.onceMessage(handler)
    }

    @discardableResult
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) -> SocketListener { inner.onError(handler) }

    @discardableResult
    func onClose(_ handler: @escaping @DJLinkActor () -> Void) -> SocketListener { inner.onClose(handler) }

    func off(_ listener: SocketListener) { inner.off(listener) }

    func removeAllListeners() { inner.removeAllListeners() }

    func bind(port: Int?, address: String?) async throws -> AddressInfo {
        try abort.check()
        return try await inner.bind(port: port, address: address)
    }

    func send(
        _ msg: [UInt8], port: Int, address: String, callback: (@DJLinkActor ((any Error)?, Int) -> Void)?
    ) {
        // 중단된 뒤나 닫은 뒤에는 한 바이트도 내보내지 않는다. 기다리는 쪽이 멈추지 않게 오류로 알린다.
        if abort.isAborted || isCloseRequested {
            guard let callback else { return }
            let error: any Error = abort.isAborted ? CLIAborted() : SocketNotRunningError()
            Task { @DJLinkActor in callback(error, 0) }
            return
        }
        do {
            try requireDestination(address)
            try abort.check()
        } catch {
            if let callback { callback(error, 0) }
            return
        }
        inner.send(msg, port: port, address: address, callback: callback)
    }

    func setBroadcast(_ flag: Bool) { inner.setBroadcast(flag) }

    func address() -> AddressInfo? { inner.address() }

    func close(_ callback: (@DJLinkActor () -> Void)?) throws {
        guard !isCloseRequested else { throw SocketNotRunningError() }
        isCloseRequested = true
        try inner.close(callback)
    }

    func setBoundInterface(name: String) throws {
        try inner.setBoundInterface(name: name)
    }
}

/// 중단된 뒤에는 연결하거나 쓰지 않는 TCP 연결.
@DJLinkActor
final class GuardedTCPConnection: TCPConnection {
    let inner: any TCPConnection
    private let abort: CLIAbort
    private let requireDestination: @DJLinkActor (String) throws -> Void

    init(
        _ inner: any TCPConnection, abort: CLIAbort, requireDestination: @escaping @DJLinkActor (String) throws -> Void
    ) {
        self.inner = inner
        self.abort = abort
        self.requireDestination = requireDestination
    }

    func connect(port: Int, host: String) async throws {
        try abort.check()
        try requireDestination(host)
        try await inner.connect(port: port, host: host)
    }

    func write(_ data: [UInt8]) async throws {
        try abort.check()
        try await inner.write(data)
    }

    func read(_ size: Int?) async throws -> [UInt8]? { try await inner.read(size) }

    func setTimeout(_ milliseconds: Int, onTimeout: (@DJLinkActor () -> Void)?) {
        inner.setTimeout(milliseconds, onTimeout: onTimeout)
    }

    var isOpen: Bool { inner.isOpen }

    func setRequiredInterface(name: String) throws { try inner.setRequiredInterface(name: name) }

    func destroy(_ error: (any Error)?) { inner.destroy(error) }
}

/// 소켓 공장 겸 소유권 장부. 라이브러리(`bringOnline`·remotedb·NFS)가 만드는 소켓이 모두 여기를 지난다.
@DJLinkActor
final class CLISocketRegistry: SocketFactory {
    private let inner: any SocketFactory
    private let abort: CLIAbort
    private var udpSockets: [GuardedUDPSocket] = []
    private var tcpConnections: [GuardedTCPConnection] = []
    /// 묶은 인터페이스 이름. 정해지면 이미 만든 UDP 소켓과 앞으로 만들 UDP 소켓이 모두 묶인다.
    private(set) var boundInterfaceName: String?
    var scope: CLINetworkScope?

    func requireDestination(_ address: String) throws {
        guard let scope, let ip = try? Address4(address), ip.subnetMask == 32, scope.contains(ip) else {
            throw CLIRuntimeError("목적지 \(address)는 선택한 인터페이스의 서브넷 밖이거나 범위가 정해지지 않았다")
        }
    }

    init(inner: any SocketFactory, abort: CLIAbort) {
        self.inner = inner
        self.abort = abort
    }

    var openUDPSocketCount: Int { udpSockets.filter { !$0.isCloseRequested }.count }

    func createUDPSocket(reuseAddr: Bool) throws -> any UDPSocket {
        try abort.check()
        let socket = GuardedUDPSocket(
            try inner.createUDPSocket(reuseAddr: reuseAddr), abort: abort,
            requireDestination: { [weak self] in
                guard let self else { throw CLIAborted() }
                try self.requireDestination($0)
            })
        // 장부에 먼저 올려 묶기가 실패해도 끝날 때 닫힌다.
        udpSockets.append(socket)
        if let boundInterfaceName { try socket.setBoundInterface(name: boundInterfaceName) }
        return socket
    }

    func createTCPConnection() throws -> any TCPConnection {
        try abort.check()
        let connection = GuardedTCPConnection(
            try inner.createTCPConnection(), abort: abort,
            requireDestination: { [weak self] in
                guard let self else { throw CLIAborted() }
                try self.requireDestination($0)
            })
        tcpConnections.append(connection)
        if let boundInterfaceName { try connection.setRequiredInterface(name: boundInterfaceName) }
        return connection
    }

    /// 이미 만든 UDP 소켓과 앞으로 만들 UDP 소켓을 이 인터페이스에 묶는다. 하나라도 실패하면 던진다.
    func bindInterface(name: String) throws {
        boundInterfaceName = name
        for socket in udpSockets where !socket.isCloseRequested {
            try socket.setBoundInterface(name: name)
        }
        for connection in tcpConnections { try connection.setRequiredInterface(name: name) }
    }

    /// 열린 소켓을 모두 닫는다. 이미 닫은 것은 건너뛰고 닫기 오류는 무시한다.
    func closeAll() async {
        for socket in udpSockets where !socket.isCloseRequested {
            try? await udpClose(socket)
        }
        for connection in tcpConnections { connection.destroy(nil) }
    }
}
