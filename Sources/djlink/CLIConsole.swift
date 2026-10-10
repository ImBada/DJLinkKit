import DJLinkKit
import Darwin
import Foundation
import Synchronization

// 원본 src/cli/index.ts의 signale 자리. 사람이 읽는 한 줄 로그를 낸다.

/// 줄 단위 출력. 시험은 `BufferCLIOutput`을 넣는다.
protocol CLIOutput: Sendable {
    func writeLine(_ line: String)
    func writeErrorLine(_ line: String)
}

/// 표준 출력·표준 오류로 쓴다. 쓰기가 실패해도(예: 닫힌 파이프, SIGPIPE를 무시하므로 `EPIPE`) 멈추거나 죽지 않고 그 줄을 버린다.
struct StandardCLIOutput: CLIOutput {
    private let outputDescriptor: Int32
    private let errorDescriptor: Int32

    init(outputDescriptor: Int32 = STDOUT_FILENO, errorDescriptor: Int32 = STDERR_FILENO) {
        self.outputDescriptor = outputDescriptor
        self.errorDescriptor = errorDescriptor
    }

    func writeLine(_ line: String) { Self.write(line, to: outputDescriptor) }

    func writeErrorLine(_ line: String) { Self.write(line, to: errorDescriptor) }

    private static func write(_ line: String, to descriptor: Int32) {
        let bytes = Array((line + "\n").utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes {
                Darwin.write(descriptor, $0.baseAddress!.advanced(by: offset), $0.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                return
            }
            offset += written
        }
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
