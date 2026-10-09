import DJLinkKit
import DJLinkTestSupport
import Testing

@testable import DJLinkPassive

@DJLinkActor
private final class MockPcapBackend: PcapBackend {
    var devices: [CapDeviceListEntry] = []
    var opens: [(device: String, filter: String, bufSize: Int, bufferSize: Int)] = []
    var deviceListCalls = 0
    func deviceList() throws -> [CapDeviceListEntry] {
        deviceListCalls += 1
        return devices
    }
    func open(device: String, filter: String, bufSize: Int, bufferSize: Int) throws {
        opens.append((device, filter, bufSize, bufferSize))
    }
    func setMinBytes(_ bytes: Int) {}
    func onPacket(_ handler: @escaping @DJLinkActor ([UInt8], Bool) -> Void) {}
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) {}
    func close() {}
}
private func mockIPv4Interface(_ address: String, _ mac: String = "00:11:22:33:44:55") -> NetworkInterfaceInfo {
    NetworkInterfaceInfo(
        address: address, netmask: "255.255.255.0", family: "IPv4", mac: mac, internal: false, cidr: "\(address)/24")
}
@DJLinkActor
private func checkOpen(
    _ iface: String, platform: String = "win32", interfaces: [(String, [NetworkInterfaceInfo])],
    devices: [CapDeviceListEntry], expected: String
) throws {
    let backend = MockPcapBackend()
    backend.devices = devices
    let adapter = PcapAdapter(
        config: PcapAdapterConfig(iface: iface), backend: backend, platform: platform,
        interfaceProvider: FakeInterfaceProvider(interfaces))
    try adapter.start()
    #expect(backend.opens.count == 1)
    #expect(backend.opens[0].device == expected)
    // 원본과 다름: expect.any(String/Number/Buffer)는 Swift의 정적 형으로 보장한다.
}
@Suite("PcapAdapter")
@DJLinkActor
struct PassivePcapAdapterTests {
    @Suite("resolveWindowsInterface (via start())")
    @DJLinkActor
    struct ResolveWindowsInterface {
        @Test("translates Node.js interface name to Npcap device path by matching IPv4")
        func translates() throws {
            try checkOpen(
                "Ethernet", interfaces: [("Ethernet", [mockIPv4Interface("192.168.1.211")])],
                devices: [
                    .init(name: "\\Device\\NPF_{AAAA-BBBB}", description: "Loopback", addresses: ["127.0.0.1"]),
                    .init(
                        name: "\\Device\\NPF_{1234-5678}", description: "Intel Ethernet", addresses: ["192.168.1.211"]),
                ], expected: "\\Device\\NPF_{1234-5678}")
        }
        @Test("falls back to original name when no matching cap device found")
        func noMatch() throws {
            try checkOpen(
                "Ethernet", interfaces: [("Ethernet", [mockIPv4Interface("192.168.1.211")])],
                devices: [.init(name: "\\Device\\NPF_{AAAA-BBBB}", description: "Loopback", addresses: ["127.0.0.1"])],
                expected: "Ethernet")
        }
        @Test("falls back to original name when Node.js interface not found")
        func missingInterface() throws {
            try checkOpen(
                "Ethernet", interfaces: [("WiFi", [mockIPv4Interface("10.0.0.1")])], devices: [], expected: "Ethernet")
        }
        @Test("falls back when interface has no IPv4 addresses")
        func noIPv4() throws {
            let ipv6 = NetworkInterfaceInfo(
                address: "fe80::1", netmask: "ffff:ffff:ffff:ffff::", family: "IPv6", mac: "00:11:22:33:44:55",
                internal: false, cidr: "fe80::1/64", scopeid: 0)
            try checkOpen(
                "Ethernet", interfaces: [("Ethernet", [ipv6])],
                devices: [.init(name: "\\Device\\NPF_{1234}", description: "test", addresses: ["192.168.1.1"])],
                expected: "Ethernet")
        }
        @Test("handles cap devices with no addresses")
        func missingAddresses() throws {
            try checkOpen(
                "Ethernet", interfaces: [("Ethernet", [mockIPv4Interface("192.168.1.100")])],
                devices: [
                    .init(name: "\\Device\\NPF_{NOADDR}", description: "No addresses", addresses: nil),
                    .init(name: "\\Device\\NPF_{MATCH}", description: "Match", addresses: ["192.168.1.100"]),
                ], expected: "\\Device\\NPF_{MATCH}")
        }
        @Test("matches first device when multiple cap devices share same address")
        func firstMatch() throws {
            try checkOpen(
                "Ethernet", interfaces: [("Ethernet", [mockIPv4Interface("192.168.1.100")])],
                devices: [
                    .init(name: "\\Device\\NPF_{FIRST}", description: "First", addresses: ["192.168.1.100"]),
                    .init(name: "\\Device\\NPF_{SECOND}", description: "Second", addresses: ["192.168.1.100"]),
                ], expected: "\\Device\\NPF_{FIRST}")
        }
    }
    @Suite("non-Windows platforms")
    @DJLinkActor
    struct NonWindows {
        @Test("does not translate interface name on macOS")
        func macOS() throws {
            try checkOpen(
                "en0", platform: "darwin", interfaces: [("en0", [mockIPv4Interface("192.168.1.100")])], devices: [],
                expected: "en0")
        }
        @Test("does not translate interface name on Linux")
        func linux() throws {
            try checkOpen(
                "eth0", platform: "linux", interfaces: [("eth0", [mockIPv4Interface("10.0.0.5")])], devices: [],
                expected: "eth0")
        }
    }
    @Suite("Windows device path passthrough")
    @DJLinkActor
    struct Passthrough {
        @Test("does not translate names that already start with \\Device\\")
        func alreadyResolved() throws {
            try checkOpen(
                "\\Device\\NPF_{ALREADY-RESOLVED}", interfaces: [], devices: [],
                expected: "\\Device\\NPF_{ALREADY-RESOLVED}")
        }
    }
}
