import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 src/virtualcdj/heartbeat.test.ts

// Byte-for-byte fixtures captured from the real iOS Stagehand app (device name
// "Stagehand"). These are the exact payloads it unicasts at ~4 Hz — the mixer
// frame to a DJM-A9, the player frame to a CDJ-3000 — from Phase 4/5 pcaps
// (§4.14.2 and the 0x68 keep-alive decode).
private let REAL_MIXER_HEARTBEAT = [UInt8](
    "5173707431576d4a4f4c"  // magic Qspt1WmJOL
        + "3a"  // type 0x3a
        + "537461676568616e6400000000000000000000"  // "Stagehand" + NUL pad (19 bytes)
        + "210200fe0004001c0000",  // trailer
    encoding: .hex
)

private let REAL_PLAYER_HEARTBEAT = [UInt8](
    "5173707431576d4a4f4c"  // magic Qspt1WmJOL
        + "68"  // type 0x68
        + "537461676568616e6400000000000000000000"  // "Stagehand" + NUL pad (19 bytes)
        + "030100"  // 0x03 persona, 0x01 subkind, 0x00 flag
        + "3a0000",  // 0x3a model-code stamp + 2 reserved
    encoding: .hex
)

/// 원본 `makeDevice(overrides)`. 바꿀 칸만 넘긴다.
private func makeDevice(
    id: DeviceID = 1,
    name: String = "CDJ-3000",
    type: DeviceType = .cdj,
    macAddr: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05],
    ip: String = "192.168.1.35"
) -> Device {
    Device(name: name, id: id, type: type, macAddr: macAddr, ip: try! Address4(ip))
}

private func stagehandVcdj() -> Device {
    makeDevice(
        id: 200,
        name: "Stagehand",
        type: .stagehand,
        ip: "192.168.1.130"
    )
}

@Suite("Stagehand heartbeat packets")
struct VirtualCDJHeartbeatPacketTests {
    @Test("mixer heartbeat matches the real iOS Stagehand 0x3a frame byte-for-byte")
    func mixerHeartbeat() {
        let packet = makeStagehandMixerHeartbeat(stagehandVcdj())
        #expect(packet.count == 40)
        #expect(packet.bytesEqual(REAL_MIXER_HEARTBEAT) == true)
    }

    @Test("player heartbeat matches the real iOS Stagehand 0x68 frame byte-for-byte")
    func playerHeartbeat() {
        let packet = makeStagehandPlayerHeartbeat(stagehandVcdj())
        #expect(packet.count == 36)
        #expect(packet.bytesEqual(REAL_PLAYER_HEARTBEAT) == true)
    }

    @Test("substitutes the configured device name into the 19-byte name field")
    func substitutesName() {
        let packet = makeStagehandMixerHeartbeat(
            stagehandVcdj()  // name "Stagehand"
        )
        // Name occupies offsets 11..29; ASCII "Stagehand" then NUL padding.
        #expect(packet.subarray(11, 20).toString(.ascii) == "Stagehand")
        #expect(packet.subarray(20, 30) == [UInt8](repeating: 0, count: 10))
    }

    @Test("truncates an over-long name to the 19-byte field without overrunning")
    func truncatesLongName() {
        let packet = makeStagehandMixerHeartbeat(
            stagehandVcdj()  // replaced below
        )
        var longDevice = stagehandVcdj()
        longDevice.name = String(repeating: "A", count: 40)
        let longName = makeStagehandMixerHeartbeat(longDevice)
        #expect(longName.count == 40)
        // Trailer still lands at offset 30.
        #expect(longName.subarray(30) == [0x21, 0x02, 0x00, 0xfe, 0x00, 0x04, 0x00, 0x1c, 0x00, 0x00])
        _ = packet
    }
}

@Suite("StagehandHeartbeat")
@DJLinkActor
struct VirtualCDJStagehandHeartbeatTests {
    // 원본 beforeEach: 보낸 것을 모으는 소켓. FakeUDPSocket이 `sent`에 모으고 콜백을 바로 부른다.
    let socket = FakeUDPSocket()
    let clock = TestClock()

    private func deviceManagerWith(_ devices: [Device]) -> DeviceManager {
        let dm = DeviceManager(FakeUDPSocket(), clock: clock)
        for d in devices {
            dm.devices[d.id] = d
        }
        return dm
    }

    @Test("heartbeats the mixer with 0x3a and the CDJ with 0x68 to port 50002")
    func heartbeatsMixerAndCDJ() {
        let mixer = makeDevice(
            id: 33,
            name: "DJM-A9",
            type: .mixer,
            ip: "192.168.1.53"
        )
        let cdj = makeDevice(
            id: 1,
            name: "CDJ-3000",
            type: .cdj,
            ip: "192.168.1.35"
        )
        let dm = deviceManagerWith([mixer, cdj])

        let hb = StagehandHeartbeat(DeviceReference(stagehandVcdj()), socket, dm, clock: clock)
        hb.start()
        hb.stop()

        let sends = socket.sent
        #expect(sends.count == 2)
        let toMixer = sends.first { $0.address == "192.168.1.53" }
        let toCdj = sends.first { $0.address == "192.168.1.35" }
        #expect(toMixer?.port == STATUS_PORT)
        #expect(toCdj?.port == STATUS_PORT)
        #expect(toMixer?.message[10] == 0x3a)
        #expect(toCdj?.message[10] == 0x68)
    }

    @Test("never heartbeats itself or other Stagehand / rekordbox peers")
    func skipsSelfAndNonTargets() {
        let me = stagehandVcdj()  // id 200
        let otherStagehand = makeDevice(
            id: 201,
            type: .stagehand,
            ip: "192.168.1.131"
        )
        let rekordbox = makeDevice(
            id: 17,
            type: .rekordbox,
            ip: "192.168.1.40"
        )
        let dm = deviceManagerWith([me, otherStagehand, rekordbox])

        let hb = StagehandHeartbeat(DeviceReference(me), socket, dm, clock: clock)
        hb.start()
        hb.stop()

        #expect(socket.sent.count == 0)
    }

    @Test("stops sending after stop()")
    func stopsAfterStop() {
        // 원본 `vi.useFakeTimers()` → TestClock
        let cdj = makeDevice()
        let dm = deviceManagerWith([cdj])
        let hb = StagehandHeartbeat(DeviceReference(stagehandVcdj()), socket, dm, clock: clock)

        hb.start()  // one immediate send
        #expect(socket.sent.count == 1)
        hb.stop()
        clock.advance(ms: 2000)
        #expect(socket.sent.count == 1)
    }
}
