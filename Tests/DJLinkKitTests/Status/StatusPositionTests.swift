import DJLinkKit
import Testing

// 원본 tests/status/position.spec.ts

/// 원본 `Buffer.alloc(0x40)` 뒤 머리말을 쓰는 것.
private func positionPacket() -> [UInt8] {
    var packet = [UInt8].alloc(0x40)
    for (i, byte) in PROLINK_HEADER.enumerated() {
        packet[i] = byte
    }
    return packet
}

@Suite("positionFromPacket")
struct StatusPositionTests {
    @Test("returns undefined for non-prolink packet")
    func nonProlinkPacket() throws {
        let packet: [UInt8] = []
        #expect(try positionFromPacket(packet) == nil)
    }

    @Test("returns undefined for packet with wrong subtype")
    func wrongSubtype() throws {
        let packet: [UInt8] =
            PROLINK_HEADER + [
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x02,  // Wrong subtype at 0x20
            ]
        #expect(try positionFromPacket(packet) == nil)
    }

    @Test("returns undefined for packet that is too short")
    func tooShort() throws {
        let packet: [UInt8] =
            PROLINK_HEADER + [
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,  // Subtype 0x00 at 0x20
                0x03,  // Device ID
                0x00,
                0x05,  // lenr too small
            ]
        #expect(try positionFromPacket(packet) == nil)
    }

    // PLAN §9: 원본 버그를 고쳐 기대값을 바꿨다(원본: tests/status/position.spec.ts, 종류 0x00도 위치로 읽음).
    @Test("parses a valid position packet from CDJ-3000")
    func validPacket() throws {
        var packet = positionPacket()

        // Write fields
        packet[0x20] = 0x00  // Subtype
        packet[0x21] = 0x03  // Device ID = 3
        packet.writeUInt16BE(0x0038, 0x22)  // lenr

        packet.writeUInt32BE(180, 0x24)  // Track length = 180 seconds (3:00)
        packet.writeUInt32BE(45500, 0x28)  // Playhead = 45.5 seconds
        packet.writeInt32BE(326 * 64, 0x2c)  // Pitch = 3.26% (326 * 64)
        packet.writeUInt32BE(1202, 0x30)  // BPM = 120.2 (1202 / 10)

        let position = try positionFromPacket(packet)

        #expect(position == nil)
    }

    // PLAN §9: 원본 버그를 고쳐 기대값을 바꿨다(원본: tests/status/position.spec.ts, 종류 0x00도 위치로 읽음).
    @Test("handles unknown BPM (0xffffffff)")
    func unknownBPM() throws {
        var packet = positionPacket()

        packet[0x20] = 0x00
        packet[0x21] = 0x02
        packet.writeUInt16BE(0x0038, 0x22)
        packet.writeUInt32BE(200, 0x24)
        packet.writeUInt32BE(10000, 0x28)
        packet.writeInt32BE(0, 0x2c)
        packet.writeUInt32BE(0xffff_ffff, 0x30)  // Unknown BPM

        let position = try positionFromPacket(packet)

        #expect(position == nil)
    }

    // PLAN §9: 원본 버그를 고쳐 기대값을 바꿨다(원본: tests/status/position.spec.ts, 종류 0x00도 위치로 읽음).
    @Test("handles negative pitch values")
    func negativePitch() throws {
        var packet = positionPacket()

        packet[0x20] = 0x00
        packet[0x21] = 0x01
        packet.writeUInt16BE(0x0038, 0x22)
        packet.writeUInt32BE(240, 0x24)
        packet.writeUInt32BE(60000, 0x28)
        packet.writeInt32BE(-200 * 64, 0x2c)  // Pitch = -2.0% (-200 * 64)
        packet.writeUInt32BE(1180, 0x30)  // BPM = 118.0

        let position = try positionFromPacket(packet)

        #expect(position == nil)
    }

    // PLAN §9: 원본 버그를 고쳐 기대값을 바꿨다(원본: tests/status/position.spec.ts, 종류 0x00도 위치로 읽음).
    @Test("handles track at start (playhead = 0)")
    func playheadAtStart() throws {
        var packet = positionPacket()

        packet[0x20] = 0x00
        packet[0x21] = 0x04
        packet.writeUInt16BE(0x0038, 0x22)
        packet.writeUInt32BE(300, 0x24)
        packet.writeUInt32BE(0, 0x28)  // Playhead at start
        packet.writeInt32BE(0, 0x2c)
        packet.writeUInt32BE(1280, 0x30)

        let position = try positionFromPacket(packet)

        #expect(position == nil)
    }
}
