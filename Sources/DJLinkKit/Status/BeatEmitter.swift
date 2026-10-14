extension EventName where Owner == BeatEmitter, Payload == CDJStatus.BeatState {
    /// 독립 비트 패킷 하나를 받을 때마다 발생한다.
    public static var beat: Self { .init("beat") }
}

/// 기존 위치·on-air 처리기와 같은 비트 소켓을 공유하며 0x28만 읽는다.
@DJLinkActor
public final class BeatEmitter: EventEmitting {
    public let emitter = EventHub<BeatEmitter>()
    private let beatSocket: any UDPSocket
    private var messageSubscription: SocketListener?

    public init(_ beatSocket: any UDPSocket) {
        self.beatSocket = beatSocket
        messageSubscription = beatSocket.onMessage { [weak self] message, _ in
            guard let beat = beatFromPacket(message) else { return }
            self?.emitter.emit(.beat, beat)
        }
    }

    /// 자기 구독만 해제한다. 같은 소켓의 위치·on-air 구독은 유지한다.
    public func stop() {
        if let messageSubscription { beatSocket.off(messageSubscription) }
        messageSubscription = nil
    }
}
