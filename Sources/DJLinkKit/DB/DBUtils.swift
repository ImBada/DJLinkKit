import Foundation

@DJLinkActor public func anlzLoader(device: Device, slot: MediaSlot, dependencies: DBDependencies = .init())
    -> AnlzResolver
{
    { path in try await dependencies.fetchFile(device, slot, path, nil, nil) }
}

public struct DBTrackOptions: Sendable {
    public var deviceId: DeviceID
    public var trackSlot: MediaSlot
    public var trackType: TrackType
    public var track: Track
    public var span: TelemetrySpan?
    public var logger: (any Logger)?
    public init(
        deviceId: DeviceID, trackSlot: MediaSlot, trackType: TrackType, track: Track, span: TelemetrySpan? = nil,
        logger: (any Logger)? = nil
    ) {
        self.deviceId = deviceId
        self.trackSlot = trackSlot
        self.trackType = trackType
        self.track = track
        self.span = span
        self.logger = logger
    }
    var queryDescriptor: QueryDescriptor { .init(menuTarget: .main, trackSlot: trackSlot, trackType: trackType) }
}

func dbTrackResult(_ result: RemoteDBQueryResult) throws -> Track {
    switch result {
    case let .track(track): return track
    case let .trackWithRawYear(track, year):
        var track = track
        track.rawYear = year
        return track
    default: throw DJLinkError("Expected track query result")
    }
}

func dbJSONString(_ value: String) -> String {
    // JSON.stringify는 /를 이스케이프하지 않는다.
    let data = try! JSONSerialization.data(
        withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}
func dbErrorMessage(_ error: any Error) -> String { String(describing: error) }
func dbSlotName(_ slot: MediaSlot) -> String { getSlotName(slot) ?? "undefined" }
func dbTrackTypeName(_ type: TrackType) -> String { getTrackTypeName(type) ?? "undefined" }

// Promise.all은 한 요청의 실패를 즉시 알리고 다른 요청은 계속 실행한다.
@DJLinkActor func dbPromiseAll<A: Sendable, B: Sendable>(
    _ first: @escaping @DJLinkActor () async throws -> A,
    _ second: @escaping @DJLinkActor () async throws -> B
) async throws -> (A, B) {
    try await withCheckedThrowingContinuation { continuation in
        var firstValue: A?
        var secondValue: B?
        var remaining = 2
        var settled = false
        func complete() {
            remaining -= 1
            if remaining == 0 && !settled {
                settled = true
                continuation.resume(returning: (firstValue!, secondValue!))
            }
        }
        func fail(_ error: any Error) {
            guard !settled else { return }
            settled = true
            continuation.resume(throwing: error)
        }
        Task { @DJLinkActor in
            do {
                firstValue = .some(try await first())
                complete()
            } catch { fail(error) }
        }
        Task { @DJLinkActor in
            do {
                secondValue = .some(try await second())
                complete()
            } catch { fail(error) }
        }
    }
}
