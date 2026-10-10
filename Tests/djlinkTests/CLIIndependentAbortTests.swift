import DJLinkKit
import Dispatch
import Foundation
import Synchronization
import Testing

@testable import djlink

final class ManualCLIScheduler: CLIIndependentScheduler {
    struct Entry: Sendable {
        var seconds: Int
        var action: @Sendable () -> Void
    }
    private let entries = Mutex<[UUID: Entry]>([:])

    func schedule(seconds: Int, _ action: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        let id = UUID()
        entries.withLock { $0[id] = Entry(seconds: seconds, action: action) }
        return { self.entries.withLock { _ = $0.removeValue(forKey: id) } }
    }

    func fire(seconds: Int) {
        let actions = entries.withLock { entries in
            let matches = entries.filter { $0.value.seconds == seconds }
            for id in matches.keys { entries.removeValue(forKey: id) }
            return matches.values.map(\.action)
        }
        for action in actions { action() }
    }

    var count: Int { entries.withLock { $0.count } }
}

final class ManualCLISignalSource: CLISignalSource {
    let handler: @Sendable (UInt) -> Void
    let cancelled = Mutex(false)

    init(_ handler: @escaping @Sendable (UInt) -> Void) { self.handler = handler }
    func cancel() { cancelled.withLock { $0 = true } }
    func emit(_ count: UInt = 1) { handler(count) }
}

private final class InterruptingFileWriter: CLIFileWriter {
    let abort: CLIAbort
    let publications = Mutex<Int>(0)

    init(abort: CLIAbort) { self.abort = abort }

    func fileExists(atPath path: String) -> Bool { false }
    func createDirectory(atPath path: String) throws {}
    func publishWithoutOverwriting(
        _ data: [UInt8], toPath path: String, checkCancellation: @Sendable () throws -> Void
    ) throws {
        // 임시 파일 쓰기·fsync 중 신호가 온 경우를 가짜로 만든다.
        abort.requestAbort(.interrupted)
        try checkCancellation()
        publications.withLock { $0 += 1 }
    }
}

@Suite("CLI actor independent interruption")
struct CLIIndependentAbortTests {
    @Test("injected signals set the flag synchronously and the second signal exits without the actor")
    func signals() {
        let abort = CLIAbort()
        let exits = Mutex<[Int32]>([])
        var sources: [ManualCLISignalSource] = []
        let handler = CLISignalHandler(
            abort: abort,
            makeSource: { _, action in
                let source = ManualCLISignalSource(action)
                sources.append(source)
                return source
            }, terminate: { code in exits.withLock { $0.append(code) } })
        sources[0].emit()
        #expect(abort.reason == .interrupted)
        #expect(exits.withLock { $0.isEmpty })
        sources[0].emit()
        #expect(exits.withLock { $0 } == [130])
        handler.remove()
        #expect(sources.allSatisfy { $0.cancelled.withLock { $0 } })
    }

    @Test("signals and timeout force exit even while the DJLinkActor queue is blocked")
    func blockedActor() {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        DJLinkActor.queue.async {
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
        }
        defer { release.signal() }
        #expect(entered.wait(timeout: .now() + 5) == .success)
        let abort = CLIAbort()
        let clock = ManualCLIScheduler()
        let exits = Mutex<[Int32]>([])
        let watchdog = CLIWatchdog(
            abort: abort, scheduler: clock,
            terminate: { code in
                exits.withLock { $0.append(code) }
            })
        watchdog.setDeadline(seconds: 15)
        clock.fire(seconds: 15)
        #expect(abort.isAborted)
        clock.fire(seconds: 3)
        #expect(exits.withLock { $0 } == [1])
        watchdog.complete()
        var sources: [ManualCLISignalSource] = []
        let interrupted = CLIAbort()
        let handler = CLISignalHandler(
            abort: interrupted,
            makeSource: { _, action in
                let source = ManualCLISignalSource(action)
                sources.append(source)
                return source
            }, terminate: { code in exits.withLock { $0.append(code) } })
        sources[0].emit()
        #expect(interrupted.reason == .interrupted)
        sources[0].emit()
        #expect(exits.withLock { $0 } == [1, 130])
        handler.remove()
    }

    @Test("coalesced signals also trigger immediate exit")
    func coalescedSignals() {
        let abort = CLIAbort()
        let exits = Mutex<[Int32]>([])
        var sources: [ManualCLISignalSource] = []
        let handler = CLISignalHandler(
            abort: abort,
            makeSource: { _, action in
                let source = ManualCLISignalSource(action)
                sources.append(source)
                return source
            }, terminate: { code in exits.withLock { $0.append(code) } })
        sources[0].emit(2)
        #expect(exits.withLock { $0 } == [130])
        handler.remove()
    }

    @Test("independent timeout aborts and forces exit when cleanup cannot run")
    func timeout() {
        let abort = CLIAbort()
        let clock = ManualCLIScheduler()
        let exits = Mutex<[Int32]>([])
        let watchdog = CLIWatchdog(
            abort: abort, scheduler: clock,
            terminate: { code in
                exits.withLock { $0.append(code) }
            })
        watchdog.setDeadline(seconds: 15)
        clock.fire(seconds: 15)
        #expect(abort.isAborted)
        #expect(throws: CLIAborted.self) { try abort.check() }
        clock.fire(seconds: 3)
        #expect(exits.withLock { $0 } == [1])
        watchdog.complete()
        #expect(clock.count == 0)
    }

    @Test("cleanup cancels the forced exit and every independent timer")
    func cleanup() {
        let abort = CLIAbort()
        let clock = ManualCLIScheduler()
        let exits = Mutex<[Int32]>([])
        let watchdog = CLIWatchdog(
            abort: abort, scheduler: clock,
            terminate: { code in
                exits.withLock { $0.append(code) }
            })
        watchdog.setDeadline(seconds: 15)
        abort.requestAbort(.interrupted)
        watchdog.complete()
        clock.fire(seconds: 3)
        clock.fire(seconds: 15)
        #expect(exits.withLock { $0.isEmpty })
        #expect(clock.count == 0)
    }

    @Test("a cancellation during fake file writing publishes zero files")
    @DJLinkActor
    func noPublication() async throws {
        let h = CLIHarness()
        let writer = InterruptingFileWriter(abort: h.abort)
        var runtime = h.makeRuntime()
        runtime.files = writer
        let session = CLISession(runtime: runtime, output: h.output, abort: h.abort)
        await #expect(throws: CLIAborted.self) {
            try await session.publishFile([1, 2], path: "/fake/out")
        }
        #expect(writer.publications.withLock { $0 } == 0)
        await session.cleanup()
    }
}
