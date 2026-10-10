import Darwin
import Network
import Testing

@testable import DJLinkKit

// 원본 시험 대응이 아니다. 모든 서버는 127.0.0.1에만 묶고 명시적으로 켰을 때만 소켓을 연다.
@DJLinkActor
private final class LoopbackServer {
    private var fd: Int32
    private var peer: Int32?
    let port: Int

    init(listening: Bool = true) throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw SystemCallError(syscall: "socket", errno: Darwin.errno) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let error = SystemCallError(syscall: "bind", errno: Darwin.errno)
            Darwin.close(fd)
            throw error
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0, !listening || Darwin.listen(fd, 1) == 0 else {
            let error = SystemCallError(syscall: "listen", errno: Darwin.errno)
            Darwin.close(fd)
            throw error
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        self.fd = fd
        port = Int(UInt16(bigEndian: addr.sin_port))
    }

    deinit {
        if let peer { Darwin.close(peer) }
        if fd >= 0 { Darwin.close(fd) }
    }

    func releasePort() {
        Darwin.close(fd)
        fd = -1
    }

    func accept() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            let accepted = Darwin.accept(fd, nil, nil)
            if accepted >= 0 {
                peer = accepted
                _ = fcntl(accepted, F_SETFL, fcntl(accepted, F_GETFL) | O_NONBLOCK)
                var on: Int32 = 1
                setsockopt(accepted, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                return
            }
            guard Darwin.errno == EAGAIN || Darwin.errno == EWOULDBLOCK else {
                throw SystemCallError(syscall: "accept", errno: Darwin.errno)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw TimeoutError("Loopback accept timed out")
    }

    func send(_ bytes: [UInt8]) throws {
        let peer = try #require(peer)
        let sent = bytes.withUnsafeBytes { Darwin.send(peer, $0.baseAddress, $0.count, 0) }
        guard sent == bytes.count else { throw SystemCallError(syscall: "send", errno: Darwin.errno) }
    }

    func finish() throws {
        let peer = try #require(peer)
        guard shutdown(peer, SHUT_WR) == 0 else { throw SystemCallError(syscall: "shutdown", errno: Darwin.errno) }
    }

    func waitForClientClose() async throws {
        let peer = try #require(peer)
        let deadline = ContinuousClock.now + .seconds(3)
        var byte: UInt8 = 0
        while ContinuousClock.now < deadline {
            let count = recv(peer, &byte, 1, 0)
            if count == 0 { return }
            guard count < 0, Darwin.errno == EAGAIN || Darwin.errno == EWOULDBLOCK else {
                throw SystemCallError(syscall: "recv", errno: Darwin.errno)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw TimeoutError("Loopback client close timed out")
    }
}

@Suite("LiveTCPConnectionLoopback", .enabled(if: TestProcess.loopbackTestsEnabled))
@DJLinkActor
struct LiveTCPConnectionLoopbackTests {
    private func connect(_ client: LiveTCPConnection, _ server: LoopbackServer) async throws {
        try await withTimeout(clock: SystemClock.shared, .seconds(3)) {
            try await client.connect(port: server.port, host: "127.0.0.1")
        }
        try await server.accept()
    }

    @Test("상대 FIN을 받으면 읽기와 쓰기 쪽을 닫는다")
    func remoteFIN() async throws {
        let server = try LoopbackServer()
        let client = LiveTCPConnection()
        defer { client.destroy(nil) }
        try await connect(client, server)
        #expect(client.isOpen)
        let read = Task { try await client.read(1) }
        try server.finish()
        #expect(try await withTimeout(clock: SystemClock.shared, .seconds(3)) { try await read.value } == nil)
        #expect(!client.isOpen)
        try await server.waitForClientClose()
    }

    @Test("연결 거부는 대기 상태에서도 connect 오류로 전달한다")
    func connectionRefused() async throws {
        // 서버에 할당된 포트를 해제해 SYN에 연결 거부 응답을 받는다.
        let server = try LoopbackServer(listening: false)
        server.releasePort()
        let client = LiveTCPConnection()
        defer { client.destroy(nil) }
        await #expect(throws: NWError.posix(.ECONNREFUSED)) {
            try await withTimeout(clock: SystemClock.shared, .seconds(3)) {
                try await client.connect(port: server.port, host: "127.0.0.1")
            }
        }
        #expect(!client.isOpen)
    }

    @Test("read(size)는 조각을 모으고 남은 바이트와 FIN의 짧은 읽기를 유지한다")
    func readSize() async throws {
        let server = try LoopbackServer()
        let client = LiveTCPConnection()
        defer { client.destroy(nil) }
        try await connect(client, server)
        var completed = false
        let read = Task { @DJLinkActor in
            let bytes = try await client.read(4)
            completed = true
            return bytes
        }
        try server.send([1, 2])
        try await Task.sleep(for: .milliseconds(30))
        #expect(!completed)
        try server.send([3, 4, 5])
        #expect(try await withTimeout(clock: SystemClock.shared, .seconds(3)) { try await read.value } == [1, 2, 3, 4])
        #expect(try await withTimeout(clock: SystemClock.shared, .seconds(3)) { try await client.read(nil) } == [5])
        let tail = Task { try await client.read(4) }
        try server.send([6, 7])
        try server.finish()
        #expect(try await withTimeout(clock: SystemClock.shared, .seconds(3)) { try await tail.value } == [6, 7])
        #expect(try await client.read(1) == nil)
    }

    @Test("setTimeout은 유휴 콜백을 부르고 0이면 끈다")
    func socketTimeout() async throws {
        let server = try LoopbackServer()
        let client = LiveTCPConnection()
        defer { client.destroy(nil) }
        try await connect(client, server)
        var calls = 0
        client.setTimeout(20) { calls += 1 }
        client.setTimeout(0, onTimeout: nil)
        try await Task.sleep(for: .milliseconds(40))
        #expect(calls == 0)
        try server.send([9])
        client.setTimeout(30) {
            calls += 1
            #expect(client.isOpen)
            client.destroy(TimeoutError())
        }
        await #expect(throws: TimeoutError()) {
            try await withTimeout(clock: SystemClock.shared, .seconds(3), error: { DJLinkError("watchdog") }) {
                try await client.read(4)
            }
        }
        #expect(calls == 1)
        #expect(!client.isOpen)
        #expect(try await client.read(1) == nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(try await client.read(1) == nil)
    }

    @Test("연결 객체를 해제하면 NWConnection도 취소한다")
    func releaseCancelsConnection() async throws {
        let server = try LoopbackServer()
        var client: LiveTCPConnection? = LiveTCPConnection()
        weak let released = client
        try await connect(try #require(client), server)
        client = nil
        #expect(released == nil)
        try await server.waitForClientClose()
    }

    @Test("이미 닫힌 UDP의 종료는 멈추지 않고 Node 오류로 거절한다")
    func repeatedUDPClose() async throws {
        let socket = try LiveSocketFactory.shared.createUDPSocket(reuseAddr: false)
        _ = try await socket.bind(port: 0, address: "127.0.0.1")
        try await withTimeout(clock: SystemClock.shared, .seconds(3)) { try await udpClose(socket) }
        await #expect(throws: SocketNotRunningError()) {
            try await withTimeout(clock: SystemClock.shared, .seconds(3)) { try await udpClose(socket) }
        }
    }
}
