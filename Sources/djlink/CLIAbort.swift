import DJLinkKit
import Dispatch
import Foundation

// 중단 토큰. Ctrl-C·SIGTERM, 제한 시간 초과, 번호 거부 같은 "여기서 끝낸다"를 한 곳에 모은다.
// 부작용(참여·송신·파일 쓰기·NFS 요청)은 만들기 직전에 `check()`로 확인한다.

/// 중단된 뒤에 부작용을 만들려 했다.
struct CLIAborted: Error, Equatable, Sendable, CustomStringConvertible {
    var description: String { "중단되었다" }
}

/// 실행 중 실패. 메시지는 사용자에게 그대로 보인다.
struct CLIRuntimeError: Error, Equatable, Sendable {
    var message: String

    init(_ message: String) { self.message = message }
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

@DJLinkActor
final class CLIAbort {
    enum Reason: Equatable, Sendable {
        /// Ctrl-C·SIGTERM. 종료 코드 130.
        case interrupted
        /// 실패로 끝낸다. 메시지는 사용자에게 보이고 종료 코드는 1.
        case failed(String)
    }

    private(set) var reason: Reason?
    private var handlers: [(id: Int, handler: @DJLinkActor () -> Void)] = []
    private var nextId = 0

    init() {}

    var isAborted: Bool { reason != nil }

    /// 처음 부른 이유만 남는다. 걸어 둔 처리기를 한 번씩 부른다.
    func abort(_ reason: Reason) {
        guard self.reason == nil else { return }
        self.reason = reason
        let pending = handlers
        handlers = []
        for entry in pending { entry.handler() }
    }

    func interrupt() { abort(.interrupted) }

    func fail(_ message: String) { abort(.failed(message)) }

    /// 부작용을 만들기 직전에 부른다. 이미 중단됐으면 던진다.
    func check() throws {
        if isAborted { throw CLIAborted() }
    }

    /// 중단될 때 한 번 부른다. 이미 중단됐으면 바로 부르고 nil을 돌려준다.
    @discardableResult
    func onAbort(_ handler: @escaping @DJLinkActor () -> Void) -> Int? {
        if isAborted {
            handler()
            return nil
        }
        nextId += 1
        handlers.append((nextId, handler))
        return nextId
    }

    func removeHandler(_ id: Int?) {
        guard let id else { return }
        handlers.removeAll { $0.id == id }
    }

    /// 중단될 때까지 기다린다(`watch` 같은 끝없는 명령).
    func wait() async {
        let waiter = CLIWaiter<Void>()
        _ = try? await waiter.wait { waiter in
            let id = self.onAbort { waiter.finish(.success(())) }
            waiter.onFinish { self.removeHandler(id) }
        }
    }

    /// `seconds` 동안 기다린다. 먼저 중단되면 true.
    func wait(seconds: Int, clock: any DJLinkClock) async -> Bool {
        let waiter = CLIWaiter<Bool>()
        let result = try? await waiter.wait { waiter in
            let timer = clock.setTimeout(.seconds(seconds)) { waiter.finish(.success(false)) }
            waiter.onFinish { clock.clearTimer(timer) }
            let id = self.onAbort { waiter.finish(.success(true)) }
            waiter.onFinish { self.removeHandler(id) }
        }
        return result ?? true
    }
}

/// 여러 원인 중 먼저 오는 것으로 한 번만 끝나는 기다림. 끝날 때 걸어 둔 구독·타이머를 모두 거둔다.
@DJLinkActor
final class CLIWaiter<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private var cleanups: [@DJLinkActor () -> Void] = []
    private var done = false

    init() {}

    /// 끝날 때 한 번 부른다. 이미 끝났으면 바로 부른다.
    func onFinish(_ cleanup: @escaping @DJLinkActor () -> Void) {
        if done {
            cleanup()
        } else {
            cleanups.append(cleanup)
        }
    }

    func finish(_ result: Result<Value, any Error>) {
        guard !done else { return }
        done = true
        let pending = cleanups
        cleanups = []
        for cleanup in pending { cleanup() }
        continuation?.resume(with: result)
        continuation = nil
    }

    /// `setup`에서 원인(구독·타이머·중단 처리기)을 건다. `setup` 안에서 바로 `finish`해도 된다.
    func wait(_ setup: (CLIWaiter<Value>) -> Void) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
            self.continuation = continuation
            setup(self)
        }
    }
}

/// SIGINT·SIGTERM을 받아 토큰을 중단한다. 두 번째 신호는 정리가 멈춘 것으로 보고 바로 끝낸다.
final class CLISignalHandler {
    private var sources: [any DispatchSourceSignal] = []

    init(abort: CLIAbort) {
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                Task { @DJLinkActor in
                    if abort.isAborted {
                        exit(CLIExitCode.interrupted)
                    } else {
                        abort.interrupt()
                    }
                }
            }
            source.resume()
            sources.append(source)
        }
    }

    /// 신호 처리를 원래대로 돌린다.
    func remove() {
        for source in sources { source.cancel() }
        sources = []
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)
    }
}
