import DJLinkKit
import DJLinkPassive
import Foundation

// 한 번의 실행이 가진 모든 것(네트워크·소켓·타이머·작업)의 주인. 끝날 때 어떤 경로로 끝나든 `cleanup()`이 거둔다.
// 부작용을 만들기 전에는 늘 `abort.check()`를 거친다.

@DJLinkActor
final class CLISession {
    let runtime: CLIRuntime
    let output: any CLIOutput
    let abort: CLIAbort
    let sockets: CLISocketRegistry
    private(set) var network: ProlinkNetwork?
    private(set) var passive: PassiveProlinkNetwork?
    /// 소켓을 묶고 대화를 제한할 인터페이스. 정해지기 전에는 듣기만 한다(아무것도 보내지 않는다).
    private(set) var scope: CLINetworkScope?
    /// 사용자가 끼어들어 끝날 때 정리 전에 한 번 부른다(예: `devices`가 지금까지 본 장치를 낸다).
    var interruptReport: (@DJLinkActor () -> Void)?

    private var deadline: TimerHandle?
    private let watchdog: CLIWatchdog?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var announcingStopped = false
    private var cleanedUp = false
    private var configuredNFS = false

    init(runtime: CLIRuntime, output: any CLIOutput, abort: CLIAbort) {
        self.runtime = runtime
        self.output = output
        self.abort = abort
        self.watchdog = runtime.independentScheduler.map { CLIWatchdog(abort: abort, scheduler: $0) }
        self.sockets = CLISocketRegistry(inner: runtime.socketFactory, abort: abort)
        // 중단되는 순간 동기로 참여부터 멈춘다(announce 타이머가 더 돌지 않게).
        abort.onAbort { [weak self] in self?.stopAnnouncing() }
    }

    // MARK: 제한 시간·작업

    /// 명령 전체 제한 시간. 넘으면 중단 토큰을 실패로 세워 남은 작업과 소켓을 정리하게 한다.
    func setDeadline(seconds: Int) {
        watchdog?.setDeadline(seconds: seconds)
        runtime.clock.clearTimeout(deadline)
        deadline = runtime.clock.setTimeout(.seconds(seconds)) { [self] in
            abort.fail("제한 시간 \(seconds)초를 넘었다. 남은 작업과 소켓을 정리하고 끝낸다(--timeout으로 바꾼다)")
        }
    }

    /// 끝나기 전에 거둘 수 있게 추적하는 작업. 이미 중단됐으면 만들지 않는다.
    func spawn(_ body: @escaping @DJLinkActor () async -> Void) {
        guard !abort.isAborted else { return }
        let id = UUID()
        tasks[id] = Task { @DJLinkActor [self] in
            await body()
            tasks.removeValue(forKey: id)
        }
    }

