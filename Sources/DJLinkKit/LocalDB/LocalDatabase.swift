import CryptoKit
import Foundation

public struct TrackLookupHint: Equatable, Sendable {
    public var trackBPM: Double?
    public init(trackBPM: Double? = nil) { self.trackBPM = trackBPM }
}
@DJLinkActor public struct TrackLookup {
    public var adapter: (any DatabaseAdapter)?
    public var track: Track?
    public var switchedTo: DatabaseType?
}
public func trackAgreesWithPlayer(_ track: Track, _ hint: TrackLookupHint) -> Bool {
    guard let reported = hint.trackBPM, track.tempo != 0, !track.tempo.isNaN else { return true }
    return abs(track.tempo - reported) < 0.05
}
public func getMediaId(_ info: MediaSlotInfo) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'Z '('zzzz')'"
    let inputs = [
        String(info.deviceId), String(info.slot.rawValue), info.name, String(info.freeBytes),
        String(info.totalBytes), String(info.trackCount), formatter.string(from: info.createdDate),
    ]
    return SHA256.hash(data: Data(inputs.joined(separator: ".").utf8)).map {
        String(format: "%02x", $0)
    }.joined()
}
public struct LocalDBCommonProgressOpts: Equatable, Sendable {
    public var device: Device
    public var slot: MediaSlot
}
public struct LocalDBDownloadProgressOpts: Equatable, Sendable {
    public var device: Device
    public var slot: MediaSlot
    public var progress: LocalDBFetchProgress
}
public struct LocalDBHydrationProgressOpts: Equatable, Sendable {
    public var device: Device
    public var slot: MediaSlot
    public var progress: HydrationProgress
}
extension EventName where Owner == LocalDatabase, Payload == LocalDBDownloadProgressOpts {
    public static var fetchProgress: Self { .init("fetchProgress") }
}
extension EventName where Owner == LocalDatabase, Payload == LocalDBHydrationProgressOpts {
    public static var hydrationProgress: Self { .init("hydrationProgress") }
}
extension EventName where Owner == LocalDatabase, Payload == LocalDBCommonProgressOpts {
    public static var hydrationDone: Self { .init("hydrationDone") }
}

