// 원본 src/control/index.ts
import DJLinkKit

/// 원본 `Options`의 `playState`는 `Cued | Playing`만 받지만 TS 형이라 Swift에서는 `PlayState`를 그대로 받는다.
/// PLAN §9: 원본은 표에 없는 값을 `undefined`로 두어 `Uint8Array.from`이 0(시작)으로 바꿨다. 이제 nil로 돌려 거부한다.
private func stateMapValue(_ playState: CDJStatus.PlayState) -> UInt8? {
    switch playState {
    case .cued: 0x01
    case .playing: 0x00
    default: nil
    }
}

/// 재생 상태 패킷에서 그 플레이어를 그대로 두는 값.
private let PLAYSTATE_NO_CHANGE: UInt8 = 0x02

/// Generates the packet used to control the playstate of CDJs in active connection mode
public func makePlaystatePacket(
    hostDevice: Device,
    device: Device,
    playState: CDJStatus.PlayState
) throws -> [UInt8] {
    // PLAN §9: 칸 i는 플레이어 i+1의 것이고 0 = 시작, 1 = 정지(cue), 2 = 그대로다.
    // 원본은 칸 번호(0-3)를 `device.id`와 견주고 나머지 칸을 0으로 채워, 대상이 한 칸 어긋나고
    // 다른 플레이어에게 시작을 보냈다(CDJ-2000nexus 실기 확인, 2026-10-14). 칸이 없는 번호는 보내지 않는다.
    guard (1...4).contains(device.id) else {
        throw DJLinkError("playstate packets only have slots for players 1-4 (got \(device.id))")
    }
    guard let value = stateMapValue(playState) else {
        throw DJLinkError("playstate packets only carry playing or cued (got \(playState))")
    }
    var packet: [UInt8] = []
    packet += PROLINK_HEADER
    packet += [0x02]
    packet += try buildName(hostDevice)
    packet += [0x01, 0x00]
    packet += [UInt8(truncatingIfNeeded: hostDevice.id)]
    packet += [0x00, 0x04]
    packet += (1...4).map { $0 == device.id ? value : PLAYSTATE_NO_CHANGE }
    return packet
}

@DJLinkActor
public final class Control {
    /// 원본은 `Device` 객체를 그대로 쥐어서 가상 CDJ 번호가 바뀌면 따라간다(``DeviceReference``).
    private let hostDevice: DeviceReference
    /// The socket used to send control packets
    private let beatSocket: any UDPSocket
    /// The socket bound to the status port, which the Load Track command must
    /// leave from: a CDJ-3000 ignores it from any other port. Absent when the
    /// control service was built without one.
    private let statusSocket: (any UDPSocket)?
    /// Randomized correlation byte per session for Stagehand commands
    private let correlationByte: Int

    /// - Parameter correlationByte: 시험에서 값을 고정하려고 둔 것. 원본에는 없고, 기본은 원본처럼 0-255 무작위.
    public init(
        _ beatSocket: any UDPSocket,
        _ hostDevice: DeviceReference,
        _ statusSocket: (any UDPSocket)? = nil,
        correlationByte: Int = Int.random(in: 0..<256)
    ) {
        self.beatSocket = beatSocket
        self.statusSocket = statusSocket
        self.hostDevice = hostDevice
        self.correlationByte = correlationByte
    }

    /// Send one Stagehand transport packet (0x07) carrying `op` with the press /
    /// release flag, for opcodes the named methods do not cover.
    public func transport(_ device: Device, _ op: Int, _ press: Bool) async throws {
        let p = try makeStagehandTransportPacket(hostDevice.device, op, press, correlationByte)
        try await udpSend(beatSocket, p, BEAT_PORT, device.ip.address)
    }

    /// Tell a player to load a track, as rekordbox does when a row is dragged
    /// onto a deck: the Load Track command (0x19) from our status port to the
    /// player's. The player answers 0x1a and the load shows in its next status.
    ///
    /// `source` names where the track lives: a device number and its slot (a
    /// player's USB or SD, or the rekordbox slot of a library served over the
    /// link).
    public func loadTrack(_ device: Device, _ trackId: Int, _ source: LoadSource) async throws {
        guard let statusSocket else {
            throw DJLinkError("loadTrack needs the status socket; connect through ProlinkNetwork")
        }
        let p = try makeLoadTrackPacket(hostDevice.device, device, trackId, source)
        try await udpSend(statusSocket, p, STATUS_PORT, device.ip.address)
    }

    /// Start or stop a CDJ on the network.
    /// Delegates automatically to Stagehand-specific transport control if connected in Stagehand mode.
    public func setPlayState(_ device: Device, _ playState: CDJStatus.PlayState) async throws {
        if hostDevice.type == .stagehand {
            if playState == .playing {
                try await play(device)
            } else {
                try await pause(device)
            }
            return
        }

        let packet = try makePlaystatePacket(hostDevice: hostDevice.device, device: device, playState: playState)
        try await udpSend(beatSocket, packet, BEAT_PORT, device.ip.address)
    }

    /// Send Stagehand PLAY command (paired 0x0f and 0x14 packets)
    public func play(_ device: Device) async throws {
        let p1 = try makeStagehandTransportPacket(hostDevice.device, 0x0f, true, correlationByte)
        let p2 = try makeStagehandTransportPacket(hostDevice.device, 0x14, true, correlationByte)
        try await udpSend(beatSocket, p1, BEAT_PORT, device.ip.address)
        try await udpSend(beatSocket, p2, BEAT_PORT, device.ip.address)
    }

    /// Send Stagehand PAUSE command (paired 0x14 packet)
    public func pause(_ device: Device) async throws {
        let p = try makeStagehandTransportPacket(hostDevice.device, 0x14, false, correlationByte)
        try await udpSend(beatSocket, p, BEAT_PORT, device.ip.address)
    }

    /// Send Stagehand SEEK forward command
    /// - Parameter press: true to start seek, false to release
    public func seekForward(_ device: Device, _ press: Bool) async throws {
        let p = try makeStagehandTransportPacket(hostDevice.device, 0x1a, press, correlationByte)
        try await udpSend(beatSocket, p, BEAT_PORT, device.ip.address)
    }

    /// Send Stagehand SEEK backward command
    /// - Parameter press: true to start seek, false to release
    public func seekBackward(_ device: Device, _ press: Bool) async throws {
        let p = try makeStagehandTransportPacket(hostDevice.device, 0x1b, press, correlationByte)
        try await udpSend(beatSocket, p, BEAT_PORT, device.ip.address)
    }

    /// Send Stagehand SKIP track command
    /// - Parameter press: true to start skip, false to release
    public func skip(_ device: Device, _ press: Bool) async throws {
        let p = try makeStagehandTransportPacket(hostDevice.device, 0x18, press, correlationByte)
        try await udpSend(beatSocket, p, BEAT_PORT, device.ip.address)
    }

    /// Send Stagehand preference write command (0x6b packet) to port 50002
    public func setPreference(_ device: Device, _ options: StagehandPrefOptions) async throws {
        let p = try makeStagehandPrefWritePacket(hostDevice.device, options)
        try await udpSend(beatSocket, p, STATUS_PORT, device.ip.address)
    }
}
