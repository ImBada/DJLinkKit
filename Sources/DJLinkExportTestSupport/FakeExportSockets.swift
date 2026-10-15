// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
import DJLinkExportSupport
// 원본의 루프백 서버 시험을 실제 소켓 없이 같은 요청·응답으로 연결하는 가짜 전송 계층.
import DJLinkKit
import DJLinkTestSupport

fileprivate struct WeakUDP { weak var value: FakeExportUDPSocket? }
fileprivate struct WeakListener { weak var value: FakeExportTCPListener? }
// 소켓만 반환하는 픽스처에서도 버스는 살아 있고, factory와 소켓 사이에는 순환이 없다.
@DJLinkActor fileprivate final class FakeExportNetwork {
    var udp: [WeakUDP] = [], listeners: [WeakListener] = []
    var clientAddress = "127.0.0.1", nextPort = 31000
    var udpBindErrors: [Int: any Error] = [:], tcpBindErrors: [Int: any Error] = [:]
    var accepted: (@DJLinkActor (FakeExportAcceptedConnection) -> Void)?
    let clock: any DJLinkClock
    init(_ clock: any DJLinkClock) { self.clock = clock }
    func allocatePort() -> Int {
        udp.removeAll { $0.value == nil }
        listeners.removeAll { $0.value == nil }
        for _ in 0..<65535 {
            if !(1...65535).contains(nextPort) { nextPort = 31000 }
            let candidate = nextPort
            nextPort = candidate == 65535 ? 1 : candidate + 1
            if !udp.contains(where: { $0.value.map { !$0.isClosed && $0.address()?.port == candidate } ?? false })
                && !listeners.contains(where: {
                    $0.value.map { !$0.isClosed && $0.address()?.port == candidate } ?? false
                })
            {
                return candidate
            }
        }
        return 0
    }
    static func wildcard(_ address: String) -> Bool { address == "0.0.0.0" || address == "::" }
    static func overlap(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.contains(":") != b.contains(":") { return a == "::" || b == "::" }
        return wildcard(a) || wildcard(b)
    }
    static func receives(_ bound: String, _ address: String) -> Bool { bound == address || wildcard(bound) }
    func deliver(_ bytes: [UInt8], from sender: FakeExportUDPSocket, port: Int, address: String) {
        guard let source = sender.address() else { return }
        let sourceAddress = Self.wildcard(source.address) ? clientAddress : source.address
        let info = RemoteInfo(
            address: sourceAddress, family: sourceAddress.contains(":") ? "IPv6" : "IPv4", port: source.port,
            size: bytes.count)
        let receivers = udp.compactMap(\.value).filter {
            !$0.isClosed && $0.address()?.port == port
                && (Self.receives($0.address()?.address ?? "", address) || address == "255.255.255.255"
                    || address.hasSuffix(".255"))
        }
        for receiver in receivers { receiver.emitMessage(bytes, from: info) }
    }
    func connect(_ client: FakeExportClientConnection, _ port: Int, _ host: String) throws {
        guard
            let listener = listeners.compactMap(\.value).first(where: {
                !$0.isClosed && $0.address()?.port == port && Self.receives($0.address()?.address ?? "", host)
            })
        else { throw DJLinkError("connect ECONNREFUSED") }
        let server = FakeTCPConnection(clock: clock)
        let connection = FakeExportAcceptedConnection(server)
        let peer = client.inner
        accepted?(connection)
        peer.onWrite = { [weak server] data in
            guard let server, server.isOpen else { throw DJLinkError("write EPIPE") }
            server.inject(data)
        }
        server.onWrite = { [weak peer] data in
            guard let peer, peer.isOpen else { throw DJLinkError("write EPIPE") }
            peer.inject(data)
        }
        // 전송 종료와 사용자의 close handler는 독립적으로 호출한다.
        try peer.setCloseHandler { [weak server, weak client] in
            if server?.isOpen == true { server?.end() }
            client?.reportClosed()
        }
        try server.setCloseHandler { [weak peer, weak connection] in
            if peer?.isOpen == true { peer?.end() }
            connection?.reportClosed()
        }
        listener.emitConnection(
            connection,
            from: RemoteInfo(
                address: clientAddress, family: clientAddress.contains(":") ? "IPv6" : "IPv4", port: allocatePort(),
                size: 0))
    }
}

