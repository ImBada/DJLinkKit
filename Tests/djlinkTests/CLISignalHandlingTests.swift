import Darwin
import Foundation
import Synchronization
import Testing

@testable import djlink

@Suite("CLI signal handling")
struct CLISignalHandlingTests {
    private final class Recorder: Sendable {
        let numbers = Mutex<[Int32]>([])
        let ignored = Mutex<[(Int32, Bool)]>([])
        let sources = Mutex<[Int32: ManualCLISignalSource]>([:])
        let exits = Mutex<[Int32]>([])

        func makeHandler(abort: CLIAbort) -> CLISignalHandler {
            CLISignalHandler(
                abort: abort,
                makeSource: { number, action in
                    let source = ManualCLISignalSource(action)
                    self.numbers.withLock { $0.append(number) }
                    self.sources.withLock { $0[number] = source }
                    return source
                },
                setIgnored: { number, ignored in self.ignored.withLock { $0.append((number, ignored)) } },
                terminate: { code in self.exits.withLock { $0.append(code) } })
        }
    }

    @Test("SIGHUP takes the same cleanup path as SIGINT and SIGTERM")
    func hangupInterrupts() {
        for number in [SIGINT, SIGTERM, SIGHUP] {
            let recorder = Recorder()
            let abort = CLIAbort()
            let handler = recorder.makeHandler(abort: abort)
            #expect(Set(recorder.numbers.withLock { $0 }) == [SIGINT, SIGTERM, SIGHUP])
            recorder.sources.withLock { $0[number] }?.emit()
            #expect(abort.reason == .interrupted, "\(number)")
            #expect(recorder.exits.withLock { $0.isEmpty })
            handler.remove()
        }
    }

    @Test("a second signal of any kind exits immediately with 130")
    func mixedSecondSignal() {
        let recorder = Recorder()
        let abort = CLIAbort()
        let handler = recorder.makeHandler(abort: abort)
        recorder.sources.withLock { $0[SIGHUP] }?.emit()
        recorder.sources.withLock { $0[SIGTERM] }?.emit()
        #expect(recorder.exits.withLock { $0 } == [130])
        handler.remove()
    }

    @Test("SIGPIPE is ignored while the handler is installed and restored when it is removed")
    func sigpipeIgnored() {
        let recorder = Recorder()
        let handler = recorder.makeHandler(abort: CLIAbort())
        #expect(recorder.ignored.withLock { $0.map(\.0) == [SIGPIPE] && $0.map(\.1) == [true] })
        handler.remove()
        #expect(recorder.ignored.withLock { $0.map(\.1) == [true, false] })
        #expect(recorder.sources.withLock { $0.values.allSatisfy { $0.cancelled.withLock { $0 } } })
    }

    @Test("writing to a pipe nobody reads is dropped instead of crashing the process")
    func closedPipe() throws {
        // 이 프로세스에서 SIGPIPE를 잠깐 무시한다(무시하지 않으면 시험 프로세스가 죽는다). 끝나면 되돌린다.
        let previous = signal(SIGPIPE, SIG_IGN)
        defer { signal(SIGPIPE, previous) }
        var descriptors: [Int32] = [0, 0]
        #expect(pipe(&descriptors) == 0)
        close(descriptors[0])
        defer { close(descriptors[1]) }
        let output = StandardCLIOutput(outputDescriptor: descriptors[1], errorDescriptor: descriptors[1])
        output.writeLine("hello")
        output.writeErrorLine("world")
        output.log(.info, "still alive")
    }

    @Test("a normal pipe receives complete lines")
    func normalPipe() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(pipe(&descriptors) == 0)
        let output = StandardCLIOutput(outputDescriptor: descriptors[1], errorDescriptor: descriptors[1])
        output.writeLine("한글 줄")
        output.log(.warn, "x")
        close(descriptors[1])
        var received = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let count = read(descriptors[0], &buffer, buffer.count)
            if count <= 0 { break }
            received += buffer[0..<count]
        }
        close(descriptors[0])
        #expect(String(decoding: received, as: UTF8.self) == "한글 줄\n[warn] x\n")
    }
}
