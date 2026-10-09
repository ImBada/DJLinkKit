import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 tests/mixstatus/index.spec.ts
// `jest.useFakeTimers()`와 `global.Date.now = jest.fn(() => currentNow)`는 TestClock으로 옮겼다.
// TestClock은 `advance`와 `runAllTimers`로 미는 만큼 `now()`도 같이 밀기 때문에 원본의 `currentNow`는 따로 두지 않는다.
// 원본은 시간을 다 민 뒤에만 `Date.now`가 바뀌고 TestClock은 타이머를 부르는 도중에도 바뀐다. 이 시험들은 시간을 밀 때
// 걸려 있는 타이머가 없어서 결과가 같다.

private let MOCK_BPM = 60.0

/// 원본 `makeState`. 바꿀 칸만 `update`에서 고친다(`...state`).
private func makeState(_ update: (inout CDJStatus.State) -> Void = { _ in }) -> CDJStatus.State {
    var state = CDJStatus.State(
        deviceId: 0,
        trackId: 0,
        trackDeviceId: 1,
        trackSlot: .usb,
        trackType: .rb,
        playState: .empty,
        isOnAir: false,
        isSync: false,
        isBpmSync: false,
        isMaster: false,
        isEmergencyMode: false,
        trackBPM: MOCK_BPM,
        effectivePitch: 0,
        sliderPitch: 0,
        beatInMeasure: 0,
        beatsUntilCue: 0,
        beat: 0,
        deviceType: 0,
        packetNum: 0
    )
    update(&state)
    return state
}

/// 원본 `expect(fn).toBeCalledWith(expect.objectContaining({deviceId, trackId}))`.
@DJLinkActor private func calledWith(_ handler: CallRecorder<CDJStatus.State>, deviceId: Int, trackId: Int) -> Bool {
    handler.calls.contains { $0.deviceId == deviceId && $0.trackId == trackId }
}

/// 원본 `expect(fn).lastCalledWith(expect.objectContaining({deviceId, trackId}))`.
@DJLinkActor private func lastCalledWith(_ handler: CallRecorder<CDJStatus.State>, deviceId: Int, trackId: Int) -> Bool {
    guard let last = handler.lastCall else { return false }
    return last.deviceId == deviceId && last.trackId == trackId
}

@Suite("mixstatus processor")
@DJLinkActor
final class MixStatusIndexTests {
    private var lastFedState: [Int: CDJStatus.State] = [:]

    // jest.useFakeTimers()
    private let clock = TestClock()

    // beforeEach: processor = new MixstatusProcessor()
    private let processor: MixstatusProcessor

    init() {
        processor = MixstatusProcessor(clock: clock)
    }

    /// Feed state to the processor. Remembering the last state and merging tnew
    /// new state in.
    private func feedState(_ deviceId: Int, _ update: (inout CDJStatus.State) -> Void = { _ in }) {
        var nextState = lastFedState[deviceId] ?? makeState { $0.deviceId = deviceId }
        update(&nextState)

        lastFedState[deviceId] = nextState
        processor.handleState(nextState)
    }

    private func advanceByBeatCount(_ beats: Double) {
        let ms = bpmToSeconds(MOCK_BPM, 0) * beats * 1000
        clock.advance(ms: ms)
        clock.runAllTimers()
    }

