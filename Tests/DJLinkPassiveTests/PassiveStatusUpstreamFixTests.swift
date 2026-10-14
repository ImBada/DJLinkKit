import DJLinkKit
import DJLinkPassive
import Testing

/// DJM-900NXS2가 비트 포트(50001)로 보낸 실제 4채널 on-air 패킷(2026-10-14 실기, 45바이트). 채널 2·3이 on-air다.
private let DJM_900NXS2_ON_AIR: [UInt8] = {
    let hex = "5173707431576d4a4f4c03444a4d2d3930304e5853320000000000000000000102210009000101000000000000"
    return stride(from: 0, to: hex.count, by: 2).map {
        let start = hex.index(hex.startIndex, offsetBy: $0)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
}()

@Suite("패시브 on-air 원본 버그 수정")
@DJLinkActor
struct PassiveStatusUpstreamFixTests {
    @Test("패시브도 비트 포트로 온 0x03 on-air 패킷만 onAir로 낸다")
    func reportsOnAirFromBeatPort() {
        let adapter = PcapAdapter(
            config: .init(iface: "en0"), backendFactory: { throw DJLinkError("시험에서 pcap을 열지 않는다") })
        let emitter = PassiveStatusEmitter(adapter)
        var received: [CDJStatus.OnAirStatus] = []
        emitter.on(.onAir) { received.append($0) }
        let info = PacketInfo(payload: DJM_900NXS2_ON_AIR, srcAddr: "10.0.0.33")
        adapter.emitter.emit(.beat, .init(packet: DJM_900NXS2_ON_AIR, info: info))
        #expect(received.count == 1)
        #expect(received.first?.deviceId == 33)
        #expect(received.first?.channels == [1: false, 2: true, 3: true, 4: false])

        var beat = DJM_900NXS2_ON_AIR
        beat[0x0a] = 0x28
        adapter.emitter.emit(.beat, .init(packet: beat, info: info))
        #expect(received.count == 1)

        emitter.stop()
        adapter.emitter.emit(.beat, .init(packet: DJM_900NXS2_ON_AIR, info: info))
        #expect(received.count == 1)
    }
}
