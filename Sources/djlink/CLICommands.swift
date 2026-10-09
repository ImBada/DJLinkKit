import DJLinkControl
import DJLinkKit
import DJLinkPassive
import Foundation

// 하위 명령 실행. 소켓·시계·파일·NFS는 `CLIRuntime`으로 주입하므로 시험은 가짜로 같은 코드를 돌린다.
// 판단 로직은 CLIArguments·CLISafety·CLIFormat에 있다.

/// 명령을 실행하고 종료 코드를 돌려준다. 시험은 가짜를 넣는다.
protocol CLICommandExecutor: Sendable {
    func execute(_ command: CLICommand, output: any CLIOutput) async -> Int32
}

/// 종료 코드. 0 정상, 1 실행 실패(제한 시간 초과 포함), 2 사용법·안전 규칙 거부, 130 중단(Ctrl-C).
enum CLIExitCode {
    static let ok: Int32 = 0
    static let failure: Int32 = 1
    static let refused: Int32 = 2
    static let interrupted: Int32 = 130
}

struct LiveCLIExecutor: CLICommandExecutor {
    private let makeRuntime: (@Sendable @DJLinkActor () -> CLIRuntime)?

    /// `runtime`을 주지 않으면 실제 소켓·시스템 인터페이스·실제 시계를 쓴다.
    init(runtime: (@Sendable @DJLinkActor () -> CLIRuntime)? = nil) {
        makeRuntime = runtime
    }

    func execute(_ command: CLICommand, output: any CLIOutput) async -> Int32 {
        await Self.run(command, output: output, makeRuntime: makeRuntime)
    }

    @DJLinkActor
    private static func run(
        _ command: CLICommand, output: any CLIOutput, makeRuntime: (@Sendable @DJLinkActor () -> CLIRuntime)?
    ) async -> Int32 {
        let runtime = makeRuntime?() ?? .live
        let abort = runtime.makeAbort()
        let signals = runtime.installsSignalHandlers ? CLISignalHandler(abort: abort) : nil
        defer { signals?.remove() }
        let session = CLISession(runtime: runtime, output: output, abort: abort)
        return await session.run(command)
    }
}

extension CLISession {
    /// 명령을 돌리고 어떤 경로로 끝나든 정리한 뒤 종료 코드를 정한다.
    /// 중단(Ctrl-C·제한 시간·번호 거부)이 먼저 오면 돌던 작업은 버리고, 정리가 소켓을 닫아 더 못 하게 한다.
    func run(_ command: CLICommand) async -> Int32 {
        let work = Task { @DJLinkActor in try await self.perform(command) }
        let finished: Result<Int32, any Error>? = await withCheckedContinuation { continuation in
            let once = Once()
            Task { @DJLinkActor in
                let result = await work.result
                if once.take() { continuation.resume(returning: result) }
            }
            abort.onAbort { if once.take() { continuation.resume(returning: nil) } }
        }
        work.cancel()
        if abort.reason == .interrupted { interruptReport?() }
        await cleanup()

        if let reason = abort.reason {
            switch reason {
            case .interrupted:
                output.log(.info, "Interrupted, closing")
                return CLIExitCode.interrupted
            case .failed(let message):
                output.log(.error, message)
                return CLIExitCode.failure
            }
        }
        switch finished {
        case .success(let code):
            return code
        case .failure(let error as CLIRuntimeError):
            output.log(.error, error.message)
        case .failure(let error):
            output.log(.error, "\(error)")
        case nil:
            break
        }
        return CLIExitCode.failure
    }

    private func perform(_ command: CLICommand) async throws -> Int32 {
        switch command {
        case .help:
            return CLIExitCode.ok
        case .devices(let seconds, let verbose):
            return try await runDevices(seconds: seconds, verbose: verbose)
        case .watch(let options, let downloadDir):
            return try await runWatch(options: options, downloadDir: downloadDir)
        case .status(let options, let all, let interval):
            return try await runStatus(options: options, all: all, positionIntervalMs: interval)
        case .metadata(let options, let target):
            return try await runMetadata(options: options, target: target)
        case .fetch(let options, let target):
            return try await runFetch(options: options, target: target)
        case .mixstatus(let options):
            return try await runMixstatus(options: options)
        case .control(let options, let request):
            return try await runControl(options: options, request: request)
        case .passive(let iface, let interval):
            return try await runPassive(iface: iface, positionIntervalMs: interval)
        }
    }

