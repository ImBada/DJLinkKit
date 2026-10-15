@DJLinkActor public protocol RemoteDBDeviceSource: AnyObject {
    var devices: [DeviceID: Device] { get }
}
public enum MenuTarget: Int, Sendable { case main = 0x01 }
public struct QueryDescriptor: Sendable {
    public var menuTarget: MenuTarget
    public var trackSlot: MediaSlot
    public var trackType: TrackType
    public init(menuTarget: MenuTarget, trackSlot: MediaSlot, trackType: TrackType) {
        self.menuTarget = menuTarget
        self.trackSlot = trackSlot
        self.trackType = trackType
    }
}
public struct LookupDescriptor: Sendable {
    public var menuTarget: MenuTarget
    public var trackSlot: MediaSlot
    public var trackType: TrackType
    public var targetDevice: Device
    public var hostDevice: Device
    public init(queryDescriptor: QueryDescriptor, targetDevice: Device, hostDevice: Device) {
        menuTarget = queryDescriptor.menuTarget
        trackSlot = queryDescriptor.trackSlot
        trackType = queryDescriptor.trackType
        self.targetDevice = targetDevice
        self.hostDevice = hostDevice
    }
}
@DJLinkActor public final class Connection {
    /// 질의가 응답을 기다리는 동안의 시간 제한(ms). 연결할 때 거는 제한(`connectToDevice`)과 같은 10초다.
    /// 소켓의 유휴 제한이라 바이트가 오가는 동안에는 늘어나고, 그만큼 아무것도 오지 않을 때만 끝낸다(PLAN §9, #47).
    public static let queryTimeoutMilliseconds = 10000
    private let socket: any TCPConnection
    private var txId = 0
    private let lock = AsyncMutex()
    private let matchesTransactionIds: Bool
    private let logger: any Logger
    public var device: Device
    /// - Parameter matchesTransactionIds: 켜면 `readMessage`가 마지막으로 쓴 요청과 트랜잭션 번호가 다른 메시지를
    ///   응답으로 쓰지 않고 건너뛴다(PLAN §9, #46). 기본값 false는 원본 동작(응답을 순서대로만 읽는다)이다.
    ///   `RemoteDatabase`는 켜서 만든다.
    public init(
        device: Device, socket: any TCPConnection, matchesTransactionIds: Bool = false,
        logger: any Logger = noopLogger
    ) {
        self.device = device
        self.socket = socket
        self.matchesTransactionIds = matchesTransactionIds
        self.logger = logger
    }
    public func writeMessage(_ message: Message, _ span: TelemetrySpan = TelemetrySpan()) async throws {
        let tx = span.startChild(SpanContext(op: "writeMessage", description: getMessageName(message.type)))
        txId += 1
        message.transactionId = txId
        try await socket.write(message.buffer)
        tx.finish()
    }
    public func readMessage(_ expect: Response, _ span: TelemetrySpan = TelemetrySpan()) async throws -> Message {
        try await lock.runExclusive {
            try await Message.fromStream(
                // 번호는 u32로 쓰이므로 비교도 하위 32비트로 한다.
                socket, expect, span, expectedTransactionId: matchesTransactionIds ? txId & 0xFFFF_FFFF : nil,
                logger: logger)
        }
    }
    /// `body`가 도는 동안 응답이 `queryTimeoutMilliseconds` 넘게 없으면 연결을 닫아(destroy) 기다리던 읽기를 오류로 끝낸다.
    /// 원본은 연결을 마치면 제한을 꺼서(`setTimeout(0)`) 응답이 없는 질의가 영영 멈추고 장치 잠금을 쥔 채 남는다(PLAN §9, #47).
    /// 닫힌 연결은 `RemoteDatabase.get`이 버리고 다음 조회에서 새로 연결한다. `body`가 끝나면 제한을 풀어 놀고 있는 연결은 열어 둔다.
    public func withQueryTimeout<T>(_ body: @DJLinkActor () async throws -> T) async throws -> T {
        let socket = socket
        let address = device.ip.address
        socket.setTimeout(Self.queryTimeoutMilliseconds) {
            socket.destroy(DJLinkError("RemoteDB query to \(address) timed out"))
        }
        defer { socket.setTimeout(0, onTimeout: nil) }
        return try await body()
    }
    public var isOpen: Bool { socket.isOpen }
    public func close() { socket.destroy(nil) }
}
@DJLinkActor public final class QueryInterface {
    private let conn: Connection
    private let hostDevice: Device
    private let lock: AsyncMutex
    public init(conn: Connection, lock: AsyncMutex, hostDevice: Device) {
        self.conn = conn
        self.lock = lock
        self.hostDevice = hostDevice
    }
    public func query(
        queryDescriptor: QueryDescriptor, query: Query, args: RemoteDBQueryArgs, span: TelemetrySpan? = nil
    ) async throws -> RemoteDBQueryResult {
        let tx =
            span?.startChild(SpanContext(op: "remoteQuery", description: getQueryName(query)))
            ?? Telemetry.startTransaction(SpanContext(name: "remoteQuery", description: getQueryName(query)))
        let descriptor = LookupDescriptor(
            queryDescriptor: queryDescriptor, targetDevice: conn.device, hostDevice: hostDevice)
        let handler = queryHandlers[query]
        return try await lock.runExclusive {
            guard let handler else { throw DJLinkError("handler is not a function") }
            let result = try await conn.withQueryTimeout { try await handler(conn, descriptor, args, tx) }
            tx.finish()
            return result
        }
    }
}
@DJLinkActor public final class RemoteDatabase {
    /// 원본은 가상 CDJ `Device` 객체를 network·announcer와 나눠 쥐고, 번호가 바뀌면 그대로 따라간다.
    private let hostDeviceRef: DeviceReference
    /// The device this service belongs to — the virtual CDJ announced on the network.
    public var hostDevice: Device { hostDeviceRef.device }
    private let deviceManager: any RemoteDBDeviceSource
    private let socketFactory: any SocketFactory
    private let serverQueryPort: Int
    private let pickQueryId: Bool
    private let closesPortQueryConnection: Bool
    private let queryIdPicker: @DJLinkActor (DeviceID, [Device]) -> DeviceID
    private let logger: any Logger
    private var connections: [DeviceID: Connection] = [:]
    private var deviceLocks: [DeviceID: AsyncMutex] = [:]
    private var queryIds: [DeviceID: DeviceID] = [:]
    public init(
        deviceManager: any RemoteDBDeviceSource, hostDevice: DeviceReference, pickQueryId: Bool = true,
        socketFactory: any SocketFactory = LiveSocketFactory.shared, serverQueryPort: Int = REMOTEDB_SERVER_QUERY_PORT,
        closesPortQueryConnection: Bool = false,
        queryIdPicker: @escaping @DJLinkActor (DeviceID, [Device]) -> DeviceID = { pickRemoteDbQueryId($0, $1) },
        logger: any Logger = noopLogger
    ) {
        self.deviceManager = deviceManager
        self.hostDeviceRef = hostDevice
        self.pickQueryId = pickQueryId
        self.closesPortQueryConnection = closesPortQueryConnection
        self.socketFactory = socketFactory
        self.serverQueryPort = serverQueryPort
        self.queryIdPicker = queryIdPicker
        self.logger = logger
    }

