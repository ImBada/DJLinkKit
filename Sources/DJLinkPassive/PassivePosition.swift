import DJLinkKit

@DJLinkActor
public final class PassivePositionEmitter: EventEmitting {
    public let emitter = EventHub<PassivePositionEmitter>()
    private let adapter: PcapAdapter
    private var beatSubscription: EventSubscription?
    public init(_ adapter: PcapAdapter) {
        self.adapter = adapter
        beatSubscription = adapter.on(.beat) { [weak self] event in
            // 원본과 다름: Node 이벤트 경계의 미처리 예외는 Swift에서 잡고 넘어간다(가이드 §4).
            guard let position = try? positionFromPacket(event.packet) else { return }
            self?.emitter.emit(.position, position)
        }
    }
    public func stop() { if let beatSubscription { adapter.off(beatSubscription) } }
}
extension EventName where Owner == PassivePositionEmitter, Payload == CDJStatus.PositionState {
    public static var position: Self { .init("position") }
}
