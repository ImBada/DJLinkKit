public struct RetryConfig: Sendable {
    public var options: RetryOptions
    public var transactionTimeout: Double?
    public init(
        retries: Int? = nil, factor: Double? = nil, minTimeout: Double? = nil,
        maxTimeout: Double? = nil, randomize: Bool? = nil, forever: Bool? = nil,
        unref: Bool? = nil, maxRetryTime: Double? = nil, transactionTimeout: Double? = nil
    ) {
        options = RetryOptions(
            retries: retries, factor: factor, minTimeout: minTimeout, maxTimeout: maxTimeout,
            randomize: randomize, forever: forever, unref: unref, maxRetryTime: maxRetryTime)
        self.transactionTimeout = transactionTimeout
    }
    public var retries: Int? {
        get { options.retries }
        set { options.retries = newValue }
    }
    public var factor: Double? {
        get { options.factor }
        set { options.factor = newValue }
    }
    public var minTimeout: Double? {
        get { options.minTimeout }
        set { options.minTimeout = newValue }
    }
    public var maxTimeout: Double? {
        get { options.maxTimeout }
        set { options.maxTimeout = newValue }
    }
    public var randomize: Bool? {
        get { options.randomize }
        set { options.randomize = newValue }
    }
    public var forever: Bool? {
        get { options.forever }
        set { options.forever = newValue }
    }
    public var unref: Bool? {
        get { options.unref }
        set { options.unref = newValue }
    }
    public var maxRetryTime: Double? {
        get { options.maxRetryTime }
        set { options.maxRetryTime = newValue }
    }
}
@DJLinkActor public final class RpcConnection {
    public var address: String
    public var retryConfig: RetryConfig
    public let socket: any UDPSocket
    public let mutex = AsyncMutex()
    public var xid = 1
    public var connected = true
    public let clock: any DJLinkClock
    public init(
        address: String, retryConfig: RetryConfig = RetryConfig(),
        socketFactory: any SocketFactory = LiveSocketFactory.shared, clock: any DJLinkClock = SystemClock.shared
    ) throws {
        self.address = address
        self.retryConfig = retryConfig
        self.clock = clock
        socket = try socketFactory.createUDPSocket(reuseAddr: false)
    }
    public func setupRequest(program: Int, version: Int, procedure: Int, data: [UInt8]) throws -> [UInt8] {
        let authBody = try rpc.UnixAuth(stamp: 0x967b8703, name: "", uid: 0, gid: 0, gids: []).toXDR()
        let request = rpc.Request(
            rpcVersion: rpc.Version, programVersion: version, program: program, procedure: procedure,
            auth: rpc.Auth(flavor: 1, body: authBody), verifier: rpc.Auth(flavor: 0, body: []), data: data)
        return try rpc.Packet(xid: xid, message: .request(request)).toXDR()
    }
    public func call(port: Int, program: Int, version: Int, procedure: Int, data: [UInt8]) async throws -> [UInt8] {
        xid += 1
        let callData = try setupRequest(program: program, version: version, procedure: procedure, data: data)
        let retryConfig = retryConfig
        let resp = try await mutex.runExclusive {
            try await withRetry(clock: clock, options: retryConfig.options, shouldRetry: { $0 is TimeoutError }) { _ in
                try await withTimeout(clock: self.clock, .ms(retryConfig.transactionTimeout ?? 1000)) {
                    try await udpSend(self.socket, callData, port, self.address)
                    return await udpRead(self.socket)
                }
            }
        }
        let packet = try rpc.Packet.fromXDR(resp)
        guard case let .response(response) = packet.message, case let .accepted(accepted) = response else {
            throw DJLinkError("RPC request was denied")
        }
        guard case let .success(data) = accepted.response else {
            throw DJLinkError("RPC did not successfully return data")
        }
        return data
    }
    public func disconnect() async throws { try await udpClose(socket) }
}
@DJLinkActor public final class RpcProgram {
    public var program: Int
    public var version: Int
    public var port: Int
    public let conn: RpcConnection
    public init(_ conn: RpcConnection, _ program: Int, _ version: Int, _ port: Int) {
        self.conn = conn
        self.program = program
        self.version = version
        self.port = port
    }
    public func call(procedure: Int, data: [UInt8]) async throws -> [UInt8] {
        try await conn.call(port: port, program: program, version: version, procedure: procedure, data: data)
    }
    public func disconnect() async throws { try await conn.disconnect() }
}
