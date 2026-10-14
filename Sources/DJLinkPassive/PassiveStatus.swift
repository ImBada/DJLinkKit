import DJLinkKit

@DJLinkActor
public final class PassiveStatusEmitter: EventEmitting {
    public let emitter = EventHub<PassiveStatusEmitter>()
    private let adapter: PcapAdapter
    private var statusSubscription: EventSubscription?
    private var beatSubscription: EventSubscription?
    public init(_ adapter: PcapAdapter) {
        self.adapter = adapter
        statusSubscription = adapter.on(.status) { [weak self] event in self?.handleStatus(event.packet) }
        // PLAN §9: 믹서는 on-air 패킷을 비트 포트(50001)로 보낸다(DJM-900NXS2 실기, 2026-10-14).
        beatSubscription = adapter.on(.beat) { [weak self] event in self?.handleBeat(event.packet) }
    }
    public func stop() {
        if let statusSubscription { adapter.off(statusSubscription) }
        if let beatSubscription { adapter.off(beatSubscription) }
    }
    /// 비트 포트에는 다른 패킷도 오므로 종류가 on-air(0x03)인 것만 읽는다.
    private func handleBeat(_ message: [UInt8]) {
        guard message.count > 0x0a, message[0x0a] == ON_AIR_PACKET_TYPE else { return }
        guard let onAir = try? onAirFromPacket(message) else { return }
        emitter.emit(.onAir, onAir)
    }
    private func handleStatus(_ message: [UInt8]) {
        do {
            if let status = try statusFromPacket(message) {
                emitter.emit(.status, status)
                return
            }
            if let media = try mediaSlotFromPacket(message) {
                emitter.emit(.mediaSlot, media)
                return
            }
            if let onAir = try onAirFromPacket(message) {
                emitter.emit(.onAir, onAir)
                return
            }
        } catch {}
    }
}
extension EventName where Owner == PassiveStatusEmitter, Payload == CDJStatus.State {
    public static var status: Self { .init("status") }
}
extension EventName where Owner == PassiveStatusEmitter, Payload == MediaSlotInfo {
    public static var mediaSlot: Self { .init("mediaSlot") }
}
extension EventName where Owner == PassiveStatusEmitter, Payload == CDJStatus.OnAirStatus {
    public static var onAir: Self { .init("onAir") }
}
extension EventName where Owner == PassiveStatusEmitter, Payload == CDJStatus.MixerState {
    public static var mixerState: Self { .init("mixerState") }
}
