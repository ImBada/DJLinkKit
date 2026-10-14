import DJLinkKit
import DJLinkTestSupport
import Dispatch
import Synchronization
import Testing

@testable import djlink

@DJLinkActor
private final class RecoveryDatabase: NetworkDatabase {
    var hostDevice: Device { mockDevice(id: 7) }
    var outcomes: [Result<Track?, DJLinkError>] = []
    var heldRequests: Set<Int> = []
    private var pending: [Int: CheckedContinuation<Track?, any Error>] = [:]
    private(set) var requests: [GetMetadata.Options] = []
    private(set) var fileRequests = 0
    var fileError: DJLinkError?
    var fileByTrack: [Int: [UInt8]] = [:]

    func getMetadata(_ opts: GetMetadata.Options) async throws -> Track? {
        let index = requests.count
        requests.append(opts)
        if heldRequests.contains(index) {
            return try await withCheckedThrowingContinuation { pending[index] = $0 }
        }
        if index < outcomes.count { return try outcomes[index].get() }
        return makeTrack(id: opts.trackId, title: "Track \(opts.trackId)")
    }

    func resolve(_ index: Int, with result: Result<Track?, DJLinkError>) {
        guard let continuation = pending.removeValue(forKey: index) else {
            Issue.record("보류한 조회가 없다")
            return
        }
        switch result {
        case .success(let track): continuation.resume(returning: track)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    func getDatabaseType(_ deviceId: DeviceID, _ slot: MediaSlot) -> DatabaseType? { nil }
    func getFile(_ opts: GetFile.Options) async throws -> [UInt8]? {
        fileRequests += 1
        if let fileError { throw fileError }
        return fileByTrack[opts.track.id]
    }
    func getArtworkThumbnail(_ opts: GetArtworkThumbnail.Options) async throws -> [UInt8]? { nil }
    func getArtwork(_ opts: GetArtworkFromFile.Options) async -> [UInt8]? { nil }
    func getWaveforms(_ opts: GetWaveforms.Options) async throws -> Waveforms? { nil }
    func getTrackAnalysis(_ opts: GetTrackAnalysis.Options) async throws -> TrackAnalysis? { nil }
    func getPlaylist(_ opts: GetPlaylist.Options) async throws -> PlaylistContents? { nil }
}

/// 파일 게시의 완료를 보류한다. 디스크에는 쓰지 않는다.
private final class RecoveryPublisher: CLIFileWriter {
    private let started = Mutex(false)
    private let gate = DispatchSemaphore(value: 0)
    private let exists: Bool
    var hasStarted: Bool { started.withLock { $0 } }
    init(exists: Bool) { self.exists = exists }
    func release() { gate.signal() }
    func fileExists(atPath path: String) -> Bool { false }
    func createDirectory(atPath path: String) throws {}
    func publishWithoutOverwriting(
        _ data: [UInt8], toPath path: String, checkCancellation: @Sendable () throws -> Void
    ) throws {
        started.withLock { $0 = true }
        guard gate.wait(timeout: .now() + 5) == .success else {
            throw CLIFileError(message: "시험 파일 게시 대기가 끝나지 않았다")
        }
        try checkCancellation()
        if exists { throw CLIFileExistsError(path: path) }
    }
}

@DJLinkActor
private func recoveryWatch(_ db: RecoveryDatabase, downloadDir: String? = nil) async throws
    -> (CLIHarness, CLISession, ProlinkNetwork, StatusEmitter)
{
    let h = CLIHarness()
    let session = h.makeSession()
    let options = CLICommonOptions(iface: "en7")
    let network = try await session.openNetwork(options: options)
    try h.announce(try cdj(1, "192.168.1.20"))
    try h.announce(try cdj(2, "192.168.1.21"))
    try await session.join(options: options)
    let status = try #require(network.statusEmitter)
    session.attachWatchTrackHandlers(network: network, statusEmitter: status, db: db, downloadDir: downloadDir)
    return (h, session, network, status)
}

@Suite("CLI watch 재접속과 조회 복구")
@DJLinkActor
struct CLIWatchRecoveryTests {
    @Test("파일 게시를 기다리다 무효화된 조회는 완료·파일 존재 안내를 출력하지 않는다", arguments: [false, true])
    func obsoletePublish(_ exists: Bool) async throws {
        let h = CLIHarness()
        let publisher = RecoveryPublisher(exists: exists)
        h.fileWriterOverride = publisher
        let session = h.makeSession()
        let db = RecoveryDatabase()
        db.fileByTrack[5] = [1, 2, 3]
        let obsolete = CLIFlag()
        let change = Task { @DJLinkActor in
            await session.handleTrackChange(
                makeState(), db: db, downloadDir: "/fake-download", isCurrent: { !obsolete.isSet })
        }
        for _ in 0..<1000 {
            if publisher.hasStarted { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(publisher.hasStarted)
        // 새 상태·연결이 관찰돼 ticket이 무효화된 상황을 같은 경계에서 재현한다.
        obsolete.set()
        publisher.release()
        #expect(await change.value == false)
        #expect(!h.output.lines.contains { $0.hasPrefix("Copied ") })
        #expect(!h.output.errorLines.contains { $0.contains("이미 있어") })
        await session.cleanup()
    }

    @Test("조회 중과 성공 뒤의 반복 상태는 중복 조회·출력을 만들지 않는다")
    func repeatedStates() async throws {
        let db = RecoveryDatabase()
        db.heldRequests = [0]
        let (h, session, _, status) = try await recoveryWatch(db)
        let state = makeState()
        for _ in 0..<50 { status.emitter.emit(.status, state) }
        await h.settle()
        #expect(db.requests.count == 1)
        db.resolve(0, with: .success(makeTrack()))
        await h.settle()
        var changedBeat = state
        changedBeat.beatInMeasure = 4
        changedBeat.effectivePitch = 1
        for _ in 0..<50 { status.emitter.emit(.status, changedBeat) }
        await h.settle()
        #expect(db.requests.count == 1)
        #expect(h.output.lines.filter { $0 == "5 Song" }.count == 1)
        h.abort.interrupt()
        await session.cleanup()
    }

    @Test("같은 곡 ID라도 원본 장치·슬롯·곡 종류가 달라지면 다시 조회한다")
    func sourceIdentityChanges() async throws {
        let db = RecoveryDatabase()
        let (h, session, _, status) = try await recoveryWatch(db)
        var state = makeState()
        status.emitter.emit(.status, state)
        await h.settle()
        state.trackDeviceId = 2
        status.emitter.emit(.status, state)
        await h.settle()
        state.trackSlot = .sd
        status.emitter.emit(.status, state)
        await h.settle()
        state.trackType = .unanalyzed
        status.emitter.emit(.status, state)
        await h.settle()
        #expect(db.requests.count == 4)
        #expect(db.requests.map(\.deviceId) == [1, 2, 2, 2])
        #expect(db.requests.map(\.trackSlot) == [.usb, .usb, .sd, .sd])
        #expect(db.requests.map(\.trackType) == [.rb, .rb, .rb, .unanalyzed])
        h.abort.interrupt()
        await session.cleanup()
    }

    @Test("재생 덱이나 원본 장치가 재접속하면 같은 곡도 0 상태 없이 다시 조회한다", arguments: [1, 2])
    func reconnectsWithSameTrack(_ removedId: Int) async throws {
        let db = RecoveryDatabase()
        let (h, session, network, status) = try await recoveryWatch(db)
        let state = makeState(deviceId: 2, trackDeviceId: 1)
        status.emitter.emit(.status, state)
        await h.settle()
        let removedDevice = network.deviceManager.devices.removeValue(forKey: removedId)
        let removed = try #require(removedDevice)
        network.deviceManager.emitter.emit(.disconnected, removed)
        try h.announce(removed)
        status.emitter.emit(.status, state)
        await h.settle()
        #expect(db.requests.count == 2)
        #expect(h.output.lines.filter { $0 == "5 Track 5" }.count == 2)
        h.abort.interrupt()
        await session.cleanup()
    }

    @Test("일시 오류와 데이터 없음은 1초 간격으로 재시도하고 성공 뒤에는 멈춘다")
    func retriesTransientFailures() async throws {
        let db = RecoveryDatabase()
        db.outcomes = [.failure(DJLinkError("일시 조회 실패")), .success(nil), .success(makeTrack())]
        let (h, session, _, status) = try await recoveryWatch(db)
        let state = makeState()
        status.emitter.emit(.status, state)
        await h.settle()
        h.clock.advance(ms: 999)
        for _ in 0..<20 { status.emitter.emit(.status, state) }
        await h.settle()
        #expect(db.requests.count == 1)
        h.clock.advance(ms: 1)
        status.emitter.emit(.status, state)
        await h.settle()
        #expect(db.requests.count == 2)
        h.clock.advance(ms: 1000)
        status.emitter.emit(.status, state)
        await h.settle()
        for _ in 0..<20 { status.emitter.emit(.status, state) }
        await h.settle()
        #expect(db.requests.count == 3)
        #expect(h.output.lines.filter { $0 == "5 Song" }.count == 1)
        h.abort.interrupt()
        await session.cleanup()
    }

    @Test("연속 실패는 3회에서 멈추고 연결이 바뀌어야 횟수를 초기화한다")
    func limitsFailures() async throws {
        let db = RecoveryDatabase()
        db.outcomes = Array(repeating: .failure(DJLinkError("조회 실패")), count: 4)
        let (h, session, network, status) = try await recoveryWatch(db)
        let state = makeState()
        for _ in 0..<3 {
            status.emitter.emit(.status, state)
            await h.settle()
            h.clock.advance(ms: 1000)
        }
        h.clock.advance(ms: 3000)
        for _ in 0..<50 { status.emitter.emit(.status, state) }
        await h.settle()
        #expect(db.requests.count == 3)
        #expect(h.output.errorLines.filter { $0.contains("3회 실패") }.count == 1)
        let removedDevice = network.deviceManager.devices.removeValue(forKey: 1)
        let device = try #require(removedDevice)
        network.deviceManager.emitter.emit(.disconnected, device)
        try h.announce(device)
        status.emitter.emit(.status, state)
        await h.settle()
        #expect(db.requests.count == 4)
        h.abort.interrupt()
        await session.cleanup()
    }

    @Test("이전 곡의 늦은 성공·실패가 새 곡 출력이나 재시도 기록을 바꾸지 않는다", arguments: [false, true])
    func ignoresOldCompletions(_ fails: Bool) async throws {
        let db = RecoveryDatabase()
        db.heldRequests = [0]
        let (h, session, _, status) = try await recoveryWatch(db)
        status.emitter.emit(.status, makeState(trackId: 5))
        await h.settle()
        status.emitter.emit(.status, makeState(trackId: 6))
        await h.settle()
        db.resolve(0, with: fails ? .failure(DJLinkError("늦은 오류")) : .success(makeTrack()))
        await h.settle()
        for _ in 0..<10 { status.emitter.emit(.status, makeState(trackId: 6)) }
        await h.settle()
        #expect(db.requests.count == 2)
        #expect(h.output.lines.filter { $0 == "6 Track 6" }.count == 1)
        #expect(!h.output.lines.contains("5 Song"))
        #expect(!h.output.errorLines.contains { $0.contains("늦은 오류") })
        h.abort.interrupt()
        await session.cleanup()
    }

    @Test("빈 덱 상태와 중단은 보류 조회 결과를 버리고 중단 뒤 새 조회를 만들지 않는다", arguments: [false, true])
    func emptyOrInterrupted(_ interrupt: Bool) async throws {
        let db = RecoveryDatabase()
        db.heldRequests = [0]
        let (h, session, _, status) = try await recoveryWatch(db)
        status.emitter.emit(.status, makeState())
        await h.settle()
        if interrupt { h.abort.interrupt() } else { status.emitter.emit(.status, makeState(trackId: 0)) }
        db.resolve(0, with: .success(makeTrack()))
        await h.settle()
        #expect(!h.output.lines.contains("5 Song"))
        if interrupt {
            status.emitter.emit(.status, makeState())
            await h.settle()
            #expect(db.requests.count == 1)
        }
        h.abort.interrupt()
        await session.cleanup()
    }

    @Test("선택적 다운로드 실패 때문에 성공한 메타데이터를 반복 조회하지 않는다")
    func downloadFailureDoesNotRetryMetadata() async throws {
        let db = RecoveryDatabase()
        db.fileError = DJLinkError("다운로드 실패")
        let (h, session, _, status) = try await recoveryWatch(db, downloadDir: "/fake-download")
        let state = makeState()
        status.emitter.emit(.status, state)
        await h.settle()
        h.clock.advance(ms: 1000)
        for _ in 0..<10 { status.emitter.emit(.status, state) }
        await h.settle()
        #expect(db.requests.count == 1 && db.fileRequests == 1)
        #expect(h.output.lines.filter { $0 == "5 Track 5" }.count == 1)
        #expect(h.files.writes == 0)
        h.abort.interrupt()
        await session.cleanup()
    }
}
