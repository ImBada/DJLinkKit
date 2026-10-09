import DJLinkKit
import Dispatch
import Foundation

/// Ctrl-C(SIGINT)·SIGTERM을 받아 기다리는 쪽을 깨운다. 소켓은 쓰지 않는다.
@DJLinkActor
final class CLIInterrupt {
    static let shared = CLIInterrupt()

    private(set) var triggered = false
    private var handlers: [@DJLinkActor () -> Void] = []
    private var sources: [any DispatchSourceSignal] = []

    private init() {}

    /// 신호를 가로챈다. 기본 동작(바로 종료)을 끄고 `wait`가 돌려받게 한다.
    func install() {
        guard sources.isEmpty else { return }
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { Task { @DJLinkActor in CLIInterrupt.shared.fire() } }
            source.resume()
            sources.append(source)
        }
    }

    /// 시험이나 다른 종료 경로가 같은 효과를 낼 때 부른다.
    func fire() {
        guard !triggered else { return }
        triggered = true
        let pending = handlers
        handlers = []
        for handler in pending { handler() }
    }

    /// 이미 받았으면 바로, 아니면 받을 때 한 번 부른다.
    func onInterrupt(_ handler: @escaping @DJLinkActor () -> Void) {
        if triggered {
            handler()
        } else {
            handlers.append(handler)
        }
    }

    /// 신호를 받을 때까지 기다린다(`watch` 같은 끝없는 명령).
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            onInterrupt { continuation.resume() }
        }
    }

    /// `seconds` 동안 기다린다. 먼저 신호를 받으면 true.
    func wait(seconds: Int, clock: any DJLinkClock = SystemClock.shared) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = Once()
            let timer = clock.setTimeout(.seconds(seconds)) {
                guard once.take() else { return }
                continuation.resume(returning: false)
            }
            onInterrupt {
                guard once.take() else { return }
                clock.clearTimeout(timer)
                continuation.resume(returning: true)
            }
        }
    }

    /// 작업과 신호 중 먼저 오는 쪽을 따른다. 신호가 먼저면 nil(작업은 취소하지 않고 버린다).
    /// 취소할 수 없는 대기(`autoconfigFromPeers` 등)도 Ctrl-C로 빠져나오게 하려는 것이다.
    /// `timeoutSeconds`를 주면 그 안에 끝나지 않을 때 `CLIRuntimeError`를 던진다.
    func race<T: Sendable>(
        timeoutSeconds: Int? = nil, timeoutMessage: String = "시간 안에 끝나지 않았다",
        _ operation: @escaping @DJLinkActor () async throws -> T
    ) async throws -> T? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T?, any Error>) in
            let once = Once()
            if let timeoutSeconds {
                SystemClock.shared.setTimeout(.seconds(timeoutSeconds)) {
                    if once.take() { continuation.resume(throwing: CLIRuntimeError(timeoutMessage)) }
                }
            }
            Task { @DJLinkActor in
                do {
                    let value = try await operation()
                    if once.take() { continuation.resume(returning: value) }
                } catch {
                    if once.take() { continuation.resume(throwing: error) }
                }
            }
            onInterrupt {
                if once.take() { continuation.resume(returning: nil) }
            }
        }
    }
}

/// 한 번만 true를 주는 표(`DJLinkActor` 위에서만 쓴다).
@DJLinkActor
final class Once {
    private var taken = false

    init() {}

    func take() -> Bool {
        if taken { return false }
        taken = true
        return true
    }
}

/// 실행 중 실패. 메시지는 사용자에게 그대로 보인다.
struct CLIRuntimeError: Error, Equatable, Sendable {
    var message: String

    init(_ message: String) { self.message = message }
}
