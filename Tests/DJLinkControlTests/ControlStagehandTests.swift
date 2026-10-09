import DJLinkControl
import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 tests/control/stagehand.spec.ts

private let hostDevice = Device(
    name: "Stagehand",
    id: 154,
    type: .stagehand,
    macAddr: [0xc8, 0x3d, 0xfc, 0x01, 0x02, 0x03],
    ip: try! Address4("192.168.1.130")
)

private let cdjDevice = Device(
    name: "CDJ-3000",
    id: 1,
    type: .cdj,
    macAddr: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55],
    ip: try! Address4("192.168.1.35")
)

@Suite("Stagehand Control")
struct ControlStagehandTests {
    @Suite("makeStagehandTransportPacket")
    struct MakeStagehandTransportPacket {
        // The iPad app's PLAY pair to a CDJ-3000, as captured 2026-05-23
        // (stagehand-allproto-20260523T142615.pcap): 0x0f then 0x14, both
        // pressed. Byte 33 is the per-command byte the app varies.
        let CAPTURED_PLAY_0F =
            "5173707431576d4a4f4c07537461676568616e6400000000000000000000030100f700300000003a0001000f00010000"
        let CAPTURED_PLAY_14 =
            "5173707431576d4a4f4c07537461676568616e6400000000000000000000030100e800300000003a0001001400010000"
        // Seek forward released.
        let CAPTURED_SEEK_FORWARD_RELEASE =
            "5173707431576d4a4f4c07537461676568616e6400000000000000000000030100ed00300000003a0001001a00000000"

        @Test("is the iPad app's packet byte for byte")
        func iPadAppsPacketByteForByte() throws {
            #expect(try makeStagehandTransportPacket(hostDevice, 0x0f, true, 0xf7).toString(.hex) == CAPTURED_PLAY_0F)
            #expect(try makeStagehandTransportPacket(hostDevice, 0x14, true, 0xe8).toString(.hex) == CAPTURED_PLAY_14)
            #expect(
                try makeStagehandTransportPacket(hostDevice, 0x1a, false, 0xed).toString(.hex)
                    == CAPTURED_SEEK_FORWARD_RELEASE
            )
        }

        @Test("should build a 48-byte 0x07 transport packet")
        func build48ByteTransportPacket() throws {
            let packet = try makeStagehandTransportPacket(hostDevice, 0x0f, true, 0xa5)

            // 원본과 다름: `toBeInstanceOf(Uint8Array)`는 Swift에서 형이 컴파일 때 정해지므로 형만 확인한다.
            #expect(type(of: packet) == [UInt8].self)
            #expect(packet.count == 48)
            #expect(packet.subarray(0, 10) == PROLINK_HEADER)
            #expect(packet[10] == 0x07)

            // 19-byte name field, then the unicast header
            #expect(packet[11] == 83) // 'S'
            #expect(packet[19] == 100) // 'd'
            #expect(packet[20] == 0)
            #expect(packet[30] == 0x03)
            #expect(packet[31] == 0x01)
            #expect(packet[32] == 0x00)

            #expect(packet[33] == 0xa5)
            #expect(packet[34] == 0x00)
            #expect(packet[35] == 0x30)
            #expect(packet[39] == 0x3a)
            #expect(packet[41] == 0x01)
            #expect(packet[43] == 0x0f)
            #expect(packet[45] == 0x01)
        }

