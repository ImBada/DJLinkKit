// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Bada
// 원본 밖 회귀: 시험 프로세스의 Link Export 실제 소켓 가드(#28). 실제 소켓은 루프백 시험에서만, 루프백 주소에만 연다.
import DJLinkExportSupport
import DJLinkKit
import Testing

@Suite("Link Export 실제 소켓 가드")
@DJLinkActor
struct ExportSocketGuardTests {
    @Test("루프백 시험이 아니면 시험 프로세스에서 실제 소켓을 만들지 않는다", .enabled(if: !TestProcess.loopbackTestsEnabled))
    func refusesOutsideLoopbackMode() {
        #expect(throws: DJLinkError.self) { _ = try LiveExportSocketFactory.shared.createUDPSocket(reuseAddr: true) }
        #expect(throws: DJLinkError.self) { _ = try LiveExportSocketFactory.shared.createTCPListener() }
        #expect(throws: DJLinkError.self) { _ = try LiveExportSocketFactory.shared.createTCPConnection() }
    }

    @Test("루프백 시험에서도 루프백 밖 주소에는 묶지 않는다", .enabled(if: TestProcess.loopbackTestsEnabled))
    func refusesNonLoopbackBind() async throws {
        let udp = try LiveExportSocketFactory.shared.createUDPSocket(reuseAddr: true)
        await #expect(throws: DJLinkError.self) { _ = try await udp.bind(port: 0, address: "0.0.0.0") }
        let tcp = try LiveExportSocketFactory.shared.createTCPListener()
        await #expect(throws: DJLinkError.self) { _ = try await tcp.bind(port: 0, address: "0.0.0.0") }
    }
}
