import Darwin
import Foundation

/// Node `os.NetworkInterfaceInfo`
public struct NetworkInterfaceInfo: Equatable, Hashable, Sendable {
    public var address: String
    public var netmask: String
    /// "IPv4" 또는 "IPv6"
    public var family: String
    /// "00:11:22:33:44:55"
    public var mac: String
    public var `internal`: Bool
    /// "192.168.1.10/24". 모르면 nil.
    public var cidr: String?
    /// IPv6에만 있다.
    public var scopeid: Int?

    public init(
        address: String,
        netmask: String,
        family: String,
        mac: String,
        internal: Bool,
        cidr: String?,
        scopeid: Int? = nil
    ) {
        self.address = address
        self.netmask = netmask
        self.family = family
        self.mac = mac
        self.internal = `internal`
        self.cidr = cidr
        self.scopeid = scopeid
    }
}

/// 원본에서 `{...iface, name}`처럼 이름을 붙여 넘기는 인터페이스.
public struct NamedNetworkInterface: Equatable, Hashable, Sendable {
    public var name: String
    public var info: NetworkInterfaceInfo

    public init(name: String, info: NetworkInterfaceInfo) {
        self.name = name
        self.info = info
    }
}

/// Node `os.networkInterfaces()`. 원본은 객체 키 순서(커널이 준 순서)에 기대므로 순서 있는 목록으로 준다.
public protocol InterfaceProvider: Sendable {
    func networkInterfaces() -> [(name: String, addresses: [NetworkInterfaceInfo])]
}

/// `getifaddrs`로 읽는 실제 구현.
public struct SystemInterfaceProvider: InterfaceProvider {
    public init() {}

    public func networkInterfaces() -> [(name: String, addresses: [NetworkInterfaceInfo])] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var macs: [String: String] = [:]
        var order: [String] = []
        var entries: [String: [NetworkInterfaceInfo]] = [:]

        // 먼저 AF_LINK에서 MAC을 모은다.
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl in
                let nlen = Int(dl.pointee.sdl_nlen)
                let alen = Int(dl.pointee.sdl_alen)
                guard alen == 6 else { return }
                // sdl_data는 이름 뒤에 주소가 온다. 구조체 크기를 넘을 수 있어 원래 포인터로 읽는다.
                let base = UnsafeRawPointer(dl).advanced(by: MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data)!)
                let bytes = (0..<alen).map { base.load(fromByteOffset: nlen + $0, as: UInt8.self) }
                macs[name] = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
            }
        }

        cursor = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr else { continue }
            let family = Int32(addr.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            let flags = Int32(ifa.pointee.ifa_flags)
            guard flags & IFF_UP != 0 else { continue }

            let address = Self.numericHost(addr)
            let netmask = ifa.pointee.ifa_netmask.map(Self.numericHost) ?? ""
            let prefix = ifa.pointee.ifa_netmask.map { Self.prefixLength($0, family: family) }
            var info = NetworkInterfaceInfo(
                address: address,
                netmask: netmask,
                family: family == AF_INET ? "IPv4" : "IPv6",
                mac: macs[name] ?? "00:00:00:00:00:00",
                internal: flags & IFF_LOOPBACK != 0,
                cidr: prefix.map { "\(address)/\($0)" }
            )
            if family == AF_INET6 {
                addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    info.scopeid = Int($0.pointee.sin6_scope_id)
                }
            }
            if entries[name] == nil { order.append(name) }
            entries[name, default: []].append(info)
        }

        return order.map { ($0, entries[$0] ?? []) }
    }

    private static func numericHost(_ addr: UnsafeMutablePointer<sockaddr>) -> String {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(addr.pointee.sa_family == UInt8(AF_INET6)
            ? MemoryLayout<sockaddr_in6>.size : MemoryLayout<sockaddr_in>.size)
        guard getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return ""
        }
        let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        // IPv6 링크 로컬의 %en0 같은 꼬리는 Node처럼 뺀다.
        return text.split(separator: "%").first.map(String.init) ?? text
    }

    private static func prefixLength(_ mask: UnsafeMutablePointer<sockaddr>, family: Int32) -> Int {
        if family == AF_INET {
            return mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr).nonzeroBitCount
            }
        }
        return mask.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
            withUnsafeBytes(of: pointer.pointee.sin6_addr) { raw in
                raw.reduce(0) { $0 + $1.nonzeroBitCount }
            }
        }
    }
}
