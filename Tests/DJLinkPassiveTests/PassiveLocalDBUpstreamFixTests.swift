import DJLinkKit
import DJLinkPassive
import DJLinkTestSupport
import Foundation
import Testing

@DJLinkActor
private final class FixLocalDBAdapter: DatabaseAdapter {
    let type: DatabaseType
    var closeCalls = 0
    init(_ type: DatabaseType) { self.type = type }
    func findTrack(_ id: Int) throws -> Track? { nil }
    func findPlaylist(_ playlistId: Int?) throws -> PlaylistQueryResult {
        .init(folders: [], playlists: [], trackEntries: [])
    }
    func close() { closeCalls += 1 }
}
@DJLinkActor
private final class FixLocalDBBackend: PassiveLocalDBBackend {
    var adapters: [FixLocalDBAdapter] = []
    var openedPaths: [String] = []
    var failsOneLibraryOpen = false
    private func make(_ type: DatabaseType) -> FixLocalDBAdapter {
        let adapter = FixLocalDBAdapter(type)
        adapters.append(adapter)
        return adapter
    }
    func makeMetadataORM() throws -> any DatabaseAdapter { make(.pdb) }
    func hydrateDatabase(
        orm: any DatabaseAdapter, pdbData: [UInt8], span: TelemetrySpan,
        onProgress: @escaping @DJLinkActor (PassiveLocalDBHydrationProgress) -> Void
    ) async throws {}
    func makeOneLibraryAdapter(tempFile: String) throws -> any DatabaseAdapter {
        openedPaths.append(tempFile)
        if failsOneLibraryOpen { throw DJLinkError("시험용 OneLibrary 열기 실패") }
        return make(.oneLibrary)
    }
}
@DJLinkActor
private final class FixLocalDBFileSystem: PassiveLocalDBFileSystem {
    var writes: [String] = []
    var unlinks: [String] = []
    var failWrite = false
    var failUnlink = false
    func tmpdir() -> String { "/fake-temp" }
    func writeFileSync(_ path: String, _ data: [UInt8]) throws {
        // 일부 바이트를 쓴 뒤 실패하는 경우에도 파일이 남았다고 가정한다.
        writes.append(path)
        if failWrite { throw DJLinkError("시험용 파일 쓰기 실패") }
    }
    func unlinkSync(_ path: String) throws {
        unlinks.append(path)
        if failUnlink { throw DJLinkError("시험용 파일 삭제 실패") }
    }
}
private func fixMedia(_ deviceId: Int = 1, _ slot: MediaSlot = .usb, name: String = "시험 매체") -> MediaSlotInfo {
    .init(
        deviceId: deviceId, slot: slot, name: name, color: .default, createdDate: Date(timeIntervalSince1970: 0),
        freeBytes: 0, totalBytes: 0, tracksType: .rb, trackCount: 1, playlistCount: 0, hasSettings: false)
}
@DJLinkActor
private func makeFixLocalDB(
    preference: DatabasePreference = .auto, backend: FixLocalDBBackend, fileSystem: FixLocalDBFileSystem,
    clock: TestClock = TestClock(), fetcher: @escaping PassiveLocalDBFileFetcher
) -> (localdb: PassiveLocalDatabase, manager: PassiveDeviceManager) {
    let adapter = PcapAdapter(
        config: .init(iface: "en0"), backendFactory: { throw DJLinkError("시험에서 pcap을 열지 않는다") })
    let manager = PassiveDeviceManager(adapter, clock: clock)
    let localdb = PassiveLocalDatabase(
        manager, PassiveStatusEmitter(adapter), preference: preference, backend: backend, clock: clock,
        fileSystem: fileSystem, fetcher: fetcher)
    return (localdb, manager)
}

