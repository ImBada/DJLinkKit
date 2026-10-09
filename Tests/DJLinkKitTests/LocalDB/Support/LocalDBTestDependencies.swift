import Foundation

@testable import DJLinkKit

func localDBTestMedia(
    deviceId: DeviceID = 3, slot: MediaSlot = .usb, name: String = "SSD Stream",
    freeBytes: UInt64 = 0, totalBytes: UInt64 = 0, trackCount: Int = 55378,
    createdDate: Date = Date(timeIntervalSince1970: 0)
) -> MediaSlotInfo {
    .init(
        deviceId: deviceId, slot: slot, name: name, color: .default, createdDate: createdDate,
        freeBytes: freeBytes, totalBytes: totalBytes, tracksType: .rb, trackCount: trackCount,
        playlistCount: 0, hasSettings: false)
}
let localDBTestCDJ = Device(
    name: "CDJ-3000", id: 3, type: .cdj, macAddr: [UInt8](repeating: 0, count: 6),
    ip: try! Address4("192.168.1.3"))
let localDBTestHost = Device(name: "", id: 7, type: .cdj, macAddr: [], ip: try! Address4("0.0.0.0"))
@DJLinkActor final class LocalDBFakeDeviceSource: LocalDBDeviceSource {
    var devices: [DeviceID: Device] = [3: localDBTestCDJ]
    var handlers: [@DJLinkActor (Device) -> Void] = []
    func on(_ event: String, _ handler: @escaping @DJLinkActor (Device) -> Void) {
        handlers.append(handler)
    }
}
@DJLinkActor final class LocalDBFakeMediaSlotSource: LocalDBMediaSlotSource {
    var media = localDBTestMedia()
    var error: (any Error)?
    func queryMediaSlot(hostDevice: Device, device: Device, slot: MediaSlot) async throws
        -> MediaSlotInfo
    {
        if let error { throw error }
        return media
    }
}
@DJLinkActor final class LocalDBFakeFileSystem: LocalDBFileSystem {
    var tmpdir = "/tmp"
    var writes: [(String, [UInt8])] = []
    var unlinks: [String] = []
    func writeFileSync(_ path: String, _ data: [UInt8]) { writes.append((path, data)) }
    func unlinkSync(_ path: String) { unlinks.append(path) }
}
@DJLinkActor final class LocalDBFakeAdapter: DatabaseAdapter {
    let type: DatabaseType
    var rows: [Track]
    var closeCalls = 0
    var findTrackCalls: [Int] = []
    init(type: DatabaseType, rows: [Track]) {
        self.type = type
        self.rows = rows
    }
    func close() { closeCalls += 1 }
    func findTrack(_ id: Int) -> Track? {
        findTrackCalls.append(id)
        return rows.first { $0.id == id }
    }
    func findPlaylist(_ playlistId: Int?) -> PlaylistQueryResult { .init() }
}
@DJLinkActor final class LocalDBFallbackHarness {
    let devices = LocalDBFakeDeviceSource()
    let status = LocalDBFakeMediaSlotSource()
    let fs = LocalDBFakeFileSystem()
    let oneLibrary: LocalDBFakeAdapter
    let pdb: LocalDBFakeAdapter
    var paths: [String] = []
    var files: [String] = ["exportLibrary.db", "export.pdb"]
    init() {
        func row(_ id: Int, _ title: String, _ tempo: Double) -> Track {
            .init(
                id: id, title: title, duration: 0, tempo: tempo, rating: 0, comment: "", filePath: "",
                fileName: "")
        }
        oneLibrary = .init(
            type: .oneLibrary,
            rows: [
                row(3078, "Purpura - Focused (Original Mix)", 126), row(500, "Only in OneLibrary", 140),
            ])
        pdb = .init(
            type: .pdb,
            rows: [
                row(32657, "The track deck 3 is playing", 128),
                row(3078, "The track deck 5 is playing", 130),
            ])
    }
    func makeLocalDatabase(_ preference: DatabasePreference = .auto) -> LocalDatabase {
        let dependencies = LocalDBDependencies(
            fetchFile: { [self] options in
                paths.append(options.path)
                guard files.contains(where: options.path.hasSuffix) else {
                    throw DJLinkError("NFS: no such file \(options.path)")
                }
                return Array(options.path.utf8)
            }, fileSystem: fs, makeOneLibraryAdapter: { [self] _ in oneLibrary },
            makeMetadataORM: { [self] in pdb }, hydrateDatabase: { _ in })
        return .init(
            hostDevice: localDBTestHost, deviceManager: devices, statusEmitter: status,
            preference: preference, dependencies: dependencies)
    }
    func downloadsOf(_ file: String) -> Int { paths.filter { $0.hasSuffix(file) }.count }
}

// 모든 표가 타이머를 걸기 전까지 시험 시계를 밀지 않는다. 실제 시간 제한에 기대지 않는다.
@DJLinkActor final class LocalDBHydrationTestGate {
    private let expected: Int
    private var reports = 0
    private var finished = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(expected: Int) { self.expected = expected }
    func report() {
        reports += 1
        if reports >= expected { resume() }
    }
    func finish() {
        finished = true
        resume()
    }
    func wait() async {
        if reports >= expected || finished { return }
        await withCheckedContinuation { continuation = $0 }
    }
    private func resume() {
        continuation?.resume()
        continuation = nil
    }
}
