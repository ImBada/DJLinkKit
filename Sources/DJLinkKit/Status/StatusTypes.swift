// 원본 src/status/types.ts
// 원본 src/types.ts의 `export * as CDJStatus from 'src/status/types'`를 이름 공간 enum과 확장으로 옮긴다.
// 그래서 형은 `CDJStatus.State`, `CDJStatus.PlayState.playing`처럼 보인다.

/// 원본 `CDJStatus` 이름 공간(`src/status/types`).
public enum CDJStatus {}

extension CDJStatus {
    /// Status flag bitmasks (byte 0x89 of the CDJ status packet).
    ///
    /// Verified against CDJ-3000 firmware (EP122 FW3.20): the deck assembles this
    /// byte in `sub_d7d3c8` (0xd7d3c8) from the BeatSyncMaster state struct, one
    /// source boolean per bit. The bits not named here:
    ///
    /// - bit 0 (0x01): structurally unused — no code path ever sets it (always 0).
    /// - bit 2 (0x04): a real, dedicated beat-sync boolean (struct +5), but its
    ///   name did not survive in the stripped `usecase::sync` async-task code. It
    ///   is normally 0, which is why it has never been observed on the wire.
    /// - bit 7 (0x80): a real bit (struct +0xa) that is default-set at init and
    ///   whose de-assertion itself triggers a state-change notification — best read
    ///   as a "sync-master active / handoff-in-progress" toggle. Also normally 0 in
    ///   steady state.
    public struct StatusFlag: OptionSet, Hashable, Sendable {
        public var rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Degraded to BPM Sync: the player is still tracking the master's tempo, but
        /// beat alignment was dropped after a pitch-bend / jog nudge. Firmware sources
        /// this from BeatSyncMaster struct +4.
        public static let bpmSync = StatusFlag(rawValue: 1 << 1)
        public static let onAir = StatusFlag(rawValue: 1 << 3)
        public static let sync = StatusFlag(rawValue: 1 << 4)
        public static let master = StatusFlag(rawValue: 1 << 5)
        public static let playing = StatusFlag(rawValue: 1 << 6)
    }

    /// Play state flags
    public struct PlayState: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
        public var rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let empty = PlayState(rawValue: 0x00)
        public static let loading = PlayState(rawValue: 0x02)
        public static let playing = PlayState(rawValue: 0x03)
        public static let looping = PlayState(rawValue: 0x04)
        public static let paused = PlayState(rawValue: 0x05)
        public static let cued = PlayState(rawValue: 0x06)
        public static let cuing = PlayState(rawValue: 0x07)
        public static let platterHeld = PlayState(rawValue: 0x08)
        public static let searching = PlayState(rawValue: 0x09)
        public static let spunDown = PlayState(rawValue: 0x0e)
        public static let ended = PlayState(rawValue: 0x11)

        /// 원본 enum의 키 이름(모르는 값이면 nil).
        public var jsName: String? {
            switch rawValue {
            case 0x00: "Empty"
            case 0x02: "Loading"
            case 0x03: "Playing"
            case 0x04: "Looping"
            case 0x05: "Paused"
            case 0x06: "Cued"
            case 0x07: "Cuing"
            case 0x08: "PlatterHeld"
            case 0x09: "Searching"
            case 0x0e: "SpunDown"
            case 0x11: "Ended"
            default: nil
            }
        }

