// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Bada
import DJLinkExportProtocol
import DJLinkExportSupport
import DJLinkExportTestSupport
import DJLinkKit
import DJLinkTestSupport
import Foundation
import Testing

@testable import DJLinkExport

/// PLAN §9: 콜백 없이 보내면 실제 소켓(`DualStackUDPSocket`)은 보내기 실패를 소켓 오류로 올린다. 그러면 비컨의 알림·상태 고리가
/// 멈춘다(2026-10-16 실기: 상태 송신이 첫 패킷 뒤 멈추고 CDJ-2000nexus의 LINK 화면에 Mac이 보이지 않았다).
@Suite @DJLinkActor struct BeaconUpstreamFixTests {
    @Test("a_failed_send_is_dropped_instead_of_raised_as_a_socket_error")
    func a_failed_send_is_dropped_instead_of_raised_as_a_socket_error() throws {
        let socket = FailingUDPSocket()
        var errors = 0
        socket.onError { _ in errors += 1 }
        send(socket, [1, 2, 3], LinkAddress(127, 0, 0, 1), 50002)
        #expect(socket.sends == 1)
        #expect(errors == 0)
    }
}

/// PLAN §9: 앱이 띄우기 전에 들은 장치 알림을 넣으면 CDJ의 다음 알림(약 2초 간격)을 기다리지 않고 바로 번호 받기를 시작한다.
/// 2026-10-16 캡처: rekordbox·DJCrate 모두 첫 번호 요청을 CDJ 알림 직후에 보내, 누른 뒤 평균 1초쯤을 알림 기다리기에 썼다.
@Suite @DJLinkActor struct BeaconSeedTests {
    static let keepAlive =
        "5173707431576d4a4f4c060043444a2d333030300000000000000000000000000103003601012497ed0b4043c0a80198030000000164"

    @Test("a_seeded_keep_alive_starts_the_join_without_waiting_for_the_next_one")
    func a_seeded_keep_alive_starts_the_join_without_waiting_for_the_next_one() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 0))
        let factory = FakeExportSocketFactory(clock: clock)
        let config = BeaconConfig(
            interface: nil, address: LinkAddress(127, 0, 0, 2), netmask: LinkAddress(255, 0, 0, 0), broadcast: .localhost,
            mac: [0, 0xe0, 0x4c, 0xcf, 0x63, 0x2e], mode: .wired, announce_port: 0, status_port: 0, player_port: 50002,
            beat_port: 50001, computer_name: "test-mac")
        let beacon = try await Beacon.start(config, SeedFacts(), socketFactory: factory, clock: clock,
                                            interfaceProvider: FakeInterfaceProvider([]))
        // 알림을 넣지 않으면 기다리기만 한다
        clock.advance(ms: 1000)
        #expect(beacon.link_state() == .waiting)
        let bytes = stride(from: 0, to: Self.keepAlive.count, by: 2).map { offset -> UInt8 in
            let start = Self.keepAlive.index(Self.keepAlive.startIndex, offsetBy: offset)
            return UInt8(Self.keepAlive[start..<Self.keepAlive.index(start, offsetBy: 2)], radix: 16)!
        }
        beacon.hear_seed(bytes, from: "127.0.0.1")
        for _ in 0..<200 where beacon.link_state() != .up(number: 17) { clock.advance(ms: 50) }
        #expect(beacon.link_state() == .up(number: 17))
        beacon.stop()
    }
}

@DJLinkActor private final class SeedFacts: LibraryFacts {
    func track_count() -> UInt16 { 1 }
    func playlist_count() -> UInt16 { 0 }
    func track_loaded(_ track: UInt32) {}
}

/// 보내기가 늘 실패하는 소켓. 실제 소켓처럼 콜백이 없으면 실패를 오류 처리기로 올린다
@DJLinkActor private final class FailingUDPSocket: UDPSocket {
    var sends = 0
    private var errorHandlers: [@DJLinkActor (any Error) -> Void] = []

    func onMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        SocketListener(id: 0)
    }
    func onceMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        SocketListener(id: 0)
    }
    @discardableResult func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) -> SocketListener {
        errorHandlers.append(handler)
        return SocketListener(id: 0)
    }
    func onClose(_ handler: @escaping @DJLinkActor () -> Void) -> SocketListener { SocketListener(id: 0) }
    func off(_ listener: SocketListener) {}
    func removeAllListeners() { errorHandlers = [] }
    func bind(port: Int?, address: String?) async throws -> AddressInfo { AddressInfo(address: "127.0.0.1", port: 0) }
    func send(_ msg: [UInt8], port: Int, address: String, callback: (@DJLinkActor ((any Error)?, Int) -> Void)?) {
        sends += 1
        let error = DJLinkError("sendto: No route to host")
        if let callback { callback(error, 0) } else { for handler in errorHandlers { handler(error) } }
    }
    func setBroadcast(_ flag: Bool) {}
    func address() -> AddressInfo? { nil }
    func close(_ callback: (@DJLinkActor () -> Void)?) throws {}
}
