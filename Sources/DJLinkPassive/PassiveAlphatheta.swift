import DJLinkKit
import Foundation

public protocol CommandRunner: Sendable {
    func execSync(_ command: String, timeout: Int) throws -> String
}

public struct ProcessCommandRunner: CommandRunner {
    public init() {}
    public func execSync(_ command: String, timeout: Int) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeout), execute: timer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        guard process.terminationStatus == 0 else { throw DJLinkError("Command failed: \(command)") }
        return String(decoding: data, as: UTF8.self)
    }
}

public enum PassivePlatform {
    public static var current: String {
        #if os(macOS)
            "darwin"
        #elseif os(Windows)
            "win32"
        #else
            "linux"
        #endif
    }
}

public struct AlphaThetaInterface: Equatable, Sendable {
    public var name: String
    public var mac: String
    public var ipv4: String?
    public var info: NetworkInterfaceInfo
    public var connectionType: String
    public var deviceIps: [String]?
    public init(
        name: String, mac: String, ipv4: String? = nil, info: NetworkInterfaceInfo, connectionType: String,
        deviceIps: [String]? = nil
    ) {
        self.name = name
        self.mac = mac
        self.ipv4 = ipv4
        self.info = info
        self.connectionType = connectionType
        self.deviceIps = deviceIps
    }
}

private let ALPHATHETA_MAC_PREFIXES = ["c8:3d:fc", "74:5e:1c", "ac:b5:7d", "b8:e8:56", "00:e0:4c"]
private func isAlphaThetaMac(_ mac: String) -> Bool {
    ALPHATHETA_MAC_PREFIXES.contains { mac.lowercased().hasPrefix($0) }
}
package func passiveIsIPv4(_ info: NetworkInterfaceInfo) -> Bool {
    // 원본과 다름: 기반 family는 String이므로 구형 Node의 숫자 4는 "4"로 주입한다.
    info.family == "IPv4" || info.family == "4"
}
private func match(_ input: String, _ pattern: String) -> String? {
    let regex = try! NSRegularExpression(pattern: pattern)
    guard let result = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
        let range = Range(result.range(at: 1), in: input)
    else { return nil }
    return String(input[range])
}

public func findAlphaThetaInterface(
    platform: String = PassivePlatform.current, commandRunner: any CommandRunner = ProcessCommandRunner(),
    interfaceProvider: any InterfaceProvider = SystemInterfaceProvider()
) -> AlphaThetaInterface? {
    findAllAlphaThetaInterfaces(platform: platform, commandRunner: commandRunner, interfaceProvider: interfaceProvider)
        .first
}

