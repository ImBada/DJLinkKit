import DJLinkKit
import DJLinkPassive
import DJLinkTestSupport
import Testing

// 원본 시험 대응이 아니다(#6). 2026-10-16 실기 pcap(CDJ-2000nexus 2대, DJM-900NXS2, Mac `en8`)에서 고른
// Ethernet 프레임 그대로다. MAC은 제조사 앞자리만 남기고 가렸고(Mac은 02:00:00:00:00:07), 그래서 UDP 검사합은 0(없음)으로 두었다.
// 곡 정보·경로는 없다. 실제 소켓이나 BPF를 열지 않는다.
private enum CapturedFrames {
    /// 1번 CDJ keep-alive(포트 50000, 54바이트)
    static let cdj1KeepAlive = bytes(
        "ffffffffffff745e1c0000010800450000525ce80000401172f6a9fe56c0a9feffffc350c350003e0000517370743157" +
        "6d4a4f4c060043444a2d323030306e6578757300000000000000010200360101745e1c000001a9fe56c0040000000100"
    )
    /// 2번 CDJ keep-alive
    static let cdj2KeepAlive = bytes(
        "ffffffffffff745e1c000002080045000052726a000040115d61a9fe56d3a9feffffc350c350003e0000517370743157" +
        "6d4a4f4c060043444a2d323030306e6578757300000000000000010200360202745e1c000002a9fe56d3040000000100"
    )
    /// DJM keep-alive(33번)
    static let djmKeepAlive = bytes(
        "ffffffffffffc83dfc00002108004500005264dc000040115ed0a9fe62f2a9feffffc350c350003e0000517370743157" +
        "6d4a4f4c0600444a4d2d3930304e585332000000000000000000010200362101c83dfc000021a9fe62f2040000000331"
    )
    /// 1번 CDJ 상태(포트 50002, 빈 덱)
    static let cdj1Status = bytes(
        "020000000007745e1c0000010800456001385ccb0000401101dea9fe56c0a9fe6fef069ac35201240000517370743157" +
        "6d4a4f4c0a43444a2d323030306e657875730000000000000001040100f8010000000000000000000000000000000000" +
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
        "00000800040400000004000000040000000000000000312e343400000000000000030084fffe000f99997fffffff7fff" +
        "ffff000f9999000000ffffffffff01ff0000000000000000000000000000000001000000000000000000000f9999000f" +
        "999900001ab60f0100000000000000000000000000000000000000000000000000000000000000000000000000000000" +
        "0000000000000000000000000000000000000000000000000000000000050000000000000000"
    )
    /// 2번 CDJ 상태(Link Export 시험 곡 10004를 17번 장치에서 올림)
    static let cdj2Status = bytes(
        "020000000007745e1c000002080045600138725900004011ec3ca9fe56d3a9fe6fef0870c35201240000517370743157" +
        "6d4a4f4c0a43444a2d323030306e657875730000000000000001040200f8020001001104010000002714000000010000" +
        "003200000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000" +
        "00000800040400000004000000040000000000000006312e34340000000000000004008cfffe00102f1a80002ee07fff" +
        "ffff00102f1a000100ff0000000101ff010000000000000000000000000000000100000000000000000000102f1a0010" +
        "2f1a00001b530f0100000000000000000000000000000000000000000000000000000000000000000000000000000000" +
        "000000000000000000000000000000000000000000000000000000000005000007b900000000"
    )
    /// DJM on-air(포트 50001, 45바이트, 하위 종류 0x02)
    static let djmOnAir = bytes(
        "ffffffffffffc83dfc00002108004520004963e6000040115fafa9fe62f2a9feffff1fabc35100350000517370743157" +
        "6d4a4f4c03444a4d2d3930304e5853320000000000000000000102210009000101000000000000"
    )
    /// 2번 CDJ 비트(포트 50001, 96바이트, 0x28)
    static let cdj2Beat = bytes(
        "ffffffffffff745e1c00000208004560007c72e5000040115c5ca9fe56d3a9feffff08ebc35100680000517370743157" +
        "6d4a4f4c2843444a2d323030306e6578757300000000000000010002003c000001f4000003e8000005dc000007d00000" +
        "0dac00000fa0ffffffffffffffffffffffffffffffffffffffffffffffff00102f1a00002ee002000002"
    )

    static func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map {
            let start = hex.index(hex.startIndex, offsetBy: $0)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }

    /// IPv4 머리가 20바이트인 프레임의 UDP payload.
    static func payload(_ frame: [UInt8]) -> [UInt8] { Array(frame.dropFirst(42)) }
}

