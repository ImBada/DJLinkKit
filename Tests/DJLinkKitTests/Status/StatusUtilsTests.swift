import DJLinkKit
import Foundation
import Testing

// 원본 tests/status/utils.spec.ts

/// 원본 `Buffer.alloc(n)` 뒤 `PROLINK_HEADER.forEach((byte, i) => (packet[i] = byte))`.
private func headerPacket(_ size: Int) -> [UInt8] {
    var packet = [UInt8].alloc(size)
    for (i, byte) in PROLINK_HEADER.enumerated() {
        packet[i] = byte
    }
    return packet
}

@Suite("statusFromPacket")
struct StatusUtilsStatusFromPacketTests {
    @Test("fails with error for non-prolink packet")
    func nonProlinkPacket() {
        let packet: [UInt8] = []

        #expect(throws: (any Error).self) { try statusFromPacket(packet) }
    }

    @Test("only handles announce packets which are large enough")
    func tooShort() throws {
        let packet = PROLINK_HEADER + [0x00, 0x00]

        #expect(try statusFromPacket(packet) == nil)
    }

    @Test("handles a real announce packet")
    func realPacket() throws {
        let packet = try readMock("status-simple.dat")

        let status = try statusFromPacket(packet)

        #expect(
            status
                == CDJStatus.State(
                    deviceId: 3,
                    trackId: 0,
                    trackDeviceId: 0,
                    trackSlot: .empty,
                    trackType: TrackType.none,
                    playState: .empty,
                    isOnAir: false,
                    isSync: false,
                    isBpmSync: false,
                    isMaster: false,
                    isEmergencyMode: false,
                    trackBPM: nil,
                    effectivePitch: 0,
                    sliderPitch: 0,
                    beatInMeasure: 0,
                    beatsUntilCue: nil,
                    beat: nil,
                    deviceType: 0x0f,
                    packetNum: 74108
                )
        )
    }
}

@Suite("mediaSlotFromPacket")
struct StatusUtilsMediaSlotFromPacketTests {
    @Test("fails with error for non-prolink packet")
    func nonProlinkPacket() {
        let packet: [UInt8] = []

        #expect(throws: (any Error).self) { try mediaSlotFromPacket(packet) }
    }

    @Test("only handles media slot packet types")
    func onlyMediaSlotPackets() throws {
        let packet = PROLINK_HEADER + [0x05]

        #expect(try mediaSlotFromPacket(packet) == nil)
    }

    @Test("handles a real media slot packet")
    func realPacket() throws {
        let packet = try readMock("media-slot-usb.dat")

        let status = try mediaSlotFromPacket(packet)

        let createdDate = try #require(ISO8601DateFormatter().date(from: "2020-10-10T00:00:00Z"))
        #expect(
            status
                == MediaSlotInfo(
                    deviceId: 2,
                    slot: .usb,
                    name: "",
                    color: .default,
                    createdDate: createdDate,
                    freeBytes: 61_048_520_704,
                    totalBytes: 62_714_675_200,
                    tracksType: TrackType(rawValue: 1),
                    trackCount: 76,
                    playlistCount: 1,
                    hasSettings: true
                )
        )
    }
}

@Suite("mixerStateFromPacket")
struct StatusUtilsMixerStateFromPacketTests {
    @Test("returns undefined for non-prolink packet")
    func nonProlinkPacket() {
        let packet: [UInt8] = []
        #expect(mixerStateFromPacket(packet) == nil)
    }

    @Test("returns undefined for wrong packet type")
    func wrongType() {
        var packet = headerPacket(266)
        packet[10] = 0x0a  // wrong type
        #expect(mixerStateFromPacket(packet) == nil)
    }

    @Test("returns undefined for packet that is too short")
    func tooShort() {
        var packet = headerPacket(100)
        packet[10] = 0x39
        #expect(mixerStateFromPacket(packet) == nil)
    }

