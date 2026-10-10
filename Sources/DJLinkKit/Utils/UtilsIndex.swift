// 원본 src/utils/index.ts

/// Get the byte representation of the device name
///
/// 원본은 이름이 20바이트를 넘으면 `Uint8Array.set`이 RangeError("offset is out of bounds")를 던진다.
/// 이름은 설정(vcdjName)에서 오므로 멈추지 않고 같은 오류를 던진다.
public func buildName(_ device: Device) throws(BufferRangeError) -> [UInt8] {
    var name = [UInt8].alloc(20)
    let bytes = [UInt8](device.name, encoding: .ascii)
    guard bytes.count <= name.count else {
        throw BufferRangeError("offset is out of bounds")
    }
    name.set(bytes)

    return name
}

/// Determines the interface that routes the given address by comparing the
/// masked addresses. This type of information is generally determined through
/// the kernels routing table, but for sake of cross-platform compatibility, we
/// do some rudimentary lookup.
///
/// 원본의 `os.networkInterfaces()`는 `interfaceProvider`로 주입받는다.
/// `new ip.Address4(cidr)`가 틀린 CIDR에 던지는 것도 그대로 던진다.
public func getMatchingInterface(
    _ ipAddr: Address4,
    interfaceProvider: any InterfaceProvider = SystemInterfaceProvider()
) throws -> NamedNetworkInterface? {
    let flatList = interfaceProvider.networkInterfaces().flatMap { entry in
        entry.addresses.map { NamedNetworkInterface(name: entry.name, info: $0) }
    }

    var matchedIface: NamedNetworkInterface?
    var matchedSubnet = 0

    for iface in flatList {
        let info = iface.info

        guard info.family == "IPv4", !info.internal, let cidr = info.cidr else {
            continue
        }

        let ifaceAddr = try Address4(cidr)

        if ipAddr.isInSubnet(ifaceAddr) && ifaceAddr.subnetMask > matchedSubnet {
            matchedIface = iface
            matchedSubnet = ifaceAddr.subnetMask
        }
    }

    return matchedIface
}

/// Computes the IPv4 subnet broadcast address for a network interface.
///
/// Builds the address from the interface CIDR so the broadcast covers the whole
/// subnet (e.g. x.x.x.255 for a /24). Falls back to the bare interface address
/// when no CIDR is available, which only reaches the host itself but avoids
/// throwing.
public func getBroadcastAddress(_ iface: NetworkInterfaceInfo) throws -> String {
    try Address4(iface.cidr ?? iface.address).endAddress().address
}

/// Given a BPM and pitch value, compute how many seconds per beat
public func bpmToSeconds(_ bpm: Double, _ pitch: Double) -> Double {
    let bps = ((pitch / 100) * bpm + bpm) / 60
    return 1 / bps
}

/// Returns a string representation of a media slot
///
/// 원본 표는 enum 키 이름을 소문자로 바꾼 것이다. 모르는 값이면 원본처럼 undefined(nil).
public func getSlotName(_ slot: MediaSlot) -> String? {
    slot.jsName?.lowercased()
}

/// Returns a string representation of a track type
///
/// 원본 표는 enum 키 이름을 소문자로 바꾼 것이다. 모르는 값이면 원본처럼 undefined(nil).
public func getTrackTypeName(_ type: TrackType) -> String? {
    type.jsName?.lowercased()
}
