import DJLinkExportSupport
import DJLinkKit
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-dbserver/src/catalog.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

public struct RootCategory: Equatable, Sendable {
    public var id: UInt32
    public var menu_item_id: UInt32
    public var disable: UInt32
    public var name: String
    public var item_type: UInt32
    public init(id: UInt32 = 0, menu_item_id: UInt32 = 0, disable: UInt32 = 0, name: String = "", item_type: UInt32 = 0)
    {
        self.id = id
        self.menu_item_id = menu_item_id
        self.disable = disable
        self.name = name
        self.item_type = item_type
    }
}

public struct TrackDetails: Equatable, Sendable {
    public var row: TrackRow
    public var comment: String
    public var key_id: UInt32
    public var key_name: String
    public var artist_id: UInt32
    public var artist: String
    public var album_id: UInt32
    public var album: String
    public var duration_s: UInt32
    public var rating: UInt32
    public var colour: UInt32
    public var genre_id: UInt32
    public var genre: String
    public var date_added: String
    public var year: UInt32
    public var bit_rate_kbps: UInt32
    public var label_id: UInt32
    public var label: String
    public var original_artist: String
    public var remixer: String
    public var path: String
    public var file_size: UInt32
    public var file_type: UInt32
    public init(
        row: TrackRow = TrackRow(), comment: String = "", key_id: UInt32 = 0, key_name: String = "",
        artist_id: UInt32 = 0, artist: String = "", album_id: UInt32 = 0, album: String = "", duration_s: UInt32 = 0,
        rating: UInt32 = 0, colour: UInt32 = 0, genre_id: UInt32 = 0, genre: String = "", date_added: String = "",
        year: UInt32 = 0, bit_rate_kbps: UInt32 = 0, label_id: UInt32 = 0, label: String = "",
        original_artist: String = "", remixer: String = "", path: String = "", file_size: UInt32 = 0,
        file_type: UInt32 = 0
    ) {
        self.row = row
        self.comment = comment
        self.key_id = key_id
        self.key_name = key_name
        self.artist_id = artist_id
        self.artist = artist
        self.album_id = album_id
        self.album = album
        self.duration_s = duration_s
        self.rating = rating
        self.colour = colour
        self.genre_id = genre_id
        self.genre = genre
        self.date_added = date_added
        self.year = year
        self.bit_rate_kbps = bit_rate_kbps
        self.label_id = label_id
        self.label = label
        self.original_artist = original_artist
        self.remixer = remixer
        self.path = path
        self.file_size = file_size
        self.file_type = file_type
    }
}

public struct HotCueBank: Equatable, Sendable {
    public var id: UInt32
    public var name: String
    public var folder: Bool
    public init(id: UInt32 = 0, name: String = "", folder: Bool = false) {
        self.id = id
        self.name = name
        self.folder = folder
    }
}

public struct HotCueBankCue: Equatable, Sendable {
    public var slot: UInt8
    public var content: UInt32
    public var in_ms: UInt32
    public var out_ms: UInt32?
    public var color: UInt32
    public var color_table_index: UInt32
    public var active_loop: Bool
    public var beat_loop_size: UInt32
    public var cue_microsec: UInt32
    public init(
        slot: UInt8 = 0, content: UInt32 = 0, in_ms: UInt32 = 0, out_ms: UInt32? = nil, color: UInt32 = 0,
        color_table_index: UInt32 = 0, active_loop: Bool = false, beat_loop_size: UInt32 = 0, cue_microsec: UInt32 = 0
    ) {
        self.slot = slot
        self.content = content
        self.in_ms = in_ms
        self.out_ms = out_ms
        self.color = color
        self.color_table_index = color_table_index
        self.active_loop = active_loop
        self.beat_loop_size = beat_loop_size
        self.cue_microsec = cue_microsec
    }
}

public struct PlayerCue: Equatable, Sendable {
    public var kind: UInt8
    public var in_ms: UInt32
    public var out_ms: UInt32?
    public var colour: UInt8?
    public var hot_colour: HotCueColour
    public var comment: String
    public var beat_loop: BeatLoop?
    public init(
        kind: UInt8 = 0, in_ms: UInt32 = 0, out_ms: UInt32? = nil, colour: UInt8? = nil,
        hot_colour: HotCueColour = .index(HOT_CUE_DEFAULT), comment: String = "", beat_loop: BeatLoop? = nil
    ) {
        self.kind = kind
        self.in_ms = in_ms
        self.out_ms = out_ms
        self.colour = colour
        self.hot_colour = hot_colour
        self.comment = comment
        self.beat_loop = beat_loop
    }
}

public struct UsbCue: Equatable, Sendable {
    public var slot: UInt8
    public var in_ms: UInt32
    public var out_ms: UInt32?
    public var color_table_index: UInt32
    public init(slot: UInt8 = 0, in_ms: UInt32 = 0, out_ms: UInt32? = nil, color_table_index: UInt32 = 0) {
        self.slot = slot
        self.in_ms = in_ms
        self.out_ms = out_ms
        self.color_table_index = color_table_index
    }
}

