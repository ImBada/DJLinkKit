// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Bada
import DJLinkExportProtocol
import DJLinkKit
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
