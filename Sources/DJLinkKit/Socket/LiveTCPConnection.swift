import Foundation
import Network

@DJLinkActor
func makeLiveTCPConnection() throws -> any TCPConnection {
    try TestProcess.guardLiveSockets()
    return LiveTCPConnection()
}

/// NWConnection의 수신 조각을 모아 promise-readable의 read(size) 의미를 유지한다.
@DJLinkActor
final class LiveTCPConnection: TCPConnection {
    private var connectGuard: (@DJLinkActor () throws -> Void)?
    func setConnectGuard(_ check: @escaping @DJLinkActor () throws -> Void) throws { connectGuard = check }
    private var closeHandler: (@DJLinkActor () -> Void)?
    func setCloseHandler(_ handler: @escaping @DJLinkActor () -> Void) throws { closeHandler = handler }
    private var connection: NWConnection?
    private(set) var requiredInterfaceName: String?

    func setRequiredInterface(name: String) throws {
        guard connection == nil else { throw DJLinkError("TCP connection already started") }
        requiredInterfaceName = name
    }

    /// 인터페이스 주소를 읽는 곳. 시험이 바꿀 수 있게 둔다.
    var interfaceProvider: any InterfaceProvider = SystemInterfaceProvider()

    /// 묶을 인터페이스의 IPv4 주소. 연결할 주소와 같은 서브넷에 있는 것을 먼저 고르고, 없으면 첫 주소다.
    /// #40: `NWPathMonitor`는 기본 경로만 보여 주소가 링크 로컬뿐인 인터페이스를 찾지 못한다. 그래서 이름 대신 주소로 묶는다.
    func localAddress(interface name: String, host: String) throws -> String {
        guard let interface = interfaceProvider.networkInterfaces().first(where: { $0.name == name }) else {
            throw DJLinkError("Network interface not found: \(name)")
        }
        let addresses = interface.addresses.filter { $0.family == "IPv4" }
        let destination = try? Address4(host)
        let sameSubnet = addresses.first { info in
            guard let destination, let cidr = info.cidr, let subnet = try? Address4(cidr) else { return false }
            return destination.isInSubnet(subnet)
        }
        guard let chosen = sameSubnet ?? addresses.first else {
            throw DJLinkError("Network interface has no IPv4 address: \(name)")
        }
        return chosen.address
    }

    private var connecting: CheckedContinuation<Void, any Error>?
    private var reads: [(size: Int?, continuation: CheckedContinuation<[UInt8]?, any Error>)] = []
    private var bytes: [UInt8] = []
    private var ended = false
    private var failure: (any Error)?
    private(set) var isOpen = false
    private var timeoutMilliseconds = 0
    private var timeoutAction: (@DJLinkActor () -> Void)?
    private var timer: TimerHandle?
    private let clock: any DJLinkClock = SystemClock.shared

    deinit {
        // isolated deinit는 macOS 15.4부터 가능하다. 15.0에서도 연결 취소는 즉시 보장한다.
        connection?.cancel()
        let clock = clock
        let timer = timer
        Task { @DJLinkActor in clock.clearTimeout(timer) }
    }

    func connect(port: Int, host: String) async throws {
        guard let port = NWEndpoint.Port(rawValue: UInt16(exactly: port) ?? 0), port.rawValue != 0 else {
            throw DJLinkError("Invalid TCP port")
        }
        let parameters = NWParameters.tcp
        if let requiredInterfaceName {
            guard !ended else { throw DJLinkError("Socket closed") }
            let local = try localAddress(interface: requiredInterfaceName, host: host)
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(local), port: .any)
        }
        try connectGuard?()
        let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        connection = conn
        try await withCheckedThrowingContinuation { continuation in
            connecting = continuation
            conn.stateUpdateHandler = { [weak self] state in
                DJLinkActor.assumeIsolated {
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard !self.ended else { return }
                        // 로컬 주소만으로는 나가는 인터페이스가 보장되지 않는다. 다른 인터페이스로 붙었으면 끊는다.
                        if let name = self.requiredInterfaceName,
                           !(self.connection?.currentPath?.availableInterfaces.contains { $0.name == name } ?? false) {
                            self.destroy(DJLinkError("TCP connection is not on network interface \(name)"))
                            return
                        }
                        self.isOpen = true
                        self.connecting?.resume()
                        self.connecting = nil
                        self.refreshTimeout()
                        self.receive()
                    case let .waiting(error):
                        if self.connecting != nil { self.destroy(error) }
                    case let .failed(error):
                        if !self.ended { self.destroy(error) }
                    case .cancelled: self.finish()
                    default: break
                    }
                }
            }
            refreshTimeout()
            conn.start(queue: DJLinkActor.queue)
        }
    }
    func write(_ data: [UInt8]) async throws {
        guard isOpen, let connection else { throw failure ?? DJLinkError("write after end") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(
                content: data.data,
                completion: .contentProcessed { [weak self] error in
                    DJLinkActor.assumeIsolated {
                        if let error {
                            self?.destroy(error)
                            continuation.resume(throwing: error)
                        } else {
                            self?.refreshTimeout()
                            continuation.resume()
                        }
                    }
                })
        }
    }
    func read(_ size: Int?) async throws -> [UInt8]? {
        try await withCheckedThrowingContinuation { continuation in
            reads.append((size, continuation))
            drain()
        }
    }
    func setTimeout(_ milliseconds: Int, onTimeout: (@DJLinkActor () -> Void)?) {
        timeoutMilliseconds = milliseconds
        timeoutAction = onTimeout
        refreshTimeout()
    }
    func destroy(_ error: (any Error)?) {
        failure = error
        bytes.removeAll()
        finish()
        connection?.cancel()
    }
    private func finish() {
        isOpen = false
        ended = true
        clock.clearTimeout(timer)
        if let connecting {
            connecting.resume(throwing: failure ?? DJLinkError("Socket closed"))
            self.connecting = nil
        }
        drain()
        let handler = closeHandler
        closeHandler = nil
        handler?()
    }
    private func refreshTimeout() {
        clock.clearTimeout(timer)
        timer = nil
        if timeoutMilliseconds > 0 && !ended {
            timer = clock.setTimeout(.ms(Double(timeoutMilliseconds))) { [weak self] in
                let action = self?.timeoutAction
                self?.timeoutAction = nil
                action?()
            }
        }
    }
    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            DJLinkActor.assumeIsolated {
                guard let self, !self.ended else { return }
                if let data, !data.isEmpty {
                    self.bytes += data.bytes
                    self.refreshTimeout()
                }
                if let error {
                    self.destroy(error)
                } else if complete {
                    // Node의 기본 allowHalfOpen=false처럼 원격 FIN에서 쓰기 쪽도 닫는다.
                    self.finish()
                    self.connection?.cancel()
                } else {
                    self.drain()
                    self.receive()
                }
            }
        }
    }
    private func drain() {
        while let first = reads.first {
            if let failure {
                self.failure = nil
                reads.removeFirst().continuation.resume(throwing: failure)
                continue
            }
            let requested = first.size ?? bytes.count
            guard ended || (first.size == nil ? !bytes.isEmpty : bytes.count >= requested) else { return }
            reads.removeFirst()
            if ended && bytes.isEmpty {
                first.continuation.resume(returning: nil)
                continue
            }
            let count = min(max(0, requested), bytes.count)
            let result = Array(bytes.prefix(count))
            bytes.removeFirst(count)
            first.continuation.resume(returning: result)
        }
    }
}
