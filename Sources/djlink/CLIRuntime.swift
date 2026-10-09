import DJLinkKit
import Foundation

// 네트워크에 붙는 공통 순서(원본 cli의 bringOnline → autoconfigFromPeers → connect).
// 소켓을 여는 코드라서 시험하지 않는다. 판단이 필요한 부분은 순수 함수로 뺐다.

/// `--iface` 이름으로 IPv4 외부 주소를 고른다.
func selectInterface(
    named name: String, in interfaces: [(name: String, addresses: [NetworkInterfaceInfo])]
) -> NetworkInterfaceInfo? {
    interfaces.first { $0.name == name }?.addresses.first { $0.family == "IPv4" && !$0.internal }
}

/// 고를 수 있는 인터페이스 이름 목록(오류 안내용).
func candidateInterfaceNames(_ interfaces: [(name: String, addresses: [NetworkInterfaceInfo])]) -> [String] {
    interfaces.filter { $0.addresses.contains { $0.family == "IPv4" && !$0.internal } }.map(\.name)
}

/// 장치 기다리는 기본 시간(초).
let discoveryTimeoutSeconds = 30

/// 가상 CDJ로 참여하지 않고 소켓만 열어 장치 알림을 듣는다.
@DJLinkActor
func openListeningNetwork(options: CLICommonOptions, output: any CLIOutput) async throws -> ProlinkNetwork {
    output.log(.await, "Bringing up prolink network")
    let config = NetworkConfig(logger: CLILogger(output: output, verbose: options.verbose))
    let network = try await bringOnline(config)
    output.log(.success, "Network online (listening on UDP \(ANNOUNCE_PORT)-\(STATUS_PORT))")
    network.deviceManager.on(.connected) { device in
        output.log(.star, "New device: \(formatDevice(device))")
    }
    network.deviceManager.on(.disconnected) { device in
        output.log(.info, "Device left: \(device.name) [id: \(device.id)]")
    }
    return network
}

/// 가상 CDJ로 참여한다. `--iface`가 있으면 그 인터페이스로, 없으면 원본처럼 처음 보이는 장치로 정한다.
/// 끼어든 Ctrl-C는 false.
@DJLinkActor
func joinNetwork(
    _ network: ProlinkNetwork, options: CLICommonOptions, knownDevice: Device? = nil, output: any CLIOutput
) async throws -> Bool {
    let provider = SystemInterfaceProvider()
    if let name = options.iface {
        guard let info = selectInterface(named: name, in: provider.networkInterfaces()) else {
            let names = candidateInterfaceNames(provider.networkInterfaces())
            throw CLIRuntimeError(
                "인터페이스 \(name)에서 IPv4 주소를 찾지 못했다. 쓸 수 있는 이름: \(names.isEmpty ? "(없음)" : names.joined(separator: ", "))"
            )
        }
        network.configure(NetworkConfig(iface: info, vcdjId: options.effectiveVcdjId))
    } else if let knownDevice {
        // 이미 본 장치와 같은 서브넷의 인터페이스를 고른다(autoconfigFromPeers와 같은 방법).
        guard let match = try getMatchingInterface(knownDevice.ip, interfaceProvider: provider) else {
            throw CLIRuntimeError("장치 \(knownDevice.ip.address)와 같은 서브넷의 인터페이스를 찾지 못했다. --iface로 정한다")
        }
        network.configure(NetworkConfig(iface: match.info, vcdjId: options.effectiveVcdjId))
    } else {
        output.log(.await, "Autoconfiguring network.. waiting for devices")
        let done: Void? = try await CLIInterrupt.shared.race(
            timeoutSeconds: discoveryTimeoutSeconds,
            timeoutMessage: "\(discoveryTimeoutSeconds)초 안에 장치를 찾지 못했다. 장치가 같은 네트워크에 있는지, --iface를 줘 보라"
        ) {
            try await network.autoconfigFromPeers()
        }
        guard done != nil else { return false }
        // autoconfigFromPeers는 번호를 기본값으로 되돌리므로 줬다면 다시 건다.
        if let id = options.vcdjId { network.configure(NetworkConfig(vcdjId: id)) }
        output.log(.success, "Autoconfigure successful!")
    }
    output.log(.await, "Connecting to network!")
    try network.connect()
    guard network.isConnected() else { throw CLIRuntimeError("Failed to connect to the network") }
    if let vcdj = network.virtualDevice {
        output.log(.star, "Network connected! Joined as virtual CDJ \"\(vcdj.name)\" [id: \(vcdj.id)]")
    }
    return true
}

/// 연결을 정리하고 소켓을 닫는다.
@DJLinkActor
func shutdown(_ network: ProlinkNetwork) async {
    if network.isConnected() { _ = try? network.disconnect() }
    try? await network.close()
}

/// 장치가 보일 때까지 기다린다(없으면 오류).
@DJLinkActor
func requireDevice(_ network: ProlinkNetwork, id: Int, timeoutMs: Int = 10_000) async throws -> Device {
    guard let device = await network.deviceManager.getDeviceEnsured(id, timeout: timeoutMs) else {
        throw CLIRuntimeError("장치 \(id)가 \(timeoutMs / 1000)초 안에 보이지 않는다. `djlink devices`로 번호를 확인한다")
    }
    return device
}