@DJLinkActor
private final class CapturePcapBackend: PcapBackend {
    var packetHandler: (@DJLinkActor ([UInt8], Bool) -> Void)?
    var closeCount = 0
    func deviceList() throws -> [CapDeviceListEntry] { [] }
    func open(device: String, filter: String, bufSize: Int, bufferSize: Int) throws {}
    func onPacket(_ handler: @escaping @DJLinkActor ([UInt8], Bool) -> Void) { packetHandler = handler }
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) {}
    func close() {
        closeCount += 1
        packetHandler = nil
    }
}

@Suite("패시브 실기 캡처(#6)")
@DJLinkActor
struct PassiveCaptureTests {
    @Test("실기 캡처의 keep-alive·on-air·비트 길이와 종류 바이트")
    func capturedShapes() {
        for frame in [CapturedFrames.cdj1KeepAlive, CapturedFrames.cdj2KeepAlive, CapturedFrames.djmKeepAlive] {
            let payload = CapturedFrames.payload(frame)
            #expect(payload.count == 54 && payload[0x0a] == 0x06)
            #expect(Int(payload[0x22]) << 8 | Int(payload[0x23]) == 54)
        }
        let onAir = CapturedFrames.payload(CapturedFrames.djmOnAir)
        #expect(onAir.count == 45 && onAir[0x0a] == 0x03 && onAir[0x20] == 0x02)
        let beat = CapturedFrames.payload(CapturedFrames.cdj2Beat)
        #expect(beat.count == 96 && beat[0x0a] == 0x28)
    }

    @Test("실기 캡처 프레임이 pcap 경로를 지나 능동 파서와 같은 장치·상태·on-air·비트로 나온다")
    func capturedFramesThroughPassive() throws {
        let backend = CapturePcapBackend()
        let network = try bringOnlinePassive(
            .init(iface: "en8", bufferSize: 2048), backend: backend,
            socketFactory: FakeSocketFactory(), clock: TestClock())
        var devices: [Device] = []
        var statuses: [CDJStatus.State] = []
        var onAirs: [CDJStatus.OnAirStatus] = []
        var beats: [CDJStatus.BeatState] = []
        network.deviceManager.on(.connected) { devices.append($0) }
        network.statusEmitter.on(.status) { statuses.append($0) }
        network.statusEmitter.on(.onAir) { onAirs.append($0) }
        network.beatEmitter.on(.beat) { beats.append($0) }

        let frames = [
            CapturedFrames.cdj1KeepAlive, CapturedFrames.cdj2KeepAlive, CapturedFrames.djmKeepAlive,
            CapturedFrames.cdj1Status, CapturedFrames.cdj2Status, CapturedFrames.djmOnAir, CapturedFrames.cdj2Beat,
        ]
        for frame in frames { backend.packetHandler?(frame, false) }

        #expect(devices.map(\.id) == [1, 2, 33])
        #expect(devices.map(\.name) == ["CDJ-2000nexus", "CDJ-2000nexus", "DJM-900NXS2"])
        #expect(devices.map(\.type) == [.cdj, .cdj, .mixer])
        #expect(devices.map(\.ip.address) == ["169.254.86.192", "169.254.86.211", "169.254.98.242"])
        #expect(devices.map(\.macAddr) == [
            [0x74, 0x5e, 0x1c, 0x00, 0x00, 0x01], [0x74, 0x5e, 0x1c, 0x00, 0x00, 0x02],
            [0xc8, 0x3d, 0xfc, 0x00, 0x00, 0x21],
        ])

        let expectedStatuses = try [CapturedFrames.cdj1Status, CapturedFrames.cdj2Status].map {
            try #require(try statusFromPacket(CapturedFrames.payload($0)))
        }
        #expect(statuses == expectedStatuses)
        #expect(statuses.map(\.deviceId) == [1, 2])
        #expect(statuses.last?.trackId == 10004)
        #expect(statuses.last?.trackDeviceId == 17)
        #expect(statuses.last?.trackSlot == .rb)

        #expect(onAirs.count == 1)
        #expect(onAirs.first?.deviceId == 33)
        #expect(onAirs.first?.channels == [1: false, 2: true, 3: true, 4: false])

        let expectedBeat = try #require(beatFromPacket(CapturedFrames.payload(CapturedFrames.cdj2Beat)))
        #expect(beats == [expectedBeat])
        #expect(beats.first?.deviceId == 2)

        network.stop()
        #expect(backend.closeCount == 1)
    }
}
