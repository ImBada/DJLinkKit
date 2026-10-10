import DJLinkKit

@DJLinkActor
public final class PassiveStatusEmitter: EventEmitting {
    public let emitter = EventHub<PassiveStatusEmitter>()
    private let adapter: PcapAdapter
    private var statusSubscription: EventSubscription?
    public init(_ adapter: PcapAdapter) {
        self.adapter = adapter
        statusSubscription = adapter.on(.status) { [weak self] event in self?.handleStatus(event.packet) }
    }
    public func stop() { if let statusSubscription { adapter.off(statusSubscription) } }
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