    @Test("does not report first state if immediately not onair and playing")
    func notReportFirstStateImmediatelyNotOnair() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)

        feedState(5) {
            $0.trackId = 123
            $0.playState = .playing
        }
        #expect(!npHandler.wasCalled)
    }

    @Test("does not report first state if off-air and played as first track")
    func notReportFirstStateOffair() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)

        feedState(1) {
            $0.trackId = 123
            $0.playState = .cued
        }

        feedState(1) {
            $0.playState = .playing
        }

        #expect(!npHandler.wasCalled)
    }

    @Test("reports an immediate on-air playing device as nowPlaying")
    func reportsImmediateOnairPlaying() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)

        feedState(5) {
            $0.trackId = 123
            $0.isOnAir = true
            $0.playState = .playing
        }
        #expect(calledWith(npHandler, deviceId: 5, trackId: 123))
    }

    @Test("reports tracks brought on-air when no others are playing")
    func reportsTracksBroughtOnair() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)

        feedState(1) {
            $0.trackId = 123
            $0.playState = .playing
        }

        // Oops forgot to bring the track on air
        feedState(1) { $0.isOnAir = true }

        #expect(calledWith(npHandler, deviceId: 1, trackId: 123))
    }

    @Test("does not report off-air playing track after live track cues")
    func notReportOffairPlayingAfterLiveCues() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)

        // Player 1 is playing
        feedState(1) {
            $0.trackId = 123
            $0.isOnAir = true
            $0.playState = .playing
        }

        #expect(npHandler.callCount == 1)
        npHandler.clear()

        // Player 2 is off air and cued
        feedState(2) {
            $0.trackId = 234
            $0.isOnAir = false
            $0.playState = .cued
        }

        // Player 2 begins playing
        feedState(2) {
            $0.playState = .playing
        }

        // Player 1 cues
        feedState(1) {
            $0.playState = .cued
        }
        #expect(!npHandler.wasCalled)
    }

    @Test("reports the stopping of a single device")
    func reportsStoppingOfSingleDevice() {
        let stoppedHandler = CallRecorder<MixstatusStopped>()
        processor.on(.stopped, stoppedHandler.handler)

        feedState(5) {
            $0.trackId = 123
            $0.isOnAir = true
            $0.playState = .playing
        }
        advanceByBeatCount(64)
        feedState(5) {
            $0.trackId = 123
            $0.isOnAir = true
            $0.playState = .ended
        }
        #expect(stoppedHandler.calls.contains(MixstatusStopped(deviceId: 5)))
    }

    @Test("reports the first device as playing when no others are")
    func reportsFirstDeviceWhenNoOthers() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)

        // Send cued states for two players
        feedState(1) {
            $0.trackId = 123
            $0.isOnAir = true
            $0.playState = .cued
        }
        feedState(2) {
            $0.trackId = 321
            $0.isOnAir = true
            $0.playState = .cued
        }

        #expect(!npHandler.wasCalled)

        // Start 2nd player playing
        feedState(2) { $0.playState = .playing }

        #expect(calledWith(npHandler, deviceId: 2, trackId: 321))
    }

    @Test("reports that a set has started when a player starts")
    func reportsSetStarted() {
        let ssHandler = CallRecorder<Void>()
        processor.on(.setStarted, ssHandler.handler)

        feedState(1) {
            $0.trackId = 123
            $0.isOnAir = true
            $0.playState = .cued
        }

        feedState(1) {
            $0.trackId = 123
            $0.isOnAir = true
            $0.playState = .playing
        }

        #expect(ssHandler.callCount == 1)
    }

    /// Loads one track, then a second, then starts palying the second offair.
    private func setupTwoTracks() {
        feedState(1) {
            $0.trackId = 123
            $0.isOnAir = true
            $0.playState = .playing
        }
        feedState(2)
        feedState(2) {
            $0.trackId = 234
            $0.playState = .playing
        }
    }

    @Test("does not report offair tracks when played")
    func notReportOffairTracksWhenPlayed() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()

        // Only first player is playing on air
        #expect(npHandler.callCount == 1)
        #expect(lastCalledWith(npHandler, deviceId: 1, trackId: 123))
    }

    @Test("does not report offair stopped tracks that come on air")
    func notReportOffairStoppedTracksComeOnair() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Both tracks stopped
        feedState(1) { $0.playState = .cued }
        feedState(2) { $0.playState = .cued }

        // Second track comes on air
        feedState(2) { $0.isOnAir = true }

        // No players should have been reported as playing
        #expect(!npHandler.wasCalled)
    }

    @Test("reports next device after the configured beats pass and both are live")
    func reportsNextDeviceAfterConfiguredBeats() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 comes onair after 64 beats
        advanceByBeatCount(64)
        feedState(2) { $0.isOnAir = true }

        #expect(!npHandler.wasCalled)

        // Player 2 stays onair. At beat 128 it is reported live.
        advanceByBeatCount(64)
        feedState(2)

        #expect(npHandler.callCount == 1)
        #expect(calledWith(npHandler, deviceId: 2, trackId: 234))
    }

    @Test("reports the next device early if the first is stopped")
    func reportsNextDeviceEarlyIfFirstStopped() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 comes onair after 64 beats
        advanceByBeatCount(64)
        feedState(2) { $0.isOnAir = true }

        // Player 1 stops, player 2 should report early
        feedState(1) { $0.playState = .cued }

        #expect(npHandler.callCount == 1)
        #expect(calledWith(npHandler, deviceId: 2, trackId: 234))
    }

    @Test("reports the next device early if the first is paused")
    func reportsNextDeviceEarlyIfFirstPaused() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 comes onair after 64 beats
        advanceByBeatCount(64)
        feedState(2) { $0.isOnAir = true }

        // Player 1 stops, player 2 should report early
        feedState(1) { $0.playState = .paused }

        // Wait 8 more beats to account for the interrupt beats
        advanceByBeatCount(8)
        feedState(1)

        #expect(npHandler.callCount == 1)
        #expect(calledWith(npHandler, deviceId: 2, trackId: 234))
    }

    @Test("reports the next device early if the first goes off air")
    func reportsNextDeviceEarlyIfFirstGoesOffAir() {
        let npHandler = CallRecorder<CDJStatus.State>()
        let stoppedHandler = CallRecorder<MixstatusStopped>()
        processor.on(.nowPlaying, npHandler.handler)
        processor.on(.stopped, stoppedHandler.handler)

        setupTwoTracks()
        npHandler.clear()

        // Player 2 comes onair after 64 beats
        advanceByBeatCount(64)
        feedState(2) { $0.isOnAir = true }

        // Player 1 goes off-air, player 2 should report early
        feedState(1) { $0.isOnAir = false }

        #expect(stoppedHandler.callCount == 0)

        // Wait 8 more beats to account for the interrupt beats
        advanceByBeatCount(8)
        feedState(1)

        #expect(stoppedHandler.callCount == 1)
        #expect(stoppedHandler.calls.contains(MixstatusStopped(deviceId: 1)))

        #expect(npHandler.callCount == 1)
        #expect(calledWith(npHandler, deviceId: 2, trackId: 234))
    }

    @Test("reports the device playing the longest if the playing track stops")
    func reportsDevicePlayingLongest() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Add one additional player that starts 32 beats in
        advanceByBeatCount(32)
        feedState(3) {
            $0.trackId = 2
            $0.isOnAir = true
            $0.playState = .playing
        }

        // Player 2 comes onair after 32 more beats
        advanceByBeatCount(32)
        feedState(2) { $0.isOnAir = true }

        // Player 1 stops, player 2 should report early
        feedState(1) { $0.playState = .cued }

        #expect(npHandler.callCount == 1)
        #expect(calledWith(npHandler, deviceId: 2, trackId: 234))
    }

    @Test("allow pause interrupts before the next device is reported live")
    func allowPauseInterrupts() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 comes onair after 64 beats
        advanceByBeatCount(64)
        feedState(2) { $0.isOnAir = true }

        // Player 1 pauses 4 beats, the next track is NOT reported live
        feedState(1) { $0.playState = .paused }
        advanceByBeatCount(4)
        feedState(1) { $0.playState = .playing }
        #expect(!npHandler.wasCalled)

        // Player 2 stays onair. At beat 128 it is reported live.
        advanceByBeatCount(60)
        feedState(2)

        #expect(npHandler.callCount == 1)
        #expect(calledWith(npHandler, deviceId: 2, trackId: 234))
    }

    @Test("allow onair interrupts before the next device is reported live")
    func allowOnairInterrupts() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 comes onair after 64 beats
        advanceByBeatCount(64)
        feedState(2) { $0.isOnAir = true }

        // Player 1 pauses 4 beats, the next track is NOT reported live
        feedState(1) { $0.isOnAir = false }
        advanceByBeatCount(4)
        feedState(1) { $0.isOnAir = true }
        #expect(!npHandler.wasCalled)

        // Player 2 stays onair. At beat 128 it is reported live.
        advanceByBeatCount(60)
        feedState(2)

        #expect(npHandler.callCount == 1)
        #expect(calledWith(npHandler, deviceId: 2, trackId: 234))
    }

    @Test("reports that a set has ended when all players stop")
    func reportsSetEnded() async {
        let seHandler = CallRecorder<Void>()
        processor.on(.setEnded, seHandler.handler)
        setupTwoTracks()

        feedState(1) { $0.playState = .cued }
        feedState(2) { $0.playState = .cued }

        #expect(!seHandler.wasCalled)

        // Set ending does not happen in beat intervals, so we don't use the
        // advanceByBeatCount helper
        clock.advance(ms: 30 * 1000)

        // await new Promise(r => new Promise(r)): Promise 뒤 이어지는 부분이 돌 때까지 양보한다
        await clock.settle()
        #expect(seHandler.wasCalled)
    }

    @Test("reports the next track on a previously played player")
    func reportsNextTrackOnPreviouslyPlayedPlayer() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 comes onair after 64 beats
        advanceByBeatCount(64)
        feedState(2) { $0.isOnAir = true }

        // Player 1 stops, player 2 reports early
        feedState(1) { $0.playState = .cued }

        #expect(npHandler.callCount == 1)
        npHandler.clear()

        // Player 1 loads a new track and begins playing
        feedState(1) { $0.trackId = 456 }
        feedState(1) { $0.playState = .playing }
        #expect(!npHandler.wasCalled)

        // 128 beats later player 1 should be reported
        advanceByBeatCount(128)
        feedState(1)

        #expect(calledWith(npHandler, deviceId: 1, trackId: 456))
    }

    @Test("reports subsequent tracks when first deck is taken off-air and cued")
    func reportsSubsequentTracksFirstDeckOffairAndCued() {
        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 comes onair after 64 beats
        advanceByBeatCount(64)
        feedState(2) { $0.isOnAir = true }

        // Player 1 goes offair, then subsequently cues itself
        feedState(1) { $0.isOnAir = false }
        advanceByBeatCount(2)
        feedState(1) { $0.playState = .cued }

        #expect(npHandler.callCount == 1)
        npHandler.clear()

        // Player 1 loads a new track and begins playing
        feedState(1) { $0.trackId = 456 }
        feedState(1) {
            $0.isOnAir = true
            $0.playState = .playing
        }
        #expect(!npHandler.wasCalled)

        // 128 beats later player 1 should be reported
        advanceByBeatCount(128)
        feedState(1)

        #expect(calledWith(npHandler, deviceId: 1, trackId: 456))
    }

    @Test("does not report after requiredPlayTime when MixstatusMode.WaitsForSilence")
    func notReportAfterRequiredPlayTimeWaitsForSilence() {
        processor.configure(MixstatusConfigPartial(mode: .waitsForSilence))

        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 comes onair after 64 beats
        advanceByBeatCount(64)
        feedState(2) { $0.isOnAir = true }

        // Player 2 stays onair. At beat 128 it is reported live.
        advanceByBeatCount(64)
        feedState(2)

        // Player 2 is NOT reported as live due to reportRequiresSilence
        #expect(!npHandler.wasCalled)

        // Player 1 stops and player 2 is reporte live
        feedState(1) { $0.playState = .cued }

        #expect(npHandler.callCount == 1)
    }

    @Test("ignores isOnAir when useOnAirStatus is false")
    func ignoresIsOnAirWhenUseOnAirStatusFalse() {
        processor.configure(MixstatusConfigPartial(useOnAirStatus: false))

        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 is reported live at beat 128 without having isOnAir set true
        advanceByBeatCount(128)
        feedState(2)

        #expect(calledWith(npHandler, deviceId: 2, trackId: 234))
    }

    @Test("reports for useOnAirStatus:false + MixstatusMode.WaitsForSilence")
    func reportsUseOnAirStatusFalseWaitsForSilence() {
        processor.configure(
            MixstatusConfigPartial(
                mode: .waitsForSilence,
                useOnAirStatus: false
            ))

        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 is not reported since player 1 has not yet stopped
        advanceByBeatCount(128)
        feedState(2)

        #expect(!npHandler.wasCalled)

        advanceByBeatCount(64)
        feedState(1) { $0.playState = .cued }

        #expect(calledWith(npHandler, deviceId: 2, trackId: 234))
    }

    @Test("reports while using MixstatusMode.FollowsMaster")
    func reportsWhileFollowsMaster() {
        processor.configure(MixstatusConfigPartial(mode: .followsMaster))

        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 is not reported since it has not yet become master
        advanceByBeatCount(128)
        feedState(2) { $0.isOnAir = true }

        #expect(!npHandler.wasCalled)

        advanceByBeatCount(64)
        feedState(1)

        // Player 2 is not reported since it has not yet become master
        #expect(!npHandler.wasCalled)

        // Player 2 becomes master and is reported
        feedState(1) { $0.isMaster = false }
        feedState(2) { $0.isMaster = true }

        #expect(calledWith(npHandler, deviceId: 2, trackId: 234))
    }

    @Test("reports with MixstatusMode.FollowsMaster, master selected early")
    func reportsFollowsMasterMasterSelectedEarly() {
        processor.configure(
            MixstatusConfigPartial(
                mode: .followsMaster,
                useOnAirStatus: false
            ))

        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)
        setupTwoTracks()
        npHandler.clear()

        // Player 2 is cued and then becomes master
        feedState(2) { $0.playState = .cued }
        feedState(2) { $0.isMaster = true }

        #expect(!npHandler.wasCalled)

        // Player 2 starts playing as master
        feedState(2) { $0.playState = .playing }

        #expect(calledWith(npHandler, deviceId: 2, trackId: 234))
    }

    // Regression: cue-juggling on the master deck (common for House/Techno DJs)
    // previously caused duplicate History entries because the Cued state drops
    // the deck from livePlayers and the next Playing transition re-emits.
    @Test("FollowsMaster: does not re-emit nowPlaying when master deck cues then plays same track")
    func followsMasterNotReEmitCuesThenPlays() {
        processor.configure(
            MixstatusConfigPartial(
                mode: .followsMaster,
                useOnAirStatus: false
            ))

        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)

        feedState(1) {
            $0.trackId = 123
            $0.isMaster = true
            $0.playState = .playing
        }
        #expect(npHandler.callCount == 1)

        feedState(1) { $0.playState = .cued }
        feedState(1) { $0.playState = .playing }

        #expect(npHandler.callCount == 1)
    }

    @Test("FollowsMaster: does not re-emit when master deck transitions Loading then plays same track")
    func followsMasterNotReEmitLoadingThenPlays() {
        processor.configure(
            MixstatusConfigPartial(
                mode: .followsMaster,
                useOnAirStatus: false
            ))

        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)

        feedState(1) {
            $0.trackId = 123
            $0.isMaster = true
            $0.playState = .playing
        }
        #expect(npHandler.callCount == 1)

        feedState(1) { $0.playState = .loading }
        feedState(1) { $0.playState = .cued }
        feedState(1) { $0.playState = .playing }

        #expect(npHandler.callCount == 1)
    }

    @Test("FollowsMaster: emits a new nowPlaying when a different track is loaded on the master deck")
    func followsMasterEmitsNewForDifferentTrack() {
        processor.configure(
            MixstatusConfigPartial(
                mode: .followsMaster,
                useOnAirStatus: false
            ))

        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)

        feedState(1) {
            $0.trackId = 123
            $0.isMaster = true
            $0.playState = .playing
        }
        #expect(npHandler.callCount == 1)

        feedState(1) { $0.playState = .cued }
        feedState(1) {
            $0.trackId = 456
            $0.playState = .loading
        }
        feedState(1) { $0.playState = .cued }
        feedState(1) { $0.playState = .playing }

        #expect(npHandler.callCount == 2)
        #expect(lastCalledWith(npHandler, deviceId: 1, trackId: 456))
    }

    @Test("does not re-emit nowPlaying when a deck cues and replays the same track in SmartTiming mode")
    func notReEmitCuesAndReplaysSmartTiming() {
        processor.configure(MixstatusConfigPartial(useOnAirStatus: false))

        let npHandler = CallRecorder<CDJStatus.State>()
        processor.on(.nowPlaying, npHandler.handler)

        feedState(1) {
            $0.trackId = 123
            $0.playState = .playing
        }
        #expect(npHandler.callCount == 1)

        // Cue and resume the same track
        feedState(1) { $0.playState = .cued }
        feedState(1) { $0.playState = .playing }

        #expect(npHandler.callCount == 1)
    }
}