// 원본 localdb/index.ts
@DJLinkActor public final class LocalDatabase: EventEmitting {
    private struct LoadedAdapter {
        var adapter: any DatabaseAdapter
        var tempFile: String?
    }
    private final class DatabaseItem {
        var loaded: LoadedAdapter
        let id: String
        let media: MediaSlotInfo
        let device: Device
        let slot: MediaSlot
        var alternate: LoadedAdapter?
        var alternateTried = false
        let alternateLock = AsyncMutex()
        init(loaded: LoadedAdapter, media: MediaSlotInfo, device: Device, slot: MediaSlot) {
            self.loaded = loaded
            self.media = media
            self.device = device
            self.slot = slot
            id = getMediaId(media)
        }
    }
    /// 원본은 가상 CDJ `Device` 객체를 network·announcer와 나눠 쥐고, 번호가 바뀌면 그대로 따라간다.
    private let hostDeviceRef: DeviceReference
    private var hostDevice: Device { hostDeviceRef.device }
    private let deviceManager: any LocalDBDeviceSource
    private let statusEmitter: any LocalDBMediaSlotSource
    private let dependencies: LocalDBDependencies
    private let clock: any DJLinkClock
    private let throwsOnMediaQueryFailure: Bool
    public let emitter = EventHub<LocalDatabase>()
    private var slotLocks: [String: AsyncMutex] = [:]
    private var dbs: [DatabaseItem] = []
    public var preference: DatabasePreference
    public convenience init(
        hostDevice: Device, deviceManager: any LocalDBDeviceSource,
        statusEmitter: any LocalDBMediaSlotSource,
        preference: DatabasePreference = .auto, dependencies: LocalDBDependencies = .init(),
        clock: any DJLinkClock = SystemClock.shared, throwsOnMediaQueryFailure: Bool = false
    ) {
        self.init(
            hostDevice: DeviceReference(hostDevice), deviceManager: deviceManager, statusEmitter: statusEmitter,
            preference: preference, dependencies: dependencies, clock: clock,
            throwsOnMediaQueryFailure: throwsOnMediaQueryFailure)
    }
    public init(
        hostDevice: DeviceReference, deviceManager: any LocalDBDeviceSource,
        statusEmitter: any LocalDBMediaSlotSource,
        preference: DatabasePreference = .auto, dependencies: LocalDBDependencies = .init(),
        clock: any DJLinkClock = SystemClock.shared, throwsOnMediaQueryFailure: Bool = false
    ) {
        self.hostDeviceRef = hostDevice
        self.deviceManager = deviceManager
        self.statusEmitter = statusEmitter
        self.preference = preference
        self.dependencies = dependencies
        self.clock = clock
        self.throwsOnMediaQueryFailure = throwsOnMediaQueryFailure
        deviceManager.on("disconnected") { [self] device in handleDeviceRemoved(device) }
    }
    public func disconnectForDevice(_ device: Device) { handleDeviceRemoved(device) }
    private func handleDeviceRemoved(_ device: Device) {
        for db in dbs where db.media.deviceId == device.id {
            closeLoaded(db.loaded)
            if let alternate = db.alternate { closeLoaded(alternate) }
        }
        dbs.removeAll { $0.media.deviceId == device.id }
    }
    private func closeLoaded(_ loaded: LoadedAdapter) {
        loaded.adapter.close()
        if let path = loaded.tempFile { try? dependencies.fileSystem.unlinkSync(path) }
    }
    private func fetchFileWithFallback(
        device: Device, slot: MediaSlot, basePath: String, tx: TelemetrySpan
    ) async throws -> [UInt8] {
        let attemptOrder =
            dependencies.platform == "win32" ? [basePath, ".\(basePath)"] : [".\(basePath)", basePath]
        func options(_ path: String) -> LocalDBFetchFileOptions {
            .init(
                device: device, slot: slot, path: path, span: tx,
                onProgress: { [self] progress in
                    emitter.emit(.fetchProgress, .init(device: device, slot: slot, progress: progress))
                })
        }
        do { return try await dependencies.fetchFile(options(attemptOrder[0])) } catch {
            return try await dependencies.fetchFile(options(attemptOrder[1]))
        }
    }
    private func tryLoadOneLibrary(device: Device, slot: MediaSlot, tx: TelemetrySpan) async
        -> LoadedAdapter?
    {
        do {
            let data = try await fetchFileWithFallback(
                device: device, slot: slot, basePath: "PIONEER/rekordbox/exportLibrary.db", tx: tx)
            let tempFile = URL(filePath: dependencies.fileSystem.tmpdir).appending(
                path: "prolink-onelibrary-\(device.id)-\(slot.rawValue)-\(clock.nowMilliseconds()).db"
            ).path
            try dependencies.fileSystem.writeFileSync(tempFile, data)
            let adapter = try dependencies.makeOneLibraryAdapter(tempFile)
            return .init(adapter: adapter, tempFile: tempFile)
        } catch { return nil }
    }
    private func loadPdbDatabase(device: Device, slot: MediaSlot, tx: TelemetrySpan) async throws
        -> any DatabaseAdapter
    {
        let data = try await fetchFileWithFallback(
            device: device, slot: slot, basePath: "PIONEER/rekordbox/export.pdb", tx: tx)
        let dbCreateTx = tx.startChild(.init(op: "setupDatabase"))
        let orm = try dependencies.makeMetadataORM()
        dbCreateTx.finish()
        try await dependencies.hydrateDatabase(
            .init(
                orm: orm, pdbData: data, span: tx,
                onProgress: { [self] progress in
                    emitter.emit(.hydrationProgress, .init(device: device, slot: slot, progress: progress))
                }))
        return orm
    }
    private func hydrateDatabase(device: Device, slot: MediaSlot, media: MediaSlotInfo) async throws
        -> DatabaseItem
    {
        let tx = dependencies.startTransaction(.init(name: "hydrateDatabase"))
        tx.setTag("slot", slot.jsName ?? "Unknown")
        tx.setData("numTracks", String(media.trackCount))
        tx.setTag("preference", preference.rawValue)
        let loaded: LoadedAdapter
        if preference == .pdb {
            loaded = .init(adapter: try await loadPdbDatabase(device: device, slot: slot, tx: tx))
            tx.setTag("dbType", "pdb")
        } else if preference == .oneLibrary {
            guard let result = await tryLoadOneLibrary(device: device, slot: slot, tx: tx) else {
                throw DJLinkError("OneLibrary database not found and preference is set to oneLibrary only")
            }
            loaded = result
            tx.setTag("dbType", "oneLibrary")
        } else if let result = await tryLoadOneLibrary(device: device, slot: slot, tx: tx) {
            loaded = result
            tx.setTag("dbType", "oneLibrary")
        } else {
            loaded = .init(adapter: try await loadPdbDatabase(device: device, slot: slot, tx: tx))
            tx.setTag("dbType", "pdb")
        }
        emitter.emit(.hydrationDone, .init(device: device, slot: slot))
        let db = DatabaseItem(loaded: loaded, media: media, device: device, slot: slot)
        dbs.append(db)
        tx.finish()
        return db
    }
    private func loadAlternate(_ db: DatabaseItem) async -> LoadedAdapter? {
        await db.alternateLock.runExclusive {
            if db.alternateTried { return db.alternate }
            if preference != .auto {
                db.alternateTried = true
                return nil
            }
            let tx = dependencies.startTransaction(.init(name: "hydrateAlternateDatabase"))
            tx.setTag("slot", db.media.slot.jsName ?? "Unknown")
            tx.setTag("activeDbType", db.loaded.adapter.type.rawValue)
            do {
                if db.loaded.adapter.type == .oneLibrary {
                    db.alternate = .init(
                        adapter: try await loadPdbDatabase(device: db.device, slot: db.slot, tx: tx))
                    tx.setTag("dbType", "pdb")
                } else {
                    db.alternate = await tryLoadOneLibrary(device: db.device, slot: db.slot, tx: tx)
                    tx.setTag("dbType", db.alternate == nil ? "none" : "oneLibrary")
                }
            } catch { db.alternate = nil }
            db.alternateTried = true
            tx.finish()
            return db.alternate
        }
    }
    public func findTrack(
        _ deviceId: DeviceID, _ slot: MediaSlot, _ trackId: Int, _ hint: TrackLookupHint = .init()
    ) async throws -> TrackLookup {
        guard let db = try await getItem(deviceId, slot) else {
            return .init(adapter: nil, track: nil, switchedTo: nil)
        }
        let active = try db.loaded.adapter.findTrack(trackId)
        if let active, trackAgreesWithPlayer(active, hint) {
            return .init(adapter: db.loaded.adapter, track: active, switchedTo: nil)
        }
        if let alternate = await loadAlternate(db),
            let other = try alternate.adapter.findTrack(trackId), trackAgreesWithPlayer(other, hint)
        {
            db.alternate = db.loaded
            db.loaded = alternate
            return .init(adapter: db.loaded.adapter, track: other, switchedTo: db.loaded.adapter.type)
        }
        return .init(adapter: db.loaded.adapter, track: active, switchedTo: nil)
    }
    public func get(_ deviceId: DeviceID, _ slot: MediaSlot) async throws -> (any DatabaseAdapter)? {
        try await getItem(deviceId, slot)?.loaded.adapter
    }
    private func getItem(_ deviceId: DeviceID, _ slot: MediaSlot) async throws -> DatabaseItem? {
        let lockKey = "\(deviceId)-\(slot.rawValue)"
        let lock = slotLocks[lockKey] ?? AsyncMutex()
        slotLocks[lockKey] = lock
        guard let device = deviceManager.devices[deviceId], device.type == .cdj,
            device.id >= MIN_CDJ_DEVICE_ID, device.id <= MAX_CDJ_DEVICE_ID
        else { return nil }
        let media: MediaSlotInfo
        do {
            media = try await statusEmitter.queryMediaSlot(
                hostDevice: hostDevice, device: device, slot: slot)
        } catch {
            // CLI 안전을 위한 추가(기본값은 원본 동작). 실패를 데이터 없음과 구별한다.
            if throwsOnMediaQueryFailure { throw error }
            return nil
        }
        guard media.tracksType == .rb else { return nil }
        let id = getMediaId(media)
        return try await lock.runExclusive {
            if let cached = dbs.first(where: { $0.id == id }) { return cached }
            return try await hydrateDatabase(device: device, slot: slot, media: media)
        }
    }
    public func getDatabaseType(_ deviceId: DeviceID, _ slot: MediaSlot) -> DatabaseType? {
        getDatabaseType(deviceId: deviceId, slot: slot)
    }
    public func getDatabaseType(deviceId: DeviceID, slot: MediaSlot) -> DatabaseType? {
        dbs.first { $0.media.deviceId == deviceId && $0.media.slot == slot }?.loaded.adapter.type
    }
    public func preload() async throws {
        let cdjDevices = deviceManager.devices.values.filter {
            $0.type == .cdj && $0.id >= MIN_CDJ_DEVICE_ID && $0.id <= MAX_CDJ_DEVICE_ID
        }
        guard !cdjDevices.isEmpty else { return }
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            var remaining = cdjDevices.count * 2
            var settled = false
            for device in cdjDevices {
                for slot in [MediaSlot.usb, .sd] {
                    Task { @DJLinkActor in
                        do {
                            _ = try await get(device.id, slot)
                            remaining -= 1
                            if remaining == 0 && !settled {
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
    }
}
