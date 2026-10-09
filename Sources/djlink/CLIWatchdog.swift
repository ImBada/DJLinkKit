import Darwin
import Dispatch
import Foundation
import Synchronization

/// DJLinkActor와 독립된 감시 시계. 취소 함수는 타이머를 거둔다.
protocol CLIIndependentScheduler: Sendable {
    func schedule(seconds: Int, _ action: @escaping @Sendable () -> Void) -> @Sendable () -> Void
}

struct DispatchCLIScheduler: CLIIndependentScheduler {
    func schedule(seconds: Int, _ action: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + .seconds(seconds))
        timer.setEventHandler(handler: action)
        timer.resume()
        return { timer.cancel() }
    }
}

/// 동기 PDB 해석·파일 시스템 호출이 멈춰도 중단 후 3초 안에 프로세스를 끝낸다.
final class CLIWatchdog: Sendable {
    /// 중단한 뒤 정리를 기다리는 시간(초). 넘으면 프로세스를 강제로 끝낸다.
    static let defaultGraceSeconds = 3

    private struct State {
        var completed = false
        var cancellations: [@Sendable () -> Void] = []
    }
    private let state = Mutex(State())
    private let scheduler: any CLIIndependentScheduler
    private let abort: CLIAbort
    private let terminate: @Sendable (Int32) -> Void
    private let graceSeconds: Int

    init(
        abort: CLIAbort, scheduler: any CLIIndependentScheduler, graceSeconds: Int = CLIWatchdog.defaultGraceSeconds,
        terminate: @escaping @Sendable (Int32) -> Void = { _exit($0) }
    ) {
        self.abort = abort
        self.scheduler = scheduler
        self.graceSeconds = graceSeconds
        self.terminate = terminate
        abort.observeRequest { [weak self] in self?.armGracePeriod() }
    }

    private func track(_ cancellation: @escaping @Sendable () -> Void) {
        let completed = state.withLock { state in
            if state.completed { return true }
            state.cancellations.append(cancellation)
            return false
        }
        if completed { cancellation() }
    }

    func setDeadline(seconds: Int) {
        track(
            scheduler.schedule(seconds: seconds) { [weak self] in
                guard let self, !self.state.withLock({ $0.completed }) else { return }
                self.abort.requestAbort(.failed("제한 시간 \(seconds)초를 넘었다(--timeout으로 바꾼다)"))
            })
    }

    private func armGracePeriod() {
        track(
            scheduler.schedule(seconds: graceSeconds) { [weak self] in
                guard let self, !self.state.withLock({ $0.completed }) else { return }
                self.terminate(self.abort.reason == .interrupted ? CLIExitCode.interrupted : CLIExitCode.failure)
            })
    }

    func complete() {
        let cancellations = state.withLock { state in
            state.completed = true
            let cancellations = state.cancellations
            state.cancellations = []
            return cancellations
        }
        for cancel in cancellations { cancel() }
    }
}
