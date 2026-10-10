import Foundation

/// 실제 소켓을 만드는 곳. 상태를 가진 형은 이것을 주입받는다(원본의 `dgram.createSocket`·`new net.Socket()`).
@DJLinkActor
public protocol SocketFactory: AnyObject, Sendable {
    /// `dgram.createSocket({type: 'udp4', reuseAddr})`
    func createUDPSocket(reuseAddr: Bool) throws -> any UDPSocket

    /// `new PromiseSocket(new net.Socket())`
    func createTCPConnection() throws -> any TCPConnection
}

/// 실제 소켓을 만드는 구현. 시험 프로세스에서는 바로 실패한다(docs/PLAN.md §11).
/// 루프백 통합 시험만 `DJLINK_LOOPBACK_TESTS=1`일 때 쓸 수 있다.
@DJLinkActor
public final class LiveSocketFactory: SocketFactory {
    public static let shared = LiveSocketFactory()

    public nonisolated init() {}

    public func createUDPSocket(reuseAddr: Bool) throws -> any UDPSocket {
        try TestProcess.guardLiveSockets()
        return try BSDUDPSocket(reuseAddr: reuseAddr)
    }

    public func createTCPConnection() throws -> any TCPConnection {
        try TestProcess.guardLiveSockets()
        return try makeLiveTCPConnection()
    }
}

/// 시험 프로세스를 알아본다.
public enum TestProcess {
    /// 지금 프로세스가 XCTest·swift-testing 시험 프로세스인가.
    public static let isRunning: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
        {
            return true
        }
        let process = ProcessInfo.processInfo.processName
        if process == "xctest" || process.hasSuffix("PackageTests") || process == "swiftpm-testing-helper" {
            return true
        }
        if let executable = ProcessInfo.processInfo.arguments.first,
           executable.contains(".xctest") || executable.hasSuffix("swiftpm-testing-helper")
        {
            return true
        }
        return NSClassFromString("XCTestCase") != nil
    }()

    /// 루프백 통합 시험을 켰는가.
    public static var loopbackTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["DJLINK_LOOPBACK_TESTS"] == "1"
    }

    static func guardLiveSockets() throws {
        if isRunning, !loopbackTestsEnabled {
            throw DJLinkError("Live sockets are disabled in test processes (set DJLINK_LOOPBACK_TESTS=1 for loopback tests)")
        }
    }
}
