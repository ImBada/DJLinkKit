import DJLinkKit
// SPDX-License-Identifier: GPL-2.0-or-later
// Rust Instant에 대응한다. 벽시계 조정은 참여·만료 시간에 영향을 주지 않는다.
import Dispatch
import Foundation

@DJLinkActor
public final class MonotonicClock: DJLinkClock {
    public static let shared = MonotonicClock()
    public nonisolated init() {}
    public func now() -> Date {
        Date(timeIntervalSince1970: Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000)
    }
    public func setTimeout(_ delay: Duration, _ action: @escaping @DJLinkActor () -> Void) -> TimerHandle {
        SystemClock.shared.setTimeout(delay, action)
    }
    public func setInterval(_ interval: Duration, _ action: @escaping @DJLinkActor () -> Void) -> TimerHandle {
        SystemClock.shared.setInterval(interval, action)
    }
    public func clearTimer(_ handle: TimerHandle) { SystemClock.shared.clearTimer(handle) }
}
