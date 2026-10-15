import DJLinkKit

@DJLinkActor
public final class PassiveRemoteDatabase {
    private let deviceManager: PassiveDeviceManager
    private let virtualDeviceId: Int
    private let socketFactory: any SocketFactory
    private var connections: [DeviceID: Connection] = [:]
    private var deviceLocks: [DeviceID: AsyncMutex] = [:]
    public init(
        _ deviceManager: PassiveDeviceManager, virtualDeviceId: Int = 5,
        socketFactory: any SocketFactory = LiveSocketFactory.shared
    ) {
        self.deviceManager = deviceManager
        self.virtualDeviceId = virtualDeviceId
        self.socketFactory = socketFactory
    }
    private func getRemoteDBServerPort(_ deviceIp: String) async throws -> Int {
        let conn = try socketFactory.createTCPConnection()
        try await conn.connect(port: REMOTEDB_SERVER_QUERY_PORT, host: deviceIp)
        try await conn.write([0x00, 0x00, 0x00, 0x0f] + [UInt8]("RemoteDBServer", encoding: .ascii) + [0])
        let resp = try await conn.read(nil)
        conn.destroy(nil)
        guard let resp else { throw DJLinkError("Invalid response from remotedb") }
        guard resp.count == 2 else { throw DJLinkError("Expected 2 bytes, got \(resp.count)") }
        return try resp.readUInt16BE()
    }
    public func connectToDevice(_ device: Device) async throws {
        let tx = Telemetry.startTransaction(SpanContext(name: "passiveConnectRemotedb"))
        tx.setData("device", device)
        let dbPort = try await getRemoteDBServerPort(device.ip.address)
        let socket = try socketFactory.createTCPConnection()
        try await socket.connect(port: dbPort, host: device.ip.address)
        try await socket.write(RemoteDBUInt32(0x01).buffer)
        let data = try await readField(socket, .uint32) as! RemoteDBUInt32
        guard data.value == 0x01 else {
            throw DJLinkError("Expected 0x01 during preamble handshake. Got \(data.value)")
        }
        let intro = Message(transactionId: 0xfffffffe, type: .introduce, args: [RemoteDBUInt32(virtualDeviceId)])
        try await socket.write(intro.buffer)
        // 소개 요청과 같은 번호(0xfffffffe)로 답한다. 다른 번호의 메시지는 건너뛴다(PLAN §9, #46).
        let resp = try await Message.fromStream(socket, .success, tx, expectedTransactionId: 0xfffffffe)
        guard resp.type == .success else { throw DJLinkError("Failed to introduce self to device ID: \(device.id)") }
        connections[device.id] = Connection(device: device, socket: socket, matchesTransactionIds: true)
        tx.finish()
    }
    public func disconnectFromDevice(_ device: Device) async {
        guard let conn = connections[device.id] else { return }
        do {
            let tx = Telemetry.startTransaction(SpanContext(name: "passiveDisconnectFromDevice"))
            tx.setData("device", device)
            try await conn.writeMessage(Message(transactionId: 0xfffffffe, type: .disconnect, args: []), tx)
            tx.finish()
        } catch {}
        conn.close()
        connections.removeValue(forKey: device.id)
    }
    public func get(_ deviceId: DeviceID) async throws -> QueryInterface? {
        guard let device = deviceManager.devices[deviceId] else { return nil }
        let lock = deviceLocks[device.id] ?? AsyncMutex()
        deviceLocks[device.id] = lock
        await lock.acquire()
        // PLAN §9(#47): 질의 시간 제한이 닫은 연결은 버리고 새로 연결한다(능동 `RemoteDatabase.get`과 같다).
        if let closed = connections[deviceId], !closed.isOpen {
            closed.close()
            connections.removeValue(forKey: deviceId)
        }
        var conn = connections[deviceId]
        if conn == nil {
            do {
                try await connectToDevice(device)
                conn = connections[deviceId]
            } catch {
                lock.release()
                throw error
            }
        }
        lock.release()
        guard let conn else { return nil }
        let host = Device(
            name: "alphatheta-connect", id: virtualDeviceId, type: .cdj, macAddr: [0, 0, 0, 0, 0, 0], ip: device.ip)
        return QueryInterface(conn: conn, lock: lock, hostDevice: host)
    }
    // 원본과 다름: 기반 query의 판별 결과 형을 유지해 비정수 year도 잃지 않는다.
    public func getTrackMetadata(deviceId: DeviceID, trackSlot: MediaSlot, trackType: TrackType, trackId: Int)
        async throws -> RemoteDBQueryResult?
    {
        try await metadata(deviceId, trackSlot, trackType, trackId, .getMetadata)
    }
    public func getGenericTrackMetadata(deviceId: DeviceID, trackSlot: MediaSlot, trackType: TrackType, trackId: Int)
        async throws -> RemoteDBQueryResult?
    {
        try await metadata(deviceId, trackSlot, trackType, trackId, .getGenericMetadata)
    }
    private func metadata(_ deviceId: DeviceID, _ slot: MediaSlot, _ type: TrackType, _ trackId: Int, _ query: Query)
        async throws -> RemoteDBQueryResult?
    {
        guard let conn = try await get(deviceId) else { return nil }
        let descriptor = QueryDescriptor(menuTarget: .main, trackSlot: slot, trackType: type)
        do {
            var result = try await conn.query(
                queryDescriptor: descriptor, query: query, args: RemoteDBQueryArgs(trackId: trackId))
            do {
                if case let .path(path) = try await conn.query(
                    queryDescriptor: descriptor, query: .getTrackInfo, args: RemoteDBQueryArgs(trackId: trackId))
                {
                    switch result {
                    case .track(var track):
                        track.filePath = path
                        result = .track(track)
                    case .trackWithRawYear(var track, let year):
                        track.filePath = path
                        result = .trackWithRawYear(track: track, year: year)
                    default: break
                    }
                }
            } catch {}
            return result
        } catch {
            connections.removeValue(forKey: deviceId)
            throw error
        }
    }
    public func stop() {
        for conn in connections.values { conn.close() }
        connections.removeAll()
    }
}
