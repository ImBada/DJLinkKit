import DJLinkKit
import Foundation
import Synchronization

// 원본 src/cli/index.ts의 signale 자리. 사람이 읽는 한 줄 로그를 낸다.

/// 줄 단위 출력. 시험은 `BufferCLIOutput`을 넣는다.
protocol CLIOutput: Sendable {
    func writeLine(_ line: String)
    func writeErrorLine(_ line: String)
}

/// 표준 출력·표준 오류로 쓴다.
struct StandardCLIOutput: CLIOutput {
    init() {}

    func writeLine(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    func writeErrorLine(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

/// 시험용. 쓴 줄을 모아 둔다.
final class BufferCLIOutput: CLIOutput {
    private let storage = Mutex<(out: [String], err: [String])>(([], []))

    init() {}

    func writeLine(_ line: String) { storage.withLock { $0.out.append(line) } }
    func writeErrorLine(_ line: String) { storage.withLock { $0.err.append(line) } }

    var lines: [String] { storage.withLock { $0.out } }
    var errorLines: [String] { storage.withLock { $0.err } }
}

/// signale 종류에 대응하는 머리표.
enum CLILogKind: String, Sendable {
    case await
    case success
    case star
    case warn
    case error
    case info
    case note
}

/// `[await] 문구` 모양의 한 줄.
func formatLogLine(_ kind: CLILogKind, _ message: String) -> String {
    "[\(kind.rawValue)] \(message)"
}

extension CLIOutput {
    func log(_ kind: CLILogKind, _ message: String) {
        if kind == .error || kind == .warn {
            writeErrorLine(formatLogLine(kind, message))
        } else {
            writeLine(formatLogLine(kind, message))
        }
    }
}

/// 라이브러리 `Logger`를 표준 오류로 내보낸다. 기본은 info 이상, `--verbose`면 debug·trace도.
struct CLILogger: Logger {
    let output: any CLIOutput
    let verbose: Bool

    init(output: any CLIOutput, verbose: Bool) {
        self.output = output
        self.verbose = verbose
    }

    private func render(_ msg: String, _ args: [any Sendable]) -> String {
        args.isEmpty ? msg : ([msg] + args.map { String(describing: $0) }).joined(separator: " ")
    }

    func trace(_ msg: String, _ args: [any Sendable]) {
        if verbose { output.writeErrorLine("[trace] \(render(msg, args))") }
    }

    func debug(_ msg: String, _ args: [any Sendable]) {
        if verbose { output.writeErrorLine("[debug] \(render(msg, args))") }
    }

    func info(_ msg: String, _ args: [any Sendable]) { output.writeErrorLine("[info] \(render(msg, args))") }
    func warn(_ msg: String, _ args: [any Sendable]) { output.writeErrorLine("[warn] \(render(msg, args))") }
    func error(_ msg: String, _ args: [any Sendable]) { output.writeErrorLine("[error] \(render(msg, args))") }
}