    // MARK: devices

    private func runDevices(seconds: Int, verbose: Bool) async throws -> Int32 {
        let network = try await openNetwork(options: CLICommonOptions(verbose: verbose))
        let report: @DJLinkActor () -> Void = { [output] in
            let devices = network.deviceManager.devices.values.sorted { $0.id < $1.id }
            output.log(.info, "\(devices.count) device(s) on the network")
            for device in devices { output.writeLine("  \(formatDevice(device))") }
        }
        interruptReport = report
        output.log(.await, "Listening for device announcements for \(seconds)s (Ctrl-C to stop)")
        if await abort.wait(seconds: seconds, clock: runtime.clock) { return CLIExitCode.interrupted }
        report()
        return CLIExitCode.ok
    }

    // MARK: watch (원본 src/cli/index.ts)

    private func runWatch(options: CLICommonOptions, downloadDir: String?) async throws -> Int32 {
        let network = try await openNetwork(options: options)
        try await join(options: options)
        guard let statusEmitter = network.statusEmitter, let db = network.db else {
            throw CLIRuntimeError("Failed to connect to the network")
        }

        if let downloadDir {
            output.log(.info, "받은 파일은 \(downloadDir)에 쓴다(이미 있는 파일은 덮어쓰지 않는다)")
        } else {
            output.log(.info, "--download-dir를 주지 않았으므로 파일은 받지 않고 제목만 출력한다")
        }

        let processor = MixstatusProcessor(clock: runtime.clock)
        statusEmitter.on(.status) { processor.handleState($0) }

        final class LastTrackIds {
            var ids: [Int: Int] = [:]
        }
        let lastTid = LastTrackIds()
        statusEmitter.on(.status) { [self] state in
            if lastTid.ids[state.deviceId] == state.trackId { return }
            lastTid.ids[state.deviceId] = state.trackId
            // 원본과 다름: 곡이 없는 상태(trackId 0)는 조회하지 않는다. 실기에 쓸데없는 질의를 보내지 않으려는 것이다.
            if state.trackId == 0 { return }
            spawn { await self.handleTrackChange(state, db: db, downloadDir: downloadDir) }
        }

        await abort.wait()
        return CLIExitCode.interrupted
    }

    func handleTrackChange(_ state: CDJStatus.State, db: any NetworkDatabase, downloadDir: String?) async {
        do {
            try abort.check()
            // 곡이 있는 장치가 인터페이스 서브넷 밖이면(다른 LAN에서 먼저 들은 같은 번호의 장치 등) 질의하지 않는다.
            if let outside = deviceOutsideScope(id: state.trackDeviceId) {
                output.log(.warn, "장치 \(outside.id) [\(outside.ip.address)]는 서브넷 밖이라 질의하지 않는다")
                return
            }
            let track = try await db.getMetadata(
                .init(
                    deviceId: state.trackDeviceId, trackSlot: state.trackSlot, trackType: state.trackType,
                    trackId: state.trackId))
            try abort.check()
            guard let track else {
                output.log(.warn, "no track")
                return
            }
            output.writeLine("\(state.trackId) \(track.title)")

            // 원본은 파일을 현재 폴더에 무조건 쓰지만, 우리 CLI는 --download-dir를 준 경우에만 쓴다(PLAN §11).
            guard let downloadDir else { return }
            if let violation = checkNeverRead(track.filePath) {
                output.log(.warn, "받지 않는다: \(violation.message)")
                return
            }
            guard let fileName = safeDownloadFileName(track.fileName) else {
                output.log(.warn, "파일 이름이 올바르지 않아 받지 않는다: \(track.fileName)")
                return
            }
            let buf = try await db.getFile(
                .init(
                    deviceId: state.trackDeviceId, trackSlot: state.trackSlot, trackType: state.trackType,
                    track: track))
            guard let buf else { return }
            // 같은 파일 이름이 다른 장치·곡에서 와도 부딪치지 않게 장치·슬롯·곡 번호를 넣는다.
            let slotName = getSlotName(state.trackSlot) ?? String(state.trackSlot.rawValue)
            let name = "\(state.trackDeviceId)-\(slotName)-\(state.trackId)-\(fileName)"
            let target = (downloadDir as NSString).appendingPathComponent(name)
            // 파일 쓰기 직전에 확인한다.
            try abort.check()
            try runtime.files.createDirectory(atPath: downloadDir)
            do {
                try runtime.files.publishWithoutOverwriting(buf, toPath: target)
                output.writeLine("Copied \(name)")
            } catch is CLIFileExistsError {
                output.log(.warn, "이미 있어 덮어쓰지 않는다: \(target)")
            }
        } catch is CLIAborted {
            return
        } catch {
            output.log(.error, "track \(state.trackId): \(error)")
        }
    }