        public var description: String { jsName ?? String(rawValue) }
    }

    /// Represents various details about the current state of the CDJ.
    public struct State: Equatable, Hashable, Sendable {
        /// The device reporting this status.
        public var deviceId: Int
        /// The ID of the track loaded on the device.
        ///
        /// 0 When no track is loaded.
        public var trackId: Int
        /// The device ID the track is loaded from.
        ///
        /// For example if you have two CDJs and you've loaded a track over the 'LINK',
        /// this will be the ID of the player with the USB media device connected to it.
        public var trackDeviceId: DeviceID
        /// The MediaSlot the track is loaded from. For example a SD card or USB device.
        public var trackSlot: MediaSlot
        /// The TrackType of the track, for example a CD or Rekordbox analyzed track.
        public var trackType: TrackType
        /// The current play state of the CDJ.
        public var playState: PlayState
        /// Whether the CDJ is currently reporting itself as 'on-air'.
        ///
        /// This is indicated by the red ring around the platter on the CDJ Nexus models.
        /// A DJM mixer must be ont he network for the CDJ to report this as true.
        public var isOnAir: Bool
        /// Whether the CDJ is synced.
        public var isSync: Bool
        /// Whether the CDJ has degraded into BPM Sync — still in Sync mode and
        /// tracking the master's tempo, but no longer beat-aligned because the DJ used
        /// pitch bend (e.g. nudged the jog wheel). Corresponds to
        /// ``StatusFlag/bpmSync`` (bit 1 of byte 0x89), which older pre-nexus
        /// players never set.
        public var isBpmSync: Bool
        /// Whether the CDJ is the master player.
        public var isMaster: Bool
        /// Whether the CDJ is in an emergency state (emergecy loop / emergency mode
        /// on newer players)
        public var isEmergencyMode: Bool
        /// The BPM of the loaded track. null if no track is loaded or the BPM is unknown.
        public var trackBPM: Double?
        /// The pitch actually *in effect* — the value shown on the BPM display,
        /// whether it comes from the local pitch fader or a synced tempo master
        /// (packet Pitch1 @ 0x8c). This is the value to combine with `trackBPM` to get
        /// the playing BPM. It is also what is reported when the jog wheel is nudged,
        /// the platter is held, or the deck spins down on the vinyl stop knob.
        public var effectivePitch: Double
        /// The *local pitch-fader* position (packet Pitch2 @ 0x98) — always tied to
        /// the physical fader, following the player's brake/release ramp as playback
        /// stops or starts, regardless of any sync master.
        public var sliderPitch: Double
        /// The current beat within the measure. 1-4. 0 when no track is loaded.
        public var beatInMeasure: Int
        /// Number of beats remaining until the next cue point is reached. Null if there
        /// is no next cue point
        public var beatsUntilCue: Int?
        /// The beat 'timestamp' of the track. Can be used to compute absolute track time
        /// given the slider pitch.
        public var beat: Int?
        /// The player-type / capability byte (packet byte 0xcc, dysentery's "nx").
        ///
        /// This is a capability *bitfield*, not a model id. Known values: `0x05` for
        /// older (pre-nexus) players, `0x0f` for nexus, and `0x1f` for the CDJ-3000
        /// and XDJ-XZ (the nexus value plus bit 4). Firmware (CDJ-3000 FW3.20, one
        /// 16-bit store in `sub_d858b8`) hardcodes `0x1f`. The byte is version-gated:
        /// a player zeroes it toward peers advertising a Pro DJ Link protocol version
        /// below 3, so a much older device on the link may report `0`.
        public var deviceType: Int
        /// A counter that increments for every status packet sent (packet byte 0xc8).
        ///
        /// Caveat: on the CDJ-3000 this field is hardwired to 0 — the firmware never
        /// writes packet offset 0xc8 (verified: no store to the status body's +0xa4).
        /// The CDJ-3000's live per-packet counter moved to its high-resolution stream
        /// packet on UDP 50004 (a big-endian u32 at that packet's offset 0x28). Do not
        /// rely on `packetNum` to detect liveness or drops on CDJ-3000 hardware.
        public var packetNum: Int

        public init(
            deviceId: Int,
            trackId: Int,
            trackDeviceId: DeviceID,
            trackSlot: MediaSlot,
            trackType: TrackType,
            playState: PlayState,
            isOnAir: Bool,
            isSync: Bool,
            isBpmSync: Bool,
            isMaster: Bool,
            isEmergencyMode: Bool,
            trackBPM: Double?,
            effectivePitch: Double,
            sliderPitch: Double,
            beatInMeasure: Int,
            beatsUntilCue: Int?,
            beat: Int?,
            deviceType: Int,
            packetNum: Int
        ) {
            self.deviceId = deviceId
            self.trackId = trackId
            self.trackDeviceId = trackDeviceId
            self.trackSlot = trackSlot
            self.trackType = trackType
            self.playState = playState
            self.isOnAir = isOnAir
            self.isSync = isSync
            self.isBpmSync = isBpmSync
            self.isMaster = isMaster
            self.isEmergencyMode = isEmergencyMode
            self.trackBPM = trackBPM
            self.effectivePitch = effectivePitch
            self.sliderPitch = sliderPitch
            self.beatInMeasure = beatInMeasure
            self.beatsUntilCue = beatsUntilCue
            self.beat = beat
            self.deviceType = deviceType
            self.packetNum = packetNum
        }
    }

    /// Absolute position information from CDJ-3000+ devices.
    /// Sent every 30ms on port 50001 while a track is loaded.
    /// Provides precise playhead position independent of beat grid.
    public struct PositionState: Equatable, Hashable, Sendable {
        /// The device ID sending this position update.
        public var deviceId: Int
        /// Track length in seconds (rounded down to nearest second).
        public var trackLength: Int
        /// Absolute playhead position in milliseconds.
        public var playhead: Int
        /// Pitch slider value as shown on screen.
        /// For example, 3.26% is represented as 3.26.
        public var pitch: Double
        /// Effective BPM (track BPM adjusted by pitch) as shown on screen.
        /// null if BPM is unknown.
        public var bpm: Double?

        public init(deviceId: Int, trackLength: Int, playhead: Int, pitch: Double, bpm: Double?) {
            self.deviceId = deviceId
            self.trackLength = trackLength
            self.playhead = playhead
            self.pitch = pitch
            self.bpm = bpm
        }
    }

    /// On-Air status from DJM mixer.
    /// Broadcast by the mixer to indicate which channels are currently audible.
    /// Supports both 4-channel (DJM-900/1000) and 6-channel (DJM-V10) mixers.
    public struct OnAirStatus: Equatable, Hashable, Sendable {
        /// The mixer device ID (typically 33 / 0x21).
        public var deviceId: Int
        /// On-air flags for channels 1-4 (always present).
        /// 0x00 = channel is off-air (silenced)
        /// 0x01 = channel is on-air (audible)
        ///
        /// 원본 `{1: boolean, …, 5?: boolean, 6?: boolean}`. 5·6은 6채널일 때만 있다.
        public var channels: [Int: Bool]
        /// Whether this is a 6-channel variant (CDJ-3000 + DJM-V10).
        /// Determined by packet subtype (0x00 = 4-channel, 0x03 = 6-channel).
        public var isSixChannel: Bool

        public init(deviceId: Int, channels: [Int: Bool], isSixChannel: Bool) {
            self.deviceId = deviceId
            self.channels = channels
            self.isSixChannel = isSixChannel
        }
    }

    /// 원본 `crossfaderAssign: 'thru' | 'A' | 'B'`.
    public enum CrossfaderAssign: String, Equatable, Hashable, Sendable {
        case thru
        case a = "A"
        case b = "B"
    }

    /// State of a single mixer channel fader, EQ, trim and routing.
    public struct ChannelState: Equatable, Hashable, Sendable {
        /// Input Trim level (0-255).
        /// Unity gain is typically 128 (0x80).
        public var trim: Int
        /// EQ High level (0-255).
        /// Fully cut at 0, unity at 128 (0x80), boosted to max at 255.
        public var eqHi: Int
        /// EQ Mid level (0-255).
        /// Fully cut at 0, unity at 128 (0x80), boosted to max at 255.
        public var eqMid: Int
        /// EQ Low level (0-255).
        /// Fully cut at 0, unity at 128 (0x80), boosted to max at 255.
        public var eqLow: Int
        /// Color FX knob position (0-255).
        /// Centered at 128 (0x80).
        public var colorFx: Int
        /// Channel fader position (0-255).
        /// 0 is completely closed, 255 is maximum level.
        public var fader: Int
        /// Crossfader assignment.
        public var crossfaderAssign: CrossfaderAssign

        public init(
            trim: Int,
            eqHi: Int,
            eqMid: Int,
            eqLow: Int,
            colorFx: Int,
            fader: Int,
            crossfaderAssign: CrossfaderAssign
        ) {
            self.trim = trim
            self.eqHi = eqHi
            self.eqMid = eqMid
            self.eqLow = eqLow
            self.colorFx = colorFx
            self.fader = fader
            self.crossfaderAssign = crossfaderAssign
        }
    }

    /// Full mixer control state parsed from Stagehand unicast status (0x39 packets).
    public struct MixerState: Equatable, Hashable, Sendable {
        /// The reporting device ID (typically 33).
        public var deviceId: Int
        /// Device name reported by the mixer (e.g. "DJM-A9").
        public var deviceName: String
        /// State of mixer channels (1-4).
        public var channels: [Int: ChannelState]
        /// Crossfader position (0-255).
        /// 0 is full-left (A), 255 is full-right (B).
        public var crossfader: Int

        public init(deviceId: Int, deviceName: String, channels: [Int: ChannelState], crossfader: Int) {
            self.deviceId = deviceId
            self.deviceName = deviceName
            self.channels = channels
            self.crossfader = crossfader
        }
    }

    /// A single audio VU level frame.
    public struct VUFrame: Equatable, Hashable, Sendable {
        /// Left channel level (0-65535).
        public var left: Int
        /// Right channel level (0-65535).
        public var right: Int

        public init(left: Int, right: Int) {
            self.left = left
            self.right = right
        }
    }

    /// Real-time sliding window audio level VU data parsed from Stagehand unicast packets (0x58).
    public struct VUState: Equatable, Hashable, Sendable {
        /// The reporting device ID (typically 33).
        public var deviceId: Int
        /// Array of 15 sliding window stereo VU level frames per channel (1-4).
        public var channels: [Int: [VUFrame]]

        public init(deviceId: Int, channels: [Int: [VUFrame]]) {
            self.deviceId = deviceId
            self.channels = channels
        }
    }
}
