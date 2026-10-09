import DJLinkKit
import Testing

// 원본 tests/devices/utils.spec.ts

@Suite("deviceFromPacket")
struct DevicesUtilsDeviceFromPacketTests {
    @Test("returns null for a non-prolink packet")
    func nonProlinkPacket() throws {
        // Foreign UDP traffic arrives on the announce socket constantly; it must
        // be ignored, not throw and crash the socket handler (NP3-446).
        let packet: [UInt8] = []

        #expect(try deviceFromPacket(packet) == nil)
    }

    @Test("only handles announce (0x06) packets")
    func onlyAnnouncePackets() throws {
        let packet = PROLINK_HEADER + [0x05]

        #expect(try deviceFromPacket(packet) == nil)
    }

    @Test("handles a real announce packet")
    func realAnnouncePacket() throws {
        let packet = try readMock("announce-cdj-2.dat")

        let device = try #require(try deviceFromPacket(packet))

        #expect(device.id == 2)
        #expect(device.type == .cdj)
        #expect(device.name == "CDJ-2000nexus")
        // 원본 `expect.objectContaining({address: '10.0.0.207'})`
        #expect(device.ip.address == "10.0.0.207")
        #expect(device.macAddr == [116, 94, 28, 87, 130, 216])
        // 원본 toEqual은 undefined 칸을 무시한다. 기대 객체에 없는 lastActive는 비어 있어야 한다.
        #expect(device.lastActive == nil)
    }
}
