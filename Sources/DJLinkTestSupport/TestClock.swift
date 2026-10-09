import DJLinkKit
import Foundation

/// jest 가짜 타이머(`jest.useFakeTimers()`)를 대신하는 시계.
///
/// - `advance(by:)` = `jest.advanceTimersByTime(ms)`: 기한이 된 타이머를 기한 순(같으면 만든 순)으로 동기로 부른다.
///   미는 도중 새로 건 타이머도 기한이 창 안이면 부른다. 반복 타이머는 앞 기한 + 간격으로 다시 건다.
/// - `runAllTimers()` = `jest.runAllTimers()`, `runOnlyPendingTimers()` = `jest.runOnlyPendingTimers()`.
/// - `now()`도 같이 움직인다(jest 현대 가짜 타이머가 `Date.now()`를 바꾸는 것처럼).
@DJLinkActor
public final class TestClock: DJLinkClock {
    private struct Entry {
        let id: UInt64
        var deadline: Duration
        let interval: Duration?
        let action: @DJLinkActor () -> Void
    }

    private let start: Date
    private var elapsed: Duration = .zero
    private var nextID: UInt64 = 0
    private var entries: [UInt64: Entry] = [:]

    /// `start`는 `Date.now()`의 처음 값.
    public nonisolated init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.start = start
    }

    public func now() -> Date {
        start.addingTimeInterval(elapsed.inMilliseconds / 1000)
    }

    /// 지금까지 민 시간.
    public var currentTime: Duration { elapsed }

    /// 걸려 있는 타이머 수(`jest.getTimerCount()`).
    public var pendingTimerCount: Int { entries.count }

    @discardableResult
    public func setTimeout(_ delay: Duration, _ action: @escaping @DJLinkActor () -> Void) -> TimerHandle {
        add(delay: delay, interval: nil, action)
    }

    @discardableResult
    public func setInterval(_ interval: Duration, _ action: @escaping @DJLinkActor () -> Void) -> TimerHandle {
        add(delay: interval, interval: interval, action)
    }

    public func clearTimer(_ handle: TimerHandle) {
        entries.removeValue(forKey: handle.id)
    }

    /// `jest.advanceTimersByTime(ms)`
    public func advance(by duration: Duration) {
        let target = elapsed + duration
        while let next = nextDue(before: target) {
            elapsed = next.deadline
            fire(next)
        }
        elapsed = target
    }

    /// `jest.advanceTimersByTime(ms)`를 밀리초 숫자로.
    public func advance(ms: Double) {
        advance(by: .ms(ms))
    }

    /// `jest.runAllTimers()`. 끝없이 도는 타이머를 막으려고 jest처럼 10만 번에서 멈춘다.
    public func runAllTimers() {
        var count = 0
        while let next = entries.values.min(by: Self.order) {
            count += 1
            precondition(count <= 100_000, "Aborting after running 100000 timers, assuming an infinite loop!")
            elapsed = max(elapsed, next.deadline)
            fire(next)
        }
    }

    /// `jest.runOnlyPendingTimers()`: 지금 걸린 타이머만 한 번씩 부른다.
    public func runOnlyPendingTimers() {
        let pending = entries.values.sorted(by: Self.order).map(\.id)
        for id in pending {
            guard let entry = entries[id] else { continue }
            elapsed = max(elapsed, entry.deadline)
            fire(entry)
        }
    }

    /// `jest.clearAllTimers()`
    public func clearAllTimers() {
        entries.removeAll()
    }

    /// 비동기 작업이 타이머를 걸 때까지 actor를 양보한다. JS에서 async 함수가 첫 await까지 동기로 도는 것을
    /// 흉내 낼 때 쓴다(시험에서 `Task { await … }`를 시작한 뒤 `advance` 전에 부른다).
    public func settle() async {
        for _ in 0..<64 {
            await Task.yield()
        }
    }

    /// 걸린 타이머가 `count`개 이상이 될 때까지 기다린다(최대 `timeout` 실제 시간).
    public func waitForTimers(atLeast count: Int, timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now + timeout
        while entries.count < count, ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    // MARK: 내부

    private func add(delay: Duration, interval: Duration?, _ action: @escaping @DJLinkActor () -> Void) -> TimerHandle {
        nextID += 1
        // Node는 1ms 미만·2^31-1ms 초과 지연을 1ms로 본다.
        let effective = delay.nodeTimerDelay
        let effectiveInterval = interval.map(\.nodeTimerDelay)
        entries[nextID] = Entry(id: nextID, deadline: elapsed + effective, interval: effectiveInterval, action: action)
        return TimerHandle(id: nextID)
    }

    private func nextDue(before target: Duration) -> Entry? {
        entries.values.filter { $0.deadline <= target }.min(by: Self.order)
    }

    private func fire(_ entry: Entry) {
        if let interval = entry.interval {
            var rescheduled = entry
            rescheduled.deadline = entry.deadline + interval
            entries[entry.id] = rescheduled
        } else {
            entries.removeValue(forKey: entry.id)
        }
        entry.action()
    }

    private static func order(_ lhs: Entry, _ rhs: Entry) -> Bool {
        lhs.deadline == rhs.deadline ? lhs.id < rhs.id : lhs.deadline < rhs.deadline
    }
}
