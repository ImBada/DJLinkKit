import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 src/status/stagehand-gating.test.ts

// The Stagehand 0x39 mixer-state parser is reverse-engineered from a DJM-A9.
// It must only run when the network was brought online in Stagehand mode; in
// 'active' (and passive) mode it would misread other mixers' faders (e.g. the
// XDJ-AZ, NP3-327). These tests pin the gating so it can't silently re-leak.

/// A well-formed 0x39 mixer-state packet (266 bytes, header + type byte).
private func makeMixerStatePacket() -> [UInt8] {
    var packet = [UInt8].alloc(266)
    packet.set(PROLINK_HEADER, 0)
    packet[10] = 0x39
    return packet
}

/// 원본 `fakeSocket()`: EventEmitter 소켓과 'message'를 내는 함수.
@DJLinkActor
private func fakeSocket() -> (socket: FakeUDPSocket, send: @DJLinkActor ([UInt8]) -> Void) {
    let socket = FakeUDPSocket()
    return (socket, { socket.emitMessage($0) })
}

@Suite("StatusEmitter Stagehand gating")
@DJLinkActor
struct StatusStagehandGatingTests {
    @Test("does NOT emit mixerState for a 0x39 packet in active mode (default)")
    func activeModeIgnoresMixerState() {
        let (socket, send) = fakeSocket()
        let emitter = StatusEmitter(socket)  // default: stagehandMode = false
        let onMixerState = CallRecorder<CDJStatus.MixerState>()
        emitter.on(.mixerState, onMixerState.handler)

        send(makeMixerStatePacket())

        #expect(!onMixerState.wasCalled)
    }

    @Test("emits mixerState for a 0x39 packet in Stagehand mode")
    func stagehandModeEmitsMixerState() {
        let (socket, send) = fakeSocket()
        let emitter = StatusEmitter(socket, stagehandMode: true)  // stagehandMode = true
        let onMixerState = CallRecorder<CDJStatus.MixerState>()
        emitter.on(.mixerState, onMixerState.handler)

        send(makeMixerStatePacket())

        #expect(onMixerState.callCount == 1)
    }
}
