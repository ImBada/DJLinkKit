// 원본 src/status/index.ts

extension EventName where Owner == StatusEmitter, Payload == CDJStatus.State {
    /// Fired each time the CDJ reports its status
    public static var status: Self { .init("status") }
}

extension EventName where Owner == StatusEmitter, Payload == MediaSlotInfo {
    /// Fired when the CDJ reports its media slot status
    public static var mediaSlot: Self { .init("mediaSlot") }
}

extension EventName where Owner == StatusEmitter, Payload == CDJStatus.OnAirStatus {
    /// Fired when the mixer broadcasts on-air channel status
    public static var onAir: Self { .init("onAir") }
}

extension EventName where Owner == StatusEmitter, Payload == CDJStatus.MixerState {
    /// Fired when the Stagehand-connected mixer reports fader/EQ/control positions
    public static var mixerState: Self { .init("mixerState") }
}

/// `queryMediaSlot`이 기다리는 동안의 구독 상태(원본은 클로저 변수로 쥔다).
@DJLinkActor
private final class MediaSlotWaiter {
    var subscription: EventSubscription?
    var handler: (@DJLinkActor (MediaSlotInfo) -> Void)?
}

/// The status emitter will report every time a device status is received
@DJLinkActor
public final class StatusEmitter: EventEmitting {
    /// 원본 `src/status/utils`의 파서들. 시험에서 바꿔 넣을 수 있게 묶었다(`jest.mock` 자리).
    public struct Parsers {
        public var statusFromPacket: @DJLinkActor ([UInt8]) throws -> CDJStatus.State?
        public var mediaSlotFromPacket: @DJLinkActor ([UInt8]) throws -> MediaSlotInfo?
        public var onAirFromPacket: @DJLinkActor ([UInt8]) throws -> CDJStatus.OnAirStatus?
        public var mixerStateFromPacket: @DJLinkActor ([UInt8]) -> CDJStatus.MixerState?

        public init(
            statusFromPacket: @escaping @DJLinkActor ([UInt8]) throws -> CDJStatus.State?,
            mediaSlotFromPacket: @escaping @DJLinkActor ([UInt8]) throws -> MediaSlotInfo?,
            onAirFromPacket: @escaping @DJLinkActor ([UInt8]) throws -> CDJStatus.OnAirStatus?,
            mixerStateFromPacket: @escaping @DJLinkActor ([UInt8]) -> CDJStatus.MixerState?
        ) {
            self.statusFromPacket = statusFromPacket
            self.mediaSlotFromPacket = mediaSlotFromPacket
            self.onAirFromPacket = onAirFromPacket
            self.mixerStateFromPacket = mixerStateFromPacket
        }

        /// 실제 파서.
        public static var live: Parsers {
            Parsers(
                statusFromPacket: { try DJLinkKit.statusFromPacket($0) },
                mediaSlotFromPacket: { try DJLinkKit.mediaSlotFromPacket($0) },
                onAirFromPacket: { try DJLinkKit.onAirFromPacket($0) },
                mixerStateFromPacket: { DJLinkKit.mixerStateFromPacket($0) }
            )
        }
    }

    private let statusSocket: any UDPSocket
    /// The EventEmitter which reports the device status
    public let emitter = EventHub<StatusEmitter>()
    /// Lock used to avoid media slot query races
    private let mediaSlotQueryLock = AsyncMutex()

    /// Whether the experimental Stagehand mixer-state (0x39) parsing is active.
    /// Only true when the network was brought online in 'stagehand' mode.
    private let stagehandMode: Bool

    private let clock: any DJLinkClock
    private let parsers: Parsers

    /// - Parameters:
    ///   - statusSocket: A UDP socket to receive CDJ status packets on
    ///   - beatSocket: 비트 포트(50001) 소켓. 주면 그 포트로 오는 믹서 on-air 패킷(0x03)도 읽는다(PLAN §9).
    ///   - stagehandMode: Enable Stagehand-only mixer-state parsing. Off by
    ///     default so 'active' and passive connections behave exactly as they did
    ///     before Stagehand was added — the 0x39 layout is reverse-engineered from a
    ///     DJM-A9 and must not be applied to other mixers (e.g. XDJ-AZ) that were
    ///     never captured.
    ///   - clock: 미디어 슬롯 응답 제한 시간(10초)에 쓰는 시계. 시험은 `TestClock`.
    ///   - parsers: 패킷 파서. 기본은 실제 파서.
    public init(
        _ statusSocket: any UDPSocket,
        beatSocket: (any UDPSocket)? = nil,
        stagehandMode: Bool = false,
        clock: any DJLinkClock = SystemClock.shared,
        parsers: Parsers = .live
    ) {
        self.statusSocket = statusSocket
        self.stagehandMode = stagehandMode
        self.clock = clock
        self.parsers = parsers
        statusSocket.onMessage { [weak self] message, _ in
            self?.handleStatus(message)
        }
        // PLAN §9: 믹서는 on-air 패킷을 비트 포트(50001)로 보낸다(DJM-900NXS2 실기, 2026-10-14).
        // 원본은 상태 소켓에서만 읽어 하나도 받지 못했다.
        beatSocket?.onMessage { [weak self] message, _ in
            self?.handleBeat(message)
        }
    }