    @Test("correctly parses a valid 0x39 mixer state packet")
    func validPacket() {
        var packet = headerPacket(266)
        packet[10] = 0x39

        // Device name "DJM-A9"
        packet.set([UInt8]("DJM-A9", encoding: .ascii), 11)

        // Crossfader position
        packet[180] = 120

        // Fill channel blocks
        for ch in 1...4 {
            let offset = 36 + (ch - 1) * 24
            packet[offset + 1] = UInt8(100 + ch)  // trim
            packet[offset + 3] = UInt8(110 + ch)  // eqHi
            packet[offset + 4] = UInt8(120 + ch)  // eqMid
            packet[offset + 6] = UInt8(130 + ch)  // eqLow
            packet[offset + 7] = UInt8(140 + ch)  // colorFx
            packet[offset + 11] = UInt8(150 + ch)  // fader
            // crossfader assign: CH1=A, CH2=B, others=thru
            packet[offset + 12] = ch == 1 ? 0x01 : ch == 2 ? 0x02 : 0x00
        }

        let state = mixerStateFromPacket(packet)
        #expect(
            state
                == CDJStatus.MixerState(
                    deviceId: 33,
                    deviceName: "DJM-A9",
                    channels: [
                        1: .init(
                            trim: 101,
                            eqHi: 111,
                            eqMid: 121,
                            eqLow: 131,
                            colorFx: 141,
                            fader: 151,
                            crossfaderAssign: .a
                        ),
                        2: .init(
                            trim: 102,
                            eqHi: 112,
                            eqMid: 122,
                            eqLow: 132,
                            colorFx: 142,
                            fader: 152,
                            crossfaderAssign: .b
                        ),
                        3: .init(
                            trim: 103,
                            eqHi: 113,
                            eqMid: 123,
                            eqLow: 133,
                            colorFx: 143,
                            fader: 153,
                            crossfaderAssign: .thru
                        ),
                        4: .init(
                            trim: 104,
                            eqHi: 114,
                            eqMid: 124,
                            eqLow: 134,
                            colorFx: 144,
                            fader: 154,
                            crossfaderAssign: .thru
                        ),
                    ],
                    crossfader: 120
                )
        )
    }
}

@Suite("vuFromPacket")
struct StatusUtilsVuFromPacketTests {
    @Test("returns undefined for non-prolink packet")
    func nonProlinkPacket() {
        let packet: [UInt8] = []
        #expect(vuFromPacket(packet) == nil)
    }

    @Test("returns undefined for wrong packet type")
    func wrongType() {
        var packet = headerPacket(584)
        packet[10] = 0x0a  // wrong type
        #expect(vuFromPacket(packet) == nil)
    }

    @Test("returns undefined for packet that is too short")
    func tooShort() {
        var packet = headerPacket(300)
        packet[10] = 0x58
        #expect(vuFromPacket(packet) == nil)
    }

    @Test("correctly parses a valid 0x58 VU level packet")
    func validPacket() throws {
        var packet = headerPacket(584)
        packet[10] = 0x58

        // Fill VU samples starting at offset 44
        for ch in 1...4 {
            let chOffset = 44 + (ch - 1) * 60
            for i in 0..<15 {
                let frameOffset = chOffset + i * 4
                packet.writeUInt16BE(1000 * ch + i, frameOffset)  // left
                packet.writeUInt16BE(2000 * ch + i, frameOffset + 2)  // right
            }
        }

        let state = try #require(vuFromPacket(packet))
        #expect(state.deviceId == 33)
        #expect(state.channels[1]?[0] == CDJStatus.VUFrame(left: 1000, right: 2000))
        #expect(state.channels[1]?[14] == CDJStatus.VUFrame(left: 1014, right: 2014))
        #expect(state.channels[4]?[0] == CDJStatus.VUFrame(left: 4000, right: 8000))
        #expect(state.channels[4]?[14] == CDJStatus.VUFrame(left: 4014, right: 8014))
    }
}