    /// 나눠 쥘 필요가 없을 때(시험 등) 장치 값으로 만든다.
    public convenience init(
        deviceManager: any RemoteDBDeviceSource, hostDevice: Device, pickQueryId: Bool = true,
        socketFactory: any SocketFactory = LiveSocketFactory.shared, serverQueryPort: Int = REMOTEDB_SERVER_QUERY_PORT,
        closesPortQueryConnection: Bool = false,
        queryIdPicker: @escaping @DJLinkActor (DeviceID, [Device]) -> DeviceID = { pickRemoteDbQueryId($0, $1) },
        logger: any Logger = noopLogger
    ) {
        self.init(
            deviceManager: deviceManager, hostDevice: DeviceReference(hostDevice), pickQueryId: pickQueryId,
            socketFactory: socketFactory, serverQueryPort: serverQueryPort,
            closesPortQueryConnection: closesPortQueryConnection, queryIdPicker: queryIdPicker, logger: logger)
    }
    public func connectToDevice(_ device: Device) async throws {
        let tx = Telemetry.startTransaction(SpanContext(name: "connectRemotedb"))
        let portConn = try socketFactory.createTCPConnection()
        // CLI 안전을 위한 추가(기본값 false는 원본 동작). 실패 때도 일회성 연결을 닫는다.
        defer { if closesPortQueryConnection { portConn.destroy(nil) } }
        try await portConn.connect(port: serverQueryPort, host: device.ip.address)
        try await portConn.write([0, 0, 0, 0x0f] + [UInt8]("RemoteDBServer", encoding: .ascii) + [0])
        guard let resp = try await portConn.read(nil) else { throw DJLinkError("Invalid response from remotedb") }
        if closesPortQueryConnection { portConn.destroy(nil) }
        guard resp.count == 2 else { throw DJLinkError("Expected 2 bytes, got \(resp.count)") }
        let dbPort = try resp.readUInt16BE()
        let socket = try socketFactory.createTCPConnection()
        socket.setTimeout(10000) {
            socket.destroy(DJLinkError("RemoteDB connection to \(device.ip.address):\(dbPort) timed out"))
        }
        try await socket.connect(port: dbPort, host: device.ip.address)
        try await socket.write(RemoteDBUInt32(1).buffer)
        let data = try await readField(socket, .uint32) as! RemoteDBUInt32
        guard data.value == 1 else { throw DJLinkError("Expected 0x01 during preamble handshake. Got \(data.value)") }
        let queryId =
            !pickQueryId || hostDevice.id <= REMOTEDB_MAX_DEVICE_ID || device.type != .cdj
            ? hostDevice.id : queryIdPicker(device.id, Array(deviceManager.devices.values))
        try await socket.write(
            Message(transactionId: 0xfffffffe, type: .introduce, args: [RemoteDBUInt32(queryId)]).buffer)
        // 소개 요청과 같은 번호(0xfffffffe)로 답한다. 다른 번호의 메시지는 건너뛴다(PLAN §9, #46).
        _ = try await Message.fromStream(socket, .success, tx, expectedTransactionId: 0xfffffffe, logger: logger)
        socket.setTimeout(0, onTimeout: nil)
        connections[device.id] = Connection(
            device: device, socket: socket, matchesTransactionIds: true, logger: logger)
        queryIds[device.id] = queryId
        tx.finish()
    }
    public func disconnectFromDevice(_ device: Device) async {
        guard let conn = connections[device.id] else { return }
        let tx = Telemetry.startTransaction(SpanContext(name: "disconnectFromDevice"))
        try? await conn.writeMessage(Message(transactionId: 0xfffffffe, type: .disconnect, args: []), tx)
        conn.close()
        connections.removeValue(forKey: device.id)
        queryIds.removeValue(forKey: device.id)
        tx.finish()
    }
    public func get(_ deviceId: DeviceID) async throws -> QueryInterface? {
        guard let device = deviceManager.devices[deviceId] else { return nil }
        let lock = deviceLocks[deviceId] ?? AsyncMutex()
        deviceLocks[deviceId] = lock
        return try await lock.runExclusive {
            if let conn = connections[deviceId], !conn.isOpen {
                conn.close()
                connections.removeValue(forKey: deviceId)
                queryIds.removeValue(forKey: deviceId)
            }
            if connections[deviceId] == nil { try await connectToDevice(device) }
            var host = hostDevice
            host.id = queryIds[deviceId] ?? host.id
            return QueryInterface(conn: connections[deviceId]!, lock: lock, hostDevice: host)
        }
    }
}
