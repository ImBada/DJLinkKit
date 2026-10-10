import DJLinkKit
import Foundation
import Testing

@testable import djlink

/// 파일을 만들지 않고 기록만 하는 로컬 DB 파일 시스템.
@DJLinkActor
private final class RecordingLocalFileSystem: LocalDBFileSystem {
    var files: Set<String> = []
    private(set) var unlinks: [String] = []
    /// 이 경로를 지우려 하면 던진다.
    var unlinkFailures: Set<String> = []
    nonisolated init() {}

    var tmpdir: String { "/fake-tmp" }

    func writeFileSync(_ path: String, _ data: [UInt8]) throws { files.insert(path) }

    func unlinkSync(_ path: String) throws {
        unlinks.append(path)
        if unlinkFailures.contains(path) { throw CLIFileError(message: "지우지 못했다: \(path)") }
        guard files.remove(path) != nil else { throw CLIFileError(message: "없다: \(path)") }
    }
}

@Suite("CLI OneLibrary temporary database cleanup")
@DJLinkActor
struct CLILocalTempCleanupTests {
    private let first = "/fake-tmp/prolink-onelibrary-1-2-1000.db"
    private let second = "/fake-tmp/prolink-onelibrary-2-2-2000.db"

    @Test("written files are remembered and ones the library removed are forgotten")
    func tracksWrites() throws {
        let inner = RecordingLocalFileSystem()
        let system = CLIGuardedLocalFileSystem(abort: CLIAbort(), inner: inner)
        #expect(system.tmpdir == "/fake-tmp")
        try system.writeFileSync(first, [1])
        try system.writeFileSync(second, [2])
        try system.writeFileSync(second, [3])
        #expect(system.writtenPaths == [first, second])
        try system.unlinkSync(first)
        #expect(system.writtenPaths == [second])
        system.removeWrittenFiles()
        #expect(system.writtenPaths.isEmpty)
        #expect(inner.files.isEmpty)
        system.removeWrittenFiles()
    }

    @Test("a file that could not be removed by the library stays tracked")
    func failedUnlinkStaysTracked() throws {
        let inner = RecordingLocalFileSystem()
        let system = CLIGuardedLocalFileSystem(abort: CLIAbort(), inner: inner)
        try system.writeFileSync(first, [1])
        inner.unlinkFailures = [first]
        #expect(throws: CLIFileError.self) { try system.unlinkSync(first) }
        #expect(system.writtenPaths == [first])
        inner.unlinkFailures = []
        system.removeWrittenFiles()
        #expect(inner.files.isEmpty)
    }

    @Test("SQLite side files next to a leftover database are removed too")
    func sideFiles() throws {
        let inner = RecordingLocalFileSystem()
        let system = CLIGuardedLocalFileSystem(abort: CLIAbort(), inner: inner)
        try system.writeFileSync(first, [1])
        inner.files.formUnion([first + "-wal", first + "-shm", "/fake-tmp/other.db"])
        system.removeWrittenFiles()
        #expect(inner.files == ["/fake-tmp/other.db"], "CLI가 쓰지 않은 파일은 건드리지 않는다")
    }

    @Test("nothing is tracked when the write is refused after an abort")
    func abortedWriteIsNotTracked() {
        let abort = CLIAbort()
        let inner = RecordingLocalFileSystem()
        let system = CLIGuardedLocalFileSystem(abort: abort, inner: inner)
        abort.requestAbort(.interrupted)
        #expect(throws: CLIAborted.self) { try system.writeFileSync(first, [1]) }
        #expect(system.writtenPaths.isEmpty)
        #expect(inner.files.isEmpty)
    }

    @Test("cleanup deletes the leftover temporary database the library wrote")
    func sessionCleanupRemovesTemporaryDatabase() async throws {
        let h = CLIHarness()
        let inner = RecordingLocalFileSystem()
        var runtime = h.makeRuntime()
        runtime.localFileSystem = inner
        let session = CLISession(runtime: runtime, output: h.output, abort: h.abort)
        let system = try #require(session.guardedLocalDBDependencies().fileSystem as? CLIGuardedLocalFileSystem)
        #expect(system === session.localFileSystem)
        try system.writeFileSync(first, [1])
        try system.writeFileSync(second, [2])
        try system.unlinkSync(second)
        #expect(inner.files == [first])
        await session.cleanup()
        #expect(inner.files.isEmpty)
    }

    @Test("an interrupted run removes the temporary database too")
    func interruptedRunRemovesTemporaryDatabase() async throws {
        let h = CLIHarness()
        let inner = RecordingLocalFileSystem()
        var runtime = h.makeRuntime()
        runtime.localFileSystem = inner
        let session = CLISession(runtime: runtime, output: h.output, abort: h.abort)
        try session.localFileSystem.writeFileSync(first, [1])
        h.abort.interrupt()
        _ = await session.run(.devices(seconds: 30, verbose: false))
        #expect(inner.files.isEmpty)
    }

    @Test("the real file system removes a leftover temporary file")
    func realFile() throws {
        let system = CLIGuardedLocalFileSystem(abort: CLIAbort())
        let path = URL(fileURLWithPath: system.tmpdir).appendingPathComponent(
            "prolink-onelibrary-djlink-test-\(UUID().uuidString).db"
        ).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try system.writeFileSync(path, [1, 2, 3])
        #expect(FileManager.default.fileExists(atPath: path))
        system.removeWrittenFiles()
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
