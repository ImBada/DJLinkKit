import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 tests/virtualcdj/stagehand.test.ts

private let mockIface = NetworkInterfaceInfo(
    address: "192.168.1.100",
    netmask: "255.255.255.0",
    family: "IPv4",
    mac: "00:11:22:33:44:55",
    internal: false,
    cidr: "192.168.1.100/24",
    scopeid: nil
)

@Suite("Stagehand Connection Method")
struct VirtualCDJStagehandTests {
    @Suite("Utility generators")
    struct UtilityGenerators {
        @Test("should derive an AlphaTheta-OUI MAC from the interface MAC")
        func derivesMac() {
            let mac = getStagehandMac(mockIface)
            // 원본과 다름: `toBeInstanceOf(Uint8Array)`는 Swift에서 형이 컴파일 때 정해지므로 형만 확인한다.
            #expect(type(of: mac) == [UInt8].self)
            #expect(mac == [0xc8, 0x3d, 0xfc, 0x33, 0x44, 0x55])
        }

        @Test("should derive the same MAC every time for the same interface")
        func sameMacEveryTime() throws {
            let copy = mockIface
            #expect(getStagehandMac(mockIface) == getStagehandMac(copy))
            #expect(try getVirtualStagehand(mockIface, 150).macAddr == getStagehandMac(mockIface))
        }

        @Test("should generate random device ID in 141-211 range")
        func randomIdRange() {
            for _ in 0..<50 {
                let id = generateStagehandDeviceId()
                #expect(id >= 141)
                #expect(id <= 211)
            }
        }

        @Test("should create a valid Stagehand device")
        func createsDevice() throws {
            let mac = getStagehandMac(mockIface)
            let device = try getVirtualStagehand(mockIface, 150, "Stagehand-Test", mac)
            #expect(device.id == 150)
            #expect(device.name == "Stagehand-Test")
            #expect(device.type == .stagehand)
            // 원본 `toBe(mac)`는 같은 객체인지 본다. [UInt8]은 값 형이라 같은 값인지 본다.
            #expect(device.macAddr == mac)
            #expect(device.ip.address == "192.168.1.100")
        }
    }

    @Suite("Packet Builders")
    struct PacketBuilders {
        @Test("should build exactly 37 bytes Stagehand 0x0a packet")
        func stage0a() throws {
            let device = try getVirtualStagehand(mockIface, 150)
            let packet = try makeStagehand0aPacket(device)
            #expect(packet.count == 37)
            #expect(packet[10] == 0x0a)  // Type
            #expect(packet[32] == 0x01)  // Protocol byte 1
            #expect(packet[33] == 0x03)  // Protocol byte 2 (Stagehand uses 03)
            #expect(Int(packet[36]) == DeviceType.stagehand.rawValue)  // 0x05
        }

        @Test("should build exactly 50 bytes Stagehand 0x02 packet")
        func stage02() throws {
            let mac = getStagehandMac(mockIface)
            let device = try getVirtualStagehand(mockIface, 150, "Stagehand", mac)
            let packet = try makeStagehand02Packet(device, mac, 1)
            #expect(packet.count == 50)
            #expect(packet[10] == 0x02)  // Type
            #expect(packet[32] == 0x01)  // Protocol
            #expect(packet[33] == 0x03)
            #expect(packet[46] == 0x3a)  // constant
            #expect(packet[47] == 1)  // counter
            #expect(Int(packet[48]) == DeviceType.stagehand.rawValue)  // 0x05
            #expect(packet[49] == 0x01)  // constant
        }

        @Test("should build exactly 54 bytes Stagehand 0x06 packet")
        func stage06() throws {
            let mac = getStagehandMac(mockIface)
            let device = try getVirtualStagehand(mockIface, 150, "Stagehand", mac)
            let packet = try makeStagehand06Packet(device, mac)
            #expect(packet.count == 54)
            #expect(packet[10] == 0x06)  // Type
            #expect(packet[32] == 0x01)  // Protocol
            #expect(packet[33] == 0x03)
            #expect(packet[36] == 150)  // device ID
            #expect(Int(packet[52]) == DeviceType.stagehand.rawValue)  // 0x05
            #expect(packet[53] == 0x20)  // trailing byte
        }
    }

    @Suite("StagehandAnnouncer Lifecycle")
    @DJLinkActor
    struct AnnouncerLifecycle {
        @Test("should start and stop announcer and send packets")
        func startsAndStops() throws {
            let mac = getStagehandMac(mockIface)
            let device = try getVirtualStagehand(mockIface, 150, "Stagehand", mac)
            let mockSocket = FakeUDPSocket()
            // 원본 `{devices: new Map()}` mock 대신 빈 DeviceManager를 쓴다.
            let clock = TestClock()
            let mockDeviceManager = DeviceManager(FakeUDPSocket(), clock: clock)

            let announcer = StagehandAnnouncer(
                DeviceReference(device),
                mockSocket,
                mockDeviceManager,
                mockIface,
                clock: clock
            )

            try announcer.start()
            #expect(!mockSocket.sent.isEmpty)
            announcer.stop()
        }
    }
}
