import DJLinkKit

@DJLinkActor
public final class PassivePositionEmitter: EventEmitting {
    public let emitter = EventHub<PassivePositionEmitter>()
    private let adapter: PcapAdapter
    private var beatSubscription: EventSubscription?
    public init(_ adapter: PcapAdapter) {
        self.adapter = adapter
        beatSubscription = adapter.emitter.onThrowing(.beat) { [weak self] event in
            guard let position = try positionFromPacket(event.packet) else { return }
            self?.emitter.emit(.position, position)
        }
    }
    public func stop() { if let beatSubscription { adapter.off(beatSubscription) } }
}
extension EventName where Owner == PassivePositionEmitter, Payload == CDJStatus.PositionState {
    public static var position: Self { .init("position") }
}