public struct MyTag: Equatable, Sendable {
    public var id: UInt32
    public var parent: UInt32
    public var seq: UInt32
    public var name: String
    public init(id: UInt32 = 0, parent: UInt32 = 0, seq: UInt32 = 0, name: String = "") {
        self.id = id
        self.parent = parent
        self.seq = seq
        self.name = name
    }
}

public struct BeatLoop: Equatable, Sendable {
    public var numerator: UInt16
    public var denominator: UInt16
    public init(_ numerator: UInt16, _ denominator: UInt16) {
        self.numerator = numerator
        self.denominator = denominator
    }
}
public enum Sort: Equatable, Hashable, Sendable {
    case `default`
    case alphabet
    case artist
    case album
    case bpm
    case rating
    case key
    case label
    case genre
    case dateAdded
    case djPlayCount
}

public enum TrackColumn: Equatable, Hashable, Sendable {
    case title
    case album
    case genre
    case artist
    case rating
    case duration
    case bpm
    case label
    case key
    case bitrate
    case color
    case comment
    case originalArtist
    case remixer
    case djPlayCount
    case dateAdded
}

public enum ArtistRole: Equatable, Hashable, Sendable {
    case original
    case remixer
}

public enum TrackScope: Equatable, Hashable, Sendable {
    case all
    case fileName
    case matching(UInt32)
    case bpm(bpm_x100: UInt32, tolerance_pct: UInt32)
    case rating(UInt32)
    case bitrate(UInt32)
    case color(UInt32)
    case durationMinute(UInt32)
    case releaseYear(decade: UInt32, year: UInt32?)
    case tagList
    case genre(genre: UInt32, artist: UInt32?, album: UInt32?)
    case label(label: UInt32, artist: UInt32?, album: UInt32?)
    case artistRole(role: ArtistRole, artist: UInt32, album: UInt32?)
    case artist(artist: UInt32, album: UInt32?)
    case album(UInt32)
    case key(key: UInt32, distance: UInt32)
    case playlist(UInt32)
    case history(UInt32)
    case dateAdded(year: UInt32, month: UInt32?, day: UInt32?)
    case search(String)
}

public enum Query: Equatable, Hashable, Sendable {
    case bpmBuckets
    case ratings
    case bitrates
    case colors
    case durationMinutes
    case releaseDecades
    case releaseYears(UInt32)
    case genres(Sort)
    case genreArtists(UInt32)
    case genreArtistAlbums(genre: UInt32, artist: UInt32?)
    case labels(Sort)
    case labelArtists(UInt32)
    case labelArtistAlbums(label: UInt32, artist: UInt32?)
    case artistRoleArtists(ArtistRole)
    case artistRoleAlbums(role: ArtistRole, artist: UInt32)
    case artists(Sort)
    case albums(Sort)
    case artistAlbums(UInt32)
    case folder(UInt32)
    case histories
    case years
    case months(UInt32)
    case days(year: UInt32, month: UInt32)
    case tracks(scope: TrackScope, sort: Sort)
}

public enum Row: Equatable, Sendable {
    case named(id: UInt32, name: String)
    case list(id: UInt32, name: String, folder: Bool, position: UInt32)
    case date(UInt32)
    case track(id: UInt32, position: UInt32)
}

public enum HotCueColour: Equatable, Sendable {
    case index(UInt8)
    case rgb([UInt8])
}

public enum Analysis: Equatable, Hashable, Sendable {
    case tag(fourcc: [UInt8], extension_: [UInt8])
    case beatGrid
    case vbr
    case extendedCueList
    case waveformPreview
    case waveformDetail
}

public enum Edit: Equatable, Sendable {
    case tag(track: UInt32, add: Bool)
    case clearTags
    case rating(track: UInt32, stars: UInt8)
    case gridOffset(track: UInt32, offset_ms: Int16)
    case hotCueBankCue(bank: UInt32, cue: HotCueBankCue)
    case historyAdd(track: UInt32)
    case historyRemove(track: UInt32)
    case historyDelete(history: UInt32)
    case saveCue(track: UInt32, cue: PlayerCue)
    case deleteCue(track: UInt32, cue: PlayerCue)
}

public let HOT_CUE_DEFAULT: UInt8 = 0x15
public let HOT_LOOP_DEFAULT: UInt8 = 0x24

