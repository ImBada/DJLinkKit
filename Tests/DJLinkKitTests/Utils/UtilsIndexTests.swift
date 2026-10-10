import DJLinkKit
import Testing

// 원본 tests/utils/index.spec.ts

@Suite("bpmToSeconds")
struct UtilsIndexBpmToSecondsTests {
    // 원본은 jest-each(`each([...]).it(...)`)라서 매개변수 시험 하나로 옮긴다.
    @Test(
        "computes [%d bpm at %d pitch] as %d second per beat",
        arguments: [
            (60.0, 0.0, 1.0),
            (120.0, 0.0, 0.5),
            (60.0, 25.0, 0.8),
        ]
    )
    func computesSecondsPerBeat(bpm: Double, pitch: Double, secondsPerBeat: Double) {
        #expect(bpmToSeconds(bpm, pitch) == secondsPerBeat)
    }
}

@Suite("buildName")
struct UtilsIndexBuildNameTests {
    @Test("should build a 20-byte name buffer from device")
    func buildsTwentyByteName() throws {
        let device = Device(
            name: "CDJ-3000",
            id: 1,
            type: DeviceType(rawValue: 1),
            macAddr: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55],
            ip: try Address4("192.168.1.1")
        )

        let result = try buildName(device)

        // 원본과 다름: `toBeInstanceOf(Uint8Array)`는 Swift에서 형이 컴파일 때 정해지므로 형만 확인한다.
        #expect(type(of: result) == [UInt8].self)
        #expect(result.count == 20)
        #expect(result.toString(.ascii).hasPrefix("CDJ-3000") == true)
    }

    @Test("should pad short names with zeros")
    func padsShortNames() throws {
        let device = Device(
            name: "XDJ",
            id: 1,
            type: DeviceType(rawValue: 1),
            macAddr: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55],
            ip: try Address4("192.168.1.1")
        )

        let result = try buildName(device)

        #expect(result.count == 20)
        #expect(result[3] == 0)  // Padding starts after 'XDJ'
    }
}

@Suite("getSlotName")
struct UtilsIndexGetSlotNameTests {
    @Test("should return slot name for USB")
    func usb() {
        #expect(getSlotName(.usb) == "usb")
    }

    @Test("should return slot name for SD")
    func sd() {
        #expect(getSlotName(.sd) == "sd")
    }

    @Test("should return slot name for RB")
    func rb() {
        #expect(getSlotName(.rb) == "rb")
    }
}

@Suite("getTrackTypeName")
struct UtilsIndexGetTrackTypeNameTests {
    @Test("should return track type name for RB")
    func rb() {
        #expect(getTrackTypeName(.rb) == "rb")
    }

    @Test("should return track type name for Unanalyzed")
    func unanalyzed() {
        #expect(getTrackTypeName(.unanalyzed) == "unanalyzed")
    }

    @Test("should return track type name for AudioCD")
    func audioCD() {
        #expect(getTrackTypeName(.audioCD) == "audiocd")
    }
}