@DJLinkActor public final class FakeExportSocketFactory: ExportSocketFactory {
    public private(set) var udpSockets: [FakeExportUDPSocket] = []
    public private(set) var tcpListeners: [FakeExportTCPListener] = []
    public private(set) var tcpConnections: [FakeTCPConnection] = []
    public private(set) var acceptedTCPConnections: [FakeExportAcceptedConnection] = []
    private let network: FakeExportNetwork
    public var clientAddress: String {
        get { network.clientAddress }
        set { network.clientAddress = newValue }
    }
    public var nextPort: Int {
        get { network.nextPort }
        set { network.nextPort = newValue }
    }
    public var udpCreateError: (any Error)?, listenerCreateError: (any Error)?
    public var udpBindErrors: [Int: any Error] {
        get { network.udpBindErrors }
        set { network.udpBindErrors = newValue }
    }
    public var tcpBindErrors: [Int: any Error] {
        get { network.tcpBindErrors }
        set { network.tcpBindErrors = newValue }
    }
    public let clock: any DJLinkClock
    public init(clock: any DJLinkClock = TestClock()) {
        self.clock = clock
        network = FakeExportNetwork(clock)
        network.accepted = { [weak self] connection in self?.acceptedTCPConnections.append(connection) }
    }
    public func allocatePort() -> Int { network.allocatePort() }
    public func createUDPSocket(reuseAddr: Bool) throws -> any UDPSocket {
        if let udpCreateError { throw udpCreateError }
        let socket = FakeExportUDPSocket(network: network, reuseAddr: reuseAddr)
        udpSockets.append(socket)
        network.udp.append(WeakUDP(value: socket))
        return socket
    }
    public func createTCPListener() throws -> any TCPListener {
        if let listenerCreateError { throw listenerCreateError }
        let listener = FakeExportTCPListener(network: network)
        tcpListeners.append(listener)
        network.listeners.append(WeakListener(value: listener))
        return listener
    }
    public func createTCPConnection() throws -> any TCPConnection {
        let client = FakeExportClientConnection(network)
        tcpConnections.append(client.inner)
        return client
    }
}

