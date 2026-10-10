/// 원본 network 시험의 DB 모듈 바꿔치기. 실제 서비스의 공개 조회 창구를 그대로 둔다.
@DJLinkActor
public protocol NetworkRemoteDatabase: DBRemoteDatabase {
    func connectToDevice(_ device: Device) async throws
    func disconnectFromDevice(_ device: Device) async
}

extension NetworkRemoteDatabase {
    public func get(_ deviceId: DeviceID) async throws -> (any DBQueryInterface)? {
        try await getDBQuery(deviceId)
    }
}

extension DBQueryInterface {
    /// 구체 QueryInterface의 기본 span 인자를 프로토콜 조회 결과에서도 그대로 제공한다.
    public func query(
        queryDescriptor: QueryDescriptor, query: Query, args: RemoteDBQueryArgs
    ) async throws -> RemoteDBQueryResult {
        try await self.query(queryDescriptor: queryDescriptor, query: query, args: args, span: nil)
    }
}

@DJLinkActor
public protocol NetworkLocalDatabase: DBLocalDatabase {
    var emitter: EventHub<LocalDatabase> { get }
    var preference: DatabasePreference { get set }
    func disconnectForDevice(_ device: Device)
    func preload() async throws
}

extension NetworkLocalDatabase {
    public func getDatabaseType(deviceId: DeviceID, slot: MediaSlot) -> DatabaseType? {
        getDatabaseType(deviceId, slot)
    }

    public func findTrack(_ deviceId: DeviceID, _ slot: MediaSlot, _ trackId: Int) async throws -> TrackLookup {
        try await findTrack(deviceId, slot, trackId, .init())
    }

    @discardableResult
    public func on<Payload>(
        _ event: EventName<LocalDatabase, Payload>, _ handler: @escaping @DJLinkActor (Payload) -> Void
    ) -> EventSubscription {
        emitter.on(event, handler)
    }

    @discardableResult
    public func once<Payload>(
        _ event: EventName<LocalDatabase, Payload>, _ handler: @escaping @DJLinkActor (Payload) -> Void
    ) -> EventSubscription {
        emitter.once(event, handler)
    }

    public func off(_ subscription: EventSubscription) { emitter.off(subscription) }

    public func events<Payload: Sendable>(_ event: EventName<LocalDatabase, Payload>) -> AsyncStream<Payload> {
        emitter.stream(event)
    }
}

@DJLinkActor
public protocol NetworkDatabase: AnyObject {
    var hostDevice: Device { get }
    func getDatabaseType(_ deviceId: DeviceID, _ slot: MediaSlot) -> DatabaseType?
    func getMetadata(_ opts: GetMetadata.Options) async throws -> Track?
    func getFile(_ opts: GetFile.Options) async throws -> [UInt8]?
    func getArtworkThumbnail(_ opts: GetArtworkThumbnail.Options) async throws -> [UInt8]?
    func getArtwork(_ opts: GetArtworkFromFile.Options) async -> [UInt8]?
    func getWaveforms(_ opts: GetWaveforms.Options) async throws -> Waveforms?
    func getTrackAnalysis(_ opts: GetTrackAnalysis.Options) async throws -> TrackAnalysis?
    func getPlaylist(_ opts: GetPlaylist.Options) async throws -> PlaylistContents?
}

extension NetworkDatabase {
    public func getDatabaseType(deviceId: DeviceID, slot: MediaSlot) -> DatabaseType? {
        getDatabaseType(deviceId, slot)
    }
}

extension RemoteDatabase: NetworkRemoteDatabase {}
extension LocalDatabase: NetworkLocalDatabase {}
extension Database: NetworkDatabase {}

@DJLinkActor
public struct NetworkDependencies {
    public var makeRemoteDatabase:
        @DJLinkActor (DeviceManager, DeviceReference, any SocketFactory) -> any NetworkRemoteDatabase
    public var makeLocalDatabase:
        @DJLinkActor (DeviceReference, DeviceManager, StatusEmitter, DatabasePreference, any DJLinkClock)
            -> any NetworkLocalDatabase
    public var makeDatabase:
        @DJLinkActor (any NetworkLocalDatabase, any NetworkRemoteDatabase, DeviceManager, any Logger, DeviceReference)
            -> any NetworkDatabase

    public init(
        makeRemoteDatabase:
            @escaping @DJLinkActor (DeviceManager, DeviceReference, any SocketFactory)
            -> any NetworkRemoteDatabase = {
                RemoteDatabase(deviceManager: $0, hostDevice: $1, socketFactory: $2)
            },
        makeLocalDatabase:
            @escaping @DJLinkActor (DeviceReference, DeviceManager, StatusEmitter, DatabasePreference, any DJLinkClock)
            -> any NetworkLocalDatabase = {
                LocalDatabase(hostDevice: $0, deviceManager: $1, statusEmitter: $2, preference: $3, clock: $4)
            },
        makeDatabase:
            @escaping @DJLinkActor (
                any NetworkLocalDatabase, any NetworkRemoteDatabase, DeviceManager, any Logger, DeviceReference
            ) -> any NetworkDatabase = {
                Database(local: $0, remote: $1, deviceManager: $2, logger: $3, hostDevice: $4)
            }
    ) {
        self.makeRemoteDatabase = makeRemoteDatabase
        self.makeLocalDatabase = makeLocalDatabase
        self.makeDatabase = makeDatabase
    }
}
