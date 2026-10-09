// 원본 src/mixstatus/index.ts

public struct MixstatusConfig: Equatable, Sendable {
    /// Selects the mixstatus reporting mode
    public var mode: MixstatusMode
    /// Specifies the duration in seconds that no tracks must be on air. This can
    /// be thought of as how long 'air silence' is reasonable in a set before a
    /// separate one is considered have begun.
    ///
    /// @default 30 (half a minute)
    public var timeBetweenSets: Double
    /// Indicates if the status objects reported should have their on-air flag
    /// read. Setting this to false will degrade the functionality of the processor
    /// such that it will not consider the value of isOnAir and always assume CDJs
    /// are live.
    ///
    /// @default true
    public var useOnAirStatus: Bool
    /// Configures how many beats a track may not be live or playing for it to
    /// still be considered active.
    ///
    /// @default 8 (two bars)
    public var allowedInterruptBeats: Double
    /// Configures how many beats the track must consecutively be playing for
    /// (since the beat it was cued at) until the track is considered to be
    /// active.
    ///
    /// Used for MixstatusMode.SmartTiming
    ///
    /// @default 128 (2 phrases)
    public var beatsUntilReported: Double

    public init(
        mode: MixstatusMode,
        timeBetweenSets: Double,
        useOnAirStatus: Bool,
        allowedInterruptBeats: Double,
        beatsUntilReported: Double
    ) {
        self.mode = mode
        self.timeBetweenSets = timeBetweenSets
        self.useOnAirStatus = useOnAirStatus
        self.allowedInterruptBeats = allowedInterruptBeats
        self.beatsUntilReported = beatsUntilReported
    }
}

/// 원본 `Partial<MixstatusConfig>`. 넘기지 않은 칸(nil)은 기본값이나 지금 값을 그대로 둔다(`{...defaultConfig, ...config}`).
public struct MixstatusConfigPartial: Equatable, Sendable {
    public var mode: MixstatusMode?
    public var timeBetweenSets: Double?
    public var useOnAirStatus: Bool?
    public var allowedInterruptBeats: Double?
    public var beatsUntilReported: Double?

    public init(
        mode: MixstatusMode? = nil,
        timeBetweenSets: Double? = nil,
        useOnAirStatus: Bool? = nil,
        allowedInterruptBeats: Double? = nil,
        beatsUntilReported: Double? = nil
    ) {
        self.mode = mode
        self.timeBetweenSets = timeBetweenSets
        self.useOnAirStatus = useOnAirStatus
        self.allowedInterruptBeats = allowedInterruptBeats
        self.beatsUntilReported = beatsUntilReported
    }
}

extension MixstatusConfig {
    fileprivate mutating func merge(_ config: MixstatusConfigPartial) {
        if let mode = config.mode { self.mode = mode }
        if let timeBetweenSets = config.timeBetweenSets { self.timeBetweenSets = timeBetweenSets }
        if let useOnAirStatus = config.useOnAirStatus { self.useOnAirStatus = useOnAirStatus }
        if let allowedInterruptBeats = config.allowedInterruptBeats {
            self.allowedInterruptBeats = allowedInterruptBeats
        }
        if let beatsUntilReported = config.beatsUntilReported { self.beatsUntilReported = beatsUntilReported }
    }
}

private let defaultConfig = MixstatusConfig(
    mode: .smartTiming,
    timeBetweenSets: 30,
    useOnAirStatus: true,
    allowedInterruptBeats: 8,
    beatsUntilReported: 128
)

/// `stopped` 이벤트가 넘기는 값(원본 `{deviceId}`).
public struct MixstatusStopped: Equatable, Sendable {
    public var deviceId: DeviceID

    public init(deviceId: DeviceID) {
        self.deviceId = deviceId
    }
}

// The interface the mix status event emitter should follow
extension EventName where Owner == MixstatusProcessor, Payload == CDJStatus.State {
    /// Fired when a track is considered to be on-air and is being heard by the
    /// audience
    public static var nowPlaying: Self { .init("nowPlaying") }
}

extension EventName where Owner == MixstatusProcessor, Payload == MixstatusStopped {
    /// Fired when a track has stopped and is completely offair
    public static var stopped: Self { .init("stopped") }
}

extension EventName where Owner == MixstatusProcessor, Payload == Void {
    /// Fired when a DJ set first starts
    public static var setStarted: Self { .init("setStarted") }
    /// Fired when tracks have been stopped
    public static var setEnded: Self { .init("setEnded") }
}

/// 원본 `Map`처럼 처음 넣은 순서를 지키는 장치 번호별 사전.
/// `set`은 이미 있는 키의 자리를 바꾸지 않고, `delete` 뒤에 다시 `set`하면 맨 뒤로 간다.
private struct InsertionOrderedMap<Value> {
    private var keys: [DeviceID] = []
    private var values: [DeviceID: Value] = [:]

