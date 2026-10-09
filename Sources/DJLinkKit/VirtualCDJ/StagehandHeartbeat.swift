// 원본 src/virtualcdj/heartbeat.ts

/// Cadence of the Stagehand unicast keep-alive, in milliseconds.
///
/// The real iOS Stagehand app heartbeats every discovered player and the mixer
/// at ~4 Hz (250ms median inter-packet gap in captured traffic). This is the
/// stream that keeps AlphaTheta hardware unicasting live state (`0x39` mixer
/// fader/EQ, `0x58` VU on the mixer; `0x69` slim status, waveform families on
/// the CDJs) to our IP — subnet-broadcast presence alone (the `0x06` keep-alive)
/// is not enough to bootstrap it.
public let STAGEHAND_HEARTBEAT_INTERVAL = 250

/// Builds a Stagehand name field for a unicast frame.
///
/// Unlike the 20-byte ``buildName(_:)`` used by the broadcast announce/claim
/// frames, unicast frames carry a 19-byte name field (offsets 11..29) with the
/// device type / model bytes beginning at offset 30. The name is ASCII, NUL
/// padded.
private func buildUnicastName(_ name: String) -> [UInt8] {
    var field = [UInt8].alloc(19)
    field.set([UInt8](name, encoding: .ascii).subarray(0, 19))
    return field
}

/// Build the Stagehand mixer keep-alive (`0x3a`, 40 bytes).
///
/// Verified byte-for-byte against the real iOS Stagehand app unicasting to a
/// DJM-A9 at 4 Hz (Phase 4/5 captures §4.14.2). The 10-byte trailer
/// `21 02 00 fe 00 04 00 1c 00 00` is constant across every observed sample —
/// byte 33 (`0xfe`) is a VCDJ sentinel, not our runtime device number, so no
/// per-device bytes vary here.
public func makeStagehandMixerHeartbeat(_ vcdj: Device) -> [UInt8] {
    var parts = PROLINK_HEADER  // 0-9: magic
    parts += [0x3a]  // 10: type 0x3a (mixer keep-alive)
    parts += buildUnicastName(vcdj.name)  // 11-29: name (19 bytes)
    parts += [
        0x21,
        0x02,
        0x00,
        0xfe,
        0x00,
        0x04,
        0x00,
        0x1c,
        0x00,
        0x00,  // 30-39: constant trailer
    ]
    return parts
}

/// Build the Stagehand player keep-alive (`0x68`, 36 bytes).
///
/// Verified byte-for-byte against the real iOS Stagehand app unicasting to a
/// CDJ-3000 at ~2-4 Hz. Body (offsets 30-35) is `03 01 00 3a 00 00`: `0x03`
/// persona/channel, `0x01` device subkind, `0x00` flag, `0x3a` Stagehand
/// model-code stamp, two reserved bytes. Constant across every observed sample.
public func makeStagehandPlayerHeartbeat(_ vcdj: Device) -> [UInt8] {
    var parts = PROLINK_HEADER  // 0-9: magic
    parts += [0x68]  // 10: type 0x68 (player keep-alive)
    parts += buildUnicastName(vcdj.name)  // 11-29: name (19 bytes)
    parts += [
        0x03,
        0x01,
        0x00,
        0x3a,
        0x00,
        0x00,  // 30-35: constant body
    ]
    return parts
}

/// Unicasts Stagehand keep-alive frames to every discovered player and mixer so
/// that AlphaTheta hardware begins (and keeps) pushing live state to our IP.
///
/// The ``StagehandAnnouncer`` makes us *visible* on the network via subnet
/// broadcast; this heartbeat is what makes hardware actually *talk back*. It
/// targets the mixer with `0x3a` and each CDJ with `0x68`, mirroring the real
/// iOS Stagehand app. Frames are sent from the status socket (port 50002) to
/// each device's port 50002, which is where their unicast state replies land and
/// where ``StatusEmitter`` listens for them.
@DJLinkActor
public final class StagehandHeartbeat {
    private let statusSocket: any UDPSocket
    /// 원본처럼 network가 넘긴 가상 장치 객체를 같이 쥔다(``DeviceReference``).
    private let vcdj: DeviceReference
    private let deviceManager: DeviceManager
    private let logger: any Logger
    private var intervalHandle: TimerHandle?
    private let clock: any DJLinkClock

    public init(
        _ vcdj: DeviceReference,
        _ statusSocket: any UDPSocket,
        _ deviceManager: DeviceManager,
        logger: any Logger = noopLogger,
        clock: any DJLinkClock = SystemClock.shared
    ) {
        self.vcdj = vcdj
        self.statusSocket = statusSocket
        self.deviceManager = deviceManager
        self.logger = logger
        self.clock = clock
    }

    public func start() {
        if intervalHandle != nil {
            return
        }

        logger.info("Starting Stagehand heartbeat (unicast keep-alive)")
        sendHeartbeats()
        intervalHandle = clock.setInterval(.ms(Double(STAGEHAND_HEARTBEAT_INTERVAL))) { [self] in
            sendHeartbeats()
        }
    }

    private func sendHeartbeats() {
        // 원본 Map은 넣은 순서로 돌지만 Swift 사전은 순서가 없어 id 순으로 돈다.
        for device in deviceManager.devices.sorted(by: { $0.key < $1.key }).map(\.value) {
            // Never heartbeat ourselves.
            if device.id == vcdj.id {
                continue
            }

            let packet: [UInt8]
            switch device.type {
            case .mixer:
                packet = makeStagehandMixerHeartbeat(vcdj.device)
            case .cdj:
                packet = makeStagehandPlayerHeartbeat(vcdj.device)
            default:
                // Rekordbox / other Stagehand peers are not heartbeat targets.
                continue
            }

            statusSocket.send(packet, port: STATUS_PORT, address: device.ip.address) { [logger] err, _ in
                if let err {
                    logger.debug(
                        "Stagehand heartbeat to \(device.name) (\(device.ip.address)) failed: \(err.jsMessage)"
                    )
                }
            }
        }
    }

    public func stop() {
        logger.info("Stopping Stagehand heartbeat")
        if let intervalHandle {
            clock.clearInterval(intervalHandle)
            self.intervalHandle = nil
        }
    }
}
