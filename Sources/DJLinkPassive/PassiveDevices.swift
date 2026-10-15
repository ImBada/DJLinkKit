import DJLinkKit
import Foundation

/// 원본의 짧은 announce는 payload 대신 캡처한 source IP를 쓴다.
func deviceFromPacketWithInfo(_ packet: [UInt8], _ info: PacketInfo) throws -> Device? {
    guard packet.indexOf(PROLINK_HEADER) == 0, packet.at(0x0a) == 0x06 else { return nil }
    let name = packet.subarray(0x0c, 0x0c + 20).toString().replacingOccurrences(of: "\0", with: "")
    let id = packet.at(0x24) ?? 0
    let isShortFormat = packet.count < 0x35
    let type: DeviceType
    let ip: Address4
    if isShortFormat {
        type = (1...6).contains(id) ? .cdj : id == 17 ? .rekordbox : .mixer
        ip = try Address4(info.srcAddr)
    } else {
        type = DeviceType(rawValue: packet.at(0x34) ?? 0)
        ip = Address4.fromInteger(try packet.readUInt32BE(0x2c))
    }
    // 원본과 다름: 누락된 deviceId는 기반 Device의 비옵셔널 Int에 맞춰 0으로 둔다.
    return Device(name: name, id: id, type: type, macAddr: packet.subarray(0x26, min(0x2c, packet.count)), ip: ip)
}

public struct PassiveDeviceManagerConfig: Equatable, Sendable {
    public var deviceTimeout: Double?
    public init(deviceTimeout: Double? = nil) { self.deviceTimeout = deviceTimeout }
}
@DJLinkActor
public final class PassiveDeviceManager: EventEmitting, RemoteDBDeviceSource {
    public let emitter = EventHub<PassiveDeviceManager>()
    public private(set) var devices: [DeviceID: Device] = [:]
    private var deviceOrder: [DeviceID] = []
    package var deviceValues: [Device] { deviceOrder.compactMap { devices[$0] } }
    private var deviceTimeouts: [DeviceID: TimerHandle] = [:]
    private var deviceTimeout: Double
    private let adapter: PcapAdapter
    private let clock: any DJLinkClock
    private var announceSubscription: EventSubscription?
    public init(
        _ adapter: PcapAdapter, config: PassiveDeviceManagerConfig? = nil, clock: any DJLinkClock = SystemClock.shared
    ) {
        self.adapter = adapter
        self.clock = clock
        deviceTimeout = config?.deviceTimeout ?? 10000
        announceSubscription = adapter.on(.announce) { [weak self] event in
            self?.handleAnnounce(event.packet, event.info)
        }
    }
    public func getDeviceEnsured(_ id: DeviceID, timeout: Double = 2000) async -> Device? {
        if let existing = devices[id] { return existing }
        final class State {
            var settled = false
            var handler: EventSubscription?
            var timeoutHandle: TimerHandle?
        }
        let state = State()
        let device: Device? = await withCheckedContinuation { continuation in
            state.handler = on(.connected) { [clock] device in
                guard device.id == id, !state.settled else { return }
                state.settled = true
                // PLAN §9: 장치가 먼저 오면 Promise.race의 남은 시간 제한도 지운다.
                clock.clearTimeout(state.timeoutHandle)
                continuation.resume(returning: device)
            }
            state.timeoutHandle = clock.setTimeout(.ms(timeout)) {
                guard !state.settled else { return }
                state.settled = true
                continuation.resume(returning: nil)
            }
        }
        if let handler = state.handler { off(handler) }
        return device
    }
    public func reconfigure(_ config: PassiveDeviceManagerConfig) {
        if let value = config.deviceTimeout { deviceTimeout = value }
    }
    public func stop() {
        if let announceSubscription { adapter.off(announceSubscription) }
        for timer in deviceTimeouts.values { clock.clearTimeout(timer) }
        deviceTimeouts.removeAll()
    }
    private func handleAnnounce(_ packet: [UInt8], _ info: PacketInfo) {
        guard let device = try? deviceFromPacketWithInfo(packet, info) else { return }
        if devices[device.id] == nil {
            devices[device.id] = device
            deviceOrder.append(device.id)
            emitter.emit(.connected, device)
        }
        emitter.emit(.announced, device)
        clock.clearTimeout(deviceTimeouts[device.id])
        deviceTimeouts[device.id] = clock.setTimeout(.ms(deviceTimeout)) { [weak self] in
            guard let self else { return }
            self.devices.removeValue(forKey: device.id)
            self.deviceOrder.removeAll { $0 == device.id }
            self.deviceTimeouts.removeValue(forKey: device.id)
            self.emitter.emit(.disconnected, device)
        }
    }
}
extension EventName where Owner == PassiveDeviceManager, Payload == Device {
    public static var connected: Self { .init("connected") }
    public static var disconnected: Self { .init("disconnected") }
    public static var announced: Self { .init("announced") }
}
