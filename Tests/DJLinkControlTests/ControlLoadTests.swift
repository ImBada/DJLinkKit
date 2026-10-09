import DJLinkControl
import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 tests/control/load.spec.ts

@Suite("makeLoadTrackPacket")
struct ControlLoadTests {
    // rekordbox 7.2.11 loading two tracks of its library (device 17, the
    // rekordbox slot) onto players 1 and 2, captured 2026-09-13 on real
    // CDJ-3000s.
    let CAPTURED_PLAYER_1 =
        "5173707431576d4a4f4c1972656b6f7264626f7800000000000000000000000101110034110000001104010001300ad700000032000000000000000000000000000000000000000000000032000000000000000000000000"
    let CAPTURED_PLAYER_2 =
        "5173707431576d4a4f4c1972656b6f7264626f78000000000000000000000001011100341100000011040100046273df00000032000000000000000000000000010000000000000000000032000000000000000000000000"

    let rekordbox = Device(
        name: "rekordbox",
        id: 17,
        type: .rekordbox,
        macAddr: [UInt8](repeating: 0, count: 6),
        ip: try! Address4("192.168.1.14")
    )

    func player(_ id: Int) -> Device {
        Device(
            name: "CDJ-3000",
            id: id,
            type: .cdj,
            macAddr: [UInt8](repeating: 0, count: 6),
            ip: try! Address4("192.168.1.\(id)")
        )
    }

    let library = LoadSource(deviceId: 17, slot: .rb, trackType: .rb)

    @Test("is rekordbox's command byte for byte")
    func rekordboxsCommandByteForByte() throws {
        #expect(
            try makeLoadTrackPacket(rekordbox, player(1), 19_925_719, library).toString(.hex)
                == CAPTURED_PLAYER_1
        )
        #expect(
            try makeLoadTrackPacket(rekordbox, player(2), 73_561_055, library).toString(.hex)
                == CAPTURED_PLAYER_2
        )
    }

    @Test("names another source and defaults the track type to rekordbox")
    func namesAnotherSource() throws {
        var stagehand = rekordbox
        stagehand.id = 150
        stagehand.name = "Stagehand"
        stagehand.type = .stagehand
        let packet = try makeLoadTrackPacket(
            stagehand,
            player(1),
            0x12345678,
            LoadSource(deviceId: 2, slot: .usb)
        )
        #expect(packet.count == 88)
        #expect(packet[33] == 150)
        #expect(packet[36] == 150)
        #expect(packet[40] == 2)
        #expect(Int(packet[41]) == MediaSlot.usb.rawValue)
        #expect(Int(packet[42]) == TrackType.rb.rawValue)
        #expect(Array(packet.subarray(44, 48)) == [0x12, 0x34, 0x56, 0x78])
        #expect(packet[0x40] == 0)
    }
}
