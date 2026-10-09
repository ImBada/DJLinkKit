import Foundation

// 원본 onelibrary-connect src/entities.ts, src/types.ts
// TS의 `Track<EntityFK.WithFKs>`처럼 형 인자로 모양을 바꾸는 형은 두 형으로 나눈다
// (`Track`/`TrackWithFKs`, `PlaylistEntry`/`PlaylistEntryWithFKs`).

/// Documentation type strictly for use with entities that have foreign key
/// attributes.
public enum EntityFK: Sendable {
    case withFKs
    case withRelations
}

public struct Artwork: Equatable, Hashable, Sendable {
    public var id: Int
    public var path: String?

    public init(id: Int, path: String? = nil) {
        self.id = id
        self.path = path
    }
}

/// `{id, name}` 모양의 엔티티(Key, Label, Color, Genre, Album, Artist)가 함께 따르는 모양.
public protocol NamedEntity: Equatable, Hashable, Sendable {
    var id: Int { get set }
    var name: String { get set }
    init(id: Int, name: String)
}

public struct Key: NamedEntity {
    public var id: Int
    public var name: String
    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Label: NamedEntity {
    public var id: Int
    public var name: String
    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Color: NamedEntity {
    public var id: Int
    public var name: String
    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Genre: NamedEntity {
    public var id: Int
    public var name: String
    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Album: NamedEntity {
    public var id: Int
    public var name: String
    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Artist: NamedEntity {
    public var id: Int
    public var name: String
    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Playlist: Equatable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var isFolder: Bool
    public var parentId: Int?

    public init(id: Int, name: String, isFolder: Bool, parentId: Int?) {
        self.id = id
        self.name = name
        self.isFolder = isFolder
        self.parentId = parentId
    }
}

/// `PlaylistEntry<EntityFK.WithRelations>`
public struct PlaylistEntry: Equatable, Sendable {
    public var id: Int
    public var sortIndex: Int
    public var track: Track

    public init(id: Int, sortIndex: Int, track: Track) {
        self.id = id
        self.sortIndex = sortIndex
        self.track = track
    }
}

/// `PlaylistEntry<EntityFK.WithFKs>`
public struct PlaylistEntryWithFKs: Equatable, Hashable, Sendable {
    public var id: Int
    public var sortIndex: Int
    public var playlistId: Int
    public var trackId: Int

    public init(id: Int, sortIndex: Int, playlistId: Int, trackId: Int) {
        self.id = id
        self.sortIndex = sortIndex
        self.playlistId = playlistId
        self.trackId = trackId
    }
}

/// `Track<EntityFK.WithFKs>`: 관계 대신 FK 번호를 가진다.
public struct TrackWithFKs: Equatable, Sendable {
    public var id: Int
    public var title: String
    public var duration: Int
    public var bitrate: Int?
    public var tempo: Double
    public var rating: Int
    public var comment: String
    public var filePath: String
    public var fileName: String
    public var trackNumber: Int?
    public var discNumber: Int?
    public var sampleRate: Int?
    public var sampleDepth: Int?
    public var playCount: Int?
    public var year: Int?
    public var mixName: String?
    public var autoloadHotcues: Bool?
    public var kuvoPublic: Bool?
    public var fileSize: Int?
    public var analyzePath: String?
    public var releaseDate: String?
    public var analyzeDate: Date?
    public var dateAdded: Date?
    public var artworkId: Int?
    public var artistId: Int?
    public var originalArtistId: Int?
    public var remixerId: Int?
    public var composerId: Int?
    public var albumId: Int?
    public var labelId: Int?
    public var genreId: Int?
    public var colorId: Int?
    public var keyId: Int?
    /// Embedded cue and loop information from the database
    public var cueAndLoops: [CueAndLoop]?

    public init(
        id: Int,
        title: String,
        duration: Int,
        bitrate: Int? = nil,
        tempo: Double,
        rating: Int,
        comment: String,
        filePath: String,
        fileName: String,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        sampleRate: Int? = nil,
        sampleDepth: Int? = nil,
        playCount: Int? = nil,
        year: Int? = nil,
        mixName: String? = nil,
        autoloadHotcues: Bool? = nil,
        kuvoPublic: Bool? = nil,
        fileSize: Int? = nil,
        analyzePath: String? = nil,
        releaseDate: String? = nil,
        analyzeDate: Date? = nil,
        dateAdded: Date? = nil,
        artworkId: Int? = nil,
        artistId: Int? = nil,
        originalArtistId: Int? = nil,
        remixerId: Int? = nil,
        composerId: Int? = nil,
        albumId: Int? = nil,
        labelId: Int? = nil,
        genreId: Int? = nil,
        colorId: Int? = nil,
        keyId: Int? = nil,
        cueAndLoops: [CueAndLoop]? = nil
    ) {
        self.id = id
        self.title = title
        self.duration = duration
        self.bitrate = bitrate
        self.tempo = tempo
        self.rating = rating
        self.comment = comment
        self.filePath = filePath
        self.fileName = fileName
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.sampleRate = sampleRate
        self.sampleDepth = sampleDepth
        self.playCount = playCount
        self.year = year
        self.mixName = mixName
        self.autoloadHotcues = autoloadHotcues
        self.kuvoPublic = kuvoPublic
        self.fileSize = fileSize
        self.analyzePath = analyzePath
        self.releaseDate = releaseDate
        self.analyzeDate = analyzeDate
        self.dateAdded = dateAdded
        self.artworkId = artworkId
        self.artistId = artistId
        self.originalArtistId = originalArtistId
        self.remixerId = remixerId
        self.composerId = composerId
        self.albumId = albumId
        self.labelId = labelId
        self.genreId = genreId
        self.colorId = colorId
        self.keyId = keyId
        self.cueAndLoops = cueAndLoops
    }
}

/// A hotcue button label
public struct HotcueButton: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let A = HotcueButton(rawValue: 1)
    public static let B = HotcueButton(rawValue: 2)
    public static let C = HotcueButton(rawValue: 3)
    public static let D = HotcueButton(rawValue: 4)
    public static let E = HotcueButton(rawValue: 5)
    public static let F = HotcueButton(rawValue: 6)
    public static let G = HotcueButton(rawValue: 7)
    public static let H = HotcueButton(rawValue: 8)

    public var description: String { "HotcueButton(\(rawValue))" }
}

/// When a custom color is not configured the cue point will be one of these
/// colors.
public struct CueColor: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let none = CueColor(rawValue: 0x00)
    public static let blank = CueColor(rawValue: 0x15)
    public static let magenta = CueColor(rawValue: 0x31)
    public static let violet = CueColor(rawValue: 0x38)
    public static let fuchsia = CueColor(rawValue: 0x3c)
    public static let lightSlateBlue = CueColor(rawValue: 0x3e)
    public static let blue = CueColor(rawValue: 0x01)
    public static let steelBlue = CueColor(rawValue: 0x05)
    public static let aqua = CueColor(rawValue: 0x09)
    public static let seaGreen = CueColor(rawValue: 0x0e)
    public static let teal = CueColor(rawValue: 0x12)
    public static let green = CueColor(rawValue: 0x16)
    public static let lime = CueColor(rawValue: 0x1a)
    public static let olive = CueColor(rawValue: 0x1e)
    public static let yellow = CueColor(rawValue: 0x20)
    public static let orange = CueColor(rawValue: 0x26)
    public static let red = CueColor(rawValue: 0x2a)
    public static let pink = CueColor(rawValue: 0x2d)

    public var description: String { "CueColor(\(rawValue))" }
}

/// Represents a single cue point. On older exports the label and color may be
/// undefined.
public struct CuePoint: Equatable, Sendable {
    /// Number of milliseconds from the start of the track.
    public var offset: Double
    /// The comment associated to the cue point
    public var label: String?
    /// RGB values of the hotcue color
    public var color: CueColor?

    public init(offset: Double, label: String? = nil, color: CueColor? = nil) {
        self.offset = offset
        self.label = label
        self.color = color
    }
}

/// A loop, similar to a cue point, but includes a length.
public struct Loop: Equatable, Sendable {
    public var offset: Double
    public var label: String?
    public var color: CueColor?
    /// The length in milliseconds of the loop
    public var length: Double

    public init(offset: Double, label: String? = nil, color: CueColor? = nil, length: Double) {
        self.offset = offset
        self.label = label
        self.color = color
        self.length = length
    }
}

/// A hotcue is like a cue point, but also includes the button it is assigned to.
public struct Hotcue: Equatable, Sendable {
    public var offset: Double
    public var label: String?
    public var color: CueColor?
    /// Which hotcue button this hotcue is assigned to.
    public var button: HotcueButton

    public init(offset: Double, label: String? = nil, color: CueColor? = nil, button: HotcueButton) {
        self.offset = offset
        self.label = label
        self.color = color
        self.button = button
    }
}

/// A hot loop, this is the union of a hotcue and a loop.
public struct Hotloop: Equatable, Sendable {
    public var offset: Double
    public var label: String?
    public var color: CueColor?
    public var button: HotcueButton
    public var length: Double

    public init(
        offset: Double,
        label: String? = nil,
        color: CueColor? = nil,
        button: HotcueButton,
        length: Double
    ) {
        self.offset = offset
        self.label = label
        self.color = color
        self.button = button
        self.length = length
    }
}

/// `CuePoint | Loop | Hotcue | Hotloop`. 원본의 `type` 판별 문자열은 `type`으로 읽는다.
public enum CueAndLoop: Equatable, Sendable {
    case cuePoint(CuePoint)
    case loop(Loop)
    case hotCue(Hotcue)
    case hotLoop(Hotloop)

    /// 원본의 `type`: 'cue_point' | 'loop' | 'hot_cue' | 'hot_loop'
    public var type: String {
        switch self {
        case .cuePoint: "cue_point"
        case .loop: "loop"
        case .hotCue: "hot_cue"
        case .hotLoop: "hot_loop"
        }
    }

    public var offset: Double {
        switch self {
        case let .cuePoint(c): c.offset
        case let .loop(c): c.offset
        case let .hotCue(c): c.offset
        case let .hotLoop(c): c.offset
        }
    }

    public var label: String? {
        switch self {
        case let .cuePoint(c): c.label
        case let .loop(c): c.label
        case let .hotCue(c): c.label
        case let .hotLoop(c): c.label
        }
    }

    public var color: CueColor? {
        switch self {
        case let .cuePoint(c): c.color
        case let .loop(c): c.color
        case let .hotCue(c): c.color
        case let .hotLoop(c): c.color
        }
    }

    /// 루프면 길이, 아니면 nil(원본에서 `length`가 없는 경우).
    public var length: Double? {
        switch self {
        case let .loop(c): c.length
        case let .hotLoop(c): c.length
        case .cuePoint, .hotCue: nil
        }
    }

    /// 핫 큐면 버튼, 아니면 nil.
    public var button: HotcueButton? {
        switch self {
        case let .hotCue(c): c.button
        case let .hotLoop(c): c.button
        case .cuePoint, .loop: nil
        }
    }
}

// MARK: - OneLibrary-specific entity types

/// User-created tag (MyTag)
public struct MyTag: Equatable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var isFolder: Bool
    public var parentId: Int?

    public init(id: Int, name: String, isFolder: Bool, parentId: Int?) {
        self.id = id
        self.name = name
        self.isFolder = isFolder
        self.parentId = parentId
    }
}

/// History session
public struct HistorySession: Equatable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var parentId: Int?

    public init(id: Int, name: String, parentId: Int?) {
        self.id = id
        self.name = name
        self.parentId = parentId
    }
}

/// Hot cue bank list
public struct HotCueBankList: Equatable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var parentId: Int?

