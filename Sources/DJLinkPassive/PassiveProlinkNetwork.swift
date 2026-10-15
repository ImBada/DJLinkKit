import DJLinkKit

public struct PassiveNetworkConfig: Equatable, Sendable {
    public var iface: String
    public var bufferSize: Int?
    public var deviceTimeout: Double?
    public var databasePreference: DatabasePreference?
    public init(
        iface: String, bufferSize: Int? = nil, deviceTimeout: Double? = nil,
        databasePreference: DatabasePreference? = nil
    ) {
        self.iface = iface
        self.bufferSize = bufferSize
        self.deviceTimeout = deviceTimeout
        self.databasePreference = databasePreference
    }
}
@DJLinkActor
public final class PassiveProlinkNetwork {
    public let adapter: PcapAdapter
    public let deviceManager: PassiveDeviceManager
    public let statusEmitter: PassiveStatusEmitter
    public let positionEmitter: PassivePositionEmitter
    public let beatEmitter: PassiveBeatEmitter
    public let localdb: PassiveLocalDatabase
    private var remoteDatabase: PassiveRemoteDatabase?
    private var mixstatusProcessor: MixstatusProcessor?
    private let socketFactory: any SocketFactory
    private let clock: any DJLinkClock
    public init(
        _ config: PassiveNetworkConfig, backend: (any PcapBackend)? = nil,
        localDBBackend: (any PassiveLocalDBBackend)? = nil,
        platform: String = PassivePlatform.current,
        interfaceProvider: any InterfaceProvider = SystemInterfaceProvider(),
        socketFactory: any SocketFactory = LiveSocketFactory.shared, clock: any DJLinkClock = SystemClock.shared,
        localDBFetcher: @escaping PassiveLocalDBFileFetcher = { device, slot, path, span, progress in
            try await DJLinkKit.fetchFile(device: device, slot: slot, path: path, onProgress: progress, span: span)
        }
    ) {
        self.socketFactory = socketFactory
        self.clock = clock
        adapter = PcapAdapter(
            config: .init(iface: config.iface, bufferSize: config.bufferSize), backend: backend, platform: platform,
            interfaceProvider: interfaceProvider, clock: clock)
        deviceManager = PassiveDeviceManager(
            adapter, config: config.deviceTimeout.map { .init(deviceTimeout: $0) }, clock: clock)
        statusEmitter = PassiveStatusEmitter(adapter)
        positionEmitter = PassivePositionEmitter(adapter)
        beatEmitter = PassiveBeatEmitter(adapter)
        localdb = PassiveLocalDatabase(
            deviceManager, statusEmitter, preference: config.databasePreference ?? .auto, backend: localDBBackend,
            platform: platform, clock: clock, fetcher: localDBFetcher)
    }
    public func start() throws { try adapter.start() }
    public func stop() {
        deviceManager.stop()
        statusEmitter.stop()
        positionEmitter.stop()
        beatEmitter.stop()
        localdb.stop()
        remoteDatabase?.stop()
        adapter.stop()
    }
    public var isCapturing: Bool { adapter.isCapturing }
    public var interfaceName: String { adapter.interfaceName }
    public var remotedb: PassiveRemoteDatabase {
        if remoteDatabase == nil { remoteDatabase = PassiveRemoteDatabase(deviceManager, socketFactory: socketFactory) }
        return remoteDatabase!
    }
    public var mixstatus: MixstatusProcessor {
        if mixstatusProcessor == nil {
            mixstatusProcessor = MixstatusProcessor(clock: clock)
            statusEmitter.on(.status) { [weak self] status in self?.mixstatusProcessor?.handleState(status) }
        }
        return mixstatusProcessor!
    }
}
@DJLinkActor
public func bringOnlinePassive(
    _ config: PassiveNetworkConfig, backend: (any PcapBackend)? = nil,
    localDBBackend: (any PassiveLocalDBBackend)? = nil,
    platform: String = PassivePlatform.current, interfaceProvider: any InterfaceProvider = SystemInterfaceProvider(),
    socketFactory: any SocketFactory = LiveSocketFactory.shared, clock: any DJLinkClock = SystemClock.shared
) throws -> PassiveProlinkNetwork {
    let network = PassiveProlinkNetwork(
        config, backend: backend, localDBBackend: localDBBackend, platform: platform,
        interfaceProvider: interfaceProvider, socketFactory: socketFactory, clock: clock)
    try network.start()
    return network
}
public struct PassiveInterface: Equatable, Sendable {
    public var name: String
    public var address: String
    public var description: String?
}
public func listInterfaces(interfaceProvider: any InterfaceProvider = SystemInterfaceProvider()) -> [PassiveInterface] {
    interfaceProvider.networkInterfaces().flatMap { name, infos in
        infos.filter { $0.family == "IPv4" && !$0.internal }.map {
            PassiveInterface(
                name: name, address: $0.address,
                description: $0.address.hasPrefix("169.254.") ? "Link-local (USB device?)" : nil)
        }
    }
}