@DJLinkActor public final class FakeExportUDPSocket: ServerUDPSocket {
    public let inner = FakeUDPSocket()
    private let network: FakeExportNetwork
    public let reuseAddr: Bool
    public private(set) var sendBufferSize: Int?, receiveBufferSize: Int?
    public var broadcastError: (any Error)?
    public var isClosed: Bool { inner.isClosed }
    public var sent: [FakeUDPSocket.Sent] { inner.sent }
    public var bindError: (any Error)? {
        get { inner.bindError }
        set { inner.bindError = newValue }
    }
    fileprivate init(network: FakeExportNetwork, reuseAddr: Bool) {
        self.network = network
        self.reuseAddr = reuseAddr
    }
    public func setSendBufferSize(_ bytes: Int) throws {
        guard !isClosed, bytes >= 0 else { throw DJLinkError("setsockopt EINVAL") }
        sendBufferSize = bytes
    }
    public func setReceiveBufferSize(_ bytes: Int) throws {
        guard !isClosed, bytes >= 0 else { throw DJLinkError("setsockopt EINVAL") }
        receiveBufferSize = bytes
    }
    @discardableResult public func onMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void)
        -> SocketListener
    { inner.onMessage(handler) }
    @discardableResult public func onceMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void)
        -> SocketListener
    { inner.onceMessage(handler) }
    @discardableResult public func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) -> SocketListener {
        inner.onError(handler)
    }
    @discardableResult public func onClose(_ handler: @escaping @DJLinkActor () -> Void) -> SocketListener {
        inner.onClose(handler)
    }
    public func off(_ listener: SocketListener) { inner.off(listener) }
    public func removeAllListeners() { inner.removeAllListeners() }
    public func setBroadcast(_ flag: Bool) { inner.setBroadcast(flag) }
    public func setBroadcastChecked(_ enabled: Bool) throws {
        guard !isClosed else { throw SocketNotRunningError() }
        if let broadcastError { throw broadcastError }
        inner.setBroadcast(enabled)
    }
    public func setBoundInterface(name: String) throws { try inner.setBoundInterface(name: name) }
    public func address() -> AddressInfo? { isClosed ? nil : inner.address() }
    public func close(_ callback: (@DJLinkActor () -> Void)?) throws {
        guard !isClosed else { throw SocketNotRunningError() }
        inner.close(callback)
    }
    public func bind(port: Int?, address: String?) async throws -> AddressInfo {
        guard !isClosed, inner.address() == nil, let requested = UInt16(exactly: port ?? 0) else {
            throw DJLinkError("bind EINVAL")
        }
        let chosen = requested == 0 ? network.allocatePort() : Int(requested)
        if let error = network.udpBindErrors[chosen] { throw error }
        let host = address ?? "0.0.0.0"
        if network.udp.compactMap(\.value).contains(where: {
            $0 !== self && !$0.isClosed && $0.address()?.port == chosen
                && FakeExportNetwork.overlap($0.address()?.address ?? "", host) && (!$0.reuseAddr || !reuseAddr)
        }) {
            throw DJLinkError("bind EADDRINUSE")
        }
        _ = try await inner.bind(port: chosen, address: host)
        inner.boundAddress = AddressInfo(address: host, family: host.contains(":") ? "IPv6" : "IPv4", port: chosen)
        return inner.boundAddress!
    }
    public func send(_ msg: [UInt8], port: Int, address: String, callback: (@DJLinkActor ((any Error)?, Int) -> Void)?)
    {
        guard !isClosed else {
            let error = SocketNotRunningError()
            if let callback { callback(error, 0) } else { inner.emitError(error) }
            return
        }
        inner.send(msg, port: port, address: address, callback: callback)
        if inner.sendError == nil { network.deliver(msg, from: self, port: port, address: address) }
    }
    public func emitMessage(_ bytes: [UInt8], from: RemoteInfo = RemoteInfo(address: "127.0.0.1", port: 0, size: 0)) {
        if !isClosed { inner.emitMessage(bytes, from: from) }
    }
}

@DJLinkActor public final class FakeExportTCPListener: TCPListener {
    private let network: FakeExportNetwork
    private var bound: AddressInfo?
    private var handlers: [UInt64: @DJLinkActor (any TCPConnection, RemoteInfo) -> Void] = [:]
    private var nextID: UInt64 = 0
    public private(set) var isClosed = false
    fileprivate init(network: FakeExportNetwork) { self.network = network }
    public func bind(port: Int, address: String) async throws -> AddressInfo {
        guard !isClosed, bound == nil, let requested = UInt16(exactly: port) else { throw DJLinkError("bind EINVAL") }
        let chosen = requested == 0 ? network.allocatePort() : Int(requested)
        if let error = network.tcpBindErrors[chosen] { throw error }
        if network.listeners.compactMap(\.value).contains(where: {
            $0 !== self && !$0.isClosed && $0.address()?.port == chosen
                && FakeExportNetwork.overlap($0.address()?.address ?? "", address)
        }) {
            throw DJLinkError("bind EADDRINUSE")
        }
        let result = AddressInfo(address: address, family: address.contains(":") ? "IPv6" : "IPv4", port: chosen)
        bound = result
        return result
    }
    @discardableResult public func onConnection(
        _ handler: @escaping @DJLinkActor (any TCPConnection, RemoteInfo) -> Void
    ) -> SocketListener {
        nextID += 1
        handlers[nextID] = handler
        return SocketListener(id: nextID)
    }
    public func off(_ listener: SocketListener) { handlers.removeValue(forKey: listener.id) }
    public func address() -> AddressInfo? { isClosed ? nil : bound }
    public func close() throws {
        isClosed = true
        handlers.removeAll()
    }
    public func emitConnection(_ connection: any TCPConnection, from: RemoteInfo) {
        guard !isClosed, !handlers.isEmpty else {
            connection.destroy(nil)
            return
        }
        let snapshot = Array(handlers.values)
        for handler in snapshot { handler(connection, from) }
    }
}

