import DJLinkKit

let networkTestInterface = NetworkInterfaceInfo(
    address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
    mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24")

@DJLinkActor
final class NetworkRemoteDatabaseMock: NetworkRemoteDatabase {
    let hostDeviceRef: DeviceReference
    var hostDevice: Device { hostDeviceRef.device }
    var disconnected: [Device] = []
    init(_ hostDevice: DeviceReference) { hostDeviceRef = hostDevice }
    func getDBQuery(_ deviceId: DeviceID) async throws -> (any DBQueryInterface)? { nil }
    func connectToDevice(_ device: Device) async throws {}
    func disconnectFromDevice(_ device: Device) async { disconnected.append(device) }
}

@DJLinkActor
final class NetworkLocalDatabaseMock: NetworkLocalDatabase {
    let emitter = EventHub<LocalDatabase>()
    let hostDeviceRef: DeviceReference
    var preference: DatabasePreference
    var disconnected: [Device] = []
    init(_ hostDevice: DeviceReference, _ preference: DatabasePreference) {
        hostDeviceRef = hostDevice
        self.preference = preference
    }
    func get(_ deviceId: DeviceID, _ slot: MediaSlot) async throws -> (any DatabaseAdapter)? { nil }
    func findTrack(_ deviceId: DeviceID, _ slot: MediaSlot, _ trackId: Int, _ hint: TrackLookupHint) async throws
        -> TrackLookup
    {
        .init(dbAdapter: nil, track: nil, switchedTo: nil)
    }
    func getDatabaseType(_ deviceId: DeviceID, _ slot: MediaSlot) -> DatabaseType? { nil }
    func disconnectForDevice(_ device: Device) { disconnected.append(device) }
    func preload() async throws {}
}

@DJLinkActor
final class NetworkUnifiedDatabaseMock: NetworkDatabase {
    let hostDeviceRef: DeviceReference
    var hostDevice: Device { hostDeviceRef.device }
    init(_ hostDevice: DeviceReference) { hostDeviceRef = hostDevice }
    func getDatabaseType(_ deviceId: DeviceID, _ slot: MediaSlot) -> DatabaseType? { nil }
    func getMetadata(_ opts: GetMetadata.Options) async throws -> Track? { nil }
    func getFile(_ opts: GetFile.Options) async throws -> [UInt8]? { nil }
    func getArtworkThumbnail(_ opts: GetArtworkThumbnail.Options) async throws -> [UInt8]? { nil }
    func getArtwork(_ opts: GetArtworkFromFile.Options) async -> [UInt8]? { nil }
    func getWaveforms(_ opts: GetWaveforms.Options) async throws -> Waveforms? { nil }
    func getTrackAnalysis(_ opts: GetTrackAnalysis.Options) async throws -> TrackAnalysis? { nil }
    func getPlaylist(_ opts: GetPlaylist.Options) async throws -> PlaylistContents? { nil }
}

@DJLinkActor
final class NetworkDatabaseMocks {
    var remote: NetworkRemoteDatabaseMock?
    var local: NetworkLocalDatabaseMock?
    var database: NetworkUnifiedDatabaseMock?
    var constructionOrder: [String] = []
    var dependencies: NetworkDependencies {
        NetworkDependencies(
            makeRemoteDatabase: { _, hostDevice, _ in
                self.constructionOrder.append("remote")
                let result = NetworkRemoteDatabaseMock(hostDevice)
                self.remote = result
                return result
            },
            makeLocalDatabase: { hostDevice, _, _, preference, _ in
                self.constructionOrder.append("local")
                let result = NetworkLocalDatabaseMock(hostDevice, preference)
                self.local = result
                return result
            },
            makeDatabase: { _, _, _, _, hostDevice in
                self.constructionOrder.append("database")
                let result = NetworkUnifiedDatabaseMock(hostDevice)
                self.database = result
                return result
            })
    }
}
