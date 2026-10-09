import Foundation

package let connectErrorHelp =
    "Network must be configured. Try using `autoconfigFromPeers` or `configure`"

private enum NetworkAnnouncer {
    case active(Announcer)
    case stagehand(StagehandAnnouncer)

    @DJLinkActor func start() throws {
        switch self {
        case .active(let service): try service.start()
        case .stagehand(let service): try service.start()
        }
    }

    @DJLinkActor func stop() {
        switch self {
        case .active(let service): service.stop()
        case .stagehand(let service): service.stop()
        }
    }

    @DJLinkActor var rejectedDeviceId: DeviceID? {
        if case .active(let service) = self { return service.rejectedDeviceId }
        return nil
    }

    @DJLinkActor var ready: Void {
        get async {
            switch self {
            case .active(let service): await service.ready
            case .stagehand(let service): await service.ready
            }
        }
    }
}

@DJLinkActor
public final class ProlinkNetwork {
    private struct ConnectionService {
        let vcdj: DeviceReference
        let announcer: NetworkAnnouncer
        let heartbeat: StagehandHeartbeat?
        let remotedb: any NetworkRemoteDatabase
        let localdb: any NetworkLocalDatabase
        let database: any NetworkDatabase
    }

    public private(set) var state: NetworkState = .online
    private let announceSocket: any UDPSocket
    package let connectionBeatSocket: any UDPSocket
    package let connectionStatusSocket: any UDPSocket
    public let deviceManager: DeviceManager
    private let networkStatusEmitter: StatusEmitter
    private let networkPositionEmitter: PositionEmitter
    private var logger: any Logger
    private var config: NetworkConfig?
    private var connection: ConnectionService?
    private var mixstatusProcessor: MixstatusProcessor?
    private let socketFactory: any SocketFactory
    private let interfaceProvider: any InterfaceProvider
    private let clock: any DJLinkClock
    private let dependencies: NetworkDependencies

    /// 별도 타깃의 Control 같은 연결 서비스를 해당 연결에 저장한다.
    package var extensionServices: [String: AnyObject] = [:]
    package var connectionDeviceReference: DeviceReference? { connection?.vcdj }

    /// 원본 @internal 생성자. 시험과 별도 소켓 소유자가 구성한 서비스를 넘긴다.
    public init(
        config: NetworkConfig? = nil,
        announceSocket: any UDPSocket, beatSocket: any UDPSocket, statusSocket: any UDPSocket,
        deviceManager: DeviceManager, statusEmitter: StatusEmitter, positionEmitter: PositionEmitter,
        socketFactory: any SocketFactory = LiveSocketFactory.shared,
        interfaceProvider: any InterfaceProvider = SystemInterfaceProvider(),
        clock: any DJLinkClock = SystemClock.shared, dependencies: NetworkDependencies = .init()
    ) {
        self.config = config
        self.logger = config?.logger ?? noopLogger
        self.announceSocket = announceSocket
        self.connectionBeatSocket = beatSocket
        self.connectionStatusSocket = statusSocket
        self.deviceManager = deviceManager
        self.networkStatusEmitter = statusEmitter
        self.networkPositionEmitter = positionEmitter
        self.socketFactory = socketFactory
        self.interfaceProvider = interfaceProvider
        self.clock = clock
        self.dependencies = dependencies
    }

    public func configure(_ config: NetworkConfig) {
        var merged = self.config ?? NetworkConfig()
        merged.merge(config)
        self.config = merged
        if let logger = config.logger { self.logger = logger }
    }

    public func autoconfigFromPeers() async throws {
        let tx = Telemetry.startTransaction(.init(name: "autoConfigure"))
        let firstDevice = await withCheckedContinuation { (continuation: CheckedContinuation<Device, Never>) in
            deviceManager.once(.connected) { continuation.resume(returning: $0) }
        }
        let iface = try getMatchingInterface(firstDevice.ip, interfaceProvider: interfaceProvider)
        tx.setTag("deviceName", firstDevice.name)
        tx.setData("deviceAddr", firstDevice.ip.address)
        tx.setData("ifaceAddr", iface?.info.address)
        guard let iface else {
            tx.setStatus(.internalError)
            tx.setTag("noIfaceFound", "yes")
            tx.finish()
            throw DJLinkError("Unable to determine network interface")
        }
        let defaultId = config?.connectMethod == .stagehand ? generateStagehandDeviceId() : DEFAULT_VCDJ_ID
        var merged = config ?? NetworkConfig()
        merged.vcdjId = defaultId
        merged.iface = iface.info
        config = merged
        tx.finish()
    }