extension RootCategory {
    public static func defaults() -> [Self] {
        let rows: [(UInt32, UInt32, UInt32, String, UInt32)] = [
            (2, 2, 0, "ARTIST", 0x81), (3, 3, 0, "ALBUM", 0x82), (4, 4, 0, "TRACK", 0x83), (12, 11, 0, "KEY", 0x8b),
            (5, 17, 0, "PLAYLIST", 0x84), (22, 19, 0, "HISTORY", 0x95), (18, 20, 0, "SEARCH", 0x91),
            (26, 27, 2, "MATCHING", 0xaa), (17, 24, 0, "FOLDER", 0x90), (27, 22, 0, "DATE ADDED", 0x8c),
        ]
        return rows.map {
            Self(
                id: UInt32($0.0), menu_item_id: UInt32($0.1), disable: UInt32($0.2), name: $0.3, item_type: UInt32($0.4)
            )
        }
    }
}
extension TrackColumn {
    public static func from_id(_ id: UInt32) -> Self {
        [
            2: .artist, 3: .album, 4: .bpm, 5: .rating, 6: .genre, 7: .comment, 8: .duration, 9: .remixer, 10: .label,
            11: .originalArtist, 12: .key, 13: .bitrate, 15: .color, 16: .djPlayCount, 17: .dateAdded,
        ][id] ?? .title
    }
}
extension Sort {
    public static let DEFAULTS: [Self] = [.default, .alphabet, .artist, .album, .bpm, .rating, .key]
    public static func from_id(_ id: UInt32) -> Self {
        [
            1: .alphabet, 2: .artist, 3: .album, 4: .bpm, 5: .rating, 6: .genre, 0xa: .label, 0xc: .key,
            0x10: .djPlayCount, 0x11: .dateAdded,
        ][id] ?? .default
    }
    public func track_column() -> TrackColumn? {
        switch self {
        case .default, .alphabet: return nil
        case .artist: return .artist
        case .album: return .album
        case .bpm: return .bpm
        case .rating: return .rating
        case .key: return .key
        case .label: return .label
        case .genre: return .genre
        case .dateAdded: return .dateAdded
        case .djPlayCount: return .djPlayCount
        }
    }
}
@DJLinkActor public protocol Catalog: AnyObject {
    func root_categories() -> [RootCategory]
    func sorts() -> [Sort]
    func key_ids() -> [UInt32]
    func key_name(_ id: UInt32) -> String
    func list(_ query: Query) -> [Row]
    func listed(_ scope: TrackScope) -> Bool
    func track_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow?
    func file_name_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow?
    func track(_ id: UInt32) -> TrackDetails?
    func artwork(_ id: UInt32) -> [UInt8]?
    func item_artwork(_ id: UInt32) -> [UInt8]?
    func analysis(_ track: UInt32, _ what: Analysis) -> [UInt8]?
    func hot_cue_banks(_ parent: UInt32?) -> [HotCueBank]
    func hot_cue_bank_cues(_ bank: UInt32) -> [HotCueBankCue]
    func hot_cue_bank_tracks(_ bank: UInt32) -> [TrackRow]
    func usb_cues(_ track: UInt32) -> [UsbCue]
    func grid_offset(_ track: UInt32) -> Int16
    func edit(_ edit: Edit) -> Bool
    func tagged(_ track: UInt32) -> Bool
    func my_tags() -> [MyTag]
    func track_my_tags(_ track: UInt32) -> [UInt32]
    func my_tags_in_use() -> Set<UInt32>
    func filter_rows(_ rows: inout [Row], _ filter: TrackFilter)
    func played(_ track: UInt32) -> Bool
}
extension Catalog {
    public func root_categories() -> [RootCategory] { RootCategory.defaults() }
    public func sorts() -> [Sort] { Sort.DEFAULTS }
    public func key_ids() -> [UInt32] { Array(1...24) }
    public func key_name(_ id: UInt32) -> String { keys.name(id) }
    public func listed(_ scope: TrackScope) -> Bool {
        switch scope {
        case .genre, .label, .artist, .album, .playlist, .tagList: return true
        default: return false
        }
    }
    public func file_name_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? { track_row(id, column) }
    public func hot_cue_banks(_ parent: UInt32?) -> [HotCueBank] { [] }
    public func hot_cue_bank_cues(_ bank: UInt32) -> [HotCueBankCue] { [] }
    public func hot_cue_bank_tracks(_ bank: UInt32) -> [TrackRow] { [] }
    public func usb_cues(_ track: UInt32) -> [UsbCue] { [] }
    public func grid_offset(_ track: UInt32) -> Int16 { 0 }
    public func edit(_ edit: Edit) -> Bool { false }
    public func tagged(_ track: UInt32) -> Bool { false }
    public func my_tags() -> [MyTag] { [] }
    public func track_my_tags(_ track: UInt32) -> [UInt32] { [] }
    public func my_tags_in_use() -> Set<UInt32> { [] }
    public func played(_ track: UInt32) -> Bool { false }
    public func filter_rows(_ rows: inout [Row], _ filter: TrackFilter) {
        guard filter.enabled else { return }
        let tags = filter.has_my_tag_conditions()
        rows.removeAll { row in
            guard case let .track(id, _) = row else { return false }
            guard let t = track(id) else { return true }
            return
                !(filter.matches(t.row.bpm_x100, t.row.key, t.rating, t.colour)
                && (!tags || filter.matches_my_tags(track_my_tags(id))))
        }
    }
}