    func get(_ key: DeviceID) -> Value? {
        values[key]
    }

    func has(_ key: DeviceID) -> Bool {
        values[key] != nil
    }

    mutating func set(_ key: DeviceID, _ value: Value) {
        if values[key] == nil {
            keys.append(key)
        }
        values[key] = value
    }

    mutating func delete(_ key: DeviceID) {
        guard values.removeValue(forKey: key) != nil else { return }
        keys.removeAll { $0 == key }
    }

    var entries: [(key: DeviceID, value: Value)] {
        keys.map { (key: $0, value: values[$0]!) }
    }
}

/// 원본 `new Promise<boolean>`. 한 번만 해결되고, 이어지는 부분(`await` 뒤)은 해결한 처리 단위가 끝난 직후에 돈다
/// (JS의 마이크로태스크). 액터 큐 끝에 붙이면(Task) 이미 큐에 있던 패킷·타이머가 먼저 돌아 순서가 바뀌므로,
/// 프로세서의 마이크로태스크 목록(`enqueueMicrotask`)에 넣는다.
@DJLinkActor
private final class SetEndingPromise {
    private var settled = false
    private let then: @DJLinkActor (Bool) -> Void
    private let enqueue: @DJLinkActor (@escaping @DJLinkActor () -> Void) -> Void

    init(
        enqueue: @escaping @DJLinkActor (@escaping @DJLinkActor () -> Void) -> Void,
        then: @escaping @DJLinkActor (Bool) -> Void
    ) {
        self.enqueue = enqueue
        self.then = then
    }

    func resolve(_ value: Bool) {
        guard !settled else { return }
        settled = true
        let then = then
        enqueue { then(value) }
    }
}

/// MixstatusProcessor is a configurable processor which when fed device state
/// will attempt to accurately determine events that happen within the DJ set.
///
/// The following events are fired:
///
/// - nowPlaying: The track is considered playing and on air to the audience.
/// - stopped:    The track was stopped / paused / went off-air.
///
/// Additionally the following non-track status are reported:
///
/// - setStarted: The first track has begun playing.
/// - setEnded:   The TimeBetweenSets has passed since any tracks were live.
///
/// See Config for configuration options.
///
/// Config options may be changed after the processor has been created and is
/// actively receiving state updates.
@DJLinkActor
public final class MixstatusProcessor: EventEmitting {
    /// Used to fire track mix status events
    public let emitter = EventHub<MixstatusProcessor>()
    /// Records the most recent state of each player
    private var lastState: [DeviceID: CDJStatus.State] = [:]
    /// Records when each device last started playing a track
    private var lastStartTime = InsertionOrderedMap<Double>()
    /// Records when a device entered a 'may stop' state. If it's in the state for
    /// long enough it will be reported as stopped.
    private var lastStoppedTimes: [DeviceID: Double] = [:]
    /// Records which players have been reported as 'live'
    private var livePlayers: Set<DeviceID> = []
    /// Records the last trackId emitted as 'nowPlaying' for each device. Used to
    /// suppress duplicate emissions when a deck is briefly cued/loaded and then
    /// resumed on the same track (a common pattern for House/Techno DJs who
    /// cue-juggle mid-track). The entry is replaced when a different trackId is
    /// emitted on the same deck, so subsequent track loads still emit normally.
    private var lastEmittedTrackId: [DeviceID: Int] = [:]
    /// Incidates if we're currentiny in an active DJ set
    private var isSetActive = false
    /// When we are waiting for a set to end, use this to cancel the timer.
    private var cancelSetEnding: (@DJLinkActor () -> Void)?
    /// The configuration for this instance of the processor
    private var config: MixstatusConfig

    private let clock: any DJLinkClock

    /// JS 마이크로태스크 대신 쓰는 목록. 가장 바깥 진입점(`handleState`, `triggerNextTrack`, 타이머 콜백)이
    /// 끝날 때 비운다.
    private var microtasks: [@DJLinkActor () -> Void] = []
    private var entryDepth = 0

    /// - Parameters:
    ///   - config: 바꿀 칸만 넘긴다(원본 `Partial<MixstatusConfig>`).
    ///   - clock: `Date.now()`·`setTimeout` 대신 쓰는 시계. 시험은 `TestClock`.
    public init(_ config: MixstatusConfigPartial? = nil, clock: any DJLinkClock = SystemClock.shared) {
        var resolved = defaultConfig
        if let config { resolved.merge(config) }
        self.config = resolved
        self.clock = clock
    }

    /// Update the configuration
    public func configure(_ config: MixstatusConfigPartial? = nil) {
        if let config { self.config.merge(config) }
    }

    /// 원본 `removeAllListeners()`
    public func removeAllListeners() {
        emitter.removeAllListeners()
    }

