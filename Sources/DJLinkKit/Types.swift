import Foundation

// 원본 src/types.ts
// 선(wire)에서 읽는 숫자 enum은 원본처럼 모르는 값도 담을 수 있게 RawRepresentable 구조체로 옮긴다
// (docs/porting-guide.md "enum"). `CDJStatus` 이름 공간은 Status/StatusTypes.swift에 있다.

/// Known device types on the network
public struct DeviceType: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let cdj = DeviceType(rawValue: 0x01)
    public static let mixer = DeviceType(rawValue: 0x03)
    public static let rekordbox = DeviceType(rawValue: 0x04)
    public static let stagehand = DeviceType(rawValue: 0x05)

    /// 원본 enum의 키 이름(모르는 값이면 nil).
    public var jsName: String? {
        switch rawValue {
        case 0x01: "CDJ"
        case 0x03: "Mixer"
        case 0x04: "Rekordbox"
        case 0x05: "Stagehand"
        default: nil
        }
    }

    public var description: String { jsName ?? String(rawValue) }
}

/// The 8-bit identifier of the device on the network
public typealias DeviceID = Int

/// Represents a device on the prolink network.
public struct Device: Equatable, Hashable, Sendable {
    public var name: String
    public var id: DeviceID
    public var type: DeviceType
    public var macAddr: [UInt8]
    public var ip: Address4
    public var lastActive: Date?

    public init(name: String, id: DeviceID, type: DeviceType, macAddr: [UInt8], ip: Address4, lastActive: Date? = nil) {
        self.name = name
        self.id = id
        self.type = type
        self.macAddr = macAddr
        self.ip = ip
        self.lastActive = lastActive
    }
}

/// Details of a particular media slot on the CDJ
public struct MediaSlotInfo: Equatable, Sendable {
    /// The device the slot physically exists on
    public var deviceId: DeviceID
    /// The slot type
    public var slot: MediaSlot
    /// The name of the media connected
    public var name: String
    /// The rekordbox configured color of the media connected
    public var color: MediaColor
    /// Creation date
    public var createdDate: Date
    /// Number of free bytes available on the media
    public var freeBytes: UInt64
    /// Number of bytes used on the media
    public var totalBytes: UInt64
    /// Specifies the available tracks type on the media
    public var tracksType: TrackType
    /// Total number of rekordbox tracks on the media. Will be zero if there is
    /// no rekordbox database on the media
    public var trackCount: Int
    /// Same as track count, except for playlists
    public var playlistCount: Int
    /// True when a rekordbox 'my settings' file has been exported to the media
    public var hasSettings: Bool

    public init(
        deviceId: DeviceID,
        slot: MediaSlot,
        name: String,
        color: MediaColor,
        createdDate: Date,
        freeBytes: UInt64,
        totalBytes: UInt64,
        tracksType: TrackType,
        trackCount: Int,
        playlistCount: Int,
        hasSettings: Bool
    ) {
        self.deviceId = deviceId
        self.slot = slot
        self.name = name
        self.color = color
        self.createdDate = createdDate
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.tracksType = tracksType
        self.trackCount = trackCount
        self.playlistCount = playlistCount
        self.hasSettings = hasSettings
    }
}

public struct MediaColor: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let `default` = MediaColor(rawValue: 0x00)
    public static let pink = MediaColor(rawValue: 0x01)
    public static let red = MediaColor(rawValue: 0x02)
    public static let orange = MediaColor(rawValue: 0x03)
    public static let yellow = MediaColor(rawValue: 0x04)
    public static let green = MediaColor(rawValue: 0x05)
    public static let aqua = MediaColor(rawValue: 0x06)
    public static let blue = MediaColor(rawValue: 0x07)
    public static let purple = MediaColor(rawValue: 0x08)

    public var description: String { "MediaColor(\(rawValue))" }
}

/// A slot where media is present on the CDJ
public struct MediaSlot: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let empty = MediaSlot(rawValue: 0x00)
    public static let cd = MediaSlot(rawValue: 0x01)
    public static let sd = MediaSlot(rawValue: 0x02)
    public static let usb = MediaSlot(rawValue: 0x03)
    public static let rb = MediaSlot(rawValue: 0x04)
    /// Possibly TIDAL, Apple Music, or other streaming
    public static let unknown05 = MediaSlot(rawValue: 0x05)
    public static let streamingDirectPlay = MediaSlot(rawValue: 0x06)
    /// Possibly TIDAL, Apple Music, or other streaming
    public static let unknown07 = MediaSlot(rawValue: 0x07)
    /// Possibly TIDAL, Apple Music, or other streaming
    public static let unknown08 = MediaSlot(rawValue: 0x08)
    public static let beatport = MediaSlot(rawValue: 0x09)

    /// 원본 enum의 키 이름(모르는 값이면 nil).
    public var jsName: String? {
        switch rawValue {
        case 0x00: "Empty"
        case 0x01: "CD"
        case 0x02: "SD"
        case 0x03: "USB"
        case 0x04: "RB"
        case 0x05: "Unknown05"
        case 0x06: "StreamingDirectPlay"
        case 0x07: "Unknown07"
        case 0x08: "Unknown08"
        case 0x09: "Beatport"
        default: nil
        }
    }

    public var description: String { jsName ?? String(rawValue) }
}

