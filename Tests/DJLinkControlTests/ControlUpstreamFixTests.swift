import DJLinkControl
import DJLinkKit
import DJLinkTestSupport
import Testing

// PLAN §9: 원본 버그를 고친 동작을 확인하는 시험. 원본 대응 시험(ControlStagehandTests 등)과 따로 둔다.

private let hostDevice = Device(
    name: "ProLink-Connect",
    id: 7,
    type: .cdj,
    macAddr: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55],
    ip: try! Address4("192.168.1.50")
)

private func player(_ id: Int) -> Device {
    Device(
        name: "CDJ-2000nexus",
        id: id,
        type: .cdj,
        macAddr: [0x74, 0x5e, 0x1c, 0x00, 0x00, 0x01],
        ip: try! Address4("192.168.1.35")
    )
}

@Suite("control upstream fixes")
struct ControlUpstreamFixTests {
    @Test("pause for player 1 stops the first slot and leaves the other players unchanged")
    func pausePacketForPlayerOne() throws {
        // CDJ-2000nexus 실기(2026-10-14): 01 02 02 02는 1번을 멈추고, 원본의 00 01 00 00은 1번을 계속 재생시켰다.
        let packet = try makePlaystatePacket(hostDevice: hostDevice, device: player(1), playState: .cued)
        let name = Array("ProLink-Connect".utf8) + [UInt8](repeating: 0, count: 5)
        #expect(packet == PROLINK_HEADER + [0x02] + name + [0x01, 0x00, 0x07, 0x00, 0x04, 0x01, 0x02, 0x02, 0x02])
    }

    @Test("puts the command in the target player's slot and no change in the others")
    func commandInTargetSlot() throws {
        for id in 1...4 {
            for (playState, value) in [(CDJStatus.PlayState.playing, UInt8(0x00)), (.cued, 0x01)] {
                let packet = try makePlaystatePacket(hostDevice: hostDevice, device: player(id), playState: playState)
                var slots: [UInt8] = [0x02, 0x02, 0x02, 0x02]
                slots[id - 1] = value
                #expect(Array(packet.suffix(4)) == slots, "\(id) \(playState)")
            }
        }
    }

    @Test("refuses players without a slot instead of starting every player")
    func refusesPlayerWithoutSlot() {
        for id in [0, 5, 6, 7, 33] {
            #expect(throws: DJLinkError.self, "\(id)") {
                try makePlaystatePacket(hostDevice: hostDevice, device: player(id), playState: .cued)
            }
        }
    }

    @Test("refuses play states other than playing and cued instead of sending start")
    func refusesOtherPlayStates() {
        let others: [CDJStatus.PlayState] = [.empty, .loading, .looping, .paused, .cuing, .ended]
        for playState in others {
            #expect(throws: DJLinkError.self, "\(playState)") {
                try makePlaystatePacket(hostDevice: hostDevice, device: player(1), playState: playState)
            }
        }
    }

    @Test("setPlayState sends nothing when the packet is refused")
    @DJLinkActor
    func setPlayStateSendsNothingWhenRefused() async {
        let socket = FakeUDPSocket()
        let control = Control(socket, DeviceReference(hostDevice))
        await #expect(throws: DJLinkError.self) { try await control.setPlayState(player(5), .playing) }
        await #expect(throws: DJLinkError.self) { try await control.setPlayState(player(1), .paused) }
        #expect(socket.sent.isEmpty)
    }
}