    // MARK: status

    private func runStatus(options: CLICommonOptions, all: Bool, positionIntervalMs: Int) async throws -> Int32 {
        let network = try await openNetwork(options: options)
        try await join(options: options)
        guard let statusEmitter = network.statusEmitter, let positionEmitter = network.positionEmitter else {
            throw CLIRuntimeError("Failed to connect to the network")
        }
        attachStatusPrinters(
            statusEmitter: statusEmitter, positionEmitter: positionEmitter, all: all,
            positionIntervalMs: positionIntervalMs)
        output.log(.await, "Printing status, precise position and on-air (Ctrl-C to stop)")
        await abort.wait()
        return CLIExitCode.interrupted
    }

    /// 상태·정밀 위치·on-air·미디어 슬롯을 한 줄씩 찍는다. 줄이는 규칙은 `StatusLineFilter`·`LineThrottle`.
    private func attachStatusPrinters(
        statusEmitter: StatusEmitter, positionEmitter: PositionEmitter, all: Bool, positionIntervalMs: Int
    ) {
        let printer = StatusPrinter(output: output, clock: runtime.clock, all: all, interval: positionIntervalMs)
        statusEmitter.on(.status) { printer.status($0) }
        statusEmitter.on(.onAir) { printer.onAir($0) }
        statusEmitter.on(.mediaSlot) { printer.mediaSlot($0) }
        positionEmitter.on(.position) { printer.position($0) }
    }

    // MARK: metadata

    private func runMetadata(options: CLICommonOptions, target: CLITrackTarget) async throws -> Int32 {
        setDeadline(seconds: target.timeoutSeconds)
        let network = try await openNetwork(options: options)
        // 먼저 듣기만 하며 대상 장치를 찾고, 그 장치가 있는 인터페이스로 참여한다.
        let device = try await requireDevice(id: target.deviceId)
        try await join(options: options, knownDevice: device)
        guard let db = network.db else { throw CLIRuntimeError("Failed to connect to the network") }
        return try await printMetadata(db: db, target: target)
    }

    /// 메타데이터·비트 그리드·파형·큐 요약을 낸다.
    func printMetadata(db: any NetworkDatabase, target: CLITrackTarget) async throws -> Int32 {
        output.log(.await, "Getting metadata: device \(target.deviceId) \(target.slot) track \(target.trackId)")
        let trackType = TrackType.rb
        try abort.check()
        guard
            let track = try await db.getMetadata(
                .init(deviceId: target.deviceId, trackSlot: target.slot, trackType: trackType, trackId: target.trackId))
        else {
            output.log(.warn, "no track")
            return CLIExitCode.failure
        }
        for line in formatTrackSummary(track) { output.writeLine(line) }
        output.writeLine(formatBeatGridSummary(track.beatGrid))

        // 요청한 파형·분석 조회가 실패하면(데이터가 없는 것과 다르다) 나머지를 낸 뒤 종료 코드 1로 끝낸다.
        var failed = false
        let trackOptions = DBTrackOptions(
            deviceId: target.deviceId, trackSlot: target.slot, trackType: trackType, track: track)
        do {
            output.writeLine(formatWaveformSummary(try await db.getWaveforms(trackOptions)))
        } catch is CLIAborted {
            throw CLIAborted()
        } catch {
            output.log(.error, "waveform: \(error)")
            failed = true
        }
        var extended: [ExtendedCue]?
        do {
            extended = try await db.getTrackAnalysis(trackOptions)?.extendedCues
        } catch is CLIAborted {
            throw CLIAborted()
        } catch {
            output.log(.error, "analysis: \(error)")
            failed = true
        }
        output.writeLine(formatCueSummary(track.cueAndLoops, extended: extended))
        return failed ? CLIExitCode.failure : CLIExitCode.ok
    }