/// Track type flags
public struct TrackType: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let none = TrackType(rawValue: 0x00)
    public static let rb = TrackType(rawValue: 0x01)
    public static let unanalyzed = TrackType(rawValue: 0x02)
    public static let audioCD = TrackType(rawValue: 0x05)
    public static let streaming = TrackType(rawValue: 0x06)

    /// 원본 enum의 키 이름(모르는 값이면 nil).
    public var jsName: String? {
        switch rawValue {
        case 0x00: "None"
        case 0x01: "RB"
        case 0x02: "Unanalyzed"
        case 0x05: "AudioCD"
        case 0x06: "Streaming"
        default: nil
        }
    }

    public var description: String { jsName ?? String(rawValue) }
}

/// A beat grid is a series of offsets from the start of the track. Each offset
/// indicates what count within the measure it is along with the BPM.
public struct BeatGridBeat: Equatable, Hashable, Sendable {
    /// Offset from the beginning of track in milliseconds of this beat.
    public var offset: Double
    /// The count of this particular beat within the measure (1-4)
    public var count: Int
    /// The BPM at this beat.
    public var bpm: Double

    public init(offset: Double, count: Int, bpm: Double) {
        self.offset = offset
        self.count = count
        self.bpm = bpm
    }
}

public typealias BeatGrid = [BeatGridBeat]

/// A waveform segment contains a height and 'whiteness' value.
public struct WaveformSegment: Equatable, Hashable, Sendable {
    /// The height this segment in the waveform. Ranges from 0 - 31.
    public var height: Int
    /// The level of "whiteness" of the waveform. 0 being completely blue, and 1
    /// being completely white.
    public var whiteness: Double

    public init(height: Int, whiteness: Double) {
        self.height = height
        self.whiteness = whiteness
    }
}

/// A HD waveform segment contains the height of the waveform, and it's color
/// represented as RGB values.
public struct WaveformHDSegment: Equatable, Hashable, Sendable {
    /// The height this segment in the waveform. Ranges from 0 - 31.
    public var height: Int
    /// the RGB value, each channel ranges from 0-1 for the segment. 항상 세 개.
    public var color: [Double]

    public init(height: Int, color: [Double]) {
        self.height = height
        self.color = color
    }
}

/// The waveform preview will be 400 segments of data.
public typealias WaveformPreview = [WaveformSegment]

/// Detailed waveforms have 150 segments per second of audio (150 'half frames'
/// per second of audio).
public typealias WaveformDetailed = [WaveformSegment]

/// HD waveforms have 150 segments per second of audio (150 'half frames' per
/// second of audio).
public typealias WaveformHD = [WaveformHDSegment]

/// The result of looking up track waveforms
public struct Waveforms: Equatable, Sendable {
    /// The full-size and full-color waveform
    public var waveformHd: WaveformHD?
    /// Color waveform preview (PWV4 tag).
    /// Raw bytes: 1200 columns × 6 bytes per column (3 frequency bands × 2 bytes each).
    public var waveformColorPreview: [UInt8]?
    /// Standard waveform preview (400 entries). Available for streaming tracks.
    public var waveformPreview: WaveformPreview?
    /// Full detailed waveform. Available for streaming tracks.
    public var waveformDetailed: WaveformDetailed?
    /// 원본 RemoteDB 미리보기의 undefined 높이를 그대로 보존한다.
    public var rawWaveformPreview: RemoteDBWaveformPreview?

    public init(
        waveformHd: WaveformHD?,
        waveformColorPreview: [UInt8]? = nil,
        waveformPreview: WaveformPreview? = nil,
        waveformDetailed: WaveformDetailed? = nil,
        rawWaveformPreview: RemoteDBWaveformPreview? = nil
    ) {
        self.waveformHd = waveformHd
        self.waveformColorPreview = waveformColorPreview
        self.waveformPreview = waveformPreview
        self.waveformDetailed = waveformDetailed
        self.rawWaveformPreview = rawWaveformPreview
    }
}