    /// 비트 포트에는 비트·정밀 위치 같은 다른 패킷도 오므로 종류가 on-air(0x03)인 것만 읽는다.
    private func handleBeat(_ message: [UInt8]) {
        guard message.count > 0x0a, message[0x0a] == ON_AIR_PACKET_TYPE else { return }
        guard let onAir = try? parsers.onAirFromPacket(message) else { return }
        emitter.emit(.onAir, onAir)
    }

    private func handleStatus(_ message: [UInt8]) {
        // 원본은 이 'message' 처리기 안에서 파서가 던지면(머리말이 아닌 패킷 등) Node 프로세스가 죽는다.
        // Swift에서는 이 경계에서 잡고 그 패킷을 버린다.
        do {
            try handleStatusPacket(message)
        } catch {
            return
        }
    }

    private func handleStatusPacket(_ message: [UInt8]) throws {
        // Stagehand mixer state (type 0x39). Only parsed in Stagehand mode — the
        // layout is DJM-A9-specific and applying it to other mixers misreads their
        // faders (NP3-327). In 'active'/passive mode we fall back to the on-air
        // flag, which is how on-air detection worked before Stagehand.
        if stagehandMode && message.count >= 11 && message[10] == 0x39 {
            if let mixerState = parsers.mixerStateFromPacket(message) {
                emitter.emit(.mixerState, mixerState)
                return
            }
        }

        if let status = try parsers.statusFromPacket(message) {
            emitter.emit(.status, status)
            return
        }

        // Media slot status is also reported on this socket
        if let mediaSlot = try parsers.mediaSlotFromPacket(message) {
            emitter.emit(.mediaSlot, mediaSlot)
            return
        }

        // On-air status from mixer is also reported on this socket
        if let onAir = try parsers.onAirFromPacket(message) {
            emitter.emit(.onAir, onAir)
            return
        }
    }

    /// Retrieve media slot status information.
    ///
    /// 원본은 `{hostDevice, device, slot}` 객체 하나를 받는다(`makeMediaSlotRequest`와 같은 모양).
    /// 10초 안에 응답이 없으면 `Timeout waiting for media slot response from device N`을 던진다.
    public func queryMediaSlot(hostDevice: Device, device: Device, slot: MediaSlot) async throws -> MediaSlotInfo {
        let request = try makeMediaSlotRequest(hostDevice: hostDevice, device: device, slot: slot)

        let media = try await mediaSlotQueryLock.runExclusive { () async throws -> MediaSlotInfo in
            try await udpSend(self.statusSocket, request, STATUS_PORT, device.ip.address)

            return try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<MediaSlotInfo, any Error>) in
                let waiter = MediaSlotWaiter()

                let timeout = self.clock.setTimeout(.ms(10000)) {
                    if let subscription = waiter.subscription { self.off(subscription) }
                    // 처리기가 waiter를 잡고 waiter가 처리기를 잡는 순환을 끊는다.
                    waiter.handler = nil
                    continuation.resume(
                        throwing: DJLinkError("Timeout waiting for media slot response from device \(device.id)")
                    )
                }

                let handler: @DJLinkActor (MediaSlotInfo) -> Void = { info in
                    // Only resolve if this is for our device and slot
                    if info.deviceId == device.id && info.slot == slot {
                        self.clock.clearTimeout(timeout)
                        waiter.handler = nil
                        continuation.resume(returning: info)
                    } else if let handler = waiter.handler {
                        // Re-register for the next event
                        waiter.subscription = self.once(.mediaSlot, handler)
                    }
                }
                waiter.handler = handler

                waiter.subscription = self.once(.mediaSlot, handler)
            }
        }

        return media
    }
}
