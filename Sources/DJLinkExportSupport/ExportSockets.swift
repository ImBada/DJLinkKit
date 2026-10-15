// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// rbxport Link Export 포트를 위한 전송 경계. 기존 MIT 클라이언트 소켓 API를 재사용한다.
import DJLinkKit

/// 서버가 받아들이는 TCP 연결. 시험은 가짜 연결을 주입하며 실제 listen을 하지 않는다.
@DJLinkActor
public protocol TCPListener: AnyObject {
    @discardableResult
    func bind(port: Int, address: String) async throws -> AddressInfo
    @discardableResult
    func onConnection(
        _ handler: @escaping @DJLinkActor (any TCPConnection, RemoteInfo) -> Void
    ) -> SocketListener
    func off(_ listener: SocketListener)
    func address() -> AddressInfo?
    func close() throws
    func shutdown() async throws
}

extension TCPListener {
    public func shutdown() async throws {
        try close()
        await Task.yield()
    }
}

@DJLinkActor
public protocol ExportSocketFactory: SocketFactory {
    func createTCPListener() throws -> any TCPListener
}

/// Rust TCP 서버가 설정하는 연결 옵션. 클라이언트 API와 분리해 받아들인 연결에만 적용한다.
@DJLinkActor
public protocol ServerTCPConnection: TCPConnection {
    func configureServer(keepaliveAfter: Int, keepaliveInterval: Int, noDelay: Bool) throws
}

@DJLinkActor
public protocol ServerUDPSocket: UDPSocket {
    func setBroadcastChecked(_ enabled: Bool) throws
    func shutdown() async throws
}
extension ServerUDPSocket {
    public func shutdown() async throws {
        do { try await udpClose(self) } catch is SocketNotRunningError {}
    }
}

/// 시험 프로세스에서 Link Export 실제 소켓을 쓸 수 있는지 정한다.
/// 기본은 금지다. `DJLINK_LOOPBACK_TESTS=1`일 때만 허용하고, 그때도 루프백 주소에만 묶는다(LAN에 보내지 않는다).
public enum ExportLiveSocketGuard {
    static let loopbackHosts: Set<String> = ["127.0.0.1", "::1"]

    public static func requireLiveOrLoopbackProcess() throws {
        if TestProcess.isRunning, !TestProcess.loopbackTestsEnabled {
            throw DJLinkError(
                "Live Link Export sockets are disabled in test processes (set DJLINK_LOOPBACK_TESTS=1 for loopback tests)"
            )
        }
    }

    public static func requireLoopbackBindInTests(_ host: String) throws {
        if TestProcess.isRunning, !loopbackHosts.contains(host) {
            throw DJLinkError("Link Export loopback tests may bind only 127.0.0.1 or ::1 (got \(host))")
        }
    }
}

/// Link Export의 실제 전송. 시험 프로세스에서는 루프백 시험(`DJLINK_LOOPBACK_TESTS=1`)일 때만 쓸 수 있다.
@DJLinkActor
public final class LiveExportSocketFactory: ExportSocketFactory {
    public static let shared = LiveExportSocketFactory()
    public nonisolated init() {}

    private func requireLiveProcess() throws {
        try ExportLiveSocketGuard.requireLiveOrLoopbackProcess()
    }

    public func createUDPSocket(reuseAddr: Bool) throws -> any UDPSocket {
        try requireLiveProcess()
        return try DualStackUDPSocket(reuseAddr: reuseAddr)
    }

    public func createTCPConnection() throws -> any TCPConnection {
        try requireLiveProcess()
        return try LiveSocketFactory.shared.createTCPConnection()
    }

    public func createTCPListener() throws -> any TCPListener {
        try requireLiveProcess()
        return try BSDTCPListener()
    }
}