    public func connect() throws {
        guard var config else { throw DJLinkError(connectErrorHelp) }
        let tx = Telemetry.startTransaction(.init(name: "connect"))
        let connectMethod = config.connectMethod ?? .active
        // CLI 안전을 위한 추가(기본값은 원본 동작). Stagehand 전체 송신 경로에 정책을 적용할 수 없으면 거부한다.
        if connectMethod == .stagehand,
            config.allowsDeviceId != nil || config.announceTargetFilter != nil || config.onDeviceIdRejected != nil
        {
            throw DJLinkError("Stagehand connection does not support the configured CLI safety policies")
        }
        let vcdjId = config.vcdjId ?? (connectMethod == .stagehand ? generateStagehandDeviceId() : DEFAULT_VCDJ_ID)
        config.vcdjId = vcdjId
        self.config = config
        let vcdjName = config.vcdjName ?? (connectMethod == .stagehand ? "Stagehand" : nil)
        // 원본과 다름: 불완전한 Partial 설정의 undefined iface 오류를 Swift 오류로 표현한다.
        guard let iface = config.iface else {
            throw DJLinkError("Cannot read properties of undefined (reading 'address')")
        }
        let vcdj = DeviceReference(
            try connectMethod == .stagehand
                ? getVirtualStagehand(iface, vcdjId, vcdjName) : getVirtualCDJ(iface, vcdjId, vcdjName))
        if let vcdjName { deviceManager.reconfigure(.init(vcdjName: vcdjName)) }
        let announcer: NetworkAnnouncer
        if connectMethod == .stagehand {
            announcer = .stagehand(
                StagehandAnnouncer(vcdj, announceSocket, deviceManager, iface, logger: logger, clock: clock))
        } else {
            announcer = .active(
                Announcer(
                    vcdj, announceSocket, deviceManager, iface,
                    fullStartup: config.fullStartup ?? false, announceToStagehand: config.announceToStagehand ?? false,
                    logger: logger, clock: clock, allowsDeviceId: config.allowsDeviceId,
                    onDeviceIdRejected: config.onDeviceIdRejected, announceTargetFilter: config.announceTargetFilter))
        }
        try announcer.start()
        var heartbeat: StagehandHeartbeat?
        if connectMethod == .stagehand {
            heartbeat = StagehandHeartbeat(vcdj, connectionStatusSocket, deviceManager, logger: logger, clock: clock)
            heartbeat?.start()
        }
        let remotedb = dependencies.makeRemoteDatabase(deviceManager, vcdj, socketFactory)
        let localdb = dependencies.makeLocalDatabase(
            vcdj, deviceManager, networkStatusEmitter, config.databasePreference ?? .auto, clock)
        let database = dependencies.makeDatabase(localdb, remotedb, deviceManager, logger, vcdj)
        // 원본과 다름: Control은 별도 타깃 확장에서 처음 접근할 때 만든다.
        // 다시 connect하면 원본처럼 새 Control을 쓰고, disconnect·close에서는 이전 것을 유지한다.
        extensionServices.removeAll()
        state = .connected
        connection = ConnectionService(
            vcdj: vcdj, announcer: announcer, heartbeat: heartbeat,
            remotedb: remotedb, localdb: localdb, database: database)
        tx.finish()
    }

    /// 원본은 close를 호출하지 않고 함수 자체를 반환한다. 상태와 연결 서비스도 유지한다.
    @discardableResult
    public func disconnect() throws -> @DJLinkActor () async throws -> Void {
        guard config != nil else { throw DJLinkError(connectErrorHelp) }
        connection?.announcer.stop()
        connection?.heartbeat?.stop()
        for device in deviceManager.devices.values {
            if let remotedb {
                // 원본도 비동기 DB 종료를 기다리지 않는다.
                Task { @DJLinkActor in await remotedb.disconnectFromDevice(device) }
            }
            localdb?.disconnectForDevice(device)
        }
        return { try await self.close() }
    }

