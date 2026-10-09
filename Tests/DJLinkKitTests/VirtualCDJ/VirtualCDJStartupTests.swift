import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 tests/virtualcdj/startup.test.ts
// 원본의 `{devices: new Map(...)}` mock DeviceManager는 실제 DeviceManager의 `devices`를 채워서,
// mock 소켓(`send`·`on`·`off` jest.fn)은 FakeUDPSocket으로 옮겼다. 실제 setTimeout과 `done`을 쓰는 시험은 TestClock으로 옮겼다.

private let mockIface = NetworkInterfaceInfo(
    address: "192.168.1.100",
    netmask: "255.255.255.0",
    family: "IPv4",
    mac: "00:11:22:33:44:55",
    internal: false,
    cidr: nil,
    scopeid: nil
)

/// 원본 `{devices: new Map(entries)} as any as DeviceManager`.
@DJLinkActor
private func mockDeviceManager(_ entries: [(DeviceID, Device)] = [], clock: TestClock) -> DeviceManager {
    let dm = DeviceManager(FakeUDPSocket(), clock: clock)
    for (id, device) in entries {
        dm.devices[id] = device
    }
    return dm
}

/// 원본 0x08 충돌 패킷.
private func conflictPacketFor(_ id: UInt8) -> [UInt8] {
    var conflictPacket = [UInt8].alloc(0x29)

    // Build 0x08 conflict packet
    conflictPacket.set([0x51, 0x73, 0x70, 0x74, 0x31, 0x57, 0x6d, 0x4a, 0x4f, 0x4c], 0)
    conflictPacket[0x0a] = 0x08  // Conflict packet type
    conflictPacket[0x24] = id  // Conflicting device ID
    return conflictPacket
}

@Suite("Full Startup Protocol")
@DJLinkActor
struct VirtualCDJStartupTests {
    @Suite("Announcer creation")
    @DJLinkActor
    struct AnnouncerCreation {
        let clock = TestClock()

        @Test("should create announcer with default fullStartup=false")
        func defaultFullStartup() throws {
            let device = try getVirtualCDJ(mockIface, 1)
            let mockSocket = FakeUDPSocket()

            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                mockDeviceManager(clock: clock),
                mockIface,
                clock: clock
            )
            // 원본 `toBeDefined()`: 만들어지기만 하면 된다.
            _ = announcer
        }

