import DJLinkKit
import DJLinkTestSupport
import Testing

// PLAN §9: 원본 버그를 고친 동작을 확인하는 시험. 원본 대응 시험(MixStatusIndexTests)과 따로 둔다.

private let MOCK_BPM = 60.0

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

@Suite("mixstatus processor upstream fixes")
@DJLinkActor
final class MixStatusUpstreamFixTests {
    private var lastFedState: [Int: CDJStatus.State] = [:]
    private let clock = TestClock()
    private let processor: MixstatusProcessor

    init() {
        processor = MixstatusProcessor(MixstatusConfigPartial(useOnAirStatus: false), clock: clock)
    }

    private func feedState(_ deviceId: Int, _ update: (inout CDJStatus.State) -> Void = { _ in }) {
        var nextState = lastFedState[deviceId] ?? makeState { $0.deviceId = deviceId }
        update(&nextState)

        lastFedState[deviceId] = nextState
        processor.handleState(nextState)
    }

    @Test("does not end the set while the same track is replayed after a cue")
    func doesNotEndSetWhenSameTrackReplayed() async {
        let seHandler = CallRecorder<Void>()
        processor.on(.setEnded, seHandler.handler)

        feedState(1) {
            $0.trackId = 123
            $0.playState = .playing
        }

        // Cue: the deck is dropped from the live players and the set may end in 30 seconds
        feedState(1) { $0.playState = .cued }

        // Resume the same track. nowPlaying is suppressed as a duplicate, but the
        // pending set ending must still be cancelled.
        clock.advance(ms: 10 * 1000)
        feedState(1) { $0.playState = .playing }

        clock.advance(ms: 60 * 1000)
        await clock.settle()
        #expect(!seHandler.wasCalled)
    }
}