/// Extended cue with color and comment support (PCO2 tag from rekordbox).
/// Includes additional metadata like RGB colors, comments, and quantized loop information.
public struct ExtendedCue: Equatable, Sendable {
    public struct RGB: Equatable, Hashable, Sendable {
        public var r: Int
        public var g: Int
        public var b: Int

        public init(r: Int, g: Int, b: Int) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    /// Hot cue number (0 for memory points, 1-8 for hot cues A-H)
    public var hotCue: Int
    /// Type of cue: 1 = simple position/cue, 2 = loop
    public var type: Int
    /// Position in milliseconds from the start of the track
    public var time: Double
    /// For loops, the end position in milliseconds
    public var loopTime: Double?
    /// Color ID referencing the color table (for memory points/loops)
    public var colorId: Int?
    /// Color code for the hot cue palette (0x00 = default green, 0x01-0x3e = palette colors)
    public var colorCode: Int?
    /// RGB color values used to illuminate the player's RGB LEDs
    public var colorRgb: RGB?
    /// User-assigned comment text for the cue
    public var comment: String?
    /// For quantized loops, the numerator of the loop size fraction (e.g., 4 for a 4-beat loop)
    public var loopNumerator: Int?
    /// For quantized loops, the denominator of the loop size fraction (e.g., 1 for a 4-beat loop)
    public var loopDenominator: Int?

    public init(
        hotCue: Int,
        type: Int,
        time: Double,
        loopTime: Double? = nil,
        colorId: Int? = nil,
        colorCode: Int? = nil,
        colorRgb: RGB? = nil,
        comment: String? = nil,
        loopNumerator: Int? = nil,
        loopDenominator: Int? = nil
    ) {
        self.hotCue = hotCue
        self.type = type
        self.time = time
        self.loopTime = loopTime
        self.colorId = colorId
        self.colorCode = colorCode
        self.colorRgb = colorRgb
        self.comment = comment
        self.loopNumerator = loopNumerator
        self.loopDenominator = loopDenominator
    }
}

/// A phrase within a track's song structure
public struct Phrase: Equatable, Sendable {
    /// Sequential phrase number starting from 1
    public var index: Int
    /// Beat number where this phrase begins
    public var beat: Int
    /// Raw phrase kind value from rekordbox
    public var kind: Int
    /// Human-readable phrase type (e.g., "Intro", "Verse 1", "Chorus")
    public var phraseType: String
    /// Whether this phrase has a fill-in section (non-zero if present)
    public var fill: Int?
    /// Beat number where the fill-in begins (if present)
    public var fillBeat: Int?

    public init(index: Int, beat: Int, kind: Int, phraseType: String, fill: Int? = nil, fillBeat: Int? = nil) {
        self.index = index
        self.beat = beat
        self.kind = kind
        self.phraseType = phraseType
        self.fill = fill
        self.fillBeat = fillBeat
    }
}

/// Song structure / phrase analysis (PSSI tag from rekordbox).
/// Used by CDJ-3000 players for phrase-based navigation and lighting control.
public struct SongStructure: Equatable, Sendable {
    /// Overall mood classification of the track
    public enum Mood: String, Equatable, Hashable, Sendable {
        case high
        case mid
        case low
    }

    /// Stylistic bank assigned for lighting control
    public enum Bank: String, Equatable, Hashable, Sendable {
        case `default`
        case cool
        case natural
        case hot
        case subtle
        case warm
        case vivid
        case club_1
        case club_2
    }

    public var mood: Mood
    public var bank: Bank
    /// Beat number where the last phrase ends (track may continue after this)
    public var endBeat: Int
    /// List of identified phrases in the track
    public var phrases: [Phrase]

    public init(mood: Mood, bank: Bank, endBeat: Int, phrases: [Phrase]) {
        self.mood = mood
        self.bank = bank
        self.endBeat = endBeat
        self.phrases = phrases
    }
}

/// 3-band color waveform preview (PWV6 tag from .2EX files).
/// Same resolution as PWV4 (typically 1200 entries) but with separate
/// low, mid, and high frequency band amplitudes.
public struct Waveform3BandPreview: Equatable, Sendable {
    public var numEntries: Int
    /// Raw interleaved bytes: numEntries × 3 (low, mid, high per entry)
    public var data: [UInt8]

    public init(numEntries: Int, data: [UInt8]) {
        self.numEntries = numEntries
        self.data = data
    }
}

/// 3-band color detail waveform (PWV7 tag from .2EX files).
/// Higher resolution than PWV6, approximately 150 entries per second.
public struct Waveform3BandDetail: Equatable, Sendable {
    public var numEntries: Int
    /// Raw interleaved bytes: numEntries × 3 (low, mid, high per entry)
    public var data: [UInt8]