        @Test("should create announcer with explicit fullStartup=false")
        func explicitFullStartupFalse() throws {
            let device = try getVirtualCDJ(mockIface, 1)
            let mockSocket = FakeUDPSocket()

            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                mockDeviceManager(clock: clock),
                mockIface,
                fullStartup: false,
                clock: clock
            )
            _ = announcer
        }

        @Test("should create announcer with fullStartup=true")
        func fullStartupTrue() throws {
            let device = try getVirtualCDJ(mockIface, 1)
            let mockSocket = FakeUDPSocket()

            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                mockDeviceManager(clock: clock),
                mockIface,
                fullStartup: true,
                clock: clock
            )
            _ = announcer
        }
    }

    @Suite("Virtual CDJ device creation")
    struct VirtualCDJDeviceCreation {
        @Test("should create standard CDJ device (player 1-4)")
        func standardDevice() throws {
            let device = try getVirtualCDJ(mockIface, 1)
            #expect(device.id == 1)
            #expect(device.type == .cdj)
            #expect(device.ip.address == "192.168.1.100")
            #expect(device.macAddr == [0x00, 0x11, 0x22, 0x33, 0x44, 0x55])
        }

        @Test("should create CDJ-3000 device (player 5)")
        func player5() throws {
            let device = try getVirtualCDJ(mockIface, 5)
            #expect(device.id == 5)
            #expect(device.type == .cdj)
        }

        @Test("should create CDJ-3000 device (player 6)")
        func player6() throws {
            let device = try getVirtualCDJ(mockIface, 6)
            #expect(device.id == 6)
            #expect(device.type == .cdj)
        }

        @Test("should create devices for valid player IDs")
        func validPlayerIds() throws {
            for id in [1, 2, 3, 4, 5, 6, 7, 10, 15, 32] {
                let device = try getVirtualCDJ(mockIface, id)
                #expect(device.id == id)
                #expect(device.type == .cdj)
                #expect(device.name == "ProLink-Connect")
            }
        }

        @Test("should accept custom device name")
        func customName() throws {
            let device = try getVirtualCDJ(mockIface, 1, "My Custom Name")
            #expect(device.id == 1)
            #expect(device.name == "My Custom Name")
        }
    }

    @Suite("Announcer lifecycle")
    @DJLinkActor
    struct AnnouncerLifecycle {
        let clock = TestClock()

        @Test("should start and stop announcer in simple mode")
        func simpleMode() throws {
            let device = try getVirtualCDJ(mockIface, 1)
            let mockSocket = FakeUDPSocket()
            let dm = mockDeviceManager([(2, try getVirtualCDJ(mockIface, 2))], clock: clock)

            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                dm,
                mockIface,
                fullStartup: false,
                clock: clock
            )

            try announcer.start()
            announcer.stop()

            // Should have registered for keep-alive
            #expect(!mockSocket.sent.isEmpty)
        }

        @Test("should start and stop announcer in full startup mode")
        func fullStartupMode() throws {
            let device = try getVirtualCDJ(mockIface, 1)
            let mockSocket = FakeUDPSocket()
            let dm = mockDeviceManager(clock: clock)

            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                dm,
                mockIface,
                fullStartup: true,
                clock: clock
            )

            try announcer.start()

            // Should set up conflict listener
            #expect(mockSocket.onCalls.contains("message"))

            announcer.stop()

            // Should remove conflict listener
            #expect(mockSocket.offEvents.contains("message"))
        }
    }

    @Suite("Conflict detection and handling")
    @DJLinkActor
    struct ConflictDetection {
        let clock = TestClock()

        @Test("should detect conflict packet (0x08)")
        func detectsConflict() throws {
            let device = try getVirtualCDJ(mockIface, 7)
            let conflictPacket = conflictPacketFor(7)

            let mockSocket = FakeUDPSocket()
            let dm = mockDeviceManager(clock: clock)

            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                dm,
                mockIface,
                fullStartup: true,
                clock: clock
            )

            try announcer.start()
            // 원본 mock `on`은 'message' 처리기를 받으면 10ms 뒤에 충돌 패킷으로 부른다.
            if mockSocket.onCalls.contains("message") {
                clock.setTimeout(.ms(10)) {
                    mockSocket.emitMessage(conflictPacket)
                }
            }

            // Give it time to detect conflict
            // 원본 `setTimeout(..., 100)` + `done`
            var finished = false
            clock.setTimeout(.ms(100)) {
                announcer.stop()
                #expect(mockSocket.onCalls.contains("message"))
                finished = true
            }
            clock.advance(ms: 100)
            #expect(finished)
        }

        @Test("should skip non-conflict packets")
        func skipsNonConflictPackets() throws {
            let device = try getVirtualCDJ(mockIface, 7)
            let nonConflictPacket = [UInt8].alloc(0x30)  // Wrong size

            let mockSocket = FakeUDPSocket()
            let dm = mockDeviceManager(clock: clock)

            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                dm,
                mockIface,
                fullStartup: true,
                clock: clock
            )

            try announcer.start()
            if mockSocket.onCalls.contains("message") {
                clock.setTimeout(.ms(10)) { mockSocket.emitMessage(nonConflictPacket) }
            }

            var finished = false
            clock.setTimeout(.ms(50)) {
                announcer.stop()
                // Should still work without throwing
                // 원본 `expect(announcer).toBeDefined()`
                _ = announcer
                finished = true
            }
            clock.advance(ms: 50)
            #expect(finished)
        }

        @Test("should select available device ID when conflict detected")
        func selectsAvailableId() throws {
            let device = try getVirtualCDJ(mockIface, 7)
            let mockSocket = FakeUDPSocket()

            // Simulate devices 7 and 8 already in use
            let existingDevice7 = try getVirtualCDJ(mockIface, 7)
            let existingDevice8 = try getVirtualCDJ(mockIface, 8)
            let dm = mockDeviceManager(
                [
                    (7, existingDevice7),
                    (8, existingDevice8),
                ],
                clock: clock
            )

            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                dm,
                mockIface,
                fullStartup: true,
                clock: clock
            )

            // Should not throw
            try announcer.start()
            announcer.stop()
        }

        @Test("should prefer high device IDs (7-32) over low IDs (1-6)")
        func prefersHighIds() throws {
            let device = try getVirtualCDJ(mockIface, 7)
            let mockSocket = FakeUDPSocket()

            // A discovered peer gives the announcer a unicast target
            let dm = mockDeviceManager([(2, try getVirtualCDJ(mockIface, 2))], clock: clock)

            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                dm,
                mockIface,
                fullStartup: true,
                clock: clock
            )

            try announcer.start()
            announcer.stop()

            // Should successfully start
            #expect(!mockSocket.sent.isEmpty)
        }
    }

    @Suite("Integration with NetworkConfig")
    @DJLinkActor
    struct NetworkConfigIntegration {
        @Test("should accept fullStartup from NetworkConfig")
        func acceptsFullStartup() throws {
            let clock = TestClock()
            let device = try getVirtualCDJ(mockIface, 1)
            let mockSocket = FakeUDPSocket()

            // 원본 `const config = {fullStartup: true}`
            let configFullStartup: Bool? = true
            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                mockDeviceManager(clock: clock),
                mockIface,
                fullStartup: configFullStartup ?? false,
                clock: clock
            )

            _ = announcer
        }
    }

    @Suite("Packet building functions")
    struct PacketBuilding {
        @Test("should build status packet with correct structure")
        func statusPacket() throws {
            let device = try getVirtualCDJ(mockIface, 1)
            let packet = makeStatusPacket(device)

            // 원본과 다름: `toBeInstanceOf(Uint8Array)`는 Swift에서 형이 컴파일 때 정해지므로 형만 확인한다.
            #expect(type(of: packet) == [UInt8].self)
            #expect(packet.count == 284)
            // Check device ID is set at correct positions
            #expect(packet[0x21] == 1)
            #expect(packet[0x24] == 1)
        }

        @Test("should build status packet for high player numbers")
        func statusPacketHighPlayer() throws {
            let device = try getVirtualCDJ(mockIface, 5)
            let packet = makeStatusPacket(device)

            #expect(packet[0x21] == 5)
            #expect(packet[0x24] == 5)
        }

        @Test("should build announce packet with correct structure")
        func announcePacket() throws {
            let device = try getVirtualCDJ(mockIface, 1)
            let packet = try makeAnnouncePacket(device)

            #expect(type(of: packet) == [UInt8].self)
            #expect(packet.count == 54)
            // Check player ID position
            #expect(packet[0x24] == 1)
            // Check player type
            #expect(Int(packet[0x25]) == DeviceType.cdj.rawValue)
        }

        @Test("should build announce packet for CDJ-3000 player numbers")
        func announcePacketHighPlayer() throws {
            let device = try getVirtualCDJ(mockIface, 5)
            let packet = try makeAnnouncePacket(device)

            #expect(packet[0x24] == 5)
            #expect(Int(packet[0x25]) == DeviceType.cdj.rawValue)
        }

        @Test("should include MAC address in announce packet")
        func announcePacketMac() throws {
            let device = try getVirtualCDJ(mockIface, 1)
            let packet = try makeAnnouncePacket(device)

            // MAC address starts at 0x26 (6 bytes)
            #expect(packet[0x26] == 0x00)
            #expect(packet[0x27] == 0x11)
            #expect(packet[0x28] == 0x22)
            #expect(packet[0x29] == 0x33)
            #expect(packet[0x2a] == 0x44)
            #expect(packet[0x2b] == 0x55)
        }

        @Test("should include IP address in announce packet")
        func announcePacketIp() throws {
            let device = try getVirtualCDJ(mockIface, 1)
            let packet = try makeAnnouncePacket(device)

            // IP address starts at 0x2C (4 bytes)
            #expect(packet[0x2c] == 192)
            #expect(packet[0x2d] == 168)
            #expect(packet[0x2e] == 1)
            #expect(packet[0x2f] == 100)
        }
    }

    @Suite("CDJ-3000 compatibility")
    @DJLinkActor
    struct CDJ3000Compatibility {
        let clock = TestClock()

        @Test("should handle player 5 with special startup packets")
        func player5() throws {
            let device = try getVirtualCDJ(mockIface, 5)
            let mockSocket = FakeUDPSocket()
            let dm = mockDeviceManager([(2, try getVirtualCDJ(mockIface, 2))], clock: clock)

            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                dm,
                mockIface,
                fullStartup: true,
                clock: clock
            )

            try announcer.start()
            announcer.stop()

            // Should send startup packets for player 5
            #expect(!mockSocket.sent.isEmpty)
        }

        @Test("should handle player 6 with special startup packets")
        func player6() throws {
            let device = try getVirtualCDJ(mockIface, 6)
            let mockSocket = FakeUDPSocket()
            let dm = mockDeviceManager([(2, try getVirtualCDJ(mockIface, 2))], clock: clock)

            let announcer = Announcer(
                DeviceReference(device),
                mockSocket,
                dm,
                mockIface,
                fullStartup: true,
                clock: clock
            )

            try announcer.start()
            announcer.stop()

            // Should send startup packets for player 6
            #expect(!mockSocket.sent.isEmpty)
        }
    }
}
