import DJLinkExportModel
import DJLinkExportProtocol
import DJLinkKit
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbl-link/src/lib.rs inline 시험.
import Testing

@testable import DJLinkExport

@Suite @DJLinkActor struct LinkSourceTests {
    @Test("library_services_bind_to_the_selected_interface_address") func bind() throws {
        let interface = Interface(
            name: "link0", address: try .init("192.168.22.7"), netmask: try .init("255.255.255.0"),
            mac: [UInt8](repeating: 0, count: 6))
        #expect(service_bind_address(interface) == interface.address.description)
    }
    final class NotationSource: Source {
        let notation: KeyNotation
        init(_ notation: KeyNotation) { self.notation = notation }
        func library() -> Library? { nil }
        func key_notation() -> KeyNotation { notation }
        func share_root() -> String { "" }
        func details(_ id: String) -> TrackDetails? { nil }
    }
    @Test("link_device_settings_follow_the_catalog_key_notation") func notation() {
        for (notation, display) in [(KeyNotation.classic, KeyDisplay.classic), (.alphanumeric, .alphanumeric)] {
            let facts = Facts(NotationSource(notation))
            #expect(facts.device_settings().key_display == display)
        }
    }
}
