import DJLinkKit
import Darwin
import Dispatch
import Foundation
import Synchronization

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

    private struct State {
        var reason: Reason?
        var observers: [@Sendable () -> Void] = []
    }
    private nonisolated let state = Mutex(State())
    nonisolated var reason: Reason? { state.withLock { $0.reason } }
    private var handlers: [(id: Int, handler: @DJLinkActor () -> Void)] = []
    private var nextId = 0

    nonisolated init() {}

    nonisolated var isAborted: Bool { reason != nil }

    /// 처음 부른 이유만 남는다. 걸어 둔 처리기를 한 번씩 부른다.
    func abort(_ reason: Reason) {
        guard record(reason) else { return }
        notifyHandlers()
    }

    /// 액터가 동기 작업에 묶여 있어도 즉시 중단 플래그를 세운다.
    nonisolated func requestAbort(_ reason: Reason) {
        guard record(reason) else { return }
        Task { @DJLinkActor in self.notifyHandlers() }
    }

    private nonisolated func record(_ reason: Reason) -> Bool {
        let observers: [@Sendable () -> Void]? = state.withLock { state in
            guard state.reason == nil else { return nil }
            state.reason = reason
            return state.observers
        }
        guard let observers else { return false }
        for observer in observers { observer() }
        return true
    }

    nonisolated func observeRequest(_ observer: @escaping @Sendable () -> Void) {
        let alreadyAborted = state.withLock { state in
            state.observers.append(observer)
            return state.reason != nil
        }
        if alreadyAborted { observer() }
    }

    private func notifyHandlers() {
        let pending = handlers
        handlers = []
        for entry in pending { entry.handler() }
    }

    func interrupt() { abort(.interrupted) }

    func fail(_ message: String) { abort(.failed(message)) }

    /// 부작용을 만들기 직전에 부른다. 이미 중단됐으면 던진다.
    nonisolated func check() throws {
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

/// 신호 소스를 바꿔 넣어 실제 프로세스 신호 없이 시험한다.
protocol CLISignalSource: Sendable {
    func cancel()
}

final class DispatchCLISignalSource: CLISignalSource, @unchecked Sendable {
    private let source: any DispatchSourceSignal
    private let number: Int32

    init(number: Int32, handler: @escaping @Sendable (UInt) -> Void) {
        self.number = number
        signal(number, SIG_IGN)
        source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
        let source = source
        source.setEventHandler { handler(source.data) }
        source.resume()
    }

    func cancel() {
        source.cancel()
        signal(number, SIG_DFL)
    }
}

/// 신호 큐에서 플래그를 세운다. 두 번째 신호는 액터와 무관하게 즉시 끝낸다.
/// SIGINT·SIGTERM·SIGHUP(터미널이 닫힘)은 같은 정리 경로로 가고, SIGPIPE는 무시한다(닫힌 파이프 쓰기는 오류로 돌아온다).
final class CLISignalHandler: Sendable {
    /// 정리 경로로 보내는 신호.
    static let interruptSignals: [Int32] = [SIGINT, SIGTERM, SIGHUP]
    /// 무시하는 신호.
    static let ignoredSignals: [Int32] = [SIGPIPE]

    private let sources: [any CLISignalSource]
    private let setIgnored: @Sendable (Int32, Bool) -> Void

    init(
        abort: CLIAbort,
        makeSource: (Int32, @escaping @Sendable (UInt) -> Void) -> any CLISignalSource = {
            DispatchCLISignalSource(number: $0, handler: $1)
        },
        setIgnored: @escaping @Sendable (Int32, Bool) -> Void = { signal($0, $1 ? SIG_IGN : SIG_DFL) },
        terminate: @escaping @Sendable (Int32) -> Void = { _exit($0) }
    ) {
        self.setIgnored = setIgnored
        for number in Self.ignoredSignals { setIgnored(number, true) }
        let count = Mutex<UInt>(0)
        sources = Self.interruptSignals.map { number in
            makeSource(number) { events in
                let total = count.withLock { count in
                    count += max(1, events)
                    return count
                }
                abort.requestAbort(.interrupted)
                if total >= 2 { terminate(CLIExitCode.interrupted) }
            }
        }
    }

    func remove() {
        for source in sources { source.cancel() }
        for number in Self.ignoredSignals { setIgnored(number, false) }
    }
}
