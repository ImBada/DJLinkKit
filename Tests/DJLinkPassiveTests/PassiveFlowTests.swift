import DJLinkKit
import DJLinkTestSupport
import Foundation
import Testing

@testable import DJLinkPassive

// 원본 시험 대응이 아닌, 실제 소켓 없이 seam·이벤트 연결을 확인하는 회귀 시험.
@DJLinkActor
private final class FlowPcapBackend: PcapBackend {
    var packet: (@DJLinkActor ([UInt8], Bool) -> Void)?
    var error: (@DJLinkActor (any Error) -> Void)?
    var openCount = 0
    var closeCount = 0
    var minimum: Int?
    var failure: DJLinkError?
    func deviceList() throws -> [CapDeviceListEntry] { [] }
    func open(device: String, filter: String, bufSize: Int, bufferSize: Int) throws {
        openCount += 1
        if let failure { throw failure }
        #expect(filter == "udp and (port 50000 or port 50001 or port 50002)")
        #expect(bufSize == 65535)
    }
    func setMinBytes(_ bytes: Int) { minimum = bytes }
    func onPacket(_ handler: @escaping @DJLinkActor ([UInt8], Bool) -> Void) { packet = handler }
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) { error = handler }
    func close() { closeCount += 1 }
}
@DJLinkActor
private final class FlowLocalDBAdapter: DatabaseAdapter {
    let type: DatabaseType
    var closes = 0
    init(_ type: DatabaseType) { self.type = type }
    func findTrack(_ id: Int) throws -> Track? { nil }
    func findPlaylist(_ playlistId: Int?) throws -> PlaylistQueryResult {
        .init(folders: [], playlists: [], trackEntries: [])
    }
    func close() { closes += 1 }
}
@DJLinkActor
private final class FlowLocalDBBackend: PassiveLocalDBBackend {
    var adapters: [FlowLocalDBAdapter] = []
    var hydrated: [[UInt8]] = []
    var tempFiles: [String] = []
    func makeMetadataORM() throws -> any DatabaseAdapter {
        let adapter = FlowLocalDBAdapter(.pdb)
        adapters.append(adapter)
        return adapter
    }
    func hydrateDatabase(
        orm: any DatabaseAdapter, pdbData: [UInt8], span: TelemetrySpan,
        onProgress: @escaping @DJLinkActor (PassiveLocalDBHydrationProgress) -> Void
    ) async throws {
        hydrated.append(pdbData)
        onProgress(.init(table: "tracks", total: 1, complete: 1))
    }
    func makeOneLibraryAdapter(tempFile: String) throws -> any DatabaseAdapter {
        tempFiles.append(tempFile)
        let adapter = FlowLocalDBAdapter(.oneLibrary)
        adapters.append(adapter)
        return adapter
    }
}
@DJLinkActor
private final class FlowLocalDBFileSystem: PassiveLocalDBFileSystem {
    var files: [String: [UInt8]] = [:]
    func tmpdir() -> String { "/fake-temp" }
    func writeFileSync(_ path: String, _ data: [UInt8]) throws { files[path] = data }
    func unlinkSync(_ path: String) throws { files.removeValue(forKey: path) }
}
private func frame(_ payload: [UInt8], port: Int, options: Bool = false) -> [UInt8] {
    let udpOffset = options ? 38 : 34
    var bytes = [UInt8](repeating: 0, count: udpOffset + 8)
    bytes.writeUInt16BE(0x0800, 12)
    bytes[14] = options ? 0x46 : 0x45
    bytes.writeUInt16BE(bytes.count - 14 + payload.count, 16)
    bytes[23] = 17
    bytes.writeUInt32BE(0x0a000001, 26)
    bytes.writeUInt32BE(0x0a000002, 30)
    bytes.writeUInt16BE(50000, udpOffset)
    bytes.writeUInt16BE(port, udpOffset + 2)
    // 어댑터가 내보낼 payload를 만드는 보조 함수라 원본의 이중 차감 16바이트를 더한다.
    bytes.writeUInt16BE(payload.count + 16, udpOffset + 4)
    return bytes + payload
}
private func announce(_ id: Int, name: String = "CDJ-test", short: Bool = true) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: short ? 46 : 54)
    bytes.replaceSubrange(0..<10, with: PROLINK_HEADER)
    bytes[10] = 6
    let encoded = Array(name.utf8).prefix(20)
    bytes.replaceSubrange(12..<(12 + encoded.count), with: encoded)
    bytes[0x24] = UInt8(id)
    bytes.replaceSubrange(0x26..<0x2c, with: [1, 2, 3, 4, 5, 6])
    if !short {
        bytes.writeUInt32BE(0x0a000009, 0x2c)
        bytes[0x34] = 4
    }
    return bytes
}
private func media(_ deviceId: Int = 1, _ slot: MediaSlot = .usb, type: TrackType = .rb) -> MediaSlotInfo {
    .init(
        deviceId: deviceId, slot: slot, name: "Test Media", color: .default,
        createdDate: Date(timeIntervalSince1970: 0), freeBytes: 0, totalBytes: 0, tracksType: type, trackCount: 1,
        playlistCount: 0, hasSettings: false)
}
@Suite("Passive seam and packet flow")
@DJLinkActor
struct PassiveFlowTests {
    @Test("decodes Ethernet IPv4 options and routes UDP packets with source IP")
    func routing() throws {
        let backend = FlowPcapBackend()
        let adapter = PcapAdapter(config: .init(iface: "en0", bufferSize: 2048), backend: backend)
        var seen: [String] = []
        var info: PacketInfo?
        adapter.on(.announce) {
            seen.append("announce")
            info = $0.info
        }
        adapter.on(.beat) { _ in seen.append("beat") }
        adapter.on(.status) { _ in seen.append("status") }
        try adapter.start()
        backend.packet?(frame([1, 2, 3], port: 50000, options: true), false)
        backend.packet?(frame([4], port: 50001), false)
        backend.packet?(frame([5], port: 50002), false)
        backend.packet?(frame([6], port: 49999), false)
        backend.packet?(frame([7], port: 50000), true)
        backend.packet?(frame([], port: 50000), false)
        var nonUDP = frame([8], port: 50000)
        nonUDP[23] = 6
        backend.packet?(nonUDP, false)
        #expect(seen == ["announce", "beat", "status"])
        #expect(info == .init(payload: [1, 2, 3], srcAddr: "10.0.0.1"))
        #expect(backend.minimum == 0)
        adapter.stop()
    }
    @Test("original UDP double subtraction drops eight bytes and treats standard announce as short format")
    func udpDoubleSubtraction() throws {
        let backend = FlowPcapBackend()
        let adapter = PcapAdapter(config: .init(iface: "en0", bufferSize: 2048), backend: backend)
        let manager = PassiveDeviceManager(adapter, clock: TestClock())
        var packets: [PcapPacket] = []
        adapter.on(.announce) { packets.append($0) }
        try adapter.start()
        let payload = announce(1, short: false)
        var bytes = frame(payload, port: ANNOUNCE_PORT)
        // 실제 패킷의 UDP 길이는 헤더 8바이트와 payload의 합이다.
        bytes.writeUInt16BE(payload.count + 8, 38)
        #expect(try PcapDecoders.UDP(bytes, 34).length == 54)
        backend.packet?(bytes, false)
        #expect(packets.count == 1)
        #expect(packets.first?.packet == Array(payload.prefix(46)))
        #expect(manager.devices[1]?.type == .cdj)
        #expect(manager.devices[1]?.ip.address == "10.0.0.1")
        for length in 0...8 {
            var short = frame([UInt8](repeating: 1, count: length), port: ANNOUNCE_PORT)
            short.writeUInt16BE(length + 8, 38)
            backend.packet?(short, false)
        }
        #expect(packets.count == 1)
        manager.stop()
        adapter.stop()
    }
    @Test("Ethernet VLAN skips one tag and keeps length and reserved values undefined")
    func vlan() throws {
        var bytes = frame([1, 2, 3], port: ANNOUNCE_PORT)
        bytes.insert(contentsOf: [0x81, 0x00, 0x00, 0x01], at: 12)
        let ethernet = try PcapDecoders.Ethernet(bytes)
        #expect(ethernet.type == 0x0800 && ethernet.offset == 18)
        let backend = FlowPcapBackend()
        let adapter = PcapAdapter(config: .init(iface: "en0", bufferSize: 2048), backend: backend)
        var packets: [PcapPacket] = []
        adapter.on(.announce) { packets.append($0) }
        try adapter.start()
        backend.packet?(bytes, false)
        #expect(packets.first?.packet == [1, 2, 3])
        for typeLength in [0, 1500, 1501, 1535, 1536] {
            bytes.writeUInt16BE(typeLength, 16)
            #expect(try PcapDecoders.Ethernet(bytes).type == (typeLength >= 1536 ? typeLength : nil))
            backend.packet?(bytes, false)
        }
        #expect(packets.count == 1)
        adapter.stop()
    }
    @Test("position parse errors reach adapter catch and stop later beat listeners")
    func positionError() throws {
        let backend = FlowPcapBackend()
        let adapter = PcapAdapter(config: .init(iface: "en0", bufferSize: 2048), backend: backend)
        let position = PassivePositionEmitter(adapter)
        let status = PassiveStatusEmitter(adapter)
        let manager = PassiveDeviceManager(adapter, clock: TestClock())
        var errors: [any Error] = []
        var laterBeats = 0
        adapter.on(.error) { errors.append($0) }
        adapter.on(.beat) { _ in laterBeats += 1 }
        var malformed = [UInt8](repeating: 0, count: 0x21)
        malformed.replaceSubrange(0..<10, with: PROLINK_HEADER)
        try adapter.start()
        backend.packet?(frame(malformed, port: BEAT_PORT), false)
        #expect(errors.count == 1 && errors.first is BufferRangeError)
        #expect(laterBeats == 0)
        backend.packet?(frame(malformed, port: STATUS_PORT), false)
        malformed[10] = 6
        backend.packet?(frame(malformed, port: ANNOUNCE_PORT), false)
        #expect(errors.count == 1)
        position.stop()
        status.stop()
        manager.stop()
        adapter.stop()
    }
    @Test("adapter start is idempotent and preserves open and missing-module errors")
    func startStop() throws {
        let backend = FlowPcapBackend()
        let adapter = PcapAdapter(config: .init(iface: "en0", bufferSize: 128), backend: backend)
        try adapter.start()
        try adapter.start()
        #expect(backend.openCount == 1 && adapter.isCapturing)
        adapter.stop()
        adapter.stop()
        #expect(backend.closeCount == 1 && !adapter.isCapturing)
        backend.failure = DJLinkError("denied")
        #expect(
            throws: DJLinkError(
                "Failed to open interface \"en0\" (device: en0) for packet capture. Ensure you have root/sudo privileges and the interface exists.\nOriginal error: Error: denied"
            )
        ) { try adapter.start() }
        let unavailable = PcapAdapter(config: .init(iface: "en0"), backendFactory: { throw DJLinkError("unavailable") })
        #expect(throws: DJLinkError(PCAP_MODULE_REQUIRED_ERROR)) { try unavailable.start() }
    }
    @Test("nonpositive capture buffer throws range error on start without opening backend")
    func bufferRange() {
        for size in [-1, 0, Int.min] {
            let backend = FlowPcapBackend()
            let adapter = PcapAdapter(config: .init(iface: "en0", bufferSize: size), backend: backend)
            #expect(throws: BufferRangeError("The value of \"size\" is out of range. Received \(size)")) {
                try adapter.start()
            }
            #expect(backend.openCount == 0 && !adapter.isCapturing)
        }
    }
    @Test("live pcap capture is blocked in test processes")
    func guardCapture() throws {
        #expect(TestProcess.isRunning)
        let backend = try LibpcapBackend()
        #expect(throws: DJLinkError("Live pcap capture is disabled in test processes")) {
            try backend.open(device: "en0", filter: "udp", bufSize: 65535, bufferSize: 2048)
        }
    }
    @Test("short announce uses source IP and device heuristics while standard format uses payload")
    func deviceFormats() throws {
        let info = PacketInfo(payload: [], srcAddr: "10.0.0.1")
        #expect(try deviceFromPacketWithInfo(announce(1), info)?.type == .cdj)
        #expect(try deviceFromPacketWithInfo(announce(17), info)?.type == .rekordbox)
        #expect(try deviceFromPacketWithInfo(announce(33), info)?.type == .mixer)
        #expect(try deviceFromPacketWithInfo(announce(1), info)?.ip.address == "10.0.0.1")
        let standard = try #require(try deviceFromPacketWithInfo(announce(1, short: false), info))
        #expect(standard.ip.address == "10.0.0.9" && standard.type == .rekordbox)
    }
    @Test("device timeout resets and stop detaches announcements without clearing devices")
    func deviceLifetime() throws {
        let backend = FlowPcapBackend()
        let clock = TestClock()
        let adapter = PcapAdapter(config: .init(iface: "en0", bufferSize: 2048), backend: backend)
        let manager = PassiveDeviceManager(adapter, clock: clock)
        var seen: [String] = []
        manager.on(.connected) { _ in seen.append("connected") }
        manager.on(.announced) { _ in seen.append("announced") }
        manager.on(.disconnected) { _ in seen.append("disconnected") }
        try adapter.start()
        backend.packet?(frame(announce(1), port: 50000), false)
        clock.advance(ms: 9000)
        backend.packet?(frame(announce(1, name: "Changed"), port: 50000), false)
        #expect(manager.devices[1]?.name == "CDJ-test")
        clock.advance(ms: 9999)
        #expect(manager.devices.count == 1)
        clock.advance(ms: 1)
        #expect(seen == ["connected", "announced", "announced", "disconnected"])
        backend.packet?(frame(announce(1), port: 50000), false)
        manager.stop()
        clock.advance(ms: 10000)
        backend.packet?(frame(announce(2), port: 50000), false)
        #expect(manager.devices.count == 1 && manager.devices[1] != nil)
        adapter.stop()
    }
    @Test("ensured-device wait matches requested ID and times out through injected clock")
    func ensured() async throws {
        let clock = TestClock()
        let adapter = PcapAdapter(config: .init(iface: "en0"), backend: FlowPcapBackend())
        let manager = PassiveDeviceManager(adapter, clock: clock)
        let waiting = Task { await manager.getDeviceEnsured(2) }
        await clock.waitForTimers(atLeast: 1)
        manager.emitter.emit(.connected, mockDevice(id: 1))
        manager.emitter.emit(.connected, mockDevice(id: 2))
        #expect(await waiting.value?.id == 2)
        clock.advance(ms: 2000)
        let timedOut = Task { await manager.getDeviceEnsured(3) }
        await clock.waitForTimers(atLeast: 1)
        clock.advance(ms: 2000)
        #expect(await timedOut.value == nil)
        #expect(manager.emitter.listenerCount(.connected) == 0)
    }
    @Test("position emitter parses beat payloads and detaches on stop")
    func position() throws {
        let backend = FlowPcapBackend()
        let adapter = PcapAdapter(config: .init(iface: "en0", bufferSize: 2048), backend: backend)
        let emitter = PassivePositionEmitter(adapter)
        var seen: [CDJStatus.PositionState] = []
        emitter.on(.position) { seen.append($0) }
        var payload = [UInt8](repeating: 0, count: 0x34)
        payload.replaceSubrange(0..<10, with: PROLINK_HEADER)
        payload[0x21] = 1
        payload.writeUInt16BE(0x0c, 0x22)
        payload.writeUInt32BE(180, 0x24)
        payload.writeUInt32BE(90000, 0x28)
        payload.writeUInt32BE(6400, 0x2c)
        payload.writeUInt32BE(1280, 0x30)
        try adapter.start()
        backend.packet?(frame(payload, port: 50001), false)
        #expect(seen == [.init(deviceId: 1, trackLength: 180, playhead: 90000, pitch: 1, bpm: 128)])
        emitter.stop()
        backend.packet?(frame(payload, port: 50001), false)
        #expect(seen.count == 1)
        adapter.stop()
    }
    @Test("local database dotted-path fallback hydrates once and caches synthetic media")
    func localDBFallback() async throws {
        let adapter = PcapAdapter(config: .init(iface: "en0"), backend: FlowPcapBackend())
        let manager = PassiveDeviceManager(adapter)
        let status = PassiveStatusEmitter(adapter)
        let backend = FlowLocalDBBackend()
        var paths: [String] = []
        var progress: [String] = []
        let localdb = PassiveLocalDatabase(
            manager, status, preference: .pdb, backend: backend,
            fetcher: { _, _, path, _, onProgress in
                paths.append(path)
                if path.hasPrefix(".") { throw DJLinkError("not found") }
                onProgress(.init(read: 3, total: 3))
                return [1, 2, 3]
            })
        localdb.on(.fetchProgress) { _ in progress.append("fetch") }
        localdb.on(.hydrationProgress) { _ in progress.append("hydrate") }
        localdb.on(.hydrationDone) { _ in progress.append("done") }
        let device = mockDevice()
        let first = try #require(await localdb.getWithoutMedia(device, .usb))
        let second = try #require(await localdb.getWithoutMedia(device, .usb))
        #expect(first === second)
        #expect(paths == [".PIONEER/rekordbox/export.pdb", "PIONEER/rekordbox/export.pdb"])
        #expect(backend.hydrated == [[1, 2, 3]])
        #expect(progress == ["fetch", "hydrate", "done"])
        localdb.stop()
        #expect(backend.adapters[0].closes == 1)
    }
    @Test("local database caches media broadcasts and rejects ineligible devices and track types")
    func localDBMedia() async throws {
        let adapter = PcapAdapter(config: .init(iface: "en0"), backend: FlowPcapBackend())
        let manager = PassiveDeviceManager(adapter)
        let status = PassiveStatusEmitter(adapter)
        let localdb = PassiveLocalDatabase(
            manager, status, backend: FlowLocalDBBackend(), fetcher: { _, _, _, _, _ in throw DJLinkError("not found") }
        )
        status.emitter.emit(.mediaSlot, media())
        status.emitter.emit(.mediaSlot, media(1, .sd))
        #expect(localdb.getAllCachedMedia() == [media(), media(1, .sd)])
        #expect(try await localdb.getWithMedia(mockDevice(id: 7), .usb, media(7)) == nil)
        #expect(try await localdb.getWithMedia(mockDevice(), .usb, media(type: .unanalyzed)) == nil)
        localdb.preference = .oneLibrary
        await #expect(throws: DJLinkError("OneLibrary database not found and preference is set to oneLibrary only")) {
            _ = try await localdb.getWithMedia(mockDevice(), .usb, media())
        }
        localdb.disconnectForDevice(mockDevice())
        #expect(localdb.getAllCachedMedia().isEmpty)
        localdb.stop()
        status.emitter.emit(.mediaSlot, media())
        #expect(localdb.getAllCachedMedia().isEmpty)
    }
    @Test("preload prepares both slot lookups before loaders can change cached media")
    func preloadOrder() async throws {
        let adapter = PcapAdapter(config: .init(iface: "en0"), backend: FlowPcapBackend())
        let manager = PassiveDeviceManager(adapter, clock: TestClock())
        let status = PassiveStatusEmitter(adapter)
        adapter.emitter.emit(
            .announce, .init(packet: announce(1), info: .init(payload: [], srcAddr: "10.0.0.1")))
        let backend = FlowLocalDBBackend()
        var slots: [MediaSlot] = []
        let localdb = PassiveLocalDatabase(
            manager, status, preference: .pdb, backend: backend,
            fileSystem: FlowLocalDBFileSystem(),
            fetcher: { _, slot, _, _, _ in
                slots.append(slot)
                // 로더가 시작된 뒤 들어온 방송은 preload에서 이미 선택한 무미디어 경로를 바꾸지 않는다.
                status.emitter.emit(.mediaSlot, media(1, .usb, type: .unanalyzed))
                status.emitter.emit(.mediaSlot, media(1, .sd, type: .unanalyzed))
                return [1, 2, 3]
            })
        try await localdb.preload()
        #expect(slots.count == 2 && slots.contains(.usb) && slots.contains(.sd))
        #expect(backend.hydrated == [[1, 2, 3], [1, 2, 3]])
        let db: (any DatabaseAdapter)? = await localdb.getWithoutMedia(mockDevice(), .usb)
        #expect(db === backend.adapters.first)
        let playlist: PlaylistQueryResult? = try db?.findPlaylist(nil)
        #expect(playlist == PlaylistQueryResult())
        localdb.stop()
        status.stop()
        manager.stop()
    }
    @Test("automatic database preference opens OneLibrary temp file and cleans it on stop")
    func oneLibrary() async throws {
        let adapter = PcapAdapter(config: .init(iface: "en0"), backend: FlowPcapBackend())
        let manager = PassiveDeviceManager(adapter)
        let status = PassiveStatusEmitter(adapter)
        let backend = FlowLocalDBBackend()
        let fileSystem = FlowLocalDBFileSystem()
        var paths: [String] = []
        let localdb = PassiveLocalDatabase(
            manager, status, backend: backend, platform: "win32", clock: TestClock(),
            fileSystem: fileSystem,
            fetcher: { _, _, path, _, _ in
                paths.append(path)
                return [1, 2, 3]
            })
        let db = try #require(try await localdb.getWithMedia(mockDevice(), .usb, media()))
        #expect(db.type == .oneLibrary)
        #expect(paths == ["PIONEER/rekordbox/exportLibrary.db"] && backend.hydrated.isEmpty)
        let temp = try #require(backend.tempFiles.first)
        #expect(fileSystem.files[temp] == [1, 2, 3])
        localdb.stop()
        #expect(fileSystem.files[temp] == nil && backend.adapters[0].closes == 1)
    }
    @Test("passive RemoteDB negotiates port and introduces original virtual device ID")
    func remoteDB() async throws {
        let adapter = PcapAdapter(config: .init(iface: "en0"), backend: FlowPcapBackend())
        let manager = PassiveDeviceManager(adapter)
        let device = mockDevice()
        adapter.emitter.emit(
            .announce, .init(packet: announce(1), info: .init(payload: [], srcAddr: device.ip.address)))
        let factory = FakeSocketFactory()
        let port = FakeTCPConnection()
        port.inject([0x12, 0x34])
        let socket = FakeTCPConnection()
        socket.inject(RemoteDBUInt32(1).buffer + Message(transactionId: 0xfffffffe, type: .success, args: []).buffer)
        var next = 0
        factory.makeTCPConnection = {
            defer { next += 1 }
            return next == 0 ? port : socket
        }
        let remote = PassiveRemoteDatabase(manager, socketFactory: factory)
        #expect(try await remote.get(9) == nil)
        #expect(try await remote.get(1) != nil)
        #expect(port.connectCalls[0].port == REMOTEDB_SERVER_QUERY_PORT && !port.isOpen)
        #expect(port.writes == [[0, 0, 0, 15] + [UInt8]("RemoteDBServer", encoding: .ascii) + [0]])
        #expect(socket.connectCalls[0].port == 0x1234)
        #expect(
            socket.writes == [
                RemoteDBUInt32(1).buffer,
                Message(transactionId: 0xfffffffe, type: .introduce, args: [RemoteDBUInt32(5)]).buffer,
            ])
        _ = try await remote.get(1)
        #expect(next == 2)
        await remote.disconnectFromDevice(device)
        #expect(!socket.isOpen)
        manager.stop()
        remote.stop()
    }
    @Test("network entrypoint wires lazy services and interface listing filters internal IPv6")
    func network() throws {
        let backend = FlowPcapBackend()
        let network = try bringOnlinePassive(
            .init(iface: "en0", bufferSize: 2048), backend: backend, socketFactory: FakeSocketFactory(),
            clock: TestClock())
        #expect(network.isCapturing && network.interfaceName == "en0")
        #expect(network.remotedb === network.remotedb && network.mixstatus === network.mixstatus)
        network.stop()
        #expect(!network.isCapturing)
        let provider = FakeInterfaceProvider([
            (
                "en15",
                [
                    .init(
                        address: "169.254.82.203", netmask: "255.255.0.0", family: "IPv4", mac: "00:00:00:00:00:00",
                        internal: false, cidr: nil)
                ]
            ),
            (
                "lo0",
                [
                    .init(
                        address: "127.0.0.1", netmask: "255.0.0.0", family: "IPv4", mac: "00:00:00:00:00:00",
                        internal: true, cidr: nil)
                ]
            ),
            (
                "en0",
                [
                    .init(
                        address: "fe80::1", netmask: "", family: "IPv6", mac: "00:00:00:00:00:00", internal: false,
                        cidr: nil)
                ]
            ),
        ])
        #expect(
            listInterfaces(interfaceProvider: provider) == [
                .init(name: "en15", address: "169.254.82.203", description: "Link-local (USB device?)")
            ])
    }
}
