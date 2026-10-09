// retry 0.12.0(MIT)의 옵션과 재시도 동작 대응. 고지는 THIRD_PARTY_NOTICES.md에 있다.
import Foundation

/// 원본 retry.OperationOptions. nil은 retry 패키지 기본값을 뜻한다.
public struct RetryOptions: Sendable {
    public var retries: Int?
    public var factor: Double?
    public var minTimeout: Double?
    public var maxTimeout: Double?
    public var randomize: Bool?
    public var forever: Bool?
    public var unref: Bool?
    public var maxRetryTime: Double?
    public init(
        retries: Int? = nil, factor: Double? = nil, minTimeout: Double? = nil,
        maxTimeout: Double? = nil, randomize: Bool? = nil, forever: Bool? = nil,
        unref: Bool? = nil, maxRetryTime: Double? = nil
    ) {
        self.retries = retries
        self.factor = factor
        self.minTimeout = minTimeout
        self.maxTimeout = maxTimeout
        self.randomize = randomize
        self.forever = forever
        self.unref = unref
        self.maxRetryTime = maxRetryTime
    }
}
/// retry(err)가 요청한 경우만 재시도한다. promise-retry처럼 재시도를 끝낸 마지막 오류를 던진다.
@DJLinkActor
public func withRetry<T>(
    clock: any DJLinkClock = SystemClock.shared,
    options: RetryOptions = RetryOptions(),
    random: @DJLinkActor () -> Double = { Double.random(in: 0..<1) },
    shouldRetry: @DJLinkActor (any Error) -> Bool = { _ in true },
    sleep: (@DJLinkActor (Duration) async throws -> Void)? = nil,
    _ operation: @DJLinkActor (_ attempt: Int) async throws -> T
) async throws -> T {
    let minimum = options.minTimeout ?? 1000
    let maximum = options.maxTimeout ?? .infinity
    guard minimum <= maximum else { throw DJLinkError("minTimeout is greater than maxTimeout") }
    var timeouts = (0..<max(0, options.retries ?? 10)).map { attempt in
        min(
            maximum,
            floor(
                (options.randomize == true ? random() + 1 : 1) * minimum
                    * pow(options.factor ?? 2, Double(attempt)) + 0.5))
    }.sorted()
    if options.forever == true && timeouts.isEmpty {
        timeouts = [min(maximum, floor((options.randomize == true ? random() + 1 : 1) * minimum + 0.5))]
    }
    let cachedTimeouts = timeouts
    let started = clock.nowMilliseconds()
    var attempt = 1
    while true {
        do { return try await operation(attempt) } catch {
            guard shouldRetry(error) else { throw error }
            let elapsed = clock.nowMilliseconds() - started
            if elapsed >= (options.maxRetryTime == nil || options.maxRetryTime == 0 ? .infinity : options.maxRetryTime!)
            {
                throw error
            }
            if timeouts.isEmpty {
                if options.forever == true {
                    timeouts = cachedTimeouts
                } else {
                    throw error
                }
            }
            let delay = timeouts.removeFirst()
            if let sleep {
                try await sleep(.ms(delay))
            } else {
                await clock.sleep(for: .ms(delay))
            }
            attempt += 1
        }
    }
}
