/// CLI 안전을 위한 추가(기본값은 원본 동작). 원본 udpRead는 유지하고 RPC opt-in에서만 쓴다.
@DJLinkActor
private final class UDPReadWaiter {
    private let socket: any UDPSocket
    private let clock: any DJLinkClock
    private var listeners: [SocketListener] = []
    private var timer: TimerHandle?
    private var continuation: CheckedContinuation<[UInt8], any Error>?
    private var done = false

    init(socket: any UDPSocket, clock: any DJLinkClock) {
        self.socket = socket
        self.clock = clock
    }

    func finish(_ result: Result<[UInt8], any Error>) {
        guard !done else { return }
        done = true
        for listener in listeners { socket.off(listener) }
        listeners = []
        clock.clearTimeout(timer)
        timer = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    func wait(duration: Duration, waitingForRetry: Bool) async throws -> [UInt8] {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            if !waitingForRetry {
                listeners.append(socket.onceMessage { [self] message, _ in finish(.success(message)) })
            }
            listeners.append(socket.onError { [self] error in finish(.failure(error)) })
            listeners.append(socket.onClose { [self] in finish(.failure(SocketNotRunningError())) })
            timer = clock.setTimeout(duration) { [self] in
                finish(waitingForRetry ? .success([]) : .failure(TimeoutError()))
            }
        }
    }
}

/// 닫기·취소·시간 초과·수신 중 먼저 오는 것으로 끝내며 모든 구독과 타이머를 거둔다.
@DJLinkActor
public func udpReadCancellable(
    _ socket: any UDPSocket, clock: any DJLinkClock, duration: Duration, waitingForRetry: Bool = false
) async throws -> [UInt8] {
    let waiter = UDPReadWaiter(socket: socket, clock: clock)
    return try await withTaskCancellationHandler {
        try await waiter.wait(duration: duration, waitingForRetry: waitingForRetry)
    } onCancel: {
        Task { @DJLinkActor in waiter.finish(.failure(CancellationError())) }
    }
}
