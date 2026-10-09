import DJLinkKit
import DJLinkTestSupport
import Foundation
import Testing

@testable import DJLinkPassive

private struct TestCommandRunner: CommandRunner {
    let run: @Sendable (String) throws -> String
    init(_ run: @escaping @Sendable (String) throws -> String) { self.run = run }
    func execSync(_ command: String, timeout: Int) throws -> String { try run(command) }
}

@Suite("alphatheta")
struct PassiveAlphathetaTests {
    @Suite("findAlphaThetaInterface")
    struct Findalphathetainterface {
        @Test("returns first interface from findAllAlphaThetaInterfaces")
        func test1168() throws {
            let runner = TestCommandRunner { cmd in
                if cmd.contains("ioreg") {
                    return "\"USB Vendor Name\" = \"AlphaTheta\"\n\"USB Product Name\" = \"XDJ-XZ\""
                }
                if cmd.contains("networksetup") {
                    return "Hardware Port: USB 10/100 LAN\nDevice: en15\nEthernet Address: c8:3d:fc:0a:58:54"
                }
                if cmd.contains("arp") { return "" }
                return ""
            }
            let provider = FakeInterfaceProvider([
                (
                    "en15",
                    [
                        NetworkInterfaceInfo(
                            address: "169.254.82.203", netmask: "255.255.255.0", family: "IPv4",
                            mac: "c8:3d:fc:0a:58:54", internal: false, cidr: "192.168.1.100/24")
                    ]
                )
            ])
            let result = findAlphaThetaInterface(platform: "darwin", commandRunner: runner, interfaceProvider: provider)
            #expect(result != nil)
            #expect(result?.name == "en15")
            #expect(result?.connectionType == "usb")
        }
        @Test("returns null when no interfaces found")
        func test2194() throws {
            let runner = TestCommandRunner { cmd in
                if cmd.contains("ioreg") {
                    return "\"USB Vendor Name\" = \"Apple\"\n\"USB Product Name\" = \"Keyboard\""
                }
                if cmd.contains("arp") { return "" }
                return ""
            }
            let provider = FakeInterfaceProvider([])
            let result = findAlphaThetaInterface(platform: "darwin", commandRunner: runner, interfaceProvider: provider)
            #expect(result == nil)
        }
    }
    @Suite("findAllAlphaThetaInterfaces")
    struct Findallalphathetainterfaces {
        @Suite("macOS USB detection")
        struct Macosusbdetection {
            @Test("detects USB-connected AlphaTheta devices")
            func test3000() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") {
                        return "\"USB Vendor Name\" = \"AlphaTheta\"\n\"USB Product Name\" = \"XDJ-XZ\""
                    }
                    if cmd.contains("networksetup") {
                        return "Hardware Port: USB 10/100 LAN\nDevice: en15\nEthernet Address: c8:3d:fc:0a:58:54"
                    }
                    if cmd.contains("arp") { return "" }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "en15",
                        [
                            NetworkInterfaceInfo(
                                address: "169.254.82.203", netmask: "255.255.255.0", family: "IPv4",
                                mac: "c8:3d:fc:0a:58:54", internal: false, cidr: "192.168.1.100/24")
                        ]
                    )
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 1)
                #expect(results[0].name == "en15")
                #expect(results[0].connectionType == "usb")
                #expect(results[0].ipv4 == "169.254.82.203")
                #expect(results[0].mac == "c8:3d:fc:0a:58:54")
            }
            @Test("detects multiple USB interfaces")
            func test4073() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") {
                        return "\"USB Vendor Name\" = \"AlphaTheta\"\n\"USB Product Name\" = \"XDJ-XZ\""
                    }
                    if cmd.contains("networksetup") {
                        return
                            "Hardware Port: USB 10/100 LAN\nDevice: en15\nEthernet Address: c8:3d:fc:0a:58:54\n\nHardware Port: USB 10/100 LAN\nDevice: en16\nEthernet Address: c8:3d:fc:0b:59:55"
                    }
                    if cmd.contains("arp") { return "" }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "en15",
                        [
                            NetworkInterfaceInfo(
                                address: "169.254.82.203", netmask: "255.255.255.0", family: "IPv4",
                                mac: "c8:3d:fc:0a:58:54", internal: false, cidr: "192.168.1.100/24")
                        ]
                    ),
                    (
                        "en16",
                        [
                            NetworkInterfaceInfo(
                                address: "169.254.82.204", netmask: "255.255.255.0", family: "IPv4",
                                mac: "c8:3d:fc:0b:59:55", internal: false, cidr: "192.168.1.100/24")
                        ]
                    ),
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 2)
                #expect(results[0].name == "en15")
                #expect(results[1].name == "en16")
            }
            @Test("returns empty array when no AlphaTheta USB device connected")
            func test5261() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") {
                        return "\"USB Vendor Name\" = \"Apple\"\n\"USB Product Name\" = \"Keyboard\""
                    }
                    if cmd.contains("arp") { return "" }
                    return ""
                }
                let provider = FakeInterfaceProvider([])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 0)
            }
            @Test("handles USB 10_100 LAN naming variant")
            func test5800() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") { return "\"USB Vendor Name\" = \"AlphaTheta\"" }
                    if cmd.contains("networksetup") {
                        return "Hardware Port: USB 10_100 LAN\nDevice: en15\nEthernet Address: c8:3d:fc:0a:58:54"
                    }
                    if cmd.contains("arp") { return "" }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "en15",
                        [
                            NetworkInterfaceInfo(
                                address: "169.254.82.203", netmask: "255.255.255.0", family: "IPv4",
                                mac: "c8:3d:fc:0a:58:54", internal: false, cidr: "192.168.1.100/24")
                        ]
                    )
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 1)
                #expect(results[0].name == "en15")
            }
        }
        @Suite("Ethernet detection via ARP cache")
        struct Ethernetdetectionviaarpcache {
            @Test("detects devices via ARP cache with AlphaTheta MAC prefix")
            func test6842() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") { throw DJLinkError("No USB device") }
                    if cmd.contains("arp") { return "? (192.168.1.119) at c8:3d:fc:11:22:33 on en0 ifscope [ethernet]" }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "en0",
                        [
                            NetworkInterfaceInfo(
                                address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
                                mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24")
                        ]
                    )
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 1)
                #expect(results[0].name == "en0")
                #expect(results[0].connectionType == "ethernet")
                #expect(results[0].deviceIps?.contains("192.168.1.119") == true)
            }
            @Test("detects devices with Pioneer DJ MAC prefix (74:5e:1c)")
            func test7778() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") { throw DJLinkError("No USB device") }
                    if cmd.contains("arp") { return "? (192.168.1.50) at 74:5e:1c:aa:bb:cc on en0 ifscope [ethernet]" }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "en0",
                        [
                            NetworkInterfaceInfo(
                                address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
                                mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24")
                        ]
                    )
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 1)
                #expect(results[0].deviceIps?.contains("192.168.1.50") == true)
            }
            @Test("detects multiple devices on same interface")
            func test8575() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") { throw DJLinkError("No USB device") }
                    if cmd.contains("arp") {
                        return
                            "? (192.168.1.119) at c8:3d:fc:11:22:33 on en0 ifscope [ethernet]\n? (192.168.1.120) at c8:3d:fc:44:55:66 on en0 ifscope [ethernet]"
                    }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "en0",
                        [
                            NetworkInterfaceInfo(
                                address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
                                mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24")
                        ]
                    )
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 1)
                #expect(results[0].deviceIps?.count == 2)
                #expect(results[0].deviceIps?.contains("192.168.1.119") == true)
                #expect(results[0].deviceIps?.contains("192.168.1.120") == true)
            }
            @Test("detects devices on multiple interfaces")
            func test9547() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") { throw DJLinkError("No USB device") }
                    if cmd.contains("arp") {
                        return
                            "? (192.168.1.119) at c8:3d:fc:11:22:33 on en0 ifscope [ethernet]\n? (10.0.0.50) at 74:5e:1c:aa:bb:cc on en1 ifscope [ethernet]"
                    }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "en0",
                        [
                            NetworkInterfaceInfo(
                                address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
                                mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24")
                        ]
                    ),
                    (
                        "en1",
                        [
                            NetworkInterfaceInfo(
                                address: "10.0.0.100", netmask: "255.255.255.0", family: "IPv4",
                                mac: "aa:bb:cc:dd:ee:ff", internal: false, cidr: "192.168.1.100/24")
                        ]
                    ),
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 2)
                #expect(results.map(\.name).contains("en0"))
                #expect(results.map(\.name).contains("en1"))
            }
            @Test("ignores non-AlphaTheta MAC addresses in ARP cache")
            func test10607() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") { throw DJLinkError("No USB device") }
                    if cmd.contains("arp") { return "? (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]" }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "en0",
                        [
                            NetworkInterfaceInfo(
                                address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
                                mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24")
                        ]
                    )
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 0)
            }
        }
        @Suite("combined USB and Ethernet detection")
        struct Combinedusbandethernetdetection {
            @Test("returns USB interfaces first, then Ethernet")
            func test11390() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") { return "\"USB Vendor Name\" = \"AlphaTheta\"" }
                    if cmd.contains("networksetup") {
                        return "Hardware Port: USB 10/100 LAN\nDevice: en15\nEthernet Address: c8:3d:fc:0a:58:54"
                    }
                    if cmd.contains("arp") { return "? (192.168.1.119) at c8:3d:fc:11:22:33 on en0 ifscope [ethernet]" }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "en0",
                        [
                            NetworkInterfaceInfo(
                                address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
                                mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24")
                        ]
                    ),
                    (
                        "en15",
                        [
                            NetworkInterfaceInfo(
                                address: "169.254.82.203", netmask: "255.255.255.0", family: "IPv4",
                                mac: "c8:3d:fc:0a:58:54", internal: false, cidr: "192.168.1.100/24")
                        ]
                    ),
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 2)
                #expect(results[0].name == "en15")
                #expect(results[0].connectionType == "usb")
                #expect(results[1].name == "en0")
                #expect(results[1].connectionType == "ethernet")
            }
            @Test("deduplicates interfaces found via both methods")
            func test12655() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") { return "\"USB Vendor Name\" = \"AlphaTheta\"" }
                    if cmd.contains("networksetup") {
                        return "Hardware Port: USB 10/100 LAN\nDevice: en15\nEthernet Address: c8:3d:fc:0a:58:54"
                    }
                    if cmd.contains("arp") {
                        return "? (169.254.88.83) at c8:3d:fc:0a:58:55 on en15 ifscope [ethernet]"
                    }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "en15",
                        [
                            NetworkInterfaceInfo(
                                address: "169.254.82.203", netmask: "255.255.255.0", family: "IPv4",
                                mac: "c8:3d:fc:0a:58:54", internal: false, cidr: "192.168.1.100/24")
                        ]
                    )
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 1)
                #expect(results[0].name == "en15")
                #expect(results[0].connectionType == "usb")
            }
        }
        @Suite("Windows detection")
        struct Windowsdetection {
            @Test("detects USB-connected devices via PowerShell")
            func test13921() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("powershell") {
                        return
                            "{\"Name\":\"Ethernet 3\",\"MacAddress\":\"C8-3D-FC-0A-58-54\",\"InterfaceDescription\":\"USB 10/100 LAN\"}"
                    }
                    if cmd.contains("arp") { return "" }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "Ethernet 3",
                        [
                            NetworkInterfaceInfo(
                                address: "169.254.82.203", netmask: "255.255.255.0", family: "IPv4",
                                mac: "c8:3d:fc:0a:58:54", internal: false, cidr: "192.168.1.100/24")
                        ]
                    )
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "win32", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 1)
                #expect(results[0].name == "Ethernet 3")
                #expect(results[0].connectionType == "usb")
            }
            @Test("detects multiple USB adapters")
            func test14845() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("powershell") {
                        return
                            "[{\"Name\":\"Ethernet 3\",\"MacAddress\":\"C8-3D-FC-0A-58-54\",\"InterfaceDescription\":\"USB 10/100 LAN\"},{\"Name\":\"Ethernet 4\",\"MacAddress\":\"74-5E-1C-AA-BB-CC\",\"InterfaceDescription\":\"Pioneer DJ Adapter\"}]"
                    }
                    if cmd.contains("arp") { return "" }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "Ethernet 3",
                        [
                            NetworkInterfaceInfo(
                                address: "169.254.82.203", netmask: "255.255.255.0", family: "IPv4",
                                mac: "c8:3d:fc:0a:58:54", internal: false, cidr: "192.168.1.100/24")
                        ]
                    ),
                    (
                        "Ethernet 4",
                        [
                            NetworkInterfaceInfo(
                                address: "169.254.82.204", netmask: "255.255.255.0", family: "IPv4",
                                mac: "74:5e:1c:aa:bb:cc", internal: false, cidr: "192.168.1.100/24")
                        ]
                    ),
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "win32", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 2)
            }
            @Test("detects devices via Windows ARP cache")
            func test16039() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("powershell") { return "" }
                    if cmd.contains("arp") {
                        return
                            "Interface: 192.168.1.100 --- 0x5\n  Internet Address      Physical Address      Type\n  192.168.1.119         c8-3d-fc-11-22-33     dynamic"
                    }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "Ethernet",
                        [
                            NetworkInterfaceInfo(
                                address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
                                mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24")
                        ]
                    )
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "win32", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 1)
                #expect(results[0].connectionType == "ethernet")
                #expect(results[0].deviceIps?.contains("192.168.1.119") == true)
            }
        }
        @Suite("Linux detection")
        struct Linuxdetection {
            @Test("detects devices via Linux ARP cache")
            func test17096() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("arp") { return "? (192.168.1.119) at c8:3d:fc:11:22:33 [ether] on eth0" }
                    return ""
                }
                let provider = FakeInterfaceProvider([
                    (
                        "eth0",
                        [
                            NetworkInterfaceInfo(
                                address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
                                mac: "00:11:22:33:44:55", internal: false, cidr: "192.168.1.100/24")
                        ]
                    )
                ])
                let results = findAllAlphaThetaInterfaces(
                    platform: "linux", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 1)
                #expect(results[0].name == "eth0")
                #expect(results[0].connectionType == "ethernet")
            }
        }
        @Suite("error handling")
        struct Errorhandling {
            @Test("handles execSync failures gracefully")
            func test17966() throws {
                let runner = TestCommandRunner { _ in throw DJLinkError("Command failed") }
                let provider = FakeInterfaceProvider([])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 0)
            }
            @Test("handles missing network interfaces gracefully")
            func test18289() throws {
                let runner = TestCommandRunner { cmd in
                    if cmd.contains("ioreg") { return "\"USB Vendor Name\" = \"AlphaTheta\"" }
                    if cmd.contains("networksetup") {
                        return "Hardware Port: USB 10/100 LAN\nDevice: en15\nEthernet Address: c8:3d:fc:0a:58:54"
                    }
                    if cmd.contains("arp") { return "" }
                    return ""
                }
                let provider = FakeInterfaceProvider([])
                let results = findAllAlphaThetaInterfaces(
                    platform: "darwin", commandRunner: runner, interfaceProvider: provider)
                #expect(results.count == 0)
            }
        }
    }
    @Suite("getArpCacheForInterface")
    struct Getarpcacheforinterface {
        @Test("returns IPs from ARP cache for specified interface")
        func test19166() throws {
            let runner = TestCommandRunner { _ in
                "? (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]\n? (192.168.1.119) at c8:3d:fc:11:22:33 on en0 ifscope [ethernet]\n? (10.0.0.1) at 11:22:33:44:55:66 on en1 ifscope [ethernet]"
            }
            let ips = getArpCacheForInterface("en0", platform: "darwin", commandRunner: runner)
            #expect(ips.count == 2)
            #expect(ips.contains("192.168.1.1"))
            #expect(ips.contains("192.168.1.119"))
            #expect(!ips.contains("10.0.0.1"))
        }
        @Test("returns empty array when interface not in ARP cache")
        func test19709() throws {
            let runner = TestCommandRunner { _ in "? (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]" }
            let ips = getArpCacheForInterface("en15", platform: "darwin", commandRunner: runner)
            #expect(ips.count == 0)
        }
        @Test("returns empty array on error")
        func test19994() throws {
            let runner = TestCommandRunner { _ in throw DJLinkError("Command failed") }
            let ips = getArpCacheForInterface("en0", platform: "darwin", commandRunner: runner)
            #expect(ips.count == 0)
        }
    }
}