@Suite("패시브 LocalDB 원본 버그 회귀")
struct PassiveLocalDBUpstreamFixTests {
    @Test("장치를 제거하면 그 장치의 모든 매체 DB를 한 번씩 닫고 임시 파일을 지운다")
    @DJLinkActor func deviceRemoval() async throws {
        let backend = FixLocalDBBackend()
        let fs = FixLocalDBFileSystem()
        let clock = TestClock()
        let (localdb, manager) = makeFixLocalDB(
            backend: backend, fileSystem: fs, clock: clock, fetcher: { _, _, _, _, _ in [1, 2, 3] })
        let removed = mockDevice(id: 1)
        let other = mockDevice(id: 4)
        // 같은 장치의 USB·SD와 교체된 USB 매체, 다른 장치의 USB 매체를 각각 OneLibrary로 연다.
        let loads = [
            (removed, fixMedia()), (removed, fixMedia(1, .sd)), (removed, fixMedia(name: "교체한 시험 매체")),
            (other, fixMedia(4)),
        ]
        for (device, media) in loads {
            // 임시 파일 이름이 시각으로 갈리므로 로드마다 시계를 민다.
            clock.advance(ms: 1)
            #expect(try await localdb.getWithMedia(device, media.slot, media)?.type == .oneLibrary)
        }
        #expect(backend.adapters.count == 4)
        #expect(fs.writes.count == 4)
        let closing = Array(backend.adapters.prefix(3))
        let retained = backend.adapters[3]
        manager.emitter.emit(.disconnected, removed)
        #expect(closing.allSatisfy { $0.closeCalls == 1 })
        #expect(retained.closeCalls == 0)
        #expect(fs.unlinks == Array(fs.writes.prefix(3)))
        // 이미 빠진 DB는 다시 닫지 않는다.
        localdb.disconnectForDevice(removed)
        #expect(closing.allSatisfy { $0.closeCalls == 1 })
        #expect(fs.unlinks.count == 3)
        localdb.stop()
        #expect(retained.closeCalls == 1)
        #expect(fs.unlinks == fs.writes)
    }

    @Test("OneLibrary 열기 실패는 임시 파일을 지운 뒤 기존 선택 정책을 따른다", arguments: [DatabasePreference.auto, .oneLibrary])
    @DJLinkActor func oneLibraryOpenFailure(preference: DatabasePreference) async throws {
        let backend = FixLocalDBBackend()
        backend.failsOneLibraryOpen = true
        let fs = FixLocalDBFileSystem()
        var downloads: [String] = []
        let (localdb, _) = makeFixLocalDB(
            preference: preference, backend: backend, fileSystem: fs,
            fetcher: { _, _, path, _, _ in
                downloads.append(path)
                return [1, 2, 3]
            })
        if preference == .oneLibrary {
            await #expect(throws: DJLinkError("OneLibrary database not found and preference is set to oneLibrary only"))
            {
                _ = try await localdb.getWithMedia(mockDevice(), .usb, fixMedia())
            }
            #expect(!downloads.contains { $0.hasSuffix("export.pdb") })
        } else {
            let loaded = try await localdb.getWithMedia(mockDevice(), .usb, fixMedia())
            #expect((loaded as? FixLocalDBAdapter)?.type == .pdb)
            #expect(downloads.contains { $0.hasSuffix("export.pdb") })
        }
        #expect(fs.writes.count == 1)
        #expect(backend.openedPaths == fs.writes)
        #expect(fs.unlinks == backend.openedPaths)
        localdb.disconnectForDevice(mockDevice())
        #expect(fs.unlinks == backend.openedPaths)
    }

    @Test("OneLibrary 파일 처리의 실패와 성공에서 임시 파일 수명을 지킨다", arguments: ["write", "unlink", "fetch", "success"])
    @DJLinkActor func oneLibraryFileLifetime(scenario: String) async throws {
        let backend = FixLocalDBBackend()
        backend.failsOneLibraryOpen = scenario != "success"
        let fs = FixLocalDBFileSystem()
        fs.failWrite = scenario == "write"
        fs.failUnlink = scenario == "unlink"
        let (localdb, _) = makeFixLocalDB(
            backend: backend, fileSystem: fs,
            fetcher: { _, _, path, _, _ in
                if scenario == "fetch", path.hasSuffix("exportLibrary.db") {
                    throw DJLinkError("시험용 다운로드 실패")
                }
                return [1, 2, 3]
            })
        let loaded = try await localdb.getWithMedia(mockDevice(), .usb, fixMedia())
        #expect(loaded?.type == (scenario == "success" ? .oneLibrary : .pdb))
        if scenario == "fetch" {
            #expect(fs.writes.isEmpty)
            #expect(fs.unlinks.isEmpty)
            #expect(backend.openedPaths.isEmpty)
        } else {
            #expect(fs.writes.count == 1)
            #expect(backend.openedPaths.count == (scenario == "write" ? 0 : 1))
            #expect(fs.unlinks == (scenario == "success" ? [] : fs.writes))
        }
        localdb.disconnectForDevice(mockDevice())
        #expect(fs.unlinks == fs.writes)
        let oneLibrary = backend.adapters.filter { $0.type == .oneLibrary }
        #expect(oneLibrary.map { $0.closeCalls } == (scenario == "success" ? [1] : []))
    }
}
