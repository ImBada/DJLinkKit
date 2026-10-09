import DJLinkControl
import DJLinkKit
import DJLinkPassive
import Foundation

// 하위 명령 실행. 실제 소켓을 열기 때문에 시험하지 않는다(판단 로직은 CLIArguments·CLISafety·CLIFormat에 있다).

/// 명령을 실행하고 종료 코드를 돌려준다. 시험은 가짜를 넣는다.
protocol CLICommandExecutor: Sendable {
    func execute(_ command: CLICommand, output: any CLIOutput) async -> Int32
}

/// 종료 코드. 0 정상, 1 실행 실패, 2 사용법·안전 규칙 거부, 130 중단(Ctrl-C).
enum CLIExitCode {
    static let ok: Int32 = 0
    static let failure: Int32 = 1
    static let refused: Int32 = 2
    static let interrupted: Int32 = 130
}

struct LiveCLIExecutor: CLICommandExecutor {
    init() {}

    func execute(_ command: CLICommand, output: any CLIOutput) async -> Int32 {
        await runLive(command, output: output)
    }
}

@DJLinkActor
private func runLive(_ command: CLICommand, output: any CLIOutput) async -> Int32 {
    CLIInterrupt.shared.install()
    do {
        switch command {
        case .help:
            return CLIExitCode.ok
        case .devices(let seconds, let verbose):
            return try await runDevices(seconds: seconds, verbose: verbose, output: output)
        case .watch(let options, let downloadDir):
            return try await runWatch(options: options, downloadDir: downloadDir, output: output)
        case .status(let options, let all, let interval):
            return try await runStatus(options: options, all: all, positionIntervalMs: interval, output: output)
        case .metadata(let options, let target):
            return try await runMetadata(options: options, target: target, output: output)
        case .fetch(let options, let target):
            return try await runFetch(options: options, target: target, output: output)
        case .mixstatus(let options):
            return try await runMixstatus(options: options, output: output)
        case .control(let options, let request):
            return try await runControl(options: options, request: request, output: output)
        case .passive(let iface, let interval):
            return try await runPassive(iface: iface, positionIntervalMs: interval, output: output)
        }
    } catch let error as CLIRuntimeError {
        output.log(.error, error.message)
        return CLIExitCode.failure
    } catch {
        output.log(.error, "\(error)")
        return CLIExitCode.failure
    }
}

// MARK: - devices

@DJLinkActor
private func runDevices(seconds: Int, verbose: Bool, output: any CLIOutput) async throws -> Int32 {
    let network = try await openListeningNetwork(options: CLICommonOptions(verbose: verbose), output: output)
    output.log(.await, "Listening for device announcements for \(seconds)s (Ctrl-C to stop)")
    let interrupted = await CLIInterrupt.shared.wait(seconds: seconds)
    let devices = network.deviceManager.devices.values.sorted { $0.id < $1.id }
    output.log(.info, "\(devices.count) device(s) on the network")
    for device in devices { output.writeLine("  \(formatDevice(device))") }
    await shutdown(network)
    return interrupted ? CLIExitCode.interrupted : CLIExitCode.ok
}

// MARK: - watch (원본 src/cli/index.ts)

/// 장치마다 마지막으로 본 곡 번호(원본 `lastTid` Map).
@DJLinkActor
private final class LastTrackIds {
    var ids: [Int: Int] = [:]
    init() {}
}

