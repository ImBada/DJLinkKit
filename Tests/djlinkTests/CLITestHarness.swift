import DJLinkKit
import DJLinkPassive
import DJLinkTestSupport
import Foundation
import Synchronization
import Testing

@testable import djlink

// 실제 소켓·LAN·시계·파일 시스템 없이 CLI 실행 경로를 돌리는 가짜 모음.

func networkInterface(_ address: String, prefix: Int = 24) -> NetworkInterfaceInfo {
    NetworkInterfaceInfo(
        address: address, netmask: "255.255.255.0", family: "IPv4", mac: "00:11:22:33:44:55", internal: false,
        cidr: "\(address)/\(prefix)")
}

func cdj(_ id: Int, _ ip: String, name: String = "CDJ-3000") throws -> Device {
    mockDevice(id: id, type: .cdj, name: name, ip: try Address4(ip))
}

func conflictPacket(_ id: Int) -> [UInt8] {
    var packet = [UInt8].alloc(0x29)
    packet.set(PROLINK_HEADER, 0)
    packet[0x0a] = 0x08
    packet[0x24] = UInt8(id)
    return packet
}

func makeState(
    deviceId: Int = 1, trackId: Int = 5, slot: MediaSlot = .usb, trackDeviceId: Int? = nil
) -> CDJStatus.State {
    CDJStatus.State(
        deviceId: deviceId, trackId: trackId, trackDeviceId: trackDeviceId ?? deviceId, trackSlot: slot, trackType: .rb,
        playState: .playing, isOnAir: false, isSync: false, isBpmSync: false, isMaster: false,
        isEmergencyMode: false, trackBPM: 128, effectivePitch: 0, sliderPitch: 0, beatInMeasure: 1,
        beatsUntilCue: nil, beat: nil, deviceType: 0x1f, packetNum: 0)
}

func makeTrack(
    id: Int = 5, title: String = "Song", filePath: String = "/Contents/a.mp3", fileName: String = "a.mp3"
) -> Track {
    Track(
        id: id, title: title, duration: 0, tempo: 0, rating: 0, comment: "", filePath: filePath, fileName: fileName)
}

/// 쓰기를 기록만 하는 가짜. 실제 파일을 만들지 않는다.
final class RecordingFileWriter: CLIFileWriter {
    struct State {
        var existing: Set<String> = []
        var published: [(path: String, data: [UInt8])] = []
        var directories: [String] = []
        var publishError: (any Error)?
    }

    let state = Mutex(State())

    init(existing: Set<String> = []) { state.withLock { $0.existing = existing } }

    var published: [(path: String, data: [UInt8])] { state.withLock { $0.published } }
    var directories: [String] { state.withLock { $0.directories } }
    var writes: Int { state.withLock { $0.published.count + $0.directories.count } }

    func fileExists(atPath path: String) -> Bool { state.withLock { $0.existing.contains(path) } }

    func createDirectory(atPath path: String) throws { state.withLock { $0.directories.append(path) } }

    func publishWithoutOverwriting(_ data: [UInt8], toPath path: String) throws {
        try state.withLock { state in
            if let error = state.publishError { throw error }
            if state.existing.contains(path) { throw CLIFileExistsError(path: path) }
            state.existing.insert(path)
            state.published.append((path, data))
        }
    }
}

/// NFS 읽기를 기록만 하는 가짜.
@DJLinkActor
final class RecordingNFS: CLINFS {
    private(set) var fetches: [String] = []
    private(set) var ranges: [String] = []
    private(set) var sizes: [String] = []
    var contents: [UInt8] = [1, 2, 3]
    /// 읽기 도중(Ctrl-C가 눌리는 때처럼) 하고 싶은 일.
    var duringFetch: (@DJLinkActor () -> Void)?
    /// true면 응답하지 않고 영원히 기다린다.
    var hangs = false

    nonisolated init() {}

    func fetchFile(
        device: Device, slot: MediaSlot, path: String, onProgress: (@DJLinkActor (FetchProgress) -> Void)?,
        chunkSize: Int?
    ) async throws -> [UInt8] {
        fetches.append(path)
        duringFetch?()
        if hangs {
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        }
        onProgress?(FetchProgress(read: contents.count, total: contents.count))
        return contents
    }

    func fetchFileRange(device: Device, slot: MediaSlot, path: String, offset: Int, length: Int) async throws -> [UInt8]
    {
        ranges.append(path)
        return contents
    }

    func fileSize(device: Device, slot: MediaSlot, path: String) async throws -> Int {
        sizes.append(path)
        return contents.count
    }

    var requestCount: Int { fetches.count + ranges.count + sizes.count }
}

/// 가짜 pcap 백엔드.
@DJLinkActor
final class FakePcapBackend: PcapBackend {
    private(set) var opened: [String] = []
    private(set) var closed = false
    var openError: (any Error)?
    private(set) var errorHandler: (@DJLinkActor (any Error) -> Void)?

    nonisolated init() {}

    func deviceList() throws -> [CapDeviceListEntry] { [] }

    func open(device: String, filter: String, bufSize: Int, bufferSize: Int) throws {
        if let openError { throw openError }
        opened.append(device)
    }

    func onPacket(_ handler: @escaping @DJLinkActor ([UInt8], Bool) -> Void) {}

    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) { errorHandler = handler }

    func close() { closed = true }
}