    // MARK: fetch

    private func runFetch(options: CLICommonOptions, target: CLIFetchTarget) async throws -> Int32 {
        // 받기 전에 확인한다: 이미 있는 파일은 덮어쓰지 않는다.
        if runtime.files.fileExists(atPath: target.out) {
            throw CLIRuntimeError("\(target.out)이 이미 있다. 덮어쓰지 않는다")
        }
        setDeadline(seconds: target.timeoutSeconds)
        _ = try await openNetwork(options: options)
        let device = try await requireDevice(id: target.deviceId)
        if target.join {
            try await join(options: options, knownDevice: device)
        } else {
            // 듣기만 하더라도 NFS 요청은 보내므로 장치가 있는 인터페이스에 묶는다.
            try lockInterface(for: device)
        }
        output.log(.await, "Fetching \(target.path) from device \(device.id) \(target.slot)")
        try guardNFS(target.path)
        final class ProgressSteps {
            var lastStep = -1
        }
        let steps = ProgressSteps()
        let bytes = try await runtime.nfs.fetchFile(
            device: device, slot: target.slot, path: target.path,
            onProgress: { [output] progress in
                guard progress.total > 0 else { return }
                let step = progress.read * 10 / progress.total
                if step != steps.lastStep {
                    steps.lastStep = step
                    output.log(
                        .info, "\(step * 10)% (\(formatByteCount(progress.read)) / \(formatByteCount(progress.total)))")
                }
            }, chunkSize: nil)
        // 파일 쓰기 직전에 확인한다.
        try abort.check()
        do {
            try runtime.files.publishWithoutOverwriting(bytes, toPath: target.out)
        } catch is CLIFileExistsError {
            throw CLIRuntimeError("\(target.out)이 이미 있다. 덮어쓰지 않는다")
        }
        output.log(.success, "Wrote \(target.out) (\(formatByteCount(bytes.count)))")
        return CLIExitCode.ok
    }

    // MARK: mixstatus

    private func runMixstatus(options: CLICommonOptions) async throws -> Int32 {
        let network = try await openNetwork(options: options)
        try await join(options: options)
        guard let processor = network.mixstatus else { throw CLIRuntimeError("Failed to connect to the network") }
        processor.on(.nowPlaying) { [output] state in
            output.log(.star, "now playing: device \(state.deviceId) track \(state.trackId) \(formatStatus(state))")
        }
        processor.on(.stopped) { [output] in output.log(.info, "stopped: device \($0.deviceId)") }
        processor.on(.setStarted) { [output] _ in output.log(.info, "set started") }
        processor.on(.setEnded) { [output] _ in output.log(.info, "set ended") }
        output.log(.await, "Printing mixstatus events (Ctrl-C to stop)")
        await abort.wait()
        return CLIExitCode.interrupted
    }

    // MARK: control