@DJLinkActor
private func runWatch(options: CLICommonOptions, downloadDir: String?, output: any CLIOutput) async throws -> Int32 {
    let network = try await openListeningNetwork(options: options, output: output)
    guard try await joinNetwork(network, options: options, output: output) else {
        await shutdown(network)
        return CLIExitCode.interrupted
    }
    guard let statusEmitter = network.statusEmitter, let db = network.db else {
        await shutdown(network)
        throw CLIRuntimeError("Failed to connect to the network")
    }

    if let downloadDir {
        output.log(.info, "받은 파일은 \(downloadDir)에 쓴다")
    } else {
        output.log(.info, "--download-dir를 주지 않았으므로 파일은 받지 않고 제목만 출력한다")
    }

    let processor = MixstatusProcessor()
    statusEmitter.on(.status) { processor.handleState($0) }

    let lastTid = LastTrackIds()
    statusEmitter.on(.status) { state in
        if lastTid.ids[state.deviceId] == state.trackId { return }
        lastTid.ids[state.deviceId] = state.trackId
        // 원본과 다름: 곡이 없는 상태(trackId 0)는 조회하지 않는다. 실기에 쓸데없는 질의를 보내지 않으려는 것이다.
        if state.trackId == 0 { return }
        Task { @DJLinkActor in
            await handleTrackChange(state, db: db, downloadDir: downloadDir, output: output)
        }
    }

    await CLIInterrupt.shared.wait()
    output.log(.info, "Interrupted, closing")
    await shutdown(network)
    return CLIExitCode.ok
}

@DJLinkActor
private func handleTrackChange(
    _ state: CDJStatus.State, db: any NetworkDatabase, downloadDir: String?, output: any CLIOutput
) async {
    do {
        let track = try await db.getMetadata(
            .init(
                deviceId: state.trackDeviceId, trackSlot: state.trackSlot, trackType: state.trackType,
                trackId: state.trackId))
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
                deviceId: state.trackDeviceId, trackSlot: state.trackSlot, trackType: state.trackType, track: track))
        guard let buf else { return }
        let directory = URL(fileURLWithPath: downloadDir, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(buf).write(to: directory.appendingPathComponent(fileName), options: .atomic)
        output.writeLine("Copied \(fileName)")
    } catch {
        output.log(.error, "track \(state.trackId): \(error)")
    }
}

// MARK: - status

@DJLinkActor
private func runStatus(
    options: CLICommonOptions, all: Bool, positionIntervalMs: Int, output: any CLIOutput
) async throws -> Int32 {
    let network = try await openListeningNetwork(options: options, output: output)
    guard try await joinNetwork(network, options: options, output: output) else {
        await shutdown(network)
        return CLIExitCode.interrupted
    }
    guard let statusEmitter = network.statusEmitter, let positionEmitter = network.positionEmitter else {
        await shutdown(network)
        throw CLIRuntimeError("Failed to connect to the network")
    }
    attachStatusPrinters(
        statusEmitter: statusEmitter, positionEmitter: positionEmitter, all: all,
        positionIntervalMs: positionIntervalMs,
        output: output)
    output.log(.await, "Printing status, precise position and on-air (Ctrl-C to stop)")
    await CLIInterrupt.shared.wait()
    await shutdown(network)
    return CLIExitCode.ok
}

/// 상태·정밀 위치·on-air·미디어 슬롯을 한 줄씩 찍는다. 줄이는 규칙은 `StatusLineFilter`·`LineThrottle`.
@DJLinkActor
private func attachStatusPrinters(
    statusEmitter: StatusEmitter, positionEmitter: PositionEmitter, all: Bool, positionIntervalMs: Int,
    output: any CLIOutput
) {
    final class Lines {
        var filter: StatusLineFilter
        var throttle: LineThrottle
        init(all: Bool, interval: Int) {
            filter = StatusLineFilter(all: all)
            throttle = LineThrottle(intervalMs: interval)
        }
    }
    let lines = Lines(all: all, interval: positionIntervalMs)
    statusEmitter.on(.status) { state in
        if let line = lines.filter.line(for: state) { output.writeLine(line) }
    }
    statusEmitter.on(.onAir) { output.writeLine(formatOnAir($0)) }
    statusEmitter.on(.mediaSlot) { output.writeLine(formatMediaSlot($0)) }
    positionEmitter.on(.position) { position in
        if lines.throttle.shouldEmit(key: position.deviceId, nowMs: SystemClock.shared.nowMilliseconds()) {
            output.writeLine(formatPosition(position))
        }
    }
}

// MARK: - metadata

