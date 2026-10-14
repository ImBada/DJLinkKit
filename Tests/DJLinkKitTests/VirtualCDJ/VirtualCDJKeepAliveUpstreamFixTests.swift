import DJLinkKit
import DJLinkTestSupport
import Testing

@Suite("가상 CDJ keep-alive 원본 버그 수정")
@DJLinkActor
struct VirtualCDJKeepAliveUpstreamFixTests {
    let iface = NetworkInterfaceInfo(
        address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
        mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24", scopeid: nil)

    @Test("keep-alive는 실제 장비처럼 54바이트이고 0x30에 장치 수를 싣는다")
    func keepAliveMatchesRealDevices() throws {
        // CDJ-2000nexus·DJM-900NXS2 실기(2026-10-14)의 0x06은 54바이트이고 길이 칸도 0x36이다.
        // 0x30 = 장치 수, 0x31-0x33 = 0, 0x34 = 장치 종류로 보이는 값(CDJ 0x01, DJM 0x03), 0x35 = 마지막 바이트.
        let clock = TestClock()
        let socket = FakeUDPSocket()
        let deviceManager = DeviceManager(FakeUDPSocket(), clock: clock)
        for (id, name) in [(1, "CDJ-2000nexus"), (2, "CDJ-2000nexus"), (33, "DJM-900NXS2")] {
            var device = try getVirtualCDJ(iface, id, name)
            if id == 33 { device.type = .mixer }
            deviceManager.devices[id] = device
        }
        let announcer = Announcer(
            DeviceReference(try getVirtualCDJ(iface, 7)), socket, deviceManager, iface, fullStartup: true,
            clock: clock)

        try announcer.start()
        clock.advance(ms: 5000)
        socket.clearSent()
        clock.advance(ms: 3000)
        announcer.stop()

        let keepAlives = socket.sent.map(\.message).filter { $0[0x0a] == 0x06 }
        #expect(!keepAlives.isEmpty)
        for packet in keepAlives {
            #expect(packet.count == 0x36)
            #expect(try packet.readUInt16BE(0x22) == packet.count)
            #expect(packet[0x24] == 7)
            #expect(packet[0x30] == 4)  // 장치 셋과 우리
            #expect(Array(packet[0x31...0x34]) == [0x00, 0x00, 0x00, 0x01])
        }
    }
}
