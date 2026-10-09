import DJLinkKit
import Dispatch
import Foundation
import Synchronization
import Testing

@testable import djlink

/// 별도 큐에서 풀어 줄 때까지 막혀 있는 파일 쓰기(느린 디스크를 흉내 낸다). 실제 파일은 만들지 않는다.
private final class BlockingFileWriter: CLIFileWriter {
    private let entered = Mutex(false)
    private let outcome = Mutex<String?>(nil)
    private let gate = DispatchSemaphore(value: 0)

    var hasStarted: Bool { entered.withLock { $0 } }
    /// `"written"`(취소를 보지 못하고 끝까지 갔다) 또는 `"cancelled"`.
    var result: String? { outcome.withLock { $0 } }

    func release() { gate.signal() }

    func fileExists(atPath path: String) -> Bool { false }
    func createDirectory(atPath path: String) throws {}

    func publishWithoutOverwriting(
        _ data: [UInt8], toPath path: String, checkCancellation: @Sendable () throws -> Void
    ) throws {
        entered.withLock { $0 = true }
        _ = gate.wait(timeout: .now() + 10)
        do {
            try checkCancellation()
            outcome.withLock { $0 = "written" }
        } catch {
            outcome.withLock { $0 = "cancelled" }
            throw error
        }
    }
}

/// 실제 시간으로 짧게 기다리며 조건을 본다(큐 스레드가 움직이는 것을 기다릴 때만 쓴다).
@DJLinkActor
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<1000 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@Suite("CLI file publish cleanup")
@DJLinkActor
struct CLIPublishCleanupTests {
    private func startFetch(_ h: CLIHarness) async throws -> CLIRun {
        let task = h.start([
            "fetch", "--device", "1", "--slot", "usb", "--path", "PIONEER/rekordbox/export.pdb", "--out",
            "/fake/out.pdb",
        ])
        await h.settle()
        try h.announce(try cdj(1, "192.168.1.20"))
        await h.settle()
        return task
    }

    @Test("the run does not end before the file queue: cleanup waits for the cancelled publish")
    func runWaitsForFileQueue() async throws {
        let h = CLIHarness()
        let writer = BlockingFileWriter()
        h.fileWriterOverride = writer
        let task = try await startFetch(h)
        #expect(await waitUntil { writer.hasStarted }, "파일 쓰기가 큐에서 시작됐다")

        h.abort.requestAbort(.interrupted)
        for _ in 0..<5 { await h.settle() }
        // 소켓은 이미 닫았지만 게시가 끝나기 전에는 run이 끝나지 않는다.
        #expect(h.allSocketsClosed)
        #expect(!task.isFinished)
        #expect(writer.result == nil)

        writer.release()
        #expect(await task.value == 130)
        #expect(writer.result == "cancelled", "큐의 쓰기는 중단을 보고 멈췄다")
    }

    @Test("a publish stuck in the queue is given up after the grace period")
    func graceExpires() async throws {
        let h = CLIHarness()
        let writer = BlockingFileWriter()
        h.fileWriterOverride = writer
        let task = try await startFetch(h)
        #expect(await waitUntil { writer.hasStarted })
        defer { writer.release() }

        h.abort.requestAbort(.interrupted)
        for _ in 0..<5 { await h.settle() }
        #expect(!task.isFinished)
        h.clock.advance(by: .seconds(CLISession.publishGraceSeconds))
        #expect(await task.value == 130)
    }

    @Test("a publish that finishes normally is not waited for and it published once")
    func normalPublish() async throws {
        let h = CLIHarness()
        let task = try await startFetch(h)
        #expect(await task.value == 0)
        #expect(h.files.published.count == 1)
    }

    @Test("no new publish starts once cleanup has begun")
    func refusedAfterCleanup() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        await session.cleanup()
        await #expect(throws: CLIAborted.self) { try await session.publishFile([1], path: "/fake/out") }
        #expect(h.files.writes == 0)
    }
}