    private func runControl(options: CLICommonOptions, request: CLIControlRequest) async throws -> Int32 {
        // 파서가 이미 거른 것을 실행 직전에 한 번 더 확인한다.
        if request.action != .load,
            let violation = checkPlayStateAllowed(
                deviceId: request.deviceId, unverifiedPlaystate: request.unverifiedPlaystate)
        {
            output.log(.error, violation.message)
            return CLIExitCode.refused
        }
        setDeadline(seconds: request.timeoutSeconds)
        // 먼저 듣기만 하며 대상 장치를 찾고, --confirm이 이름과 같을 때만 가상 CDJ로 참여한다.
        let network = try await openNetwork(options: options)
        let device = try await requireDevice(id: request.deviceId)
        if let violation = checkControlConfirmation(device: device, confirm: request.confirm) {
            output.log(.error, violation.message)
            return CLIExitCode.refused
        }
        try await join(options: options, knownDevice: device)
        guard let control = network.control, let statusEmitter = network.statusEmitter else {
            throw CLIRuntimeError("Failed to connect to the network")
        }

        final class LastStatus {
            var line: String?
        }
        let last = LastStatus()
        statusEmitter.on(.status) { state in
            if state.deviceId == device.id { last.line = formatStatus(state) }
        }
        // 제어 패킷을 보내기 직전에 확인한다.
        try abort.check()
        switch request.action {
        case .play:
            try await control.setPlayState(device, .playing)
        case .pause:
            // 능동 연결에서 정지 명령(0x01)은 `.cued`로 보낸다.
            try await control.setPlayState(device, .cued)
        case .load:
            guard let load = request.load else { throw CLIRuntimeError("load에는 곡 위치가 필요하다") }
            try await control.loadTrack(
                device, load.trackId,
                LoadSource(deviceId: load.sourceDeviceId, slot: load.slot, trackType: load.trackType))
        }
        output.log(.success, "Sent \(request.action.rawValue) to \(device.name) [id: \(device.id)]")
        if await abort.wait(seconds: 3, clock: runtime.clock) { return CLIExitCode.interrupted }
        if let line = last.line { output.writeLine("after: \(line)") }
        return CLIExitCode.ok
    }

    // MARK: passive

    private func runPassive(iface: String, positionIntervalMs: Int) async throws -> Int32 {
        output.log(.await, "Starting passive capture on \(iface) (needs BPF/root access; nothing is sent)")
        let network = try openPassive(iface: iface)
        output.log(.success, "Capturing on \(network.interfaceName)")
        network.deviceManager.on(.connected) { [output] in output.log(.star, "New device: \(formatDevice($0))") }
        network.deviceManager.on(.disconnected) { [output] in
            output.log(.info, "Device left: \($0.name) [id: \($0.id)]")
        }
        let printer = StatusPrinter(output: output, clock: runtime.clock, all: false, interval: positionIntervalMs)
        network.statusEmitter.on(.status) { printer.status($0) }
        network.statusEmitter.on(.onAir) { printer.onAir($0) }
        network.statusEmitter.on(.mediaSlot) { printer.mediaSlot($0) }
        network.positionEmitter.on(.position) { printer.position($0) }
        await abort.wait()
        return CLIExitCode.interrupted
    }
}

/// 상태·정밀 위치·on-air·미디어 슬롯을 한 줄씩 찍는 처리기. 줄이는 규칙은 `StatusLineFilter`·`LineThrottle`.
@DJLinkActor
private final class StatusPrinter {
    private let output: any CLIOutput
    private let clock: any DJLinkClock
    private var filter: StatusLineFilter
    private var throttle: LineThrottle

    init(output: any CLIOutput, clock: any DJLinkClock, all: Bool, interval: Int) {
        self.output = output
        self.clock = clock
        filter = StatusLineFilter(all: all)
        throttle = LineThrottle(intervalMs: interval)
    }

    func status(_ state: CDJStatus.State) {
        if let line = filter.line(for: state) { output.writeLine(line) }
    }

    func onAir(_ value: CDJStatus.OnAirStatus) { output.writeLine(formatOnAir(value)) }

    func mediaSlot(_ value: MediaSlotInfo) { output.writeLine(formatMediaSlot(value)) }

    func position(_ position: CDJStatus.PositionState) {
        if throttle.shouldEmit(key: position.deviceId, nowMs: clock.nowMilliseconds()) {
            output.writeLine(formatPosition(position))
        }
    }
}
