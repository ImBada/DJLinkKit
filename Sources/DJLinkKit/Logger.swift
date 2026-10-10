import os

/// 원본 `src/logger.ts`. 쓰는 쪽이 자기 로거를 넣을 수 있고, 넣지 않으면 아무것도 하지 않는다.
/// 원본의 `...args`는 문자열로 바꿔 넘긴다.
public protocol Logger: Sendable {
    func trace(_ msg: String, _ args: [any Sendable])
    func debug(_ msg: String, _ args: [any Sendable])
    func info(_ msg: String, _ args: [any Sendable])
    func warn(_ msg: String, _ args: [any Sendable])
    func error(_ msg: String, _ args: [any Sendable])
}

extension Logger {
    public func trace(_ msg: String, _ args: any Sendable...) { trace(msg, args) }
    public func debug(_ msg: String, _ args: any Sendable...) { debug(msg, args) }
    public func info(_ msg: String, _ args: any Sendable...) { info(msg, args) }
    public func warn(_ msg: String, _ args: any Sendable...) { warn(msg, args) }
    public func error(_ msg: String, _ args: any Sendable...) { error(msg, args) }
}

/// 원본 `noopLogger`
public struct NoopLogger: Logger {
    public init() {}
    public func trace(_ msg: String, _ args: [any Sendable]) {}
    public func debug(_ msg: String, _ args: [any Sendable]) {}
    public func info(_ msg: String, _ args: [any Sendable]) {}
    public func warn(_ msg: String, _ args: [any Sendable]) {}
    public func error(_ msg: String, _ args: [any Sendable]) {}
}

public let noopLogger: any Logger = NoopLogger()

/// `os.Logger`로 내보내는 로거(원본 signale 자리).
public struct OSLogLogger: Logger {
    private let logger: os.Logger

    public init(subsystem: String = "DJLinkKit", category: String = "default") {
        logger = os.Logger(subsystem: subsystem, category: category)
    }

    private func render(_ msg: String, _ args: [any Sendable]) -> String {
        args.isEmpty ? msg : ([msg] + args.map { String(describing: $0) }).joined(separator: " ")
    }

    public func trace(_ msg: String, _ args: [any Sendable]) {
        logger.trace("\(render(msg, args), privacy: .public)")
    }

    public func debug(_ msg: String, _ args: [any Sendable]) {
        logger.debug("\(render(msg, args), privacy: .public)")
    }

    public func info(_ msg: String, _ args: [any Sendable]) {
        logger.info("\(render(msg, args), privacy: .public)")
    }

    public func warn(_ msg: String, _ args: [any Sendable]) {
        logger.warning("\(render(msg, args), privacy: .public)")
    }

    public func error(_ msg: String, _ args: [any Sendable]) {
        logger.error("\(render(msg, args), privacy: .public)")
    }
}
