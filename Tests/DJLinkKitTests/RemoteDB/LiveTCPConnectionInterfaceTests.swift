import Testing

@testable import DJLinkKit

// 원본 시험 대응이 아니다(CLI 안전을 위한 추가). 소켓을 열지 않는다: 인터페이스 목록을 바꿔 끼우고 연결 전에 끝나는 경로만 본다.
private struct FixedInterfaces: InterfaceProvider {
    var interfaces: [(name: String, addresses: [NetworkInterfaceInfo])]
    func networkInterfaces() -> [(name: String, addresses: [NetworkInterfaceInfo])] { interfaces }
}

private func ipv4(_ address: String, _ prefix: Int) -> NetworkInterfaceInfo {
    NetworkInterfaceInfo(
        address: address, netmask: "", family: "IPv4", mac: "00:00:00:00:00:00", internal: false,
        cidr: "\(address)/\(prefix)")
}

private let linkLocalIPv6 = NetworkInterfaceInfo(
    address: "fe80::1", netmask: "ffff:ffff:ffff:ffff::", family: "IPv6", mac: "00:00:00:00:00:00",
    internal: false, cidr: "fe80::1/64", scopeid: 8)

@Suite("LiveTCPConnectionInterface") @DJLinkActor
struct LiveTCPConnectionInterfaceTests {
    @Test("a connection destroyed before connecting fails without looking up the interface")
    func destroyedBeforeConnect() async throws {
        let client = LiveTCPConnection()
        client.interfaceProvider = FixedInterfaces(interfaces: [])
        try client.setRequiredInterface(name: "djlink-test-interface")
        client.destroy(nil)
        await #expect(throws: DJLinkError("Socket closed")) {
            try await client.connect(port: 12345, host: "192.0.2.1")
        }
        #expect(!client.isOpen)
    }

    @Test("a missing interface is refused before the connect guard and socket")
    func missingInterface() async throws {
        let client = LiveTCPConnection()
        client.interfaceProvider = FixedInterfaces(interfaces: [("en0", [ipv4("192.0.2.10", 24)])])
        var guarded = false
        try client.setConnectGuard { guarded = true }
        try client.setRequiredInterface(name: "djlink-test-interface")
        await #expect(throws: DJLinkError("Network interface not found: djlink-test-interface")) {
            try await client.connect(port: 12345, host: "192.0.2.1")
        }
        #expect(!guarded)
        #expect(!client.isOpen)
    }

    @Test("an interface without an IPv4 address is refused before the connect guard and socket")
    func interfaceWithoutIPv4() async throws {
        let client = LiveTCPConnection()
        client.interfaceProvider = FixedInterfaces(interfaces: [("djlink-test-interface", [linkLocalIPv6])])
        var guarded = false
        try client.setConnectGuard { guarded = true }
        try client.setRequiredInterface(name: "djlink-test-interface")
        await #expect(throws: DJLinkError("Network interface has no IPv4 address: djlink-test-interface")) {
            try await client.connect(port: 12345, host: "192.0.2.1")
        }
        #expect(!guarded)
        #expect(!client.isOpen)
    }

    @Test("binds to the interface address in the destination's subnet, else the first IPv4 address")
    func localAddressChoice() throws {
        let client = LiveTCPConnection()
        client.interfaceProvider = FixedInterfaces(interfaces: [
            ("en0", [ipv4("192.0.2.10", 24)]),
            ("en8", [linkLocalIPv6, ipv4("198.51.100.7", 24), ipv4("169.254.111.239", 16)]),
        ])
        #expect(try client.localAddress(interface: "en8", host: "169.254.86.192") == "169.254.111.239")
        #expect(try client.localAddress(interface: "en8", host: "198.51.100.20") == "198.51.100.7")
        #expect(try client.localAddress(interface: "en8", host: "203.0.113.5") == "198.51.100.7")
        #expect(try client.localAddress(interface: "en0", host: "169.254.86.192") == "192.0.2.10")
    }
}
