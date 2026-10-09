import Foundation

/// 인자 해석 → 안전 검사 → 실행. 소켓을 여는 일은 `executor`가 한다(시험은 가짜를 넣는다).
struct CLIApplication: Sendable {
    var output: any CLIOutput
    var processLister: any ProcessLister
    var executor: any CLICommandExecutor

    init(
        output: any CLIOutput = StandardCLIOutput(),
        processLister: any ProcessLister = DarwinProcessLister(),
        executor: any CLICommandExecutor = LiveCLIExecutor()
    ) {
        self.output = output
        self.processLister = processLister
        self.executor = executor
    }

    /// `arguments`는 프로그램 이름을 뺀 인자. 종료 코드를 돌려준다.
    func run(_ arguments: [String]) async -> Int32 {
        let command: CLICommand
        do {
            command = try parseArguments(arguments)
        } catch {
            output.log(.error, error.message)
            output.writeErrorLine("`djlink \(error.subcommand.map { "\($0.rawValue) " } ?? "")--help`로 사용법을 본다.")
            return CLIExitCode.refused
        }
        if case .help(let topic) = command {
            output.writeLine(helpText(topic))
            return CLIExitCode.ok
        }
        // 소켓을 잡기 전에 같은 Mac의 rekordbox를 확인한다(docs/PLAN.md §11). 확인하지 못해도 거부한다.
        if command.touchesNetwork, let violation = checkRekordboxNotRunning(lister: processLister) {
            output.log(.error, violation.message)
            return CLIExitCode.refused
        }
        return await executor.execute(command, output: output)
    }
}

@main
struct DJLinkCLI {
    static func main() async {
        let code = await CLIApplication().run(Array(CommandLine.arguments.dropFirst()))
        exit(code)
    }
}