    /// 원본 `removeAllListeners(event)`
    public func removeAllListeners<Payload>(_ event: EventName<MixstatusProcessor, Payload>) {
        emitter.removeAllListeners(event)
    }

    private func enqueueMicrotask(_ job: @escaping @DJLinkActor () -> Void) {
        microtasks.append(job)
        if entryDepth == 0 {
            drainMicrotasks()
        }
    }

    private func drainMicrotasks() {
        while !microtasks.isEmpty {
            let job = microtasks.removeFirst()
            job()
        }
    }

    /// 바깥에서 들어오는 처리 단위. 끝나면 그동안 쌓인 마이크로태스크를 차례로 돌린다.
    private func entry(_ body: () -> Void) {
        entryDepth += 1
        body()
        entryDepth -= 1
        if entryDepth == 0 {
            drainMicrotasks()
        }
    }

    /// Helper to account for the useOnAirStatus config. If not configured
    /// with this flag the state will always be determined as on air.
    private func onAir(_ state: CDJStatus.State) -> Bool {
        config.useOnAirStatus ? state.isOnAir : true
    }

    /// Report a player as 'live'. Will not report the state if the player has
    /// already previously been reported as live.
    private func promotePlayer(_ state: CDJStatus.State) {
        let deviceId = state.deviceId

        if !onAir(state) || !isPlaying(state) {
            return
        }

        if livePlayers.contains(deviceId) {
            return
        }

        // PLAN §9: 원본은 이 취소가 중복 판정 뒤에 있어, 같은 곡을 다시 틀면 재생 중에 setEnded가 났다.
        // 중복이어도 데크가 다시 라이브로 돌아왔으므로 세트 종료 대기는 취소한다.
        if let cancelSetEnding {
            cancelSetEnding()
        }

        // Suppress duplicate nowPlaying for the same track on the same deck. This
        // can happen when a DJ cues mid-track and resumes (Cued/Loading/Ended are
        // all stoppingStates that drop the deck from livePlayers, so the next play
        // of the same trackId would otherwise re-emit). When a different track is
        // loaded, the trackId differs and the new emission proceeds normally.
        if lastEmittedTrackId[deviceId] == state.trackId {
            return
        }

        if !isSetActive {
            isSetActive = true
            emitter.emit(.setStarted, ())
        }

        livePlayers.insert(deviceId)
        lastEmittedTrackId[deviceId] = state.trackId

        emitter.emit(.nowPlaying, state)
    }

    /// Locate the player that has been playing for the longest time and is onair,
    /// and report that device as now playing.
    private func promoteNextPlayer() {
        // 원본: 후보를 startedAt 내림차순으로 안정 정렬한 뒤 pop(= 가장 이른 startedAt, 같으면 Map에 나중에 들어간 쪽).
        var longestPlayingId: DeviceID?
        var earliest = Double.infinity
        for (deviceId, startedAt) in lastStartTime.entries {
            guard !livePlayers.contains(deviceId) else { continue }
            guard let state = lastState[deviceId], isPlaying(state) else { continue }
            if longestPlayingId == nil || startedAt <= earliest {
                longestPlayingId = deviceId
                earliest = startedAt
            }
        }

        // No other players currently playing?
        guard let longestPlayingId else {
            setMayStop()
            return
        }

        // We know this value is available since we have a live player playing ID
        let nextPlayerState = lastState[longestPlayingId]!
        promotePlayer(nextPlayerState)
    }

    private func markPlayerStopped(_ state: CDJStatus.State) {
        let deviceId = state.deviceId
        lastStoppedTimes.removeValue(forKey: deviceId)
        lastStartTime.delete(deviceId)
        livePlayers.remove(deviceId)

        promoteNextPlayer()
        emitter.emit(.stopped, MixstatusStopped(deviceId: deviceId))
    }

    // 원본은 async 함수다. `await` 앞은 동기로 돌고, 뒤는 Promise가 풀린 다음 차례에 돈다(SetEndingPromise).
    private func setMayStop() {
        // We handle the set ending interrupt as a async timeout as in the case with
        // a set ending, the DJ may immediately turn off the CDJs, stopping state
        // packets meaning we can't process on a heartbeat.
        if !isSetActive {
            return
        }

        // If any tracks are still playing the set has not ended
        if lastState.values.contains(where: { isPlaying($0) && onAir($0) }) {
            return
        }

        let promise = SetEndingPromise(enqueue: { [self] in enqueueMicrotask($0) }) { [self] shouldEnd in
            cancelSetEnding = nil

            if !shouldEnd || !isSetActive {
                return
            }

            emitter.emit(.setEnded, ())
        }
        let endTimeout = clock.setTimeout(.ms(config.timeBetweenSets * 1000)) { [self] in
            entry { promise.resolve(true) }
        }
        cancelSetEnding = { [clock] in
            clock.clearTimeout(endTimeout)
            promise.resolve(false)
        }
    }