@DJLinkActor
private func runMetadata(
    options: CLICommonOptions, target: CLITrackTarget, output: any CLIOutput
) async throws -> Int32 {
    let network = try await openListeningNetwork(options: options, output: output)
    guard try await joinNetwork(network, options: options, output: output) else {
        await shutdown(network)
        return CLIExitCode.interrupted
    }
    let result: Int32?
    do {
        result = try await CLIInterrupt.shared.race {
            try await printMetadata(network: network, target: target, output: output)
        }
    } catch {
        await shutdown(network)
        throw error
    }
    await shutdown(network)
    return result ?? CLIExitCode.interrupted
}

@DJLinkActor
private func printMetadata(network: ProlinkNetwork, target: CLITrackTarget, output: any CLIOutput) async throws -> Int32
{
    guard let db = network.db else { throw CLIRuntimeError("Failed to connect to the network") }
    _ = try await requireDevice(network, id: target.deviceId)
    output.log(.await, "Getting metadata: device \(target.deviceId) \(target.slot) track \(target.trackId)")
    let trackType = TrackType.rb
    guard
        let track = try await db.getMetadata(
            .init(deviceId: target.deviceId, trackSlot: target.slot, trackType: trackType, trackId: target.trackId))
    else {
        output.log(.warn, "no track")
        return CLIExitCode.failure
    }
    for line in formatTrackSummary(track) { output.writeLine(line) }
    output.writeLine(formatBeatGridSummary(track.beatGrid))

    let options = DBTrackOptions(
        deviceId: target.deviceId, trackSlot: target.slot, trackType: trackType, track: track)
    do {
        output.writeLine(formatWaveformSummary(try await db.getWaveforms(options)))
    } catch {
        output.log(.warn, "waveform: \(error)")
    }
    var extended: [ExtendedCue]?
    do {
        extended = try await db.getTrackAnalysis(options)?.extendedCues
    } catch {
        output.log(.warn, "analysis: \(error)")
    }
    output.writeLine(formatCueSummary(track.cueAndLoops, extended: extended))
    return CLIExitCode.ok
}

// MARK: - fetch

@DJLinkActor
private final class ProgressSteps {
    var lastStep = -1
    init() {}
}

@DJLinkActor
private func runFetch(options: CLICommonOptions, target: CLIFetchTarget, output: any CLIOutput) async throws -> Int32 {
    let outURL = URL(fileURLWithPath: target.out)
    // 받기 전에 확인한다: 이미 있는 파일은 덮어쓰지 않는다.
    if FileManager.default.fileExists(atPath: outURL.path) {
        throw CLIRuntimeError("\(target.out)이 이미 있다. 덮어쓰지 않는다")
    }
    let network = try await openListeningNetwork(options: options, output: output)
    if target.join {
        guard try await joinNetwork(network, options: options, output: output) else {
            await shutdown(network)
            return CLIExitCode.interrupted
        }
    }
    let result: Int32?
    do {
        result = try await CLIInterrupt.shared.race {
            let device = try await requireDevice(network, id: target.deviceId)
            output.log(.await, "Fetching \(target.path) from device \(device.id) \(target.slot)")
            let steps = ProgressSteps()
            let bytes = try await fetchFile(
                device: device, slot: target.slot, path: target.path,
                onProgress: { progress in
                    guard progress.total > 0 else { return }
                    let step = progress.read * 10 / progress.total
                    if step != steps.lastStep {
                        steps.lastStep = step
                        output.log(
                            .info,
                            "\(step * 10)% (\(formatByteCount(progress.read)) / \(formatByteCount(progress.total)))")
                    }
                })
            try Data(bytes).write(to: outURL, options: [.atomic, .withoutOverwriting])
            output.log(.success, "Wrote \(target.out) (\(formatByteCount(bytes.count)))")
            return CLIExitCode.ok
        }
    } catch {
        await shutdown(network)
        throw error
    }
    await shutdown(network)
    return result ?? CLIExitCode.interrupted
}

// MARK: - mixstatus