    public init(numEntries: Int, data: [UInt8]) {
        self.numEntries = numEntries
        self.data = data
    }
}

/// Vocal detection configuration (PWVC tag from .2EX files).
/// Threshold values used to classify frequency content as vocal or non-vocal.
///
/// Values are u16 but observed range across 192 real files is 80-159,
/// matching the 0-255 byte scale used by waveform band values.
/// Observed ranges: low 80-114, mid 80-146, high 98-159.
public struct VocalConfig: Equatable, Hashable, Sendable {
    public var thresholdLow: Int
    public var thresholdMid: Int
    public var thresholdHigh: Int

    public init(thresholdLow: Int, thresholdMid: Int, thresholdHigh: Int) {
        self.thresholdLow = thresholdLow
        self.thresholdMid = thresholdMid
        self.thresholdHigh = thresholdHigh
    }
}

/// Monochrome waveform preview data (PWAV/PWV2 tags).
/// PWAV contains 400 bytes, PWV2 contains 100 bytes.
public struct WaveformPreviewData: Equatable, Sendable {
    /// Raw waveform data - each byte encodes height and whiteness
    public var data: [UInt8]

    public init(data: [UInt8]) {
        self.data = data
    }
}

/// 원본 `tracks`(`{[Symbol.asyncIterator]: iterateTracks}`). 순회를 시작할 때마다 처음부터 새로 조회한다.
public struct PlaylistTracks: AsyncSequence, Sendable {
    public typealias Element = Track
    public typealias Failure = any Error

    private let makeStream: @Sendable () -> AsyncThrowingStream<Track, any Error>

    /// `makeStream`은 순회마다 불려 새 스트림을 만든다.
    public init(_ makeStream: @escaping @Sendable () -> AsyncThrowingStream<Track, any Error>) {
        self.makeStream = makeStream
    }

    public func makeAsyncIterator() -> AsyncThrowingStream<Track, any Error>.AsyncIterator {
        makeStream().makeAsyncIterator()
    }
}

/// Represents the contents of a playlist
public struct PlaylistContents: Sendable {
    /// The playlists in this playlist.
    public var playlists: [Playlist]
    /// The folders in this playlist.
    public var folders: [Playlist]
    /// The tracks in this playlist. This is an AsyncIterator as looking up track
    /// metadata may be slow when connected to the remote database.
    public var tracks: PlaylistTracks
    /// The total number of tracks in this playlist.
    public var totalTracks: Int

    public init(
        playlists: [Playlist],
        folders: [Playlist],
        tracks: PlaylistTracks,
        totalTracks: Int
    ) {
        self.playlists = playlists
        self.folders = folders
        self.tracks = tracks
        self.totalTracks = totalTracks
    }
}

public enum NetworkState: Int, Equatable, Hashable, Sendable {
    /// The network is offline when we don't have an open connection to the network
    /// (no connection to the announcement and or status UDP socket is present).
    case offline
    /// The network is online when we have opened sockets to the network, but have
    /// not yet started announcing ourselves as a virtual CDJ.
    case online
    /// The network is connected once we have heard from another device on the network
    case connected
    /// The network may have failed to connect if we aren't able to open the
    /// announcement and or status UDP socket.
    case failed
}

/// Mixstatus reporting modes specify how the mixstatus processor will determine when a new
/// track is 'now playing'.
public enum MixstatusMode: Int, Equatable, Hashable, Sendable {
    /// Tracks will be smartly marked as playing following rules:
    ///
    /// - The track that has been in the play state with the CDJ in the "on air" state
    ///   for the longest period of time (allowing for a configurable length of
    ///   interruption with allowedInterruptBeats) is considered to be the active
    ///   track that incoming tracks will be compared against.
    ///
    /// - A incoming track will immediately be reported as nowPlaying if it is on
    ///   air, playing, and the last active track has been cued.
    ///
    /// - A incoming track will be reported as nowPlaying if the active track has
    ///   not been on air or has not been playing for the configured
    ///   allowedInterruptBeats.
    ///
    /// - A incoming track will be reported as nowPlaying if it has played
    ///   consecutively (with allowedInterruptBeats honored for the incoming track)
    ///   for the configured beatsUntilReported.
    case smartTiming
    /// Tracks will not be reported after the beatsUntilReported AND will ONLY
    /// be reported if the other track has gone into a non-playing play state, or
    /// taken off air (when useOnAirStatus is enabled).
    case waitsForSilence
    /// The track will simply be reported only after the player becomes master.
    case followsMaster
}
