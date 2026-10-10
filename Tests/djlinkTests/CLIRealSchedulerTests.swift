import DJLinkKit
import Dispatch
import Synchronization
import Testing

@testable import djlink

// 소켓을 열지 않는다. 실제 `DispatchCLIScheduler`가 `DJLinkActor.queue`와 별개로 도는지 본다(시험이 1~2초 걸린다).
@Suite("CLI real scheduler independence")
struct CLIRealSchedulerTests {
    @Test("the real scheduler fires the deadline and the forced exit while the DJLinkActor queue is blocked")
    func firesWhileActorBlocked() {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        DJLinkActor.queue.async {
            entered.signal()
            _ = release.wait(timeout: .now() + 10)
        }
        defer { release.signal() }
        #expect(entered.wait(timeout: .now() + 5) == .success)
        // 액터에 올린 일은 큐가 풀리기 전에는 돌지 않는다. 시험 내내 막혀 있었음을 보인다.
        let actorRan = DispatchSemaphore(value: 0)
        Task { @DJLinkActor in actorRan.signal() }

        let abort = CLIAbort()
        let terminated = DispatchSemaphore(value: 0)
        let exits = Mutex<[Int32]>([])
        let watchdog = CLIWatchdog(
            abort: abort, scheduler: DispatchCLIScheduler(), graceSeconds: 1,
            terminate: { code in
                exits.withLock { $0.append(code) }
                terminated.signal()
            })
        watchdog.setDeadline(seconds: 1)
        // 제한 시간 1초 → 중단(실패) → 정리 유예 1초 → 강제 종료. 모두 액터와 무관하다.
        #expect(terminated.wait(timeout: .now() + 6) == .success)
        guard case .failed(let message)? = abort.reason else {
            Issue.record("제한 시간이 중단을 실패로 세웠어야 한다: \(String(describing: abort.reason))")
            return
        }
        #expect(message.contains("제한 시간 1초"))
        #expect(exits.withLock { $0 } == [1])
        #expect(actorRan.wait(timeout: .now() + 0.05) == .timedOut, "그동안 액터는 계속 막혀 있었다")
        watchdog.complete()
    }

    @Test("an interrupt arms the real forced exit with code 130 even though the actor is blocked")
    func interruptWhileActorBlocked() {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        DJLinkActor.queue.async {
            entered.signal()
            _ = release.wait(timeout: .now() + 10)
        }
        defer { release.signal() }
        #expect(entered.wait(timeout: .now() + 5) == .success)
        let abort = CLIAbort()
        let terminated = DispatchSemaphore(value: 0)
        let exits = Mutex<[Int32]>([])
        let watchdog = CLIWatchdog(
            abort: abort, scheduler: DispatchCLIScheduler(), graceSeconds: 1,
            terminate: { code in
                exits.withLock { $0.append(code) }
                terminated.signal()
            })
        abort.requestAbort(.interrupted)
        #expect(terminated.wait(timeout: .now() + 5) == .success)
        #expect(exits.withLock { $0 } == [130])
        watchdog.complete()
    }

    @Test("completing cancels the real timers so neither fires later")
    func completeCancelsTimers() {
        let abort = CLIAbort()
        let fired = DispatchSemaphore(value: 0)
        let watchdog = CLIWatchdog(
            abort: abort, scheduler: DispatchCLIScheduler(), graceSeconds: 1, terminate: { _ in fired.signal() })
        watchdog.setDeadline(seconds: 1)
        watchdog.complete()
        #expect(fired.wait(timeout: .now() + 1.6) == .timedOut)
        #expect(!abort.isAborted)
    }
}
