import DJLinkExportProtocol
// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbxport/crates/rbl-link/src/interface_mode.rs (90bfb53).
import Foundation
import SystemConfiguration

enum InterfaceMode {
    enum ServiceError: Error { case unavailable }
    static func classify<S: Sequence>(_ selected: [UInt8], _ services: S) -> ConnectionMode
    where S.Element == Swift.Result<[UInt8]?, ServiceError> {
        for service in services {
            switch service {
            case let .success(mac) where mac == selected: return .wireless
            case .success: break
            case .failure: return .unknown
            }
        }
        return .wired
    }
    static func parse_mac(_ address: String) -> [UInt8]? {
        let bytes = Array(address.utf8)
        guard bytes.count == 17 else { return nil }
        func hex_digit(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: return byte - 48
            case 97...102: return byte - 97 + 10
            case 65...70: return byte - 65 + 10
            default: return nil
            }
        }
        var mac = [UInt8]()
        for index in 0..<6 {
            let offset = index * 3
            guard (index == 5 || bytes[offset + 2] == 58), let hi = hex_digit(bytes[offset]),
                let lo = hex_digit(bytes[offset + 1])
            else { return nil }
            mac.append(hi << 4 | lo)
        }
        return mac
    }
    static func selected(_ mac: [UInt8]) -> ConnectionMode {
        guard let preferences = SCPreferencesCreate(nil, "rbxport LINK interface mode" as CFString, nil),
            let set = SCNetworkSetCopyCurrent(preferences),
            let services = SCNetworkSetCopyServices(set) as? [SCNetworkService]
        else { return .unknown }
        // 원본처럼 일치하는 서비스를 찾으면 뒤의 잘못된 데이터는 읽지 않는다.
        for service in services {
            guard let interface = SCNetworkServiceGetInterface(service),
                let type = SCNetworkInterfaceGetInterfaceType(interface)
            else { return .unknown }
            guard CFEqual(type, kSCNetworkInterfaceTypeIEEE80211) else { continue }
            guard let address = SCNetworkInterfaceGetHardwareAddressString(interface),
                let parsed = parse_mac(address as String), (address as String).canBeConverted(to: .ascii)
            else { return .unknown }
            if parsed == mac { return .wireless }
        }
        return .wired
    }
}
func connection_mode_for(mac: [UInt8]) -> ConnectionMode { InterfaceMode.selected(mac) }
