import CryptoKit
import DJLinkKit
import Foundation

/// 4단계의 DatabasePreference·DatabaseType에 연결할 seam.
public enum PassiveLocalDBPreference: String, Sendable { case auto, oneLibrary, pdb }
public enum PassiveLocalDBType: String, Sendable { case oneLibrary, pdb }
public struct PassiveLocalDBPlaylistQueryResult: Equatable, Sendable {
    public var folders: [Playlist]
    public var playlists: [Playlist]
    public var trackEntries: [PlaylistEntryWithFKs]
    public init(folders: [Playlist], playlists: [Playlist], trackEntries: [PlaylistEntryWithFKs]) {
        self.folders = folders
        self.playlists = playlists
        self.trackEntries = trackEntries
    }
}
@DJLinkActor
public protocol PassiveLocalDBAdapter: AnyObject {
    var type: PassiveLocalDBType { get }
    func findTrack(id: Int) throws -> Track?
    func findPlaylist(playlistId: Int?) throws -> PassiveLocalDBPlaylistQueryResult
    func close()
}
public struct PassiveLocalDBHydrationProgress: Equatable, Sendable {
    public var table: String
    public var total: Int
    public var complete: Int
    public init(table: String, total: Int, complete: Int) {
        self.table = table
        self.total = total
        self.complete = complete
    }
}
/// 실제 MetadataORM·hydrator·OneLibraryAdapter만 4단계 뒤에 둔다.
@DJLinkActor
public protocol PassiveLocalDBBackend: AnyObject {
    func makeMetadataORM() throws -> any PassiveLocalDBAdapter
    func hydrateDatabase(
        orm: any PassiveLocalDBAdapter, pdbData: [UInt8], span: TelemetrySpan,
        onProgress: @escaping @DJLinkActor (PassiveLocalDBHydrationProgress) -> Void) async throws
    func makeOneLibraryAdapter(tempFile: String) throws -> any PassiveLocalDBAdapter
}
public typealias PassiveLocalDBFileFetcher =
    @DJLinkActor (Device, MediaSlot, String, TelemetrySpan, @escaping @DJLinkActor (FetchProgress) -> Void) async throws
    -> [UInt8]
@DJLinkActor
public protocol PassiveLocalDBFileSystem {
    func tmpdir() -> String
    func writeFileSync(_ path: String, _ data: [UInt8]) throws
    func unlinkSync(_ path: String) throws
}
public struct PassiveLocalDBSystemFileSystem: PassiveLocalDBFileSystem {
    public init() {}
    public func tmpdir() -> String { NSTemporaryDirectory() }
    public func writeFileSync(_ path: String, _ data: [UInt8]) throws {
        try Data(data).write(to: URL(fileURLWithPath: path))
    }
    public func unlinkSync(_ path: String) throws { try FileManager.default.removeItem(atPath: path) }
}
@DJLinkActor private var passiveLocalDBBackend: (any PassiveLocalDBBackend)?
@DJLinkActor public func configurePassiveLocalDBBackend(_ backend: any PassiveLocalDBBackend) {
    passiveLocalDBBackend = backend
}

public struct PassiveLocalDBDownloadProgressOpts: Sendable {
    public var device: Device
    public var slot: MediaSlot
    public var progress: FetchProgress
}
public struct PassiveLocalDBHydrationProgressOpts: Sendable {
    public var device: Device
    public var slot: MediaSlot
    public var progress: PassiveLocalDBHydrationProgress
}
public struct PassiveLocalDBHydrationDoneOpts: Sendable {
    public var device: Device
    public var slot: MediaSlot
}
private struct DatabaseItem {
    var id: String
    var media: MediaSlotInfo
    var adapter: any PassiveLocalDBAdapter
    var tempFile: String?
}
func getMediaId(_ info: MediaSlotInfo) -> String {
    // 원본 Array.join은 Date.toString을 쓴다. ISO 문자열로 바꾸면 캐시 키가 달라진다.
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'Z"
    let style: TimeZone.NameStyle =
        TimeZone.current.isDaylightSavingTime(for: info.createdDate) ? .daylightSaving : .standard
    let zoneName = TimeZone.current.localizedName(for: style, locale: Locale(identifier: "en_US")) ?? ""
    let date = formatter.string(from: info.createdDate) + " (\(zoneName))"
    let inputs = [
        String(info.deviceId), String(info.slot.rawValue), info.name, String(info.freeBytes), String(info.totalBytes),
        String(info.trackCount), date,
    ]
    return SHA256.hash(data: Data(inputs.joined(separator: ".").utf8)).map { String(format: "%02x", $0) }.joined()
}

