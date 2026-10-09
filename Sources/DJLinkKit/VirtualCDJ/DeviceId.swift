import Foundation

// 원본 src/virtualcdj/device-id.ts

/// The highest device ID a CDJ will answer remotedb queries from.
///
/// This limit applies to the device-ID byte inside the remotedb protocol (the
/// Introduce message and every query header), NOT to the ID we announce on the
/// network. Hardware-verified on a CDJ-3000 (2026-08-30, two players + DJM-V5,
/// announced as VCDJ 7 throughout): queries carrying 1-6 are all answered —
/// including IDs of absent players and the target's own ID — while 7 and above
/// are silently ignored (the TCP connection and Introduce succeed, the query
/// never gets a response). See ``pickRemoteDbQueryId(_:_:)``.
public let REMOTEDB_MAX_DEVICE_ID = 6

/// The highest device ID the prolink protocol allows.
public let MAX_DEVICE_ID = 32

/// `DeviceType.Mixer` and `DeviceType.CDJ`, inlined so this module stays free
/// of runtime imports — it is re-exported into consumers' test environments,
/// where pulling in the whole type module (and its ip-address dependency) is
/// dead weight.
private let MIXER_DEVICE_TYPE = 0x03
private let CDJ_DEVICE_TYPE = 0x01

/// How many player numbers each mixer can hand out.
///
/// Players take their number from the mixer channel they are plugged into, so
/// an N-channel mixer only ever produces players 1..N — and N+1 is the lowest
/// number that no player on that rig can claim.
///
/// These are physical channel counts, deliberately NOT the `channelCount` in
/// the app's own capability table, which caps the DJM-V10 at 4 for its mixer
/// signal model. Capping here would put us on player 5 of a 6-channel rig,
/// which is the collision this table exists to avoid.
public let MIXER_PLAYER_CEILING: [String: Int] = [
    // 6-channel flagships — no player number in 1-6 is safe on these
    "DJM-V10": 6,
    "DJM-V10-LF": 6,

    // 4-channel
    "DJM-A9": 4,
    "DJM-900NXS2": 4,
    "DJM-900NXS": 4,
    "DJM-900SRT": 4,
    "DJM-850": 4,
    "DJM-800": 4,
    "DJM-750MK2": 4,
    "DJM-750": 4,
    "DJM-TOUR1": 4,
    "DJM-2000NXS": 4,
    "DJM-2000": 4,
    "EUPHONIA": 4,

    // 3-channel (2026)
    "DJM-V5": 3,

    // 2-channel
    "DJM-450": 2,
    "DJM-350": 2,
    "DJM-250MK2": 2,

    // All-in-ones: their built-in players occupy numbers too, so the ceiling is
    // however many decks the unit announces rather than its mixer channel count
    "XDJ-XZ": 4,
    "XDJ-AZ": 4,
    "XDJ-RX3": 2,
    "XDJ-RX2": 2,
    "XDJ-RX": 2,
    "XDJ-AN": 2,
    "OPUS-QUAD": 4,
]

/// What to assume about a mixer whose model we do not recognise.
///
/// Four is both the most common layout and the choice that keeps remotedb
/// metadata working: assuming six would push us to player 7 on every mixer
/// released after this table was written, silently losing metadata for
/// unanalyzed and streaming tracks. A six-channel unit we failed to recognise
/// may later claim the number we took, which the announcer's conflict handling
/// resolves by moving us.
public let DEFAULT_MIXER_PLAYER_CEILING = 4

/// The fields ``playerNumberCeiling(_:)`` reads off a discovered device.
public protocol DeviceLike {
    var name: String { get }
    var type: DeviceType { get }
}

/// The highest player number the discovered gear can hand out, or undefined
/// when nothing on the network implies one.
///
/// Undefined means we have no mixer to reason from — players may have been
/// numbered by hand anywhere in 1-6, and there is no better guess available.
public func playerNumberCeiling<Devices: Sequence>(_ devices: Devices) -> Int?
where Devices.Element: DeviceLike {
    var ceiling: Int?

    for device in devices {
        let known = MIXER_PLAYER_CEILING[jsTrim(device.name).uppercased()]
        let value =
            known ?? (device.type.rawValue == MIXER_DEVICE_TYPE ? DEFAULT_MIXER_PLAYER_CEILING : nil)

        if let value, ceiling == nil || value > ceiling! {
            ceiling = value
        }
    }

    return ceiling
}

public struct PickDeviceIdOptions: Equatable, Sendable {
    /// Prefer an ID in the 1-6 range, the range real players number themselves
    /// in. Purely conventional: remotedb metadata no longer depends on our
    /// announced ID (``pickRemoteDbQueryId(_:_:)`` chooses the in-protocol query
    /// ID independently), but sitting where gear expects players keeps us
    /// legible on link displays and avoids surprising other tooling.
    ///
    /// @default false
    public var preferPlayerRange: Bool?
    /// The highest player number the rig can hand out, from
    /// ``playerNumberCeiling(_:)``. The search starts just above it, so the
    /// number we take is one no player on this rig can be assigned.
    ///
    /// When omitted, the 1-6 range is searched downwards instead: players number
    /// themselves from 1 upwards, so the top of the range is the least likely to
    /// be claimed by a CDJ that powers on later.
    public var playerCeiling: Int?

