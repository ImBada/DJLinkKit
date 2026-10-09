// 원본 src/control/load.ts
import DJLinkKit

/// Where the track a Load Track command names lives: the device holding the
/// media, its slot, and the track type as the player's status reports it.
public struct LoadSource: Equatable, Sendable {
    public var deviceId: DeviceID
    public var slot: MediaSlot
    public var trackType: TrackType?

    public init(deviceId: DeviceID, slot: MediaSlot, trackType: TrackType? = nil) {
        self.deviceId = deviceId
        self.slot = slot
        self.trackType = trackType
    }
}

/// Byte length of a Load Track command.
public let LOAD_TRACK_LENGTH = 0x58

/// Generates the Load Track command (0x19, 88 bytes), unicast to a player's
/// status port.
///
/// Byte for byte what rekordbox 7.2 sends a CDJ-3000 (captured 2026-09-13 and
/// verified live on two CDJ-3000s): the status-style header with a 20-byte
/// name, `01 01`, our device number, the length `0034` of what follows, our
/// number again, then the source device, slot and track type, the track ID
/// big-endian, `32` at 0x33, the destination player counted from zero at
/// 0x40, and `32` at 0x4b.
///
/// A player only honours the command from the address its keep-alives
/// announced and from port 50002.
public func makeLoadTrackPacket(
    _ hostDevice: Device,
    _ device: Device,
    _ trackId: Int,
    _ source: LoadSource
) throws(BufferRangeError) -> [UInt8] {
    var packet = [UInt8].alloc(LOAD_TRACK_LENGTH)

    // 0-9: magic header
    packet.set(PROLINK_HEADER, 0)
    // 10: kind 0x19
    packet[10] = 0x19
    // 11-30: device name (20 bytes)
    packet.set(try buildName(hostDevice), 11)
    // 31-35: 01, subtype 01, our number, then the length 0x0034 of what follows
    packet[31] = 0x01
    packet[32] = 0x01
    // 원본은 Uint8Array 대입이라 바이트 범위를 넘으면 256으로 나눈 나머지가 된다.
    packet[33] = UInt8(truncatingIfNeeded: hostDevice.id)
    packet[34] = 0x00
    packet[35] = 0x34
    // 36: our number again
    packet[36] = UInt8(truncatingIfNeeded: hostDevice.id)
    // 40-42: the source device, its slot and the track type
    packet[40] = UInt8(truncatingIfNeeded: source.deviceId)
    packet[41] = UInt8(truncatingIfNeeded: source.slot.rawValue)
    packet[42] = UInt8(truncatingIfNeeded: (source.trackType ?? .rb).rawValue)
    // 44-47: the track ID, big-endian
    // 원본 `>>>`는 먼저 32비트 부호 없는 수로 바꾼다.
    let id32 = UInt32(truncatingIfNeeded: trackId)
    packet[44] = UInt8((id32 >> 24) & 0xff)
    packet[45] = UInt8((id32 >> 16) & 0xff)
    packet[46] = UInt8((id32 >> 8) & 0xff)
    packet[47] = UInt8(id32 & 0xff)
    packet[0x33] = 0x32
    // 0x40: the player to load onto, counted from zero; a player accepts the
    // command by address regardless
    packet[0x40] = UInt8(truncatingIfNeeded: max(device.id - 1, 0))
    packet[0x4b] = 0x32

    return packet
}
