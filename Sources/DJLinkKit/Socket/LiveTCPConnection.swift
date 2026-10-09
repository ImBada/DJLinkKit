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

    /// 인터페이스 이름을 찾는 동안의 대기. `destroy`가 바로 풀 수 있게 들고 있는다.
    private struct InterfaceResolution {
        var continuation: CheckedContinuation<NWInterface, any Error>
        var monitor: NWPathMonitor
        var timer: TimerHandle?
    }
    private var resolution: InterfaceResolution?
    /// 인터페이스 해석을 기다리는 중인가(시험용).
    var isResolvingInterface: Bool { resolution != nil }
    /// 시험이 경로 감시를 시작하지 않고 대기 상태만 만들 때 끈다. 기본은 원본처럼 감시한다.
    var startsPathMonitor = true

    private func resolveInterface(_ name: String) async throws -> NWInterface {
        guard !ended else { throw DJLinkError("Socket closed") }
        let monitor = NWPathMonitor()
        return try await withCheckedThrowingContinuation { continuation in
            let timer = clock.setTimeout(.seconds(3)) { [self] in
                finishResolving(.failure(DJLinkError("Network interface not found: \(name)")))
            }
            resolution = InterfaceResolution(continuation: continuation, monitor: monitor, timer: timer)
            monitor.pathUpdateHandler = { path in
                DJLinkActor.assumeIsolated {
                    if let interface = path.availableInterfaces.first(where: { $0.name == name }) {
                        self.finishResolving(.success(interface))
                    } else {
                        self.finishResolving(.failure(DJLinkError("Network interface not found: \(name)")))
                    }
                }
            }
            if startsPathMonitor { monitor.start(queue: DJLinkActor.queue) }
        }
    }

    /// 인터페이스 해석 대기를 한 번만 끝낸다. 타이머와 감시를 거둔다.
    private func finishResolving(_ result: Result<NWInterface, any Error>) {
        guard let pending = resolution else { return }
        resolution = nil
        clock.clearTimeout(pending.timer)
        pending.monitor.cancel()
        pending.continuation.resume(with: result)
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
            parameters.requiredInterface = try await resolveInterface(requiredInterfaceName)
            guard !ended else { throw DJLinkError("Socket closed") }
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
        // CLI 안전을 위한 추가: 인터페이스를 찾는 중이면 destroy가 3초를 기다리지 않고 바로 푼다.
        finishResolving(.failure(failure ?? DJLinkError("Socket closed")))
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
