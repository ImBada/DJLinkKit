// 원본 src/utils/telemetry.ts. 원본도 Sentry를 뺀 빈 구현이다. 범위 밖이라 부르는 자리만 남긴다(docs/PLAN.md §1).

/// Context for starting a child span.
public struct SpanContext: Sendable {
    public var name: String?
    public var op: String?
    public var description: String?

    public init(name: String? = nil, op: String? = nil, description: String? = nil) {
        self.name = name
        self.op = op
        self.description = description
    }
}

/// Span status values for telemetry.
public enum SpanStatus: String, Sendable {
    case ok
    case cancelled
    case unknown
    case invalidArgument = "invalid_argument"
    case deadlineExceeded = "deadline_exceeded"
    case notFound = "not_found"
    case alreadyExists = "already_exists"
    case permissionDenied = "permission_denied"
    case resourceExhausted = "resource_exhausted"
    case failedPrecondition = "failed_precondition"
    case aborted
    case outOfRange = "out_of_range"
    case unimplemented
    case internalError = "internal_error"
    case unavailable
    case dataLoss = "data_loss"
    case unauthenticated
}

/// No-op span implementation.
public struct TelemetrySpan: Sendable {
    public init() {}

    @discardableResult
    public func startChild(_ context: SpanContext = SpanContext()) -> TelemetrySpan { self }
    @discardableResult
    public func setData(_ key: String, _ value: any Sendable) -> TelemetrySpan { self }
    @discardableResult
    public func setTag(_ key: String, _ value: String) -> TelemetrySpan { self }
    @discardableResult
    public func setStatus(_ status: SpanStatus) -> TelemetrySpan { self }
    public func end() {}
    public func finish() {}
}

/// 원본 telemetry 모듈의 함수들. 모두 아무것도 하지 않는다.
public enum Telemetry {
    public static func isTelemetryEnabled() -> Bool { false }
    public static func `init`(_ options: (any Sendable)? = nil) {}
    public static func startTransaction(_ context: SpanContext) -> TelemetrySpan { TelemetrySpan() }
    @discardableResult
    public static func captureException(_ exception: any Error, _ hint: (any Sendable)? = nil) -> String { "" }
    @discardableResult
    public static func captureMessage(_ message: String, _ level: (any Sendable)? = nil) -> String { "" }
    public static func setTag(_ key: String, _ value: String) {}
}