    /// 파일 쓰기·fsync·게시가 DJLinkActor를 점유하지 않게 별도 큐에서 한다.
    func publishFile(_ data: [UInt8], path: String, directory: String? = nil) async throws {
        let files = runtime.files
        let abort = abort
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try abort.check()
                    if let directory { try files.createDirectory(atPath: directory) }
                    try files.publishWithoutOverwriting(data, toPath: path, checkCancellation: { try abort.check() })
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: 인터페이스

    /// 이름으로 인터페이스를 찾아 범위를 만든다.
    func resolveScope(named name: String) throws -> CLINetworkScope {
        let interfaces = runtime.interfaceProvider.networkInterfaces()
        guard let info = selectInterface(named: name, in: interfaces) else {
            let names = candidateInterfaceNames(interfaces)
            throw CLIRuntimeError(
                "인터페이스 \(name)에서 IPv4 주소를 찾지 못했다. 쓸 수 있는 이름: \(names.isEmpty ? "(없음)" : names.joined(separator: ", "))"
            )
        }
        return try CLINetworkScope(name: name, info: info)
    }

    /// 이 인터페이스로 확정한다: 소켓을 묶고 이후 대화를 이 서브넷으로 제한한다.
    func lock(_ scope: CLINetworkScope) throws {
        if let current = self.scope {
            guard current == scope else {
                throw CLIRuntimeError("이미 \(current.description)로 정했는데 \(scope.description)로 바꾸려 했다")
            }
            return
        }
        try sockets.bindInterface(name: scope.name)
        self.scope = scope
        sockets.scope = scope
        output.log(.info, "Interface \(scope.description): 소켓을 묶었고 이 서브넷의 장치하고만 통신한다")
    }

    /// 장치가 있는 서브넷의 인터페이스를 찾는다.
    func scopeMatching(_ device: Device) throws -> CLINetworkScope? {
        guard let match = try getMatchingInterface(device.ip, interfaceProvider: runtime.interfaceProvider) else {
            return nil
        }
        return try CLINetworkScope(name: match.name, info: match.info)
    }

    /// 대상 장치가 있는 인터페이스로 확정한다. 이미 정했다면 장치가 그 서브넷 안인지만 확인한다.
    func lockInterface(for device: Device) throws {
        if let scope {
            try requireInScope(device, scope)
            return
        }
        guard let matched = try scopeMatching(device) else {
            throw CLIRuntimeError("장치 \(device.ip.address)와 같은 서브넷의 인터페이스를 찾지 못했다. --iface로 정한다")
        }
        try lock(matched)
    }

    private func requireInScope(_ device: Device, _ scope: CLINetworkScope) throws {
        guard scope.contains(device) else {
            throw CLIRuntimeError(
                "장치 \(device.id) [\(device.ip.address)]는 인터페이스 \(scope.description)의 서브넷 밖이라 쓰지 않는다")
        }
    }

    /// 처음 보이는 장치(이미 본 것이 있으면 그것)의 인터페이스로 확정한다. 없을 때만 새 장치를 기다린다.
    private func lockInterfaceFromPeers() async throws {
        guard let manager = network?.deviceManager else { throw CLIRuntimeError("네트워크가 열리지 않았다") }
        for device in manager.devices.values.sorted(by: { $0.id < $1.id }) {
            if let matched = try scopeMatching(device) {
                try lock(matched)
                return
            }
        }
        output.log(.await, "Autoconfiguring network.. waiting for devices")
        let waiter = CLIWaiter<CLINetworkScope>()
        let matched = try await waiter.wait { waiter in
            let subscription = manager.on(.connected) { [self] device in
                if let matched = try? scopeMatching(device) { waiter.finish(.success(matched)) }
            }
            waiter.onFinish { manager.off(subscription) }
            let timer = runtime.clock.setTimeout(.seconds(discoveryTimeoutSeconds)) {
                waiter.finish(
                    .failure(
                        CLIRuntimeError(
                            "\(discoveryTimeoutSeconds)초 안에 장치를 찾지 못했다. 장치가 같은 네트워크에 있는지, --iface를 줘 보라")))
            }
            waiter.onFinish { [runtime] in runtime.clock.clearTimer(timer) }
            let id = abort.onAbort { waiter.finish(.failure(CLIAborted())) }
            waiter.onFinish { [abort] in abort.removeHandler(id) }
        }
        try lock(matched)
        output.log(.success, "Autoconfigure successful!")
    }

    // MARK: 네트워크 열기·참여

    /// 소켓을 열어 듣기만 한다(가상 CDJ로 참여하지 않는다). `--iface`가 있으면 그 인터페이스에 먼저 묶는다.
    func openNetwork(options: CLICommonOptions) async throws -> ProlinkNetwork {
        try abort.check()
        if let name = options.iface { try lock(try resolveScope(named: name)) }
        configureNFS()
        output.log(.await, "Bringing up prolink network")
        let config = NetworkConfig(logger: CLILogger(output: output, verbose: options.verbose))
        let network = try await bringOnline(
            config, socketFactory: sockets, interfaceProvider: runtime.interfaceProvider, clock: runtime.clock,
            dependencies: guardedNetworkDependencies())
        self.network = network
        try abort.check()
        output.log(.success, "Network online (listening on UDP \(ANNOUNCE_PORT)-\(STATUS_PORT))")
        network.deviceManager.on(.connected) { [output] device in
            output.log(.star, "New device: \(formatDevice(device))")
        }
        network.deviceManager.on(.disconnected) { [output] device in
            output.log(.info, "Device left: \(device.name) [id: \(device.id)]")
        }
        return network
    }

    /// 대상 장치가 보일 때까지 기다린다. 인터페이스가 정해져 있으면 그 서브넷 안의 장치만 받는다.
    func requireDevice(id: Int, timeoutSeconds: Int = deviceWaitSeconds) async throws -> Device {
        try abort.check()
        guard let manager = network?.deviceManager else { throw CLIRuntimeError("네트워크가 열리지 않았다") }
        let device: Device
        if let known = manager.devices[id] {
            device = known
        } else {
            let waiter = CLIWaiter<Device>()
            device = try await waiter.wait { waiter in
                let subscription = manager.on(.connected) { found in
                    if found.id == id { waiter.finish(.success(found)) }
                }
                waiter.onFinish { manager.off(subscription) }
                let timer = runtime.clock.setTimeout(.seconds(timeoutSeconds)) {
                    waiter.finish(
                        .failure(
                            CLIRuntimeError(
                                "장치 \(id)가 \(timeoutSeconds)초 안에 보이지 않는다. `djlink devices`로 번호를 확인한다")))
                }
                waiter.onFinish { [runtime] in runtime.clock.clearTimer(timer) }
                let abortId = abort.onAbort { waiter.finish(.failure(CLIAborted())) }
                waiter.onFinish { [abort] in abort.removeHandler(abortId) }
            }
        }
        if let scope { try requireInScope(device, scope) }
        return device
    }

    /// 이미 알고 있는 장치가 고른 인터페이스의 서브넷 밖에 있으면 그 장치를 돌려준다(그런 장치에는 질의를 보내지 않는다).
    func deviceOutsideScope(id: DeviceID) -> Device? {
        guard let scope, let device = network?.deviceManager.devices[id] else { return nil }
        return scope.contains(device) ? nil : device
    }

    /// 가상 CDJ로 참여한다. 인터페이스가 정해지지 않았으면 `knownDevice`가 있는 서브넷, 그것도 없으면 처음 보이는 장치로 정한다.
    func join(options: CLICommonOptions, knownDevice: Device? = nil) async throws {
        try abort.check()
        guard let network else { throw CLIRuntimeError("네트워크가 열리지 않았다") }
        if let knownDevice {
            try lockInterface(for: knownDevice)
        } else if scope == nil {
            try await lockInterfaceFromPeers()
        }
        guard let scope else { throw CLIRuntimeError("인터페이스를 정하지 못했다") }
        let allowPlayerId = options.allowPlayerId
        let reportRejection: @DJLinkActor (DeviceID) -> Void = { [self] id in
            abort.fail(
                "가상 CDJ 번호가 \(id)번으로 바뀌어야 하는데 허용하지 않는 번호라(1~6은 --allow-player-id가 있을 때만) 그 번호로 보내기 전에 참여를 멈췄다"
            )
        }
        network.configure(
            NetworkConfig(
                iface: scope.info, vcdjId: options.effectiveVcdjId,
                allowsDeviceId: {
                    checkVirtualCDJId($0, allowPlayerId: allowPlayerId) == nil && 1...MAX_DEVICE_ID ~= $0
                },
                onDeviceIdRejected: reportRejection,
                announceTargetFilter: { scope.contains($0) }))
        output.log(.await, "Connecting to network!")
        // announce를 시작하기 직전에 한 번 더 확인한다.
        try abort.check()
        try network.connect()
        guard network.isConnected() else { throw CLIRuntimeError("Failed to connect to the network") }
        if let vcdj = network.virtualDevice {
            output.log(.star, "Network connected! Joined as virtual CDJ \"\(vcdj.name)\" [id: \(vcdj.id)]")
        }
    }

    // MARK: NFS 경로 검사

    /// 모든 NFS 읽기가 거치는 검사. 중단됐거나 읽지 않는 경로면 던진다.
    func guardNFS(_ path: String, device: Device? = nil) throws {
        if let device { try sockets.requireDestination(device.ip.address) }
        try abort.check()
        if let violation = checkNeverRead(path) { throw CLIRuntimeError(violation.message) }
    }

    private func configureNFS() {
        guard runtime.configuresNFSGlobals, !configuredNFS else { return }
        configuredNFS = true
        configureNFSDependencies(socketFactory: sockets, clock: runtime.clock)
        configureNFSPathGuard { [self] device, _, path in try guardNFS(path, device: device) }
    }

    private func guardedNetworkDependencies() -> NetworkDependencies {
        NetworkDependencies(
            makeLocalDatabase: { [self] host, manager, statusEmitter, preference, clock in
                LocalDatabase(
                    hostDevice: host, deviceManager: manager, statusEmitter: statusEmitter, preference: preference,
                    dependencies: guardedLocalDBDependencies(), clock: clock)
            },
            makeDatabase: { [self] local, remote, manager, logger, host in
                Database(
                    local: local, remote: remote, deviceManager: manager, logger: logger, hostDevice: host,
                    dependencies: guardedDBDependencies())
            })
    }

    func guardedDBDependencies() -> DBDependencies {
        DBDependencies(
            fetchFile: { [self] device, slot, path, progress, chunkSize in
                try guardNFS(path, device: device)
                return try await runtime.nfs.fetchFile(
                    device: device, slot: slot, path: path, onProgress: progress, chunkSize: chunkSize)
            },
            extractArtworkFromDevice: { [self] device, slot, path, logger in
                try guardNFS(path, device: device)
                return try await DJLinkKit.extractArtworkFromDevice(
                    device, slot, path, logger, source: CLIGuardedArtworkSource(session: self))
            })
    }

    func guardedLocalDBDependencies() -> LocalDBDependencies {
        LocalDBDependencies(
            fetchFile: { [self] options in
                try guardNFS(options.path, device: options.device)
                var onProgress: (@DJLinkActor (FetchProgress) -> Void)?
                if let callback = options.onProgress {
                    onProgress = { callback(LocalDBFetchProgress(read: $0.read, total: $0.total)) }
                }
                return try await runtime.nfs.fetchFile(
                    device: options.device, slot: options.slot, path: options.path, onProgress: onProgress,
                    chunkSize: nil)
            },
            fileSystem: CLIGuardedLocalFileSystem(abort: abort))
    }

    // MARK: 패시브

    func openPassive(iface: String) throws -> PassiveProlinkNetwork {
        try abort.check()
        let network = runtime.makePassiveNetwork(PassiveNetworkConfig(iface: iface))
        passive = network
        // 시작하기 전에 건다: 캡처 도중 오류가 나면 조용히 멈추지 않고 실패로 끝낸다.
        network.adapter.on(.error) { [abort] error in abort.fail("패킷 캡처 오류: \(error)") }
        do {
            try network.start()
        } catch {
            throw CLIRuntimeError("패시브 캡처를 시작하지 못했다: \(error)")
        }
        return network
    }

    // MARK: 정리

    private func stopAnnouncing() {
        guard !announcingStopped, let network, network.isConnected() else { return }
        announcingStopped = true
        _ = try? network.disconnect()
    }

    /// 어떤 경로로 끝나든 한 번 부른다. 참여를 멈추고, 작업·NFS 연결·소켓을 모두 거둔다. 여러 번 불러도 안전하다.
    func cleanup() async {
        guard !cleanedUp else { return }
        cleanedUp = true
        runtime.clock.clearTimeout(deadline)
        deadline = nil
        stopAnnouncing()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        passive?.stop()
        if configuredNFS {
            configureNFSPathGuard(nil)
            await closeAllNFSClients()
            configureNFSDependencies(socketFactory: LiveSocketFactory.shared, clock: SystemClock.shared)
        }
        if let network { try? await network.close() }
        await sockets.closeAll()
        watchdog?.complete()
    }
}

/// 앨범아트·메타데이터 추출이 NFS를 읽을 때 경로 검사를 거치게 하는 소스.
struct CLIGuardedArtworkSource: ArtworkNFSFileSource {
    let session: CLISession

    func fetchFileRange(device: Device, slot: MediaSlot, path: String, offset: Int, length: Int) async throws -> [UInt8]
    {
        try await session.guardNFS(path, device: device)
        return try await session.runtime.nfs.fetchFileRange(
            device: device, slot: slot, path: path, offset: offset, length: length)
    }

    func getFileInfo(device: Device, slot: MediaSlot, path: String) async throws -> ArtworkNFSFileInfo {
        try await session.guardNFS(path, device: device)
        return ArtworkNFSFileInfo(size: try await session.runtime.nfs.fileSize(device: device, slot: slot, path: path))
    }
}

/// OneLibrary를 임시 파일로 풀 때 중단된 뒤에는 쓰지 않는다.
@DJLinkActor
struct CLIGuardedLocalFileSystem: LocalDBFileSystem {
    let abort: CLIAbort
    private let inner = LocalDBNativeFileSystem()

    init(abort: CLIAbort) { self.abort = abort }

    var tmpdir: String { inner.tmpdir }

    func writeFileSync(_ path: String, _ data: [UInt8]) throws {
        try abort.check()
        try inner.writeFileSync(path, data)
    }

    func unlinkSync(_ path: String) throws { try inner.unlinkSync(path) }
}