        @Test("should support press=false as release flag")
        func pressFalseAsReleaseFlag() throws {
            let packet = try makeStagehandTransportPacket(hostDevice, 0x1a, false, 0x12)
            #expect(packet[45] == 0x00)
        }
    }

    @Suite("makeStagehandPrefWritePacket")
    struct MakeStagehandPrefWritePacket {
        // The iPad app switching on-air display ON, same capture.
        let CAPTURED_ON_AIR_ON =
            "5173707431576d4a4f4c6b537461676568616e64000000000000000000000301003a00500100000000000000810000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

        @Test("is the iPad app's packet byte for byte")
        func iPadAppsPacketByteForByte() throws {
            #expect(
                try makeStagehandPrefWritePacket(hostDevice, StagehandPrefOptions(onAir: .on)).toString(.hex)
                    == CAPTURED_ON_AIR_ON
            )
        }

        @Test("should build a 116-byte 0x6b preference write packet")
        func build116BytePrefWritePacket() throws {
            let packet = try makeStagehandPrefWritePacket(
                hostDevice,
                StagehandPrefOptions(onAir: .on, quantize: 2)
            )

            // 원본과 다름: `toBeInstanceOf(Uint8Array)`는 Swift에서 형이 컴파일 때 정해지므로 형만 확인한다.
            #expect(type(of: packet) == [UInt8].self)
            #expect(packet.count == 116)
            #expect(packet.subarray(0, 10) == PROLINK_HEADER)
            #expect(packet[10] == 0x6b)
            #expect(packet[11] == 83) // 'S'
            #expect(packet[30] == 0x03)
            #expect(packet[31] == 0x01)
            #expect(packet[32] == 0x00)
            #expect(packet[33] == 0x3a)
            #expect(packet[34] == 0x00)
            #expect(packet[35] == 0x50)
            #expect(packet[36] == 0x01)
            #expect(packet[44] == 0x81) // onAir ON
            #expect(packet[60] == 0x82) // quantize index 2 (0x80 | 2)
        }

        @Test("should set onAir=off to 0x80")
        func onAirOffTo0x80() throws {
            let packet = try makeStagehandPrefWritePacket(hostDevice, StagehandPrefOptions(onAir: .off))
            #expect(packet[44] == 0x80)
        }
    }

    @DJLinkActor
    @Suite("Control Class Integration")
    struct ControlClassIntegration {
        // 원본 mockSocket은 send마다 콜백을 바로 불러 준다. FakeUDPSocket 기본값이 같다.
        let mockSocket = FakeUDPSocket()

        @Test("setPlayState should delegate to Stagehand transport commands when host is Stagehand")
        func setPlayStateDelegatesToStagehand() async throws {
            let control = Control(mockSocket, DeviceReference(hostDevice))

            try await control.setPlayState(cdjDevice, .playing)

            // Should have sent 2 packets: 0x0f and 0x14 on BEAT_PORT
            #expect(mockSocket.sent.count == 2)

            let firstCall = mockSocket.sent[0]
            #expect(firstCall.port == BEAT_PORT)
            #expect(firstCall.address == "192.168.1.35")

            let secondCall = mockSocket.sent[1]
            #expect(secondCall.port == BEAT_PORT)
            #expect(secondCall.address == "192.168.1.35")
        }

        @Test("setPlayState should send standard active packet when host is CDJ")
        func setPlayStateStandardActivePacket() async throws {
            let regularHostDevice = Device(
                name: "ProLink-Connect",
                id: 7,
                type: .cdj,
                macAddr: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55],
                ip: try Address4("192.168.1.50")
            )

            let control = Control(mockSocket, DeviceReference(regularHostDevice))

            try await control.setPlayState(cdjDevice, .playing)

            // Should have sent exactly 1 packet
            #expect(mockSocket.sent.count == 1)

            let call = mockSocket.sent[0]
            #expect(call.port == BEAT_PORT)
            #expect(call.address == "192.168.1.35")
        }

        @Test("should expose seek, skip and setPreference on Control")
        func exposeSeekSkipSetPreference() async throws {
            let control = Control(mockSocket, DeviceReference(hostDevice))

            try await control.seekForward(cdjDevice, true)
            try await control.seekBackward(cdjDevice, false)
            try await control.skip(cdjDevice, true)
            try await control.setPreference(cdjDevice, StagehandPrefOptions(onAir: .on))

            // 4 calls (seekForward, seekBackward, skip, setPreference)
            #expect(mockSocket.sent.count == 4)

            // Last call is setPreference on STATUS_PORT
            let lastCall = mockSocket.sent[3]
            #expect(lastCall.port == STATUS_PORT)
            #expect(lastCall.address == "192.168.1.35")
        }
    }
}