/// 어느 UDP 소켓의 bind를 실패시키는 소켓 공장(`bringOnline`이 중간에 실패하는 경로).
@DJLinkActor
final class FailingBindFactory: SocketFactory {
    let inner = FakeSocketFactory()
    let failingIndex: Int

    nonisolated init(failingIndex: Int) { self.failingIndex = failingIndex }

    func createUDPSocket(reuseAddr: Bool) throws -> any UDPSocket {
        let socket = try inner.createUDPSocket(reuseAddr: reuseAddr)
        if inner.udpSockets.count - 1 == failingIndex, let fake = socket as? FakeUDPSocket {
            fake.bindError = DJLinkError("bind failed (test)")
        }
        return socket
    }

    func createTCPConnection() throws -> any TCPConnection { try inner.createTCPConnection() }
}

/// 가짜 런타임으로 명령을 돌리는 도구. 소켓은 `FakeSocketFactory`, 시간은 `TestClock`이다.
@DJLinkActor
final class CLIHarness {
    let factory: any SocketFactory
    let fakeFactory: FakeSocketFactory
    let clock = TestClock()
    let interfaces: FakeInterfaceProvider
    let files: RecordingFileWriter
    let nfs = RecordingNFS()
    let backend = FakePcapBackend()
    let abort = CLIAbort()
    let output = BufferCLIOutput()

    init(
        interfaces: [(name: String, addresses: [NetworkInterfaceInfo])] = [
            ("en7", [networkInterface("192.168.1.100")]), ("en0", [networkInterface("10.0.0.5")]),
        ],
        existingFiles: Set<String> = [], factory: FakeSocketFactory = FakeSocketFactory()
    ) {
        self.fakeFactory = factory
        self.factory = factory
        self.interfaces = FakeInterfaceProvider(interfaces)
        self.files = RecordingFileWriter(existing: existingFiles)
    }

    /// 소켓 공장을 바꿔 쓰는 경우(실패 주입).
    init(socketFactory: any SocketFactory, fake: FakeSocketFactory) {
        self.fakeFactory = fake
        self.factory = socketFactory
        self.interfaces = FakeInterfaceProvider([("en7", [networkInterface("192.168.1.100")])])
        self.files = RecordingFileWriter()
    }

    func makeRuntime() -> CLIRuntime {
        var runtime = CLIRuntime.live
        runtime.socketFactory = factory
        runtime.interfaceProvider = interfaces
        runtime.clock = clock
        runtime.files = files
        runtime.nfs = nfs
        let abort = self.abort
        runtime.makeAbort = { abort }
        runtime.installsSignalHandlers = false
        runtime.configuresNFSGlobals = false
        let backend = self.backend
        let clock = self.clock
        runtime.makePassiveNetwork = { PassiveProlinkNetwork($0, backend: backend, clock: clock) }
        return runtime
    }

    func makeSession() -> CLISession {
        CLISession(runtime: makeRuntime(), output: output, abort: abort)
    }

    /// 인자를 해석해 명령을 시작한다. 끝나면 종료 코드를 돌려주는 작업.
    func start(_ arguments: [String]) -> CLIRun {
        // swiftlint:disable:next force_try
        let command = try! parseArguments(arguments)
        return start(command)
    }

    func start(_ command: CLICommand) -> CLIRun {
        let runtime = makeRuntime()
        let output = self.output
        return CLIRun(abort: abort) {
            await LiveCLIExecutor(runtime: { runtime }).execute(command, output: output)
        }
    }

    /// 장치가 announce한 것처럼 announce 소켓에 패킷을 넣는다.
    func announce(_ device: Device) throws {
        fakeFactory.udpSockets[0].emitMessage(try makeAnnouncePacket(device))
    }

    /// 앞서 시작한 작업이 멈출 곳까지 가도록 양보한다.
    func settle() async { await clock.settle() }

    var announceSocket: FakeUDPSocket { fakeFactory.udpSockets[0] }
    var beatSocket: FakeUDPSocket { fakeFactory.udpSockets[1] }
    var statusSocket: FakeUDPSocket { fakeFactory.udpSockets[2] }

    /// 지금까지 UDP 소켓으로 내보낸 모든 패킷 수.
    var totalSent: Int { fakeFactory.udpSockets.reduce(0) { $0 + $1.sent.count } }

    var allSocketsClosed: Bool { !fakeFactory.udpSockets.isEmpty && fakeFactory.udpSockets.allSatisfy { $0.isClosed } }
}

/// 시작한 명령 하나. 끝나지 않으면 시험이 멈추지 않도록 실패로 기록하고 중단한다.
@DJLinkActor
final class CLIRun {
    private var code: Int32?
    private let abort: CLIAbort

    init(abort: CLIAbort, body: @escaping @DJLinkActor () async -> Int32) {
        self.abort = abort
        Task { @DJLinkActor [self] in code = await body() }
    }

    var value: Int32 {
        get async {
            if let code = await waitForCode() { return code }
            Issue.record("명령이 끝나지 않았다(시험이 멈추지 않게 중단한다)")
            abort.interrupt()
            return await waitForCode() ?? -1
        }
    }

    private func waitForCode() async -> Int32? {
        for _ in 0..<20_000 {
            if let code { return code }
            await Task.yield()
        }
        return code
    }
}