@DJLinkActor fileprivate final class FakeExportClientConnection: TCPConnection {
    let inner: FakeTCPConnection
    private var closeHandler: (@DJLinkActor () -> Void)?
    init(_ network: FakeExportNetwork) {
        inner = FakeTCPConnection(clock: network.clock)
        inner.onConnect = { [network, weak self] port, host in
            guard let self else { throw DJLinkError("connect ECONNREFUSED") }
            try network.connect(self, port, host)
        }
    }
    func reportClosed() {
        let handler = closeHandler
        closeHandler = nil
        handler?()
    }
    var isOpen: Bool { inner.isOpen }
    func connect(port: Int, host: String) async throws { try await inner.connect(port: port, host: host) }
    func read(_ size: Int?) async throws -> [UInt8]? { try await inner.read(size) }
    func write(_ data: [UInt8]) async throws { try await inner.write(data) }
    func setTimeout(_ milliseconds: Int, onTimeout: (@DJLinkActor () -> Void)?) {
        inner.setTimeout(milliseconds, onTimeout: onTimeout)
    }
    func setRequiredInterface(name: String) throws { try inner.setRequiredInterface(name: name) }
    func setConnectGuard(_ check: @escaping @DJLinkActor () throws -> Void) throws { try inner.setConnectGuard(check) }
    func setCloseHandler(_ handler: @escaping @DJLinkActor () -> Void) throws { closeHandler = handler }
    func destroy(_ error: (any Error)?) {
        inner.destroy(error)
        reportClosed()
    }
    deinit {
        let inner = inner
        Task { @DJLinkActor in inner.destroy(nil) }
    }
}
@DJLinkActor public final class FakeExportAcceptedConnection: ServerTCPConnection {
    public let inner: FakeTCPConnection
    private var closeHandler: (@DJLinkActor () -> Void)?
    public private(set) var keepaliveAfter: Int?, keepaliveInterval: Int?, noDelay: Bool?
    public init(_ inner: FakeTCPConnection) { self.inner = inner }
    public func configureServer(keepaliveAfter: Int, keepaliveInterval: Int, noDelay: Bool) throws {
        guard isOpen, keepaliveAfter > 0, keepaliveInterval > 0 else { throw DJLinkError("setsockopt EINVAL") }
        self.keepaliveAfter = keepaliveAfter
        self.keepaliveInterval = keepaliveInterval
        self.noDelay = noDelay
    }
    public var isOpen: Bool { inner.isOpen }
    public func connect(port: Int, host: String) async throws { try await inner.connect(port: port, host: host) }
    public func read(_ size: Int?) async throws -> [UInt8]? { try await inner.read(size) }
    public func write(_ data: [UInt8]) async throws { try await inner.write(data) }
    public func setTimeout(_ milliseconds: Int, onTimeout: (@DJLinkActor () -> Void)?) {
        inner.setTimeout(milliseconds, onTimeout: onTimeout)
    }
    public func setRequiredInterface(name: String) throws { try inner.setRequiredInterface(name: name) }
    public func setConnectGuard(_ check: @escaping @DJLinkActor () throws -> Void) throws {
        try inner.setConnectGuard(check)
    }
    public func setCloseHandler(_ handler: @escaping @DJLinkActor () -> Void) throws { closeHandler = handler }
    fileprivate func reportClosed() {
        let handler = closeHandler
        closeHandler = nil
        handler?()
    }
    public func destroy(_ error: (any Error)?) {
        inner.destroy(error)
        reportClosed()
    }
    deinit {
        let inner = inner
        Task { @DJLinkActor in inner.destroy(nil) }
    }
}
