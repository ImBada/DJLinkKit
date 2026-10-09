import DJLinkKit
import Testing

// 원본 tests/status/on-air.test.ts

/// 원본 `Buffer.alloc(size)` 뒤 `Buffer.from('Qspt1WmJOL', 'ascii').copy(packet)`.
private func packetWithHeader(_ size: Int) -> [UInt8] {
    let header = [UInt8]("Qspt1WmJOL", encoding: .ascii)
    var packet = [UInt8].alloc(size)
    packet.set(header)
    return packet
}

@Suite("on-air packet parsing")
struct StatusOnAirTests {
    @Suite("4-channel variant (DJM-900/1000)")
    struct FourChannel {
        @Test("should parse 4-channel on-air packet")
        func parsesFourChannel() throws {
            // Build a 4-channel on-air packet
            // Header: Qspt1WmJOL (10 bytes)
            //
            // Packet structure:
            // [0x00-0x09]: Header
            // [0x0a]: Type (0x06 for mixer updates)
            // [0x0b]: Unknown
            // [0x0c-0x1f]: Device name (padded with 00)
            // [0x20]: Subtype (0x00 for 4-channel)
            // [0x21]: Device ID (mixer = 0x21 / 33)
            // [0x22-0x23]: Length (0x0009)
            // [0x24]: F1 (Channel 1 on-air flag)
            // [0x25]: F2 (Channel 2 on-air flag)
            // [0x26]: F3 (Channel 3 on-air flag)
            // [0x27]: F4 (Channel 4 on-air flag)
            // [0x28-0x2d]: Padding

            var packet = packetWithHeader(0x2e)
            packet[0x0a] = 0x06  // Type
            packet[0x20] = 0x00  // Subtype (4-channel)
            packet[0x21] = 0x21  // Device ID (mixer)
            packet.writeUInt16BE(0x0009, 0x22)  // Length
            packet[0x24] = 0x01  // Channel 1: on-air
            packet[0x25] = 0x00  // Channel 2: off-air
            packet[0x26] = 0x01  // Channel 3: on-air
            packet[0x27] = 0x00  // Channel 4: off-air

            let onAir = try onAirFromPacket(packet)

            #expect(onAir != nil)
            let status = try #require(onAir)
            #expect(status.deviceId == 0x21)
            #expect(status.channels[1] == true)
            #expect(status.channels[2] == false)
            #expect(status.channels[3] == true)
            #expect(status.channels[4] == false)
            #expect(status.isSixChannel == false)
            #expect(status.channels[5] == nil)
            #expect(status.channels[6] == nil)
        }

        @Test("should return undefined for invalid 4-channel packet")
        func invalidFourChannel() throws {
            var packet = packetWithHeader(0x2e)
            packet[0x0a] = 0x06
            packet[0x20] = 0x00
            packet[0x21] = 0x21
            packet.writeUInt16BE(0x0008, 0x22)  // Wrong length

            let onAir = try onAirFromPacket(packet)
            #expect(onAir == nil)
        }
    }

    @Suite("6-channel variant (CDJ-3000 + DJM-V10)")
    struct SixChannel {
        @Test("should parse 6-channel on-air packet")
        func parsesSixChannel() throws {
            // Build a 6-channel on-air packet
            var packet = packetWithHeader(0x36)
            packet[0x0a] = 0x06  // Type
            packet[0x20] = 0x03  // Subtype (6-channel)
            packet[0x21] = 0x21  // Device ID (mixer)
            packet.writeUInt16BE(0x0011, 0x22)  // Length (6-channel)
            packet[0x24] = 0x01  // Channel 1: on-air
            packet[0x25] = 0x01  // Channel 2: on-air
            packet[0x26] = 0x00  // Channel 3: off-air
            packet[0x27] = 0x01  // Channel 4: on-air
            packet[0x2e] = 0x00  // Channel 5: off-air
            packet[0x2f] = 0x01  // Channel 6: on-air

            let onAir = try onAirFromPacket(packet)

            #expect(onAir != nil)
            let status = try #require(onAir)
            #expect(status.deviceId == 0x21)
            #expect(status.channels[1] == true)
            #expect(status.channels[2] == true)
            #expect(status.channels[3] == false)
            #expect(status.channels[4] == true)
            #expect(status.channels[5] == false)
            #expect(status.channels[6] == true)
            #expect(status.isSixChannel == true)
        }

        @Test("should return undefined for invalid 6-channel packet")
        func invalidSixChannel() throws {
            var packet = packetWithHeader(0x36)
            packet[0x0a] = 0x06
            packet[0x20] = 0x03
            packet[0x21] = 0x21
            packet.writeUInt16BE(0x0009, 0x22)  // Wrong length for 6-channel

            let onAir = try onAirFromPacket(packet)
            #expect(onAir == nil)
        }

        @Test("should return undefined if packet is too short")
        func tooShort() throws {
            var packet = packetWithHeader(0x30)  // Too short
            packet[0x0a] = 0x06
            packet[0x20] = 0x03
            packet[0x21] = 0x21
            packet.writeUInt16BE(0x0011, 0x22)

            let onAir = try onAirFromPacket(packet)
            #expect(onAir == nil)
        }
    }

    @Suite("edge cases")
    struct EdgeCases {
        @Test("should return undefined for packet without prolink header")
        func noHeader() throws {
            var packet = [UInt8].alloc(0x36)
            packet[0x20] = 0x03
            packet[0x21] = 0x21

            let onAir = try onAirFromPacket(packet)
            #expect(onAir == nil)
        }

        @Test("should handle all channels on-air")
        func allOnAir() throws {
            var packet = packetWithHeader(0x36)
            packet[0x0a] = 0x06
            packet[0x20] = 0x03
            packet[0x21] = 0x21
            packet.writeUInt16BE(0x0011, 0x22)
            packet[0x24] = 0x01
            packet[0x25] = 0x01
            packet[0x26] = 0x01
            packet[0x27] = 0x01
            packet[0x2e] = 0x01
            packet[0x2f] = 0x01

            let onAir = try #require(try onAirFromPacket(packet))

            #expect(onAir.channels[1] == true)
            #expect(onAir.channels[2] == true)
            #expect(onAir.channels[3] == true)
            #expect(onAir.channels[4] == true)
            #expect(onAir.channels[5] == true)
            #expect(onAir.channels[6] == true)
        }

        @Test("should handle all channels off-air")
        func allOffAir() throws {
            var packet = packetWithHeader(0x36)
            packet[0x0a] = 0x06
            packet[0x20] = 0x03
            packet[0x21] = 0x21
            packet.writeUInt16BE(0x0011, 0x22)
            // All channels already 0x00 from buffer.alloc

            let onAir = try #require(try onAirFromPacket(packet))

            #expect(onAir.channels[1] == false)
            #expect(onAir.channels[2] == false)
            #expect(onAir.channels[3] == false)
            #expect(onAir.channels[4] == false)
            #expect(onAir.channels[5] == false)
            #expect(onAir.channels[6] == false)
        }
    }
}