    public func close() async throws {
        // Promise.all처럼 모두 시작하고, 하나가 실패하면 나머지 종료를 취소하지 않는다.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            var remaining = 3
            var settled = false
            for socket in [announceSocket, connectionStatusSocket, connectionBeatSocket] {
                Task { @DJLinkActor in
                    do {
                        try await udpClose(socket)
                        remaining -= 1
                        if remaining == 0, !settled {
                            settled = true
                            continuation.resume()
                        }
                    } catch {
                        if !settled {
                            settled = true
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }

    public var isConfigured: Bool { config != nil }
    public func isConnected() -> Bool { state == .connected }
    public var statusEmitter: StatusEmitter? { state == .connected ? networkStatusEmitter : nil }
    public var positionEmitter: PositionEmitter? { state == .connected ? networkPositionEmitter : nil }
    public var virtualDevice: Device? { connection?.vcdj.device }
    public var db: (any NetworkDatabase)? { connection?.database }
    public var localdb: (any NetworkLocalDatabase)? { connection?.localdb }
    public var remotedb: (any NetworkRemoteDatabase)? { connection?.remotedb }

    /// CLI 안전 정책의 startup 번호 거부 상태.
    public var startupRejectedDeviceId: DeviceID? { connection?.announcer.rejectedDeviceId }

    /// startupReady가 끝난 뒤 번호 거부를 오류로 구별한다.
    public func waitUntilReady() async throws {
        await startupReady
        if let startupRejectedDeviceId {
            throw DJLinkError("Device ID \(startupRejectedDeviceId) is not allowed")
        }
    }

    public var startupReady: Void {
        get async {
            if let connection { await connection.announcer.ready }
        }
    }

    public var mixstatus: MixstatusProcessor? {
        guard connection != nil else { return nil }
        if mixstatusProcessor == nil {
            let processor = MixstatusProcessor(clock: clock)
            mixstatusProcessor = processor
            // 원본처럼 구독이 처리기를 쥔다(network를 놓아도 처리기는 계속 상태를 받는다).
            networkStatusEmitter.on(.status) { status in processor.handleState(status) }
        }
        return mixstatusProcessor
    }
}

@DJLinkActor
public func bringOnline(
    _ config: NetworkConfig? = nil,
    socketFactory: any SocketFactory = LiveSocketFactory.shared,
    interfaceProvider: any InterfaceProvider = SystemInterfaceProvider(),
    clock: any DJLinkClock = SystemClock.shared, dependencies: NetworkDependencies = .init()
) async throws -> ProlinkNetwork {
    Telemetry.setTag("connectionId", UUID().uuidString)
    let tx = Telemetry.startTransaction(.init(name: "bringOnline"))
    let announceSocket = try socketFactory.createUDPSocket(reuseAddr: true)
    let beatSocket = try socketFactory.createUDPSocket(reuseAddr: true)
    let statusSocket = try socketFactory.createUDPSocket(reuseAddr: true)
    do {
        try await udpBind(announceSocket, ANNOUNCE_PORT, "0.0.0.0")
        try await udpBind(beatSocket, BEAT_PORT, "0.0.0.0")
        try await udpBind(statusSocket, STATUS_PORT, "0.0.0.0")
        announceSocket.setBroadcast(true)
    } catch {
        Telemetry.captureException(error)
        tx.setStatus(.unavailable)
        tx.finish()
        throw error
    }
    let stagehandMode = config?.connectMethod == .stagehand
    let deviceManager = DeviceManager(announceSocket, clock: clock)
    let statusEmitter = StatusEmitter(statusSocket, stagehandMode: stagehandMode, clock: clock)
    let positionEmitter = PositionEmitter(beatSocket, stagehandMode: stagehandMode)
    tx.finish()
    return ProlinkNetwork(
        config: config, announceSocket: announceSocket, beatSocket: beatSocket, statusSocket: statusSocket,
        deviceManager: deviceManager, statusEmitter: statusEmitter, positionEmitter: positionEmitter,
        socketFactory: socketFactory, interfaceProvider: interfaceProvider, clock: clock, dependencies: dependencies)
}

@DJLinkActor
public func bringOnlineStagehand(
    _ config: NetworkConfig? = nil,
    socketFactory: any SocketFactory = LiveSocketFactory.shared,
    interfaceProvider: any InterfaceProvider = SystemInterfaceProvider(),
    clock: any DJLinkClock = SystemClock.shared, dependencies: NetworkDependencies = .init()
) async throws -> ProlinkNetwork {
    var config = config ?? NetworkConfig()
    config.connectMethod = .stagehand
    return try await bringOnline(
        config, socketFactory: socketFactory, interfaceProvider: interfaceProvider, clock: clock,
        dependencies: dependencies)
}
