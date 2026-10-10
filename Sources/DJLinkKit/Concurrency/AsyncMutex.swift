/// 원본 `async-mutex`의 `Mutex`. 기다리는 순서대로(FIFO) 넘긴다.
///
/// 모든 상태가 `DJLinkActor`에 있어도 `await` 사이에서는 다른 작업이 끼어든다.
/// 원본이 `runExclusive`로 막는 곳은 이것으로 똑같이 막는다.
@DJLinkActor
public final class AsyncMutex {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public nonisolated init() {}

    /// `mutex.isLocked()`
    public var isLocked: Bool { locked }

    /// `mutex.acquire()`
    public func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// `release()`. 기다리는 쪽이 있으면 잠근 채로 넘긴다.
    public func release() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// `mutex.runExclusive(fn)`
    public func runExclusive<T>(_ body: @DJLinkActor () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }
}

/// `promise-timeout`의 `TimeoutError`(문구 "Timeout").
public struct TimeoutError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String = "Timeout") {
        self.message = message
    }

    public var description: String { message }
}

/// `promise-timeout`의 `timeout(promise, ms)`. 먼저 끝나는 쪽을 돌려준다.
/// 시간이 먼저 되면 `error`(기본 `TimeoutError()`)를 던진다. 원본 Promise처럼 진 작업은 멈추지 않고 끝까지 돈다.
@DJLinkActor
public func withTimeout<T: Sendable>(
    clock: any DJLinkClock,
    _ duration: Duration,
    error makeError: @escaping @DJLinkActor () -> any Error = { TimeoutError() },
    _ operation: @escaping @DJLinkActor () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
        var settled = false
        let timer = clock.setTimeout(duration) {
            guard !settled else { return }
            settled = true
            continuation.resume(throwing: makeError())
        }
        Task { @DJLinkActor in
            do {
                let value = try await operation()
                guard !settled else { return }
                settled = true
                clock.clearTimeout(timer)
                continuation.resume(returning: value)
            } catch {
                guard !settled else { return }
                settled = true
                clock.clearTimeout(timer)
                continuation.resume(throwing: error)
            }
        }
    }
}
