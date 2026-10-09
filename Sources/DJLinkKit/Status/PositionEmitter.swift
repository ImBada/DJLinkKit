// 원본 src/status/position.ts

extension EventName where Owner == PositionEmitter, Payload == CDJStatus.PositionState {
    /// Fired when an absolute position packet is received from a CDJ-3000+.
    /// These packets are sent approximately every 30ms while a track is loaded.
    public static var position: Self { .init("position") }
}

extension EventName where Owner == PositionEmitter, Payload == CDJStatus.VUState {
    /// Fired when real-time VU levels are received from the mixer under Stagehand connection.
    public static var vu: Self { .init("vu") }
}

/// The position emitter reports absolute playhead position updates from CDJ-3000+ devices.
/// These packets provide precise track position independent of beat grids, enabling
/// accurate timecode, lighting cue, and video synchronization even during scratching,
/// reverse play, loops, and needle jumps.
@DJLinkActor
public final class PositionEmitter: EventEmitting {
    /// The EventEmitter which reports position updates
    public let emitter = EventHub<PositionEmitter>()

    /// Whether experimental Stagehand VU-meter (0x58) parsing is active.
    private let stagehandMode: Bool

    /// - Parameters:
    ///   - beatSocket: A UDP socket to receive position packets on port 50001
    ///   - stagehandMode: Enable Stagehand-only VU-meter parsing. Off by default
    ///     so non-Stagehand connections behave as they did before Stagehand.
    public init(_ beatSocket: any UDPSocket, stagehandMode: Bool = false) {
        self.stagehandMode = stagehandMode
        beatSocket.onMessage { [weak self] message, _ in
            self?.handlePosition(message)
        }
    }

    private func handlePosition(_ message: [UInt8]) {
        // Stagehand VU meter (type 0x58) — only parsed in Stagehand mode.
        if stagehandMode && message.count >= 11 && message[10] == 0x58 {
            if let vu = vuFromPacket(message) {
                emitter.emit(.vu, vu)
                return
            }
        }

        // 원본은 이 'message' 처리기 안에서 파서가 던지면(0x21~0x23 길이 패킷) Node 프로세스가 죽는다.
        // Swift에서는 이 경계에서 잡고 그 패킷을 버린다.
        guard let position = try? positionFromPacket(message) else {
            return
        }

        emitter.emit(.position, position)
    }
}