@DJLinkActor
private func runMixstatus(options: CLICommonOptions, output: any CLIOutput) async throws -> Int32 {
    let network = try await openListeningNetwork(options: options, output: output)
    guard try await joinNetwork(network, options: options, output: output) else {
        await shutdown(network)
        return CLIExitCode.interrupted
    }
    guard let processor = network.mixstatus else {
        await shutdown(network)
        throw CLIRuntimeError("Failed to connect to the network")
    }
    processor.on(.nowPlaying) { state in
        output.log(.star, "now playing: device \(state.deviceId) track \(state.trackId) \(formatStatus(state))")
    }
    processor.on(.stopped) { output.log(.info, "stopped: device \($0.deviceId)") }
    processor.on(.setStarted) { _ in output.log(.info, "set started") }
    processor.on(.setEnded) { _ in output.log(.info, "set ended") }
    output.log(.await, "Printing mixstatus events (Ctrl-C to stop)")
    await CLIInterrupt.shared.wait()
    await shutdown(network)
    return CLIExitCode.ok
}

// MARK: - control

@DJLinkActor
private func runControl(options: CLICommonOptions, request: CLIControlRequest, output: any CLIOutput) async throws
    -> Int32
{
    // 먼저 듣기만 하며 대상 장치를 찾고, --confirm이 이름과 같을 때만 가상 CDJ로 참여한다.
    let network = try await openListeningNetwork(options: options, output: output)
    let device: Device
    do {
        guard let found = try await CLIInterrupt.shared.race({ try await requireDevice(network, id: request.deviceId) })
        else {
            await shutdown(network)
            return CLIExitCode.interrupted
        }
        device = found
    } catch {
        await shutdown(network)
        throw error
    }
    if let violation = checkControlConfirmation(device: device, confirm: request.confirm) {
        output.log(.error, violation.message)
        await shutdown(network)
        return CLIExitCode.refused
    }
    guard try await joinNetwork(network, options: options, knownDevice: device, output: output) else {
        await shutdown(network)
        return CLIExitCode.interrupted
    }
    guard let control = network.control, let statusEmitter = network.statusEmitter else {
        await shutdown(network)
        throw CLIRuntimeError("Failed to connect to the network")
    }

    final class LastStatus {
        var line: String?
        init() {}
    }
    let last = LastStatus()
    statusEmitter.on(.status) { state in
        if state.deviceId == device.id { last.line = formatStatus(state) }
    }
    do {
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
    } catch {
        await shutdown(network)
        throw error
    }
    output.log(.success, "Sent \(request.action.rawValue) to \(device.name) [id: \(device.id)]")
    let interrupted = await CLIInterrupt.shared.wait(seconds: 3)
    if let line = last.line { output.writeLine("after: \(line)") }
    await shutdown(network)
    return interrupted ? CLIExitCode.interrupted : CLIExitCode.ok
}

// MARK: - passive

@DJLinkActor
private func runPassive(iface: String, positionIntervalMs: Int, output: any CLIOutput) async throws -> Int32 {
    output.log(.await, "Starting passive capture on \(iface) (needs BPF/root access; nothing is sent)")
    let network: PassiveProlinkNetwork
    do {
        network = try bringOnlinePassive(PassiveNetworkConfig(iface: iface))
    } catch {
        throw CLIRuntimeError("패시브 캡처를 시작하지 못했다: \(error)")
    }
    output.log(.success, "Capturing on \(network.interfaceName)")
    network.deviceManager.on(.connected) { output.log(.star, "New device: \(formatDevice($0))") }
    network.deviceManager.on(.disconnected) { output.log(.info, "Device left: \($0.name) [id: \($0.id)]") }

    final class Lines {
        var filter = StatusLineFilter(all: false)
        var throttle: LineThrottle
        init(interval: Int) { throttle = LineThrottle(intervalMs: interval) }
    }
    let lines = Lines(interval: positionIntervalMs)
    network.statusEmitter.on(.status) { state in
        if let line = lines.filter.line(for: state) { output.writeLine(line) }
    }
    network.statusEmitter.on(.onAir) { output.writeLine(formatOnAir($0)) }
    network.statusEmitter.on(.mediaSlot) { output.writeLine(formatMediaSlot($0)) }
    network.positionEmitter.on(.position) { position in
        if lines.throttle.shouldEmit(key: position.deviceId, nowMs: SystemClock.shared.nowMilliseconds()) {
            output.writeLine(formatPosition(position))
        }
    }
    await CLIInterrupt.shared.wait()
    network.stop()
    return CLIExitCode.ok
}
