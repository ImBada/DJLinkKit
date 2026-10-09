import DJLinkKit
import DJLinkTestSupport
import Foundation
import Synchronization

func dbTrack(_ id: Int, _ title: String = "", tempo: Double = 0) -> Track {
    Track(id: id, title: title, duration: 0, tempo: tempo, rating: 0, comment: "", filePath: "", fileName: "")
}

final class DBTestLogger: Logger {
    private let messages = Mutex<[String: [String]]>([:])
    var warnings: [String] { messages.withLock { $0["warn", default: []] } }
    var infos: [String] { messages.withLock { $0["info", default: []] } }
    func trace(_ msg: String, _ args: [any Sendable]) {}
    func debug(_ msg: String, _ args: [any Sendable]) {}
    func info(_ msg: String, _ args: [any Sendable]) { messages.withLock { $0["info", default: []].append(msg) } }
    func warn(_ msg: String, _ args: [any Sendable]) { messages.withLock { $0["warn", default: []].append(msg) } }
    func error(_ msg: String, _ args: [any Sendable]) {}
}

@DJLinkActor final class DBTestAdapter: DatabaseAdapter {
    var type: DatabaseType = .pdb
    var tracks: [Int: Track] = [:]
    var trackCalls: [Int] = []
    var playlistResult = PlaylistQueryResult()
    func findTrack(_ id: Int) throws -> Track? {
        trackCalls.append(id)
        return tracks[id]
    }
    func findPlaylist(_ playlistId: Int?) throws -> PlaylistQueryResult { playlistResult }
    func close() {}
}

@DJLinkActor final class DBTestLocal: DBLocalDatabase {
    var adapter: (any DatabaseAdapter)?
    var switchedTo: DatabaseType?
    var lookupCalls: [(DeviceID, MediaSlot, Int, TrackLookupHint)] = []
    init(_ adapter: (any DatabaseAdapter)?, switchedTo: DatabaseType? = nil) {
        self.adapter = adapter
        self.switchedTo = switchedTo
    }
    func get(_ deviceId: DeviceID, _ slot: MediaSlot) async throws -> (any DatabaseAdapter)? { adapter }
    func findTrack(_ deviceId: DeviceID, _ slot: MediaSlot, _ trackId: Int, _ hint: TrackLookupHint) async throws
        -> TrackLookup
    {
        lookupCalls.append((deviceId, slot, trackId, hint))
        let track = try adapter?.findTrack(trackId)
        return TrackLookup(dbAdapter: adapter, track: track, switchedTo: track == nil ? nil : switchedTo)
    }
    func getDatabaseType(_ deviceId: DeviceID, _ slot: MediaSlot) -> DatabaseType? { adapter?.type }
}

@DJLinkActor final class DBTestQuery: DBQueryInterface {
    var calls: [(Query, RemoteDBQueryArgs)] = []
    var handler: @DJLinkActor (Query, RemoteDBQueryArgs) async throws -> RemoteDBQueryResult
    init(_ handler: @escaping @DJLinkActor (Query, RemoteDBQueryArgs) async throws -> RemoteDBQueryResult) {
        self.handler = handler
    }
    func query(queryDescriptor: QueryDescriptor, query: Query, args: RemoteDBQueryArgs, span: TelemetrySpan?)
        async throws -> RemoteDBQueryResult
    {
        calls.append((query, args))
        return try await handler(query, args)
    }
}

@DJLinkActor final class DBTestRemote: DBRemoteDatabase {
    var hostDevice: Device
    var connection: (any DBQueryInterface)?
    var getCalls: [DeviceID] = []
    var error: (any Error)?
    init(_ connection: (any DBQueryInterface)?, hostId: Int = 5) {
        self.connection = connection
        self.hostDevice = mockDevice(id: hostId)
    }
    func getDBQuery(_ deviceId: DeviceID) async throws -> (any DBQueryInterface)? {
        getCalls.append(deviceId)
        if let error { throw error }
        return connection
    }
}

@DJLinkActor final class DBTestDevices: DBDeviceSource {
    var device: Device? = mockDevice(
        id: 3, name: "CDJ-3000", ip: try! Address4("192.168.1.3"), macAddr: Array(repeating: 0, count: 6))
    func getDeviceEnsured(_ id: DeviceID, timeout: Int) async -> Device? { device }
}

@DJLinkActor func dbDependencies() -> DBDependencies {
    DBDependencies(loadAnlz: { _, _, _ in AnlzResponse() })
}
