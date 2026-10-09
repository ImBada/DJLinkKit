import DJLinkKit
import Synchronization
import Testing

@testable import djlink

private struct FakeProcessLister: ProcessLister {
    var names: [String]

    func processNames() throws -> [String] { names }
}

/// 실행을 받아 적기만 하는 가짜. 소켓을 열지 않는다.
private final class RecordingExecutor: CLICommandExecutor {
    private let received = Mutex<[CLICommand]>([])
    let exitCode: Int32

    init(exitCode: Int32 = 0) { self.exitCode = exitCode }

    func execute(_ command: CLICommand, output: any CLIOutput) async -> Int32 {
        received.withLock { $0.append(command) }
        return exitCode
    }

    var commands: [CLICommand] { received.withLock { $0 } }
}

private func makeApplication(
    processes: [String] = ["launchd"], executor: RecordingExecutor = RecordingExecutor()
) -> (CLIApplication, BufferCLIOutput, RecordingExecutor) {
    let output = BufferCLIOutput()
    return (
        CLIApplication(output: output, processLister: FakeProcessLister(names: processes), executor: executor), output,
        executor
    )
}

@Suite("CLI application")
struct CLIApplicationTests {
    @Test("help prints and never reaches the executor or the process check")
    func help() async {
        let (app, output, executor) = makeApplication(processes: ["rekordbox"])
        #expect(await app.run([]) == 0)
        #expect(await app.run(["watch", "--help"]) == 0)
        #expect(output.lines.count == 2)
        #expect(output.lines[0].contains("djlink"))
        #expect(output.lines[1].contains("--download-dir"))
        #expect(executor.commands.isEmpty)
    }

    @Test("a usage error is refused with exit code 2 and nothing is executed")
    func usageError() async {
        let (app, output, executor) = makeApplication()
        #expect(await app.run(["bogus"]) == 2)
        #expect(await app.run(["watch", "--vcdj-id", "3"]) == 2)
        #expect(await app.run(["control", "play", "--device", "1"]) == 2)
        #expect(executor.commands.isEmpty)
        #expect(output.errorLines.contains { $0.contains("--allow-player-id") })
        #expect(output.errorLines.contains { $0.contains("--confirm") })
    }

    @Test("rekordbox running stops every network command before it starts")
    func rekordboxRunning() async {
        let commands: [[String]] = [
            ["devices"], ["watch"], ["status"], ["mixstatus"], ["passive", "--iface", "en7"],
            ["metadata", "--device", "1", "--slot", "usb", "--track-id", "1"],
            ["fetch", "--device", "1", "--slot", "usb", "--path", "a", "--out", "o"],
            ["control", "play", "--device", "1", "--confirm", "CDJ-3000"],
        ]
        for arguments in commands {
            let (app, output, executor) = makeApplication(processes: ["launchd", "rekordboxAgent"])
            #expect(await app.run(arguments) == 2, "\(arguments)")
            #expect(executor.commands.isEmpty, "\(arguments)")
            #expect(output.errorLines.contains { $0.contains("rekordboxAgent") }, "\(arguments)")
        }
    }

    @Test("a valid command reaches the executor and returns its exit code")
    func executes() async {
        let executor = RecordingExecutor(exitCode: 7)
        let (app, _, _) = makeApplication(executor: executor)
        #expect(await app.run(["devices", "--seconds", "2"]) == 7)
        #expect(executor.commands == [.devices(seconds: 2, verbose: false)])
    }

    @Test("a never-read fetch path is refused before the process check or any socket")
    func neverReadFetch() async {
        let (app, output, executor) = makeApplication()
        let code = await app.run([
            "fetch", "--device", "1", "--slot", "usb", "--path", "PIONEER/extracted/x", "--out", "o",
        ])
        #expect(code == 2)
        #expect(executor.commands.isEmpty)
        #expect(output.errorLines.contains { $0.contains("PIONEER/extracted") })
    }

    @Test("the help text covers every subcommand and the safety rules")
    func helpTexts() {
        let top = helpText(nil)
        for subcommand in CLISubcommand.allCases {
            #expect(top.contains(subcommand.rawValue))
            #expect(!helpText(subcommand).isEmpty)
        }
        #expect(top.contains("rekordbox"))
        #expect(top.contains("--confirm"))
        #expect(helpText(.control).contains("--confirm"))
        #expect(helpText(.watch).contains("--download-dir"))
    }
}
