import DJLinkKit

extension EventName where Owner == PassiveBeatEmitter, Payload == CDJStatus.BeatState {
    public static var beat: Self { .init("beat") }
}

/// 패시브 어댑터의 비트 포트에서 0x28만 읽는다. 캡처나 소켓은 직접 열지 않는다.
@DJLinkActor
public final class PassiveBeatEmitter: EventEmitting {
    public let emitter = EventHub<PassiveBeatEmitter>()
    private let adapter: PcapAdapter
    private var beatSubscription: EventSubscription?

    public init(_ adapter: PcapAdapter) {
        self.adapter = adapter
        beatSubscription = adapter.on(.beat) { [weak self] event in
            guard let beat = beatFromPacket(event.packet) else { return }
            self?.emitter.emit(.beat, beat)
        }
    }

    public func stop() {
        if let beatSubscription { adapter.off(beatSubscription) }
        beatSubscription = nil
    }
}
