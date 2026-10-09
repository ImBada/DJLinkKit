import DJLinkKit

/// 원본 promise-readable의 크기 지정 읽기와 종료를 흉내 내는 TCP 연결.
@DJLinkActor
public final class FakeTCPConnection: TCPConnection {
    public private(set) var connectCalls: [(port: Int, host: String)] = []
    public private(set) var requiredInterfaces: [String] = []
    public var interfaceError: (any Error)?
    public func setRequiredInterface(name: String) throws {
        if let interfaceError { throw interfaceError }
        requiredInterfaces.append(name)
    }
    public private(set) var writes: [[UInt8]] = []
    public private(set) var readCalls: [Int?] = []
    public private(set) var isOpen = true
    public var onConnect: (@DJLinkActor (Int, String) throws -> Void)?
    public var onWrite: (@DJLinkActor ([UInt8]) throws -> Void)?
    public var connectError: (any Error)?
    public var writeError: (any Error)?
    private var bytes: [UInt8] = []
    private var ended = false
    private var failure: (any Error)?
    private var waiters: [(size: Int?, continuation: CheckedContinuation<[UInt8]?, any Error>)] = []
    private let clock: any DJLinkClock
    private var timer: TimerHandle?
    private var timeoutMilliseconds = 0
    private var timeoutAction: (@DJLinkActor () -> Void)?
    public init(clock: any DJLinkClock = SystemClock.shared) { self.clock = clock }
    public func connect(port: Int, host: String) async throws {
        connectCalls.append((port, host))
        if let connectError { throw connectError }
        isOpen = true
        try onConnect?(port, host)
        refreshTimeout()
    }
    public func write(_ data: [UInt8]) async throws {
        guard isOpen else { throw failure ?? DJLinkError("write after end") }
        if let writeError { throw writeError }
        writes.append(data)
        try onWrite?(data)
        refreshTimeout()
    }
    public func read(_ size: Int?) async throws -> [UInt8]? {
        readCalls.append(size)
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append((size, continuation))
            drain()
        }
    }
    public func inject(_ data: [UInt8]) {
        bytes += data
        refreshTimeout()
        drain()
    }
    public func end() {
        ended = true
        isOpen = false
        clock.clearTimeout(timer)
        drain()
    }
    public func emitTimeout() {
        let action = timeoutAction
        timeoutAction = nil
        action?()
    }
    public func setTimeout(_ milliseconds: Int, onTimeout: (@DJLinkActor () -> Void)?) {
        timeoutMilliseconds = milliseconds
        timeoutAction = onTimeout
        refreshTimeout()
    }
    public func destroy(_ error: (any Error)?) {
        failure = error
        bytes.removeAll()
        ended = true
        isOpen = false
        clock.clearTimeout(timer)
        drain()
    }
    private func refreshTimeout() {
        clock.clearTimeout(timer)
        timer = nil
        if timeoutMilliseconds > 0 && isOpen {
            timer = clock.setTimeout(.ms(Double(timeoutMilliseconds))) { [weak self] in self?.emitTimeout() }
        }
    }
    private func drain() {
        while let first = waiters.first {
            if let failure {
                self.failure = nil
                waiters.removeFirst().continuation.resume(throwing: failure)
                continue
            }
            let requested = first.size ?? bytes.count
            guard ended || (first.size == nil ? !bytes.isEmpty : bytes.count >= requested) else { return }
            waiters.removeFirst()
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