    /// Called to indicate that we think this player may be the first one to start
    /// playing. Will check if no other players are playing, if so it will report
    /// the player as now playing.
    private func playerMayBeFirst(_ state: CDJStatus.State) {
        let otherPlayersPlaying = lastState.values
            .filter { $0.deviceId != state.deviceId }
            .contains { onAir($0) && isPlaying($0) }

        if otherPlayersPlaying {
            return
        }

        promotePlayer(state)
    }

    /// Called when the player is in a state where it is no longer playing, but
    /// may come back onair. Examples are slip pause, or 'cutting' a track on the
    /// mixer taking it offair.
    private func playerMayStop(_ state: CDJStatus.State) {
        lastStoppedTimes[state.deviceId] = clock.nowMilliseconds()
    }

    /// Called to indicate that a device has reported a different playState than
    /// it had previously reported.
    private func handlePlaystateChange(_ lastState: CDJStatus.State, _ state: CDJStatus.State) {
        let deviceId = state.deviceId

        let isFollowingMaster = config.mode == .followsMaster && state.isMaster

        let nowPlaying = isPlaying(state)
        let wasPlaying = isPlaying(lastState)

        let isNowPlaying = nowPlaying && !wasPlaying

        // Was this device in a 'may stop' state and it has begun on-air playing
        // again?
        if lastStoppedTimes[deviceId] != nil && nowPlaying && onAir(state) {
            lastStoppedTimes.removeValue(forKey: deviceId)
            return
        }

        if isNowPlaying && isFollowingMaster {
            promotePlayer(state)
        }

        if isNowPlaying {
            lastStartTime.set(deviceId, clock.nowMilliseconds())
            playerMayBeFirst(state)
            return
        }

        if wasPlaying && isStopping(state) {
            markPlayerStopped(state)
            return
        }

        if wasPlaying && !nowPlaying {
            playerMayStop(state)
        }
    }

    private func handleOnairChange(_ state: CDJStatus.State) {
        let deviceId = state.deviceId

        // Player may have just been brought on with nothing else playing
        playerMayBeFirst(state)

        if !livePlayers.contains(deviceId) {
            return
        }

        if !onAir(state) {
            playerMayStop(state)
            return
        }

        // Play has come back onair
        lastStoppedTimes.removeValue(forKey: deviceId)
    }

    /// Feed a CDJStatus state object to the mix state processor
    public func handleState(_ state: CDJStatus.State) {
        entry { processState(state) }
    }

    private func processState(_ state: CDJStatus.State) {
        let deviceId = state.deviceId
        let playState = state.playState

        let lastState = self.lastState[deviceId]
        self.lastState[deviceId] = state

        // If this is the first time we've heard from this CDJ, and it is on air
        // and playing, report it immediately. This is different from reporting the
        // first playing track, as the CDJ will have already sent many states.
        if lastState == nil && onAir(state) && isPlaying(state) {
            lastStartTime.set(deviceId, clock.nowMilliseconds())
            playerMayBeFirst(state)
            return
        }

        // Play state has changed since this play last reported
        if let lastState, lastState.playState != playState {
            handlePlaystateChange(lastState, state)
        }

        if let lastState, onAir(lastState) != onAir(state) {
            handleOnairChange(state)
        }

        // Are we simply following master?
        if config.mode == .followsMaster && lastState?.isMaster == false && state.isMaster {
            promotePlayer(state)
            return
        }

        // 원본 `state.trackBPM!`: trackBPM이 null이면 JS 산술에서 0으로 취급되어 길이가 Infinity가 된다.
        let secondsPerBeat = bpmToSeconds(state.trackBPM ?? 0, state.effectivePitch)

        // If a device has been playing for the required number of beats, we may be
        // able to report it as live
        let startedAt = lastStartTime.get(deviceId)
        let requiredPlayTime = config.beatsUntilReported * secondsPerBeat * 1000

        if config.mode == .smartTiming, let startedAt, requiredPlayTime <= clock.nowMilliseconds() - startedAt {
            promotePlayer(state)
        }

        // If a device has been in a 'potentially stopped' state for long enough,
        // we can mark the track as truly stopped.
        let stoppedAt = lastStoppedTimes[deviceId]
        let requiredStopTime = config.allowedInterruptBeats * secondsPerBeat * 1000

        if let stoppedAt, requiredStopTime <= clock.nowMilliseconds() - stoppedAt {
            markPlayerStopped(state)
        }
    }

    /// Manually reports the track that has been playing the longest which has not
    /// yet been reported as live.
    public func triggerNextTrack() {
        entry { promoteNextPlayer() }
    }
}
