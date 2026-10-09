// 원본 src/devices/index.ts

/// The upper bound in milliseconds to wait when looking for a device to be on
/// the network when using the `getDeviceEnsured` method.
///
/// 원본은 모듈 안 상수다. 공개 함수의 기본 인자로 쓰려고 `@usableFromInline`을 붙인다.
@usableFromInline let ENSURED_TIMEOUT = 2000

/// `getDeviceEnsured`의 `Promise.race` 상태(먼저 끝난 쪽만 결과를 낸다).
@DJLinkActor
private final class EnsuredRace {
    var settled = false
    var handler: EventSubscription?
}

extension EventName where Owner == DeviceManager, Payload == Device {
    /// Fired when a new device becomes available on the network
    public static var connected: Self { .init("connected") }
    /// Fired when a device has not announced itself on the network for the
    /// specified timeout.
    public static var disconnected: Self { .init("disconnected") }
    /// Fired every time the device announces itself on the network
    public static var announced: Self { .init("announced") }
}

/// The device manager is responsible for tracking devices that appear on the
/// prolink network, providing an API to react to devices livecycle events as
/// they connect and disconnect form the network.
@DJLinkActor
public final class DeviceManager: EventEmitting {
    /// 원본 `Config`. 넘기지 않은 칸(nil)은 기본값이나 지금 값을 그대로 둔다(`{...defaultConfig, ...config}`).
    public struct Config: Equatable, Sendable {
        /// Time in milliseconds after which a device is considered to have
        /// disconnected if it has not broadcast an announcement.
        ///
        /// @default 10000 ms
        public var deviceTimeout: Int?
        /// The name of the virtual CDJ to filter out from device announcements.
        /// This prevents our own device from appearing in the device list.
        ///
        /// @default VIRTUAL_CDJ_NAME constant
        public var vcdjName: String?

        public init(deviceTimeout: Int? = nil, vcdjName: String? = nil) {
            self.deviceTimeout = deviceTimeout
            self.vcdjName = vcdjName
        }
    }

    /// The configuration object that may be passed to reconfigure the manager
    public typealias ConfigEditable = Config

    /// 원본 `Required<Config>`. 모든 칸이 채워진 설정.
    private struct ResolvedConfig {
        var deviceTimeout: Int
        var vcdjName: String

        mutating func merge(_ config: Config) {
            if let deviceTimeout = config.deviceTimeout { self.deviceTimeout = deviceTimeout }
            if let vcdjName = config.vcdjName { self.vcdjName = vcdjName }
        }
    }

    private static let defaultConfig = ResolvedConfig(deviceTimeout: 10000, vcdjName: VIRTUAL_CDJ_NAME)

    /// Device manager configuration
    private var config: ResolvedConfig
    /// Tracks device timeout handlers, as devices announce themselves these
    /// timeouts will be updated.
    private var deviceTimeouts: [DeviceID: TimerHandle] = [:]
    /// The EventEmitter which will be used to trigger device lifecycle events
    public let emitter = EventHub<DeviceManager>()

    private let clock: any DJLinkClock
    /// 원본 `src/devices/utils`의 `deviceFromPacket`. 시험에서 바꿔 넣는다(원본 시험의 `jest.mock`).
    private let deviceFromPacket: @DJLinkActor ([UInt8]) throws -> Device?

    /// The map of all active devices currently available on the network.
    ///
    /// 원본 `get devices()`는 바꿀 수 있는 Map을 그대로 돌려준다. 같은 뜻으로 밖에서도 바꿀 수 있게 둔다.
    /// 원본 Map은 넣은 순서로 돌지만 Swift 사전은 순서가 없다. 차례가 필요한 곳은 id 순으로 돈다.
    public var devices: [DeviceID: Device] = [:]

    /// - Parameters:
    ///   - announceSocket: 장치 알림(50000)을 받는 소켓.
    ///   - clock: `setTimeout` 대신 쓰는 시계. 시험은 `TestClock`.
    ///   - deviceFromPacket: 알림 패킷 파서. 기본은 `DJLinkKit.deviceFromPacket`.
    public init(
        _ announceSocket: any UDPSocket,
        config: Config = Config(),
        clock: any DJLinkClock = SystemClock.shared,
        deviceFromPacket: @escaping @DJLinkActor ([UInt8]) throws -> Device? = { try DJLinkKit.deviceFromPacket($0) }
    ) {
        var resolved = Self.defaultConfig
        resolved.merge(config)
        self.config = resolved
        self.clock = clock
        self.deviceFromPacket = deviceFromPacket

        // Begin listening for device announcements
        announceSocket.onMessage { [weak self] message, _ in
            self?.handleAnnounce(message)
        }
    }

    /// Waits for a specific device ID to appear on the network, with a
    /// configurable timeout, in which case it will resolve with null.
    public func getDeviceEnsured(_ id: DeviceID, timeout: Int = ENSURED_TIMEOUT) async -> Device? {
        if let existingDevice = devices[id] {
            return existingDevice
        }

        // Wait for the device to be connected
        // 원본 `Promise.race([devicePromise, setTimeout])`. 원본처럼 장치가 먼저 와도 타이머는 지우지 않는다.
        return await withCheckedContinuation { (continuation: CheckedContinuation<Device?, Never>) in
            let race = EnsuredRace()

            race.handler = on(.connected) { [weak self] device in
                guard device.id == id, !race.settled else { return }
                race.settled = true
                if let handler = race.handler { self?.off(handler) }
                continuation.resume(returning: device)
            }

            clock.setTimeout(.ms(Double(timeout))) { [weak self] in
                guard !race.settled else { return }
                race.settled = true
                if let handler = race.handler { self?.off(handler) }
                continuation.resume(returning: nil)
            }
        }
    }

    public func reconfigure(_ config: ConfigEditable) {
        self.config.merge(config)
    }

    private func handleAnnounce(_ message: [UInt8]) {
        // This runs on every UDP datagram the announce socket receives, so a parse
        // failure here would surface as an uncaught exception on the socket and
        // crash the process. Foreign or truncated packets are ignored instead.
        let parsed: Device?
        do {
            parsed = try deviceFromPacket(message)
        } catch {
            return
        }

        guard let device = parsed else {
            return
        }

        if device.name == config.vcdjName {
            return
        }

        // Device has not checked in before
        if devices[device.id] == nil {
            devices[device.id] = device
            emitter.emit(.connected, device)
        }

        emitter.emit(.announced, device)

        // Reset the device timeout handler
        if let activeTimeout = deviceTimeouts[device.id] {
            clock.clearTimeout(activeTimeout)
        }

        let timeout = config.deviceTimeout
        let newTimeout = clock.setTimeout(.ms(Double(timeout))) { [self] in
            handleDisconnect(device)
        }
        deviceTimeouts[device.id] = newTimeout
    }

    private func handleDisconnect(_ removedDevice: Device) {
        devices.removeValue(forKey: removedDevice.id)
        deviceTimeouts.removeValue(forKey: removedDevice.id)

        emitter.emit(.disconnected, removedDevice)
    }
}

// remotedb가 기대는 모양(원본은 DeviceManager를 그대로 받는다).
extension DeviceManager: RemoteDBDeviceSource {}