    public init(preferPlayerRange: Bool? = nil, playerCeiling: Int? = nil) {
        self.preferPlayerRange = preferPlayerRange
        self.playerCeiling = playerCeiling
    }
}

private func descending(_ from: Int, _ to: Int) -> [DeviceID] {
    var ids: [DeviceID] = []
    var id = from
    while id >= to {
        ids.append(id)
        id -= 1
    }
    return ids
}

private func ascending(_ from: Int, _ to: Int) -> [DeviceID] {
    var ids: [DeviceID] = []
    var id = from
    while id <= to {
        ids.append(id)
        id += 1
    }
    return ids
}

/// Pick a device ID that no device on the network is currently using.
///
/// Taking an ID a live player already holds knocks that player off the network
/// mid-set, so every caller that chooses its own ID should route through here
/// rather than hardcoding one.
///
/// Returns null when every ID from 1 to 32 is occupied, in which case there is
/// no safe ID and the caller must not join the network.
public func pickAvailableDeviceId<UsedIds: Sequence>(
    _ usedIds: UsedIds,
    _ options: PickDeviceIdOptions = PickDeviceIdOptions()
) -> DeviceID? where UsedIds.Element == DeviceID {
    let preferPlayerRange = options.preferPlayerRange ?? false
    let playerCeiling = options.playerCeiling
    let used = Set(usedIds)

    let aboveThePlayers =
        playerCeiling == nil
        ? descending(REMOTEDB_MAX_DEVICE_ID, 1)
        : ascending(playerCeiling! + 1, REMOTEDB_MAX_DEVICE_ID)

    let outsidePlayerRange = ascending(REMOTEDB_MAX_DEVICE_ID + 1, MAX_DEVICE_ID)

    // Numbers a player on this rig could be assigned. Last resort: better to
    // contend for a slot than not to join at all, and the announcer moves us if
    // the player that owns it shows up.
    let amongThePlayers =
        playerCeiling == nil
        ? []
        : descending(min(playerCeiling!, REMOTEDB_MAX_DEVICE_ID), 1)

    let search =
        preferPlayerRange
        ? aboveThePlayers + outsidePlayerRange + amongThePlayers
        : outsidePlayerRange + aboveThePlayers + amongThePlayers

    return search.first { !used.contains($0) }
}

/// The fields ``pickRemoteDbQueryId(_:_:)`` reads off a discovered device.
public protocol QueryIdDeviceLike {
    var id: DeviceID { get }
    var type: DeviceType { get }
}

/// Choose the device ID to carry inside remotedb messages when querying a CDJ.
///
/// CDJs only answer remotedb queries whose in-protocol device-ID byte is in
/// 1-6, but that byte is independent of the ID we announce on the network — so
/// a virtual CDJ announced safely above the player range (say 7 behind a
/// DJM-V10) can still query metadata by carrying an in-range ID here. Verified
/// on a CDJ-3000 (2026-08-30): absent IDs and even the target's own ID are
/// answered; 7+ is silently dropped.
///
/// Older players are documented (dysentery, nexus era) as stricter: the byte
/// had to be 1-4, belong to a player actually on the network, and not be the
/// player being queried. The preference order below satisfies those rules
/// whenever the rig makes it possible, then falls back through choices newer
/// players accept.
public func pickRemoteDbQueryId<Devices: Sequence>(
    _ targetId: DeviceID,
    _ devices: Devices
) -> DeviceID where Devices.Element: QueryIdDeviceLike {
    // 원본 Set은 넣은 순서를 지키지만 아래에서 정렬하므로 순서는 결과에 영향이 없다.
    var playerIds = Set<DeviceID>()
    for device in devices {
        if device.type.rawValue == CDJ_DEVICE_TYPE && device.id <= REMOTEDB_MAX_DEVICE_ID {
            playerIds.insert(device.id)
        }
    }

    // A live player that isn't the target, lowest first — 1-4 satisfies every
    // documented era of the restriction.
    let otherPlayers = playerIds.filter { $0 != targetId }.sorted()
    if let first = otherPlayers.first {
        return first
    }

    // No other player on the rig: take the lowest 1-6 ID no player holds.
    for id in 1...REMOTEDB_MAX_DEVICE_ID {
        if id != targetId && !playerIds.contains(id) {
            return id
        }
    }

    // Six players and every one of them is the target? Impossible, but the
    // target's own ID is answered too, so it is a safe closing fallback.
    return targetId
}

extension Device: DeviceLike, QueryIdDeviceLike {}

/// JS `String.prototype.trim()`. 공백과 줄바꿈(유니코드 공백·BOM 포함)을 앞뒤에서 지운다.
private func jsTrim(_ string: String) -> String {
    string.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
}
