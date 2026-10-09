import DJLinkKit
import DJLinkTestSupport
import Testing

@Suite("가상 CDJ 상태 머리말 원본 버그 수정")
struct VirtualCDJStatusUpstreamFixTests {
    @Test("상태 머리말은 0에 쓰고 이름 영역은 이름과 영 패딩으로 유지한다", arguments: ["CDJ", "SwiftVirtualCDJ"])
    func headerAndName(_ name: String) {
        let device = mockDevice(id: 7, name: name)
        let packet = makeStatusPacket(device)
        #expect(packet.subarray(0, 10) == PROLINK_HEADER)
        #expect(packet[0x0a] == 0x0a)
        #expect(packet.subarray(0x0b, 0x1f) == [UInt8](name, encoding: .ascii) + [UInt8].alloc(20 - name.utf8.count))
        #expect(packet[0x21] == 7)
        #expect(packet[0x24] == 7)
        #expect(packet.subarray(0x7c, 0x80) == [UInt8](VIRTUAL_CDJ_FIRMWARE, encoding: .ascii))
        #expect(packet.count == 284)
    }

    @Test("생성한 상태 패킷을 기존 상태 파서가 읽을 수 있다")
    func parsesGeneratedStatus() throws {
        let packet = makeStatusPacket(mockDevice(id: 7, name: "CDJ"))
        #expect(try statusFromPacket(packet)?.deviceId == 7)
    }
}
