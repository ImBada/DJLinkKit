import Dispatch
import Foundation

/// `setTimeout`·`setInterval`이 돌려주는 손잡이. `clearTimeout`·`clearInterval`에 넘긴다.
public struct TimerHandle: Hashable, Sendable {
    public let id: UInt64

    public init(id: UInt64) {
        self.id = id
    }
}

/// 원본의 `setTimeout`·`setInterval`·`clearTimeout`·`Date.now()`를 대신한다.
///
/// 상태를 가진 형은 이것을 주입받는다. 실제로는 `SystemClock`, 시험에서는
/// `DJLinkTestSupport.TestClock`(jest 가짜 타이머처럼 `advance(by:)`로 시간을 민다)을 넣는다.
/// 콜백은 모두 `DJLinkActor` 위에서 불린다.
public protocol DJLinkClock: AnyObject, Sendable {
    /// `Date.now()`
    @DJLinkActor func now() -> Date

    /// `setTimeout(fn, delay)`
    @DJLinkActor @discardableResult
    func setTimeout(_ delay: Duration, _ action: @escaping @DJLinkActor () -> Void) -> TimerHandle

    /// `setInterval(fn, interval)`
    @DJLinkActor @discardableResult
    func setInterval(_ interval: Duration, _ action: @escaping @DJLinkActor () -> Void) -> TimerHandle

    /// `clearTimeout`·`clearInterval`. 이미 끝났거나 모르는 손잡이는 무시한다.
    @DJLinkActor func clearTimer(_ handle: TimerHandle)
}

extension DJLinkClock {
    @DJLinkActor public func clearTimeout(_ handle: TimerHandle?) {
        if let handle { clearTimer(handle) }
    }

    @DJLinkActor public func clearInterval(_ handle: TimerHandle?) {
        if let handle { clearTimer(handle) }
    }

    /// `Date.now()`를 밀리초 정수로.
    @DJLinkActor public func nowMilliseconds() -> Double {
        (now().timeIntervalSince1970 * 1000).rounded(.down)
    }

    /// `await new Promise(r => setTimeout(r, delay))`
    @DJLinkActor public func sleep(for delay: Duration) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            setTimeout(delay) { continuation.resume() }
        }
    }
}

/// 실제 시계. 타이머는 `DJLinkActor.queue` 위의 DispatchSourceTimer로 돈다.
@DJLinkActor
public final class SystemClock: DJLinkClock {
    public static let shared = SystemClock()

    private var nextID: UInt64 = 0
    private var timers: [UInt64: DispatchSourceTimer] = [:]

    public nonisolated init() {}

    public func now() -> Date {
        Date()
    }

    @discardableResult
    public func setTimeout(_ delay: Duration, _ action: @escaping @DJLinkActor () -> Void) -> TimerHandle {
        schedule(delay: delay, repeating: nil, action)
    }

    @discardableResult
    public func setInterval(_ interval: Duration, _ action: @escaping @DJLinkActor () -> Void) -> TimerHandle {
        schedule(delay: interval, repeating: interval, action)
    }

    public func clearTimer(_ handle: TimerHandle) {
        timers.removeValue(forKey: handle.id)?.cancel()
    }

    private func schedule(
        delay: Duration,
        repeating: Duration?,
        _ action: @escaping @DJLinkActor () -> Void
    ) -> TimerHandle {
        nextID += 1
        let id = nextID
        let source = DispatchSource.makeTimerSource(queue: DJLinkActor.queue)
        // Node 규칙대로 1ms 미만·2^31-1ms 초과 지연은 1ms로 본다.
        let start = DispatchTime.now() + Self.dispatchInterval(delay.nodeTimerDelay)
        if let repeating {
            source.schedule(deadline: start, repeating: Self.dispatchInterval(repeating.nodeTimerDelay))
        } else {
            source.schedule(deadline: start)
        }
        // 콜백은 큐 위에서 불린다. actor 격리를 가정해 원래 순서대로 부른다.
        let fire: @Sendable () -> Void = { [weak self] in
            DJLinkActor.assumeIsolated {
                guard let self, self.timers[id] != nil else { return }
                if repeating == nil {
                    self.timers.removeValue(forKey: id)?.cancel()
                }
                action()
            }
        }
        source.setEventHandler(handler: fire)
        timers[id] = source
        source.resume()
        return TimerHandle(id: id)
    }

    private static func dispatchInterval(_ duration: Duration) -> DispatchTimeInterval {
        let (seconds, attoseconds) = duration.components
        let nanos = seconds * 1_000_000_000 + attoseconds / 1_000_000_000
        return .nanoseconds(Int(clamping: nanos))
    }
}

extension Duration {
    /// 원본의 밀리초 숫자를 그대로 옮길 때 쓴다. 예: `.ms(1500)`
    /// NaN은 0, 범위를 넘는 값은 `Int64` 끝으로 자른다(멈추지 않는다).
    public static func ms(_ value: Double) -> Duration {
        let nanos = (value * 1_000_000).rounded()
        if nanos.isNaN { return .zero }
        if nanos >= Double(Int64.max) { return .nanoseconds(Int64.max) }
        if nanos <= Double(Int64.min) { return .nanoseconds(Int64.min) }
        return .nanoseconds(Int64(nanos))
    }

    /// Node `setTimeout`·`setInterval`의 지연 규칙: 1ms보다 작거나 2^31-1ms보다 크면 1ms로 본다.
    public var nodeTimerDelay: Duration {
        if self < .milliseconds(1) || self > .milliseconds(2_147_483_647) {
            return .milliseconds(1)
        }
        return self
    }

    /// 밀리초(소수 포함)로 바꾼다.
    public var inMilliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}
