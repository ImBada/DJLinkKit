// SPDX-License-Identifier: GPL-2.0-or-later
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

/// Link Export의 실제 전송. 기존 루프백 시험 옵션과 관계없이 시험 프로세스에서는 금지한다.
@DJLinkActor
public final class LiveExportSocketFactory: ExportSocketFactory {
    public static let shared = LiveExportSocketFactory()
    public nonisolated init() {}

    private func requireLiveProcess() throws {
        if TestProcess.isRunning { throw DJLinkError("Live Link Export sockets are disabled in test processes") }
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