@DJLinkActor
public final class PassiveLocalDatabase: EventEmitting {
    public let emitter = EventHub<PassiveLocalDatabase>()
    private let deviceManager: PassiveDeviceManager
    private let statusEmitter: PassiveStatusEmitter
    private var slotLocks: [String: AsyncMutex] = [:]
    private var dbs: [DatabaseItem] = []
    private var mediaCache: [String: MediaSlotInfo] = [:]
    private var mediaOrder: [String] = []
    public var preference: PassiveLocalDBPreference
    private let backend: (any PassiveLocalDBBackend)?
    private let fetcher: PassiveLocalDBFileFetcher
    private let fileSystem: any PassiveLocalDBFileSystem
    private let platform: String
    private let clock: any DJLinkClock
    private var disconnectedSubscription: EventSubscription?
    private var mediaSubscription: EventSubscription?
    public init(
        _ deviceManager: PassiveDeviceManager, _ statusEmitter: PassiveStatusEmitter,
        preference: PassiveLocalDBPreference = .auto, backend: (any PassiveLocalDBBackend)? = nil,
        platform: String = PassivePlatform.current, clock: any DJLinkClock = SystemClock.shared,
        fileSystem: any PassiveLocalDBFileSystem = PassiveLocalDBSystemFileSystem(),
        fetcher: @escaping PassiveLocalDBFileFetcher = { device, slot, path, span, progress in
            try await DJLinkKit.fetchFile(device: device, slot: slot, path: path, onProgress: progress, span: span)
        }
    ) {
        self.deviceManager = deviceManager
        self.statusEmitter = statusEmitter
        self.preference = preference
        self.backend = backend ?? passiveLocalDBBackend ?? DJLinkKitPassiveLocalDBBackend()
        self.platform = platform
        self.clock = clock
        self.fetcher = fetcher
        self.fileSystem = fileSystem
        disconnectedSubscription = deviceManager.on(.disconnected) { [weak self] device in
            self?.handleDeviceRemoved(device)
        }
        mediaSubscription = statusEmitter.on(.mediaSlot) { [weak self] info in self?.handleMediaSlot(info) }
    }
    public func getCachedMedia(_ deviceId: DeviceID, _ slot: MediaSlot) -> MediaSlotInfo? {
        mediaCache["\(deviceId)-\(slot.rawValue)"]
    }
    public func getAllCachedMedia() -> [MediaSlotInfo] { mediaOrder.compactMap { mediaCache[$0] } }
    public func disconnectForDevice(_ device: Device) { handleDeviceRemoved(device) }
    public func stop() {
        if let disconnectedSubscription { deviceManager.off(disconnectedSubscription) }
        if let mediaSubscription { statusEmitter.off(mediaSubscription) }
        for db in dbs { cleanup(db) }
        dbs.removeAll()
        mediaCache.removeAll()
        mediaOrder.removeAll()
    }
    private func cleanup(_ db: DatabaseItem) {
        db.adapter.close()
        if let tempFile = db.tempFile { try? fileSystem.unlinkSync(tempFile) }
    }
    private func handleMediaSlot(_ info: MediaSlotInfo) {
        let key = "\(info.deviceId)-\(info.slot.rawValue)"
        if mediaCache[key] == nil { mediaOrder.append(key) }
        mediaCache[key] = info
    }
    private func handleDeviceRemoved(_ device: Device) {
        // 원본은 find로 첫 DB만 닫고 filter로 해당 장치의 모든 DB를 뺀다. 그대로 둔다.
        if let db = dbs.first(where: { $0.media.deviceId == device.id }) { cleanup(db) }
        dbs.removeAll { $0.media.deviceId == device.id }
        let keys = mediaOrder.filter { $0.hasPrefix("\(device.id)-") }
        for key in keys { mediaCache.removeValue(forKey: key) }
        mediaOrder.removeAll { $0.hasPrefix("\(device.id)-") }
    }
    private func fetchFileWithFallback(_ device: Device, _ slot: MediaSlot, _ basePath: String, _ tx: TelemetrySpan)
        async throws -> [UInt8]
    {
        let order = platform == "win32" ? [basePath, ".\(basePath)"] : [".\(basePath)", basePath]
        let progress: @DJLinkActor (FetchProgress) -> Void = { [self] progress in
            emitter.emit(.fetchProgress, .init(device: device, slot: slot, progress: progress))
        }
        do { return try await fetcher(device, slot, order[0], tx, progress) } catch {
            return try await fetcher(device, slot, order[1], tx, progress)
        }
    }
    private func requireBackend() throws -> any PassiveLocalDBBackend {
        guard let backend else { throw DJLinkError("PassiveLocalDB backend is not connected") }
        return backend
    }
    private func tryLoadOneLibrary(_ device: Device, _ slot: MediaSlot, _ tx: TelemetrySpan) async -> (
        adapter: any PassiveLocalDBAdapter, tempFile: String
    )? {
        do {
            let data = try await fetchFileWithFallback(device, slot, "PIONEER/rekordbox/exportLibrary.db", tx)
            let tempFile = URL(fileURLWithPath: fileSystem.tmpdir()).appendingPathComponent(
                "prolink-onelibrary-\(device.id)-\(slot.rawValue)-\(Int64(clock.nowMilliseconds())).db"
            ).path
            try fileSystem.writeFileSync(tempFile, data)
            let adapter = try requireBackend().makeOneLibraryAdapter(tempFile: tempFile)
            return (adapter, tempFile)
        } catch { return nil }
    }
    private func loadPdbDatabase(_ device: Device, _ slot: MediaSlot, _ tx: TelemetrySpan) async throws
        -> any PassiveLocalDBAdapter
    {
        let pdbData = try await fetchFileWithFallback(device, slot, "PIONEER/rekordbox/export.pdb", tx)
        let dbCreateTx = tx.startChild(SpanContext(op: "setupDatabase"))
        let backend = try requireBackend()
        let orm = try backend.makeMetadataORM()
        dbCreateTx.finish()
        try await backend.hydrateDatabase(orm: orm, pdbData: pdbData, span: tx) { [self] progress in
            emitter.emit(.hydrationProgress, .init(device: device, slot: slot, progress: progress))
        }
        return orm
    }
    private func hydrateDatabase(_ device: Device, _ slot: MediaSlot, _ media: MediaSlotInfo) async throws
        -> DatabaseItem
    {
        let tx = Telemetry.startTransaction(SpanContext(name: "hydrateDatabase"))
        tx.setTag("slot", getSlotName(media.slot) ?? "undefined")
        tx.setData("numTracks", String(media.trackCount))
        tx.setTag("preference", preference.rawValue)
        let adapter: any PassiveLocalDBAdapter
        var tempFile: String?
        if preference == .pdb {
            adapter = try await loadPdbDatabase(device, slot, tx)
            tx.setTag("dbType", "pdb")
        } else if preference == .oneLibrary {
            guard let result = await tryLoadOneLibrary(device, slot, tx) else {
                throw DJLinkError("OneLibrary database not found and preference is set to oneLibrary only")
            }
            adapter = result.adapter
            tempFile = result.tempFile
            tx.setTag("dbType", "oneLibrary")
        } else if let result = await tryLoadOneLibrary(device, slot, tx) {
            adapter = result.adapter
            tempFile = result.tempFile
            tx.setTag("dbType", "oneLibrary")
        } else {
            adapter = try await loadPdbDatabase(device, slot, tx)
            tx.setTag("dbType", "pdb")
        }
        emitter.emit(.hydrationDone, .init(device: device, slot: slot))
        let db = DatabaseItem(id: getMediaId(media), media: media, adapter: adapter, tempFile: tempFile)
        dbs.append(db)
        tx.finish()
        return db
    }
    public func get(_ deviceId: DeviceID, _ slot: MediaSlot) async throws -> (any PassiveLocalDBAdapter)? {
        let cachedMedia = getCachedMedia(deviceId, slot)
        guard let device = deviceManager.devices[deviceId] else { return nil }
        if let cachedMedia { return try await getWithMedia(device, slot, cachedMedia) }
        return await getWithoutMedia(device, slot)
    }
    public func getWithMedia(_ device: Device, _ slot: MediaSlot, _ media: MediaSlotInfo) async throws -> (
        any PassiveLocalDBAdapter
    )? {
        let lockKey = "\(device.id)-\(slot.rawValue)"
        let lock = slotLocks[lockKey] ?? AsyncMutex()
        slotLocks[lockKey] = lock
        guard eligible(device), media.tracksType == .rb else { return nil }
        let id = getMediaId(media)
        let db = try await lock.runExclusive {
            if let cached = dbs.first(where: { $0.id == id }) { return cached }
            return try await hydrateDatabase(device, slot, media)
        }
        return db.adapter
    }
    public func getWithoutMedia(_ device: Device, _ slot: MediaSlot) async -> (any PassiveLocalDBAdapter)? {
        let lockKey = "\(device.id)-\(slot.rawValue)-nomedia"
        let lock = slotLocks[lockKey] ?? AsyncMutex()
        slotLocks[lockKey] = lock
        guard eligible(device) else { return nil }
        if let existing = dbs.first(where: { $0.media.deviceId == device.id && $0.media.slot == slot }) {
            return existing.adapter
        }
        do {
            let db = try await lock.runExclusive {
                if let cached = dbs.first(where: { $0.media.deviceId == device.id && $0.media.slot == slot }) {
                    return cached
                }
                let media = MediaSlotInfo(
                    deviceId: device.id, slot: slot, name: "Unknown Media", color: .default,
                    createdDate: Date(timeIntervalSince1970: 0), freeBytes: 0, totalBytes: 0, tracksType: .rb,
                    trackCount: 0, playlistCount: 0, hasSettings: false)
                return try await hydrateDatabase(device, slot, media)
            }
            return db.adapter
        } catch { return nil }
    }
    private func eligible(_ device: Device) -> Bool {
        device.type == .cdj && device.id >= MIN_CDJ_DEVICE_ID && device.id <= MAX_CDJ_DEVICE_ID
    }
    public func preload() async throws {
        let devices = deviceManager.deviceValues.filter(eligible)
        guard !devices.isEmpty else { return }
        // 원본 Promise.all처럼 첫 실패를 바로 돌려주고 나머지 로더는 취소하지 않는다.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            final class State {
                var remaining = 0
                var settled = false
            }
            let state = State()
            state.remaining = devices.count * 2
            for device in devices {
                for slot in [MediaSlot.usb, .sd] {
                    Task { @DJLinkActor in
                        do {
                            _ = try await get(device.id, slot)
                            state.remaining -= 1
                            if !state.settled && state.remaining == 0 {
                                state.settled = true
                                continuation.resume()
                            }
                        } catch {
                            if !state.settled {
                                state.settled = true
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }
        }
    }
}
extension EventName where Owner == PassiveLocalDatabase, Payload == PassiveLocalDBDownloadProgressOpts {
    public static var fetchProgress: Self { .init("fetchProgress") }
}
extension EventName where Owner == PassiveLocalDatabase, Payload == PassiveLocalDBHydrationProgressOpts {
    public static var hydrationProgress: Self { .init("hydrationProgress") }
}
extension EventName where Owner == PassiveLocalDatabase, Payload == PassiveLocalDBHydrationDoneOpts {
    public static var hydrationDone: Self { .init("hydrationDone") }
}