public func findAllAlphaThetaInterfaces(
    platform: String = PassivePlatform.current, commandRunner: any CommandRunner = ProcessCommandRunner(),
    interfaceProvider: any InterfaceProvider = SystemInterfaceProvider()
) -> [AlphaThetaInterface] {
    var results: [AlphaThetaInterface] = []
    if platform == "darwin" {
        results = findAllAlphaThetaInterfacesMacOS(commandRunner, interfaceProvider)
    } else if platform == "win32" {
        results = findAllAlphaThetaInterfacesWindows(commandRunner, interfaceProvider)
    }
    var seenInterfaces = Set(results.map(\.name))
    for iface in findAllAlphaThetaViaEthernet(platform, commandRunner, interfaceProvider)
    where !seenInterfaces.contains(iface.name) {
        results.append(iface)
        seenInterfaces.insert(iface.name)
    }
    return results
}
private func findAllAlphaThetaInterfacesMacOS(_ runner: any CommandRunner, _ provider: any InterfaceProvider)
    -> [AlphaThetaInterface]
{
    do {
        let ioregOutput = try runner.execSync(
            "ioreg -p IOUSB -l -w 0 | grep -E '\"USB Vendor Name\"|\"USB Product Name\"'", timeout: 5000)
        guard ioregOutput.lowercased().contains("alphatheta") else { return [] }
        let output = try runner.execSync("networksetup -listallhardwareports", timeout: 5000)
        let separator = try! NSRegularExpression(pattern: "\n\n+")
        let blocks = separator.stringByReplacingMatches(
            in: output, range: NSRange(output.startIndex..., in: output), withTemplate: "\u{1}"
        ).components(separatedBy: "\u{1}")
        let usbLanInterfaces = blocks.compactMap { block -> (String, String)? in
            guard block.contains("USB 10/100 LAN") || block.contains("USB 10_100 LAN"),
                let name = match(block, #"Device:\s*(\S+)"#), let mac = match(block, #"Ethernet Address:\s*(\S+)"#)
            else { return nil }
            return (name, mac)
        }
        guard !usbLanInterfaces.isEmpty else { return [] }
        let interfaces = provider.networkInterfaces()
        return usbLanInterfaces.compactMap { name, mac in
            guard let infos = interfaces.first(where: { $0.name == name })?.addresses else { return nil }
            let ipv4 = infos.first(where: passiveIsIPv4)
            guard let info = ipv4 ?? infos.first else { return nil }
            return AlphaThetaInterface(name: name, mac: mac, ipv4: ipv4?.address, info: info, connectionType: "usb")
        }
    } catch { return [] }
}
private func findAllAlphaThetaInterfacesWindows(_ runner: any CommandRunner, _ provider: any InterfaceProvider)
    -> [AlphaThetaInterface]
{
    do {
        let psCommand = """

                  Get-NetAdapter | Where-Object {
                    $_.InterfaceDescription -like '*AlphaTheta*' -or
                    $_.InterfaceDescription -like '*Pioneer*' -or
                    $_.InterfaceDescription -like '*USB 10/100 LAN*'
                  } | Select-Object -Property Name, MacAddress, InterfaceDescription | ConvertTo-Json
                
            """
        let output = try runner.execSync(
            "powershell -Command \"\(psCommand.replacingOccurrences(of: "\n", with: " "))\"", timeout: 10000)
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let adapters = try JSONSerialization.jsonObject(with: Data(output.utf8))
        let adapterList = adapters as? [[String: Any]] ?? (adapters as? [String: Any]).map { [$0] } ?? []
        guard !adapterList.isEmpty else { return [] }
        let interfaces = provider.networkInterfaces()
        var results: [AlphaThetaInterface] = []
        for adapter in adapterList {
            let targetMac = (adapter["MacAddress"] as? String)?.replacingOccurrences(of: "-", with: ":").lowercased()
            var found = false
            for (name, infos) in interfaces {
                if let matched = infos.first(where: { $0.mac.lowercased() == targetMac }) {
                    let ipv4 = infos.first(where: passiveIsIPv4)
                    results.append(
                        .init(
                            name: name, mac: matched.mac, ipv4: ipv4?.address, info: ipv4 ?? matched,
                            connectionType: "usb"))
                    found = true
                    break
                }
            }
            if !found, let name = adapter["Name"] as? String,
                let infos = interfaces.first(where: { $0.name == name })?.addresses,
                let info = infos.first(where: passiveIsIPv4) ?? infos.first
            {
                results.append(
                    .init(
                        name: name, mac: adapter["MacAddress"] as? String ?? "",
                        ipv4: infos.first(where: passiveIsIPv4)?.address, info: info, connectionType: "usb"))
            }
        }
        return results
    } catch { return [] }
}

public func inferDeviceIpFromHost(_ hostIp: String) -> String? {
    guard hostIp.hasPrefix("169.254.") else { return nil }
    return nil
}
public func getArpCacheForInterface(
    _ interfaceName: String, platform: String = PassivePlatform.current,
    commandRunner: any CommandRunner = ProcessCommandRunner()
) -> [String] {
    do {
        if platform == "darwin" || platform == "linux" {
            let output = try commandRunner.execSync("arp -an", timeout: 5000)
            return output.components(separatedBy: "\n").compactMap { line in
                line.contains(interfaceName) ? match(line, #"\((\d+\.\d+\.\d+\.\d+)\)"#) : nil
            }
        }
    } catch {}
    return []
}
private struct ArpEntry {
    var ip: String
    var mac: String
}
private func getAlphaThetaArpEntries(_ platform: String, _ runner: any CommandRunner) -> [(
    name: String, entries: [ArpEntry]
)] {
    var result: [(name: String, entries: [ArpEntry])] = []
    func append(_ name: String, _ ip: String, _ mac: String) {
        guard isAlphaThetaMac(mac) else { return }
        if let index = result.firstIndex(where: { $0.name == name }) {
            result[index].entries.append(.init(ip: ip, mac: mac))
        } else {
            result.append((name, [.init(ip: ip, mac: mac)]))
        }
    }
    do {
        if platform == "darwin" || platform == "linux" {
            let output = try runner.execSync("arp -an", timeout: 5000)
            for line in output.components(separatedBy: "\n") {
                if let ip = match(line, #"\((\d+\.\d+\.\d+\.\d+)\)"#), let mac = match(line, #"(?i)at\s+([0-9a-f:]+)"#),
                    let iface = match(line, #"on\s+(\S+)"#)
                {
                    append(iface, ip, mac)
                }
            }
        } else if platform == "win32" {
            let output = try runner.execSync("arp -a", timeout: 5000)
            var currentInterface = ""
            for line in output.components(separatedBy: "\n") {
                if let header = match(line, #"Interface:\s+(\d+\.\d+\.\d+\.\d+)"#) {
                    currentInterface = header
                    continue
                }
                if !currentInterface.isEmpty, let ip = match(line, #"(?i)(\d+\.\d+\.\d+\.\d+)\s+[0-9a-f-]+"#),
                    let mac = match(line, #"(?i)\d+\.\d+\.\d+\.\d+\s+([0-9a-f-]+)"#)
                {
                    append(currentInterface, ip, mac.replacingOccurrences(of: "-", with: ":"))
                }
            }
        }
    } catch {}
    return result
}
private func findAllAlphaThetaViaEthernet(
    _ platform: String, _ runner: any CommandRunner, _ provider: any InterfaceProvider
) -> [AlphaThetaInterface] {
    let entries = getAlphaThetaArpEntries(platform, runner)
    guard !entries.isEmpty else { return [] }
    let interfaces = provider.networkInterfaces()
    return entries.compactMap { arpName, devices in
        guard
            let iface = interfaces.first(where: { $0.name == arpName })
                ?? interfaces.first(where: {
                    $0.addresses.contains(where: { passiveIsIPv4($0) && $0.address == arpName })
                }),
            let ipv4 = iface.addresses.first(where: passiveIsIPv4)
        else { return nil }
        return AlphaThetaInterface(
            name: iface.name, mac: ipv4.mac, ipv4: ipv4.address, info: ipv4, connectionType: "ethernet",
            deviceIps: devices.map(\.ip))
    }
}