    public init(id: Int, name: String, parentId: Int?) {
        self.id = id
        self.name = name
        self.parentId = parentId
    }
}

/// Menu item for browsing
public struct MenuItem: Equatable, Hashable, Sendable {
    public var id: Int
    public var kind: Int
    public var name: String

    public init(id: Int, kind: Int, name: String) {
        self.id = id
        self.kind = kind
        self.name = name
    }
}

/// Browse category
public struct Category: Equatable, Hashable, Sendable {
    public var id: Int
    public var menuItemId: Int
    public var name: String
    public var kind: Int
    public var isVisible: Bool

    public init(id: Int, menuItemId: Int, name: String, kind: Int, isVisible: Bool) {
        self.id = id
        self.menuItemId = menuItemId
        self.name = name
        self.kind = kind
        self.isVisible = isVisible
    }
}

/// Sort option
public struct SortOption: Equatable, Hashable, Sendable {
    public var id: Int
    public var menuItemId: Int
    public var name: String
    public var kind: Int
    public var isVisible: Bool
    public var isSelectedAsSubColumn: Bool

    public init(id: Int, menuItemId: Int, name: String, kind: Int, isVisible: Bool, isSelectedAsSubColumn: Bool) {
        self.id = id
        self.menuItemId = menuItemId
        self.name = name
        self.kind = kind
        self.isVisible = isVisible
        self.isSelectedAsSubColumn = isSelectedAsSubColumn
    }
}

/// Device property
public struct DeviceProperty: Equatable, Hashable, Sendable {
    public var deviceName: String
    public var dbVersion: String
    public var numberOfContents: Int
    public var createdDate: String
    public var backgroundColorType: Int

    public init(
        deviceName: String, dbVersion: String, numberOfContents: Int, createdDate: String, backgroundColorType: Int
    ) {
        self.deviceName = deviceName
        self.dbVersion = dbVersion
        self.numberOfContents = numberOfContents
        self.createdDate = createdDate
        self.backgroundColorType = backgroundColorType
    }
}
