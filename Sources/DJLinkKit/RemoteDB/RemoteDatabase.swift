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
    private let socket: any TCPConnection
    private var txId = 0
    private let lock = AsyncMutex()
    public var device: Device
    public init(device: Device, socket: any TCPConnection) {
        self.device = device
        self.socket = socket
    }
    public func writeMessage(_ message: Message, _ span: TelemetrySpan = TelemetrySpan()) async throws {
        let tx = span.startChild(SpanContext(op: "writeMessage", description: getMessageName(message.type)))
        txId += 1
        message.transactionId = txId
        try await socket.write(message.buffer)
        tx.finish()
    }
    public func readMessage(_ expect: Response, _ span: TelemetrySpan = TelemetrySpan()) async throws -> Message {
        try await lock.runExclusive { try await Message.fromStream(socket, expect, span) }
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
            let result = try await handler(conn, descriptor, args, tx)
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
    private let queryIdPicker: @DJLinkActor (DeviceID, [Device]) -> DeviceID
    private var connections: [DeviceID: Connection] = [:]
    private var deviceLocks: [DeviceID: AsyncMutex] = [:]
    private var queryIds: [DeviceID: DeviceID] = [:]
    public init(
        deviceManager: any RemoteDBDeviceSource, hostDevice: DeviceReference, pickQueryId: Bool = true,
        socketFactory: any SocketFactory = LiveSocketFactory.shared, serverQueryPort: Int = REMOTEDB_SERVER_QUERY_PORT,
        queryIdPicker: @escaping @DJLinkActor (DeviceID, [Device]) -> DeviceID = { pickRemoteDbQueryId($0, $1) }
    ) {
        self.deviceManager = deviceManager
        self.hostDeviceRef = hostDevice
        self.pickQueryId = pickQueryId
        self.socketFactory = socketFactory
        self.serverQueryPort = serverQueryPort
        self.queryIdPicker = queryIdPicker
    }

    /// 나눠 쥘 필요가 없을 때(시험 등) 장치 값으로 만든다.
    public convenience init(
        deviceManager: any RemoteDBDeviceSource, hostDevice: Device, pickQueryId: Bool = true,
        socketFactory: any SocketFactory = LiveSocketFactory.shared, serverQueryPort: Int = REMOTEDB_SERVER_QUERY_PORT,
        queryIdPicker: @escaping @DJLinkActor (DeviceID, [Device]) -> DeviceID = { pickRemoteDbQueryId($0, $1) }
    ) {
        self.init(
            deviceManager: deviceManager, hostDevice: DeviceReference(hostDevice), pickQueryId: pickQueryId,
            socketFactory: socketFactory, serverQueryPort: serverQueryPort, queryIdPicker: queryIdPicker)
    }
    public func connectToDevice(_ device: Device) async throws {
        let tx = Telemetry.startTransaction(SpanContext(name: "connectRemotedb"))
        let portConn = try socketFactory.createTCPConnection()
        try await portConn.connect(port: serverQueryPort, host: device.ip.address)
        try await portConn.write([0, 0, 0, 0x0f] + [UInt8]("RemoteDBServer", encoding: .ascii) + [0])
        guard let resp = try await portConn.read(nil) else { throw DJLinkError("Invalid response from remotedb") }
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
        _ = try await Message.fromStream(socket, .success, tx)
        socket.setTimeout(0, onTimeout: nil)
        connections[device.id] = Connection(device: device, socket: socket)
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
