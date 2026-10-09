@DJLinkActor public protocol DBLocalDatabase: AnyObject {
    func get(_ deviceId: DeviceID, _ slot: MediaSlot) async throws -> (any DatabaseAdapter)?
    func findTrack(_ deviceId: DeviceID, _ slot: MediaSlot, _ trackId: Int, _ hint: TrackLookupHint) async throws
        -> TrackLookup
    func getDatabaseType(_ deviceId: DeviceID, _ slot: MediaSlot) -> DatabaseType?
}
@DJLinkActor public protocol DBQueryInterface: AnyObject {
    func query(queryDescriptor: QueryDescriptor, query: Query, args: RemoteDBQueryArgs, span: TelemetrySpan?)
        async throws -> RemoteDBQueryResult
}
@DJLinkActor public protocol DBRemoteDatabase: AnyObject {
    var hostDevice: Device { get }
    func getDBQuery(_ deviceId: DeviceID) async throws -> (any DBQueryInterface)?
}
@DJLinkActor public protocol DBDeviceSource: AnyObject {
    func getDeviceEnsured(_ id: DeviceID, timeout: Int) async -> Device?
}

extension LocalDatabase: DBLocalDatabase {}
extension QueryInterface: DBQueryInterface {}
extension RemoteDatabase: DBRemoteDatabase {
    // 원본 get의 구체 반환형을 유지하고 프로토콜로 넓히는 창구만 더한다.
    public func getDBQuery(_ deviceId: DeviceID) async throws -> (any DBQueryInterface)? { try await get(deviceId) }
}
extension DeviceManager: DBDeviceSource {}

@DJLinkActor public struct DBDependencies {
    public var loadAnlz: @DJLinkActor (Track, String, AnlzResolver) async throws -> AnlzResponse
    public var fetchFile:
        @DJLinkActor (Device, MediaSlot, String, (@DJLinkActor (FetchProgress) -> Void)?, Int?) async throws -> [UInt8]
    public var extractArtworkFromDevice:
        @DJLinkActor (Device, MediaSlot, String, any Logger) async throws -> ExtractedArtwork?
    public init(
        loadAnlz: @escaping @DJLinkActor (Track, String, AnlzResolver) async throws -> AnlzResponse = {
            track, type, resolver in
            try await DJLinkKit.loadAnlz(track, type: type, anlzResolver: resolver)
        },
        fetchFile:
            @escaping @DJLinkActor (Device, MediaSlot, String, (@DJLinkActor (FetchProgress) -> Void)?, Int?)
            async throws -> [UInt8] = { device, slot, path, progress, chunkSize in
                try await DJLinkKit.fetchFile(
                    device: device, slot: slot, path: path, onProgress: progress, chunkSize: chunkSize)
            },
        extractArtworkFromDevice:
            @escaping @DJLinkActor (Device, MediaSlot, String, any Logger) async throws -> ExtractedArtwork? = {
                device, slot, path, logger in
                try await DJLinkKit.extractArtworkFromDevice(device, slot, path, logger)
            }
    ) {
        self.loadAnlz = loadAnlz
        self.fetchFile = fetchFile
        self.extractArtworkFromDevice = extractArtworkFromDevice
    }
}

extension TrackLookup {
    /// DB 주입점을 구현하는 외부 가짜도 로컬 조회 결과를 만들 수 있다.
    public init(dbAdapter: (any DatabaseAdapter)?, track: Track?, switchedTo: DatabaseType?) {
        self.init(adapter: dbAdapter, track: track, switchedTo: switchedTo)
    }
}
