import DJLinkExportProtocol
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbl-link/src/interface_mode.rs의 inline 시험.
import Testing

@testable import DJLinkExport

@Suite struct InterfaceModeTests {
    let SELECTED: [UInt8] = [0x10, 0xab, 0x02, 0xcd, 0x34, 0xef]
    func fixture_mode(_ services: [(Bool, String?)]?) -> ConnectionMode {
        guard let services else { return .unknown }
        return InterfaceMode.classify(
            SELECTED,
            services.lazy.map { wireless, address -> Swift.Result<[UInt8]?, InterfaceMode.ServiceError> in
                if !wireless { return .success(nil) }
                guard let address, let mac = InterfaceMode.parse_mac(address) else { return .failure(.unavailable) }
                return .success(mac)
            })
    }
    @Test("matching_ieee80211_service_is_wireless") func matching() {
        #expect(fixture_mode([(false, "10:ab:02:cd:34:ef"), (true, "10:AB:02:cD:34:ef")]) == .wireless)
    }
    @Test("successful_nonmatching_enumeration_is_wired") func nonmatching() {
        for services
            in ([[], [(false, "10:ab:02:cd:34:ef")], [(false, nil), (true, "00:11:22:33:44:55")]] as [[(Bool, String?)]])
        { #expect(fixture_mode(services) == .wired) }
    }
    @Test("unavailable_or_invalid_wireless_address_is_unknown") func unavailable() {
        #expect(fixture_mode(nil) == .unknown)
        #expect(fixture_mode([(true, nil)]) == .unknown)
        #expect(fixture_mode([(true, "invalid")]) == .unknown)
        #expect(
            InterfaceMode.classify(
                [UInt8](repeating: 0, count: 6),
                [Swift.Result<[UInt8]?, InterfaceMode.ServiceError>.failure(.unavailable)])
                == .unknown)
    }
    @Test("matching_service_returns_before_later_invalid_data") func early() {
        #expect(fixture_mode([(true, "10:ab:02:cd:34:ef"), (true, "invalid"), (true, nil)]) == .wireless)
        #expect(fixture_mode([(true, "invalid"), (true, "10:ab:02:cd:34:ef")]) == .unknown)
    }
    @Test("mac_parser_requires_six_hex_octets_and_colons") func parser() {
        #expect(InterfaceMode.parse_mac("10:AB:02:cD:34:ef") == SELECTED)
        #expect(InterfaceMode.parse_mac("00:00:00:00:00:00") == [UInt8](repeating: 0, count: 6))
        for invalid in [
            "", "10:ab:02:cd:34", "10:ab:02:cd:34:ef:00", "10-ab-02-cd-34-ef", "10:ab:02:cd:34:eg", "1:ab:02:cd:34:ef",
            " 10:ab:02:cd:34:ef", "10:ab:02:cd:34:ef ", "é0:ab:02:cd:34:ef",
        ] { #expect(InterfaceMode.parse_mac(invalid) == nil) }
    }
}
