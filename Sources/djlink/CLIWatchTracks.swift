import DJLinkKit
import Foundation

/// watch의 조회 중복·재시도·이전 연결의 늦은 결과를 관리한다. 타이머나 소켓은 만들지 않는다.
@DJLinkActor
final class WatchTrackTracker {
    struct Key: Equatable {
        let trackDeviceId: DeviceID
        let trackSlot: MediaSlot
        let trackType: TrackType
        let trackId: Int

        init(_ state: CDJStatus.State) {
            trackDeviceId = state.trackDeviceId
            trackSlot = state.trackSlot
            trackType = state.trackType
            trackId = state.trackId
        }
    }

    struct Ticket: Equatable {
        let deviceId: DeviceID
        let key: Key
        let id: UUID
    }

    private struct Entry {
        var ticket: Ticket
        var running = true
        var succeeded = false
        var attempts = 1
        var retryAfter: Double = 0
    }

    /// 최초 조회와 두 번의 재시도. 새 곡 또는 새 연결에서만 횟수를 초기화한다.
    static let maximumAttempts = 3
    static let retryIntervalMs: Double = 1000
    private let clock: any DJLinkClock
    private var entries: [DeviceID: Entry] = [:]
    private var stopped = false

    init(clock: any DJLinkClock) { self.clock = clock }

    func begin(_ state: CDJStatus.State) -> Ticket? {
        guard !stopped else { return nil }
        if state.trackId == 0 {
            entries.removeValue(forKey: state.deviceId)
            return nil
        }
        let key = Key(state)
        let ticket = Ticket(deviceId: state.deviceId, key: key, id: UUID())
        if var entry = entries[state.deviceId], entry.ticket.key == key {
            guard !entry.running, !entry.succeeded, entry.attempts < Self.maximumAttempts,
                clock.nowMilliseconds() >= entry.retryAfter
            else { return nil }
            entry.ticket = ticket
            entry.running = true
            entry.attempts += 1
            entries[state.deviceId] = entry
        } else {
            entries[state.deviceId] = Entry(ticket: ticket)
        }
        return ticket
    }

    func isCurrent(_ ticket: Ticket) -> Bool {
        !stopped && entries[ticket.deviceId]?.ticket == ticket
    }

    /// 반환값이 true이면 이번 실패로 재시도 한도에 도달했다.
    @discardableResult
    func finish(_ ticket: Ticket, succeeded: Bool) -> Bool {
        guard isCurrent(ticket), var entry = entries[ticket.deviceId], entry.running else { return false }
        entry.running = false
        entry.succeeded = succeeded
        entry.retryAfter = clock.nowMilliseconds() + Self.retryIntervalMs
        entries[ticket.deviceId] = entry
        return !succeeded && entry.attempts == Self.maximumAttempts
    }

    /// 재생 덱이나 원본 장치가 이탈·재발견되면 그 연결에 속한 결과를 무효화한다.
    func deviceChanged(_ deviceId: DeviceID) {
        let removed = entries.filter { $0.key == deviceId || $0.value.ticket.key.trackDeviceId == deviceId }.map(\.key)
        for id in removed { entries.removeValue(forKey: id) }
    }

    func stop() {
        stopped = true
        entries.removeAll()
    }
}
