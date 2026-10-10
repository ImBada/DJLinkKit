import DJLinkKit
import DJLinkPassive
import Testing

@Suite("패시브 위치 파서 원본 버그 수정")
@DJLinkActor
struct PassivePositionUpstreamFixTests {
    @Test("패시브 위치 이벤트는 0x28을 버리고 0x0b만 읽는다")
    func filtersPacketTypes() {
        let adapter = PcapAdapter(
            config: .init(iface: "en0"), backendFactory: { throw DJLinkError("시험에서 pcap을 열지 않는다") })
        let emitter = PassivePositionEmitter(adapter)
        var positions: [CDJStatus.PositionState] = []
        emitter.on(.position) { positions.append($0) }
        var packet = [UInt8].alloc(0x34)
        packet.set(PROLINK_HEADER, 0)
        packet[0x0a] = 0x28
        packet[0x21] = 3
        packet.writeUInt16BE(0x0c, 0x22)
        let info = PacketInfo(payload: packet, srcAddr: "10.0.0.1")
        adapter.emitter.emit(.beat, .init(packet: packet, info: info))
        #expect(positions.isEmpty)
        packet[0x0a] = 0x0b
        adapter.emitter.emit(.beat, .init(packet: packet, info: info))
        #expect(positions.count == 1)
        emitter.stop()
    }
}
