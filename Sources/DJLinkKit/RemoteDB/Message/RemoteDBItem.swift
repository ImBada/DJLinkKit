import Foundation

public struct ItemType: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let path = Self(rawValue: 0x0000)
    public static let folder = Self(rawValue: 0x0001)
    public static let albumTitle = Self(rawValue: 0x0002)
    public static let disc = Self(rawValue: 0x0003)
    public static let trackTitle = Self(rawValue: 0x0004)
    public static let genre = Self(rawValue: 0x0006)
    public static let artist = Self(rawValue: 0x0007)
    public static let playlist = Self(rawValue: 0x0008)
    public static let rating = Self(rawValue: 0x000a)
    public static let duration = Self(rawValue: 0x000b)
    public static let tempo = Self(rawValue: 0x000d)
    public static let label = Self(rawValue: 0x000e)
    public static let key = Self(rawValue: 0x000f)
    public static let bitRate = Self(rawValue: 0x0010)
    public static let year = Self(rawValue: 0x0011)
    public static let comment = Self(rawValue: 0x0023)
    public static let historyPlaylist = Self(rawValue: 0x0024)
    public static let originalArtist = Self(rawValue: 0x0028)
    public static let remixer = Self(rawValue: 0x0029)
    public static let dateAdded = Self(rawValue: 0x002e)
    public static let unknown01 = Self(rawValue: 0x002f)
    public static let unknown02 = Self(rawValue: 0x002a)
    public static let colorNone = Self(rawValue: 0x0013)
    public static let colorPink = Self(rawValue: 0x0014)
    public static let colorRed = Self(rawValue: 0x0015)
    public static let colorOrange = Self(rawValue: 0x0016)
    public static let colorYellow = Self(rawValue: 0x0017)
    public static let colorGreen = Self(rawValue: 0x0018)
    public static let colorAqua = Self(rawValue: 0x0019)
    public static let colorBlue = Self(rawValue: 0x001a)
    public static let colorPurple = Self(rawValue: 0x001b)
    public static let menuGenre = Self(rawValue: 0x0080)
    public static let menuArtist = Self(rawValue: 0x0081)
    public static let menuAlbum = Self(rawValue: 0x0082)
    public static let menuTrack = Self(rawValue: 0x0083)
    public static let menuPlaylist = Self(rawValue: 0x0084)
    public static let menuBPM = Self(rawValue: 0x0085)
    public static let menuRating = Self(rawValue: 0x0086)
    public static let menuYear = Self(rawValue: 0x0087)
    public static let menuRemixer = Self(rawValue: 0x0088)
    public static let menuLabel = Self(rawValue: 0x0089)
    public static let menuOriginal = Self(rawValue: 0x008a)
    public static let menuKey = Self(rawValue: 0x008b)
    public static let menuColor = Self(rawValue: 0x008e)
    public static let menuFolder = Self(rawValue: 0x0090)
    public static let menuSearch = Self(rawValue: 0x0091)
    public static let menuTime = Self(rawValue: 0x0092)
    public static let menuBit = Self(rawValue: 0x0093)
    public static let menuFilename = Self(rawValue: 0x0094)
    public static let menuHistory = Self(rawValue: 0x0095)
    public static let streamingTrackMetadata = Self(rawValue: 0x0099)
    public static let menuAll = Self(rawValue: 0x00a0)
    public static let trackTitleAlbum = Self(rawValue: 0x0204)
    public static let trackTitleGenre = Self(rawValue: 0x0604)
    public static let trackTitleArtist = Self(rawValue: 0x0704)
    public static let trackTitleRating = Self(rawValue: 0x0a04)
    public static let trackTitleTime = Self(rawValue: 0x0b04)
    public static let trackTitleBPM = Self(rawValue: 0x0d04)
    public static let trackTitleLabel = Self(rawValue: 0x0e04)
    public static let trackTitleKey = Self(rawValue: 0x0f04)
    public static let trackTitleBitRate = Self(rawValue: 0x1004)
    public static let trackTitleColor = Self(rawValue: 0x1a04)
    public static let trackTitleComment = Self(rawValue: 0x2304)
    public static let trackTitleOriginalArtist = Self(rawValue: 0x2804)
    public static let trackTitleRemixer = Self(rawValue: 0x2904)
    public static let trackTitleDJPlayCount = Self(rawValue: 0x2a04)
    public static let menuTrackTitleDateAdded = Self(rawValue: 0x2e04)
    public var jsName: String? {
        switch rawValue {
        case 0x0000: "Path"
        case 0x0001: "Folder"
        case 0x0002: "AlbumTitle"
        case 0x0003: "Disc"
        case 0x0004: "TrackTitle"
        case 0x0006: "Genre"
        case 0x0007: "Artist"
        case 0x0008: "Playlist"
        case 0x000a: "Rating"
        case 0x000b: "Duration"
        case 0x000d: "Tempo"
        case 0x000e: "Label"
        case 0x000f: "Key"
        case 0x0010: "BitRate"
        case 0x0011: "Year"
        case 0x0023: "Comment"
        case 0x0024: "HistoryPlaylist"
        case 0x0028: "OriginalArtist"
        case 0x0029: "Remixer"
        case 0x002e: "DateAdded"
        case 0x002f: "Unknown01"
        case 0x002a: "Unknown02"
        case 0x0013: "ColorNone"
        case 0x0014: "ColorPink"
        case 0x0015: "ColorRed"
        case 0x0016: "ColorOrange"
        case 0x0017: "ColorYellow"
        case 0x0018: "ColorGreen"
        case 0x0019: "ColorAqua"
        case 0x001a: "ColorBlue"
        case 0x001b: "ColorPurple"
        case 0x0080: "MenuGenre"
        case 0x0081: "MenuArtist"
        case 0x0082: "MenuAlbum"
        case 0x0083: "MenuTrack"
        case 0x0084: "MenuPlaylist"
        case 0x0085: "MenuBPM"
        case 0x0086: "MenuRating"
        case 0x0087: "MenuYear"
        case 0x0088: "MenuRemixer"
        case 0x0089: "MenuLabel"
        case 0x008a: "MenuOriginal"
        case 0x008b: "MenuKey"
        case 0x008e: "MenuColor"
        case 0x0090: "MenuFolder"
        case 0x0091: "MenuSearch"
        case 0x0092: "MenuTime"
        case 0x0093: "MenuBit"
        case 0x0094: "MenuFilename"
        case 0x0095: "MenuHistory"
        case 0x0099: "StreamingTrackMetadata"
        case 0x00a0: "MenuAll"
        case 0x0204: "TrackTitleAlbum"
        case 0x0604: "TrackTitleGenre"
        case 0x0704: "TrackTitleArtist"
        case 0x0a04: "TrackTitleRating"
        case 0x0b04: "TrackTitleTime"
        case 0x0d04: "TrackTitleBPM"
        case 0x0e04: "TrackTitleLabel"
        case 0x0f04: "TrackTitleKey"
        case 0x1004: "TrackTitleBitRate"
        case 0x1a04: "TrackTitleColor"
        case 0x2304: "TrackTitleComment"
        case 0x2804: "TrackTitleOriginalArtist"
        case 0x2904: "TrackTitleRemixer"
        case 0x2a04: "TrackTitleDJPlayCount"
        case 0x2e04: "MenuTrackTitleDateAdded"
        default: nil
        }
    }
}
/// TypeScript의 형 단언은 런타임 값을 바꾸지 않는다. 형이 다른 .value도 그대로 보존한다.
public enum RemoteDBItemValue: Equatable, Sendable {
    case number(Int)
    case decimal(Double)
    case string(String)
    case binary([UInt8])

    var integer: Int? {
        if case let .number(value) = self { return value }
        return nil
    }
    var text: String? {
        if case let .string(value) = self { return value }
        return nil
    }
    var numeric: Double {
        switch self {
        case let .number(value): return Double(value)
        case let .decimal(value): return value
        case let .string(value): return remoteDBJSNumber(value)
        case let .binary(value): return remoteDBJSNumber(value.toString(.utf8))
        }
    }
    var propertyKey: String {
        switch self {
        case let .number(value): return String(value)
        case let .decimal(value): return String(value)
        case let .string(value): return value
        case let .binary(value): return value.toString(.utf8)
        }
    }
}

/// rawValues가 원본 결과다. 기존 정수·문자열 속성은 정상 응답을 쓰는 쪽의 형 있는 창구다.
public struct Items: Equatable, Sendable {
    public var rawValues: [String: RemoteDBItemValue]
    public var type: ItemType {
        get {
            let key = rawValues["type"]?.propertyKey ?? ""
            let value = Int(key)
            return ItemType(rawValue: value.flatMap { String($0) == key ? $0 : nil } ?? -1)
        }
        set { rawValues["type"] = .number(newValue.rawValue) }
    }
    public var id: Int? {
        get { rawValues["id"]?.integer }
        set { rawValues["id"] = newValue.map(RemoteDBItemValue.number) }
    }
    public var name: String? {
        get { rawValues["name"]?.text }
        set { rawValues["name"] = newValue.map(RemoteDBItemValue.string) }
    }
    public var title: String? {
        get { rawValues["title"]?.text }
        set { rawValues["title"] = newValue.map(RemoteDBItemValue.string) }
    }
    public var artworkId: Int? {
        get { rawValues["artworkId"]?.integer }
        set { rawValues["artworkId"] = newValue.map(RemoteDBItemValue.number) }
    }
    public var artist: String? {
        get { rawValues["artist"]?.text }
        set { rawValues["artist"] = newValue.map(RemoteDBItemValue.string) }
    }
    public var path: String? {
        get { rawValues["path"]?.text }
        set { rawValues["path"] = newValue.map(RemoteDBItemValue.string) }
    }
    public var bitrate: Int? {
        get { rawValues["bitrate"]?.integer }
        set { rawValues["bitrate"] = newValue.map(RemoteDBItemValue.number) }
    }
    public var comment: String? {
        get { rawValues["comment"]?.text }
        set { rawValues["comment"] = newValue.map(RemoteDBItemValue.string) }
    }
    public var year: Double? {
        get { rawValues["year"].map(\.numeric) }
        set { rawValues["year"] = newValue.map(RemoteDBItemValue.decimal) }
    }
    public var rating: Int? {
        get { rawValues["rating"]?.integer }
        set { rawValues["rating"] = newValue.map(RemoteDBItemValue.number) }
    }
    public var bpm: Double? {
        get { rawValues["bpm"].map(\.numeric) }
        set { rawValues["bpm"] = newValue.map(RemoteDBItemValue.decimal) }
    }
    public var duration: Int? {
        get { rawValues["duration"]?.integer }
        set { rawValues["duration"] = newValue.map(RemoteDBItemValue.number) }
    }
    public var parentId: Int? {
        get { rawValues["parentId"]?.integer }
        set { rawValues["parentId"] = newValue.map(RemoteDBItemValue.number) }
    }
    public var mainId: Int? {
        get { rawValues["mainId"]?.integer }
        set { rawValues["mainId"] = newValue.map(RemoteDBItemValue.number) }
    }
    public var label1: String? {
        get { rawValues["label1"]?.text }
        set { rawValues["label1"] = newValue.map(RemoteDBItemValue.string) }
    }
    public var label2: String? {
        get { rawValues["label2"]?.text }
        set { rawValues["label2"] = newValue.map(RemoteDBItemValue.string) }
    }
    public init(
        type: ItemType,
        id: Int? = nil,
        name: String? = nil,
        title: String? = nil,
        artworkId: Int? = nil,
        artist: String? = nil,
        path: String? = nil,
        bitrate: Int? = nil,
        comment: String? = nil,
        year: Double? = nil,
        rating: Int? = nil,
        bpm: Double? = nil,
        duration: Int? = nil,
        parentId: Int? = nil,
        mainId: Int? = nil,
        label1: String? = nil,
        label2: String? = nil
    ) {
        rawValues = ["type": .number(type.rawValue)]
        self.id = id
        self.name = name
        self.title = title
        self.artworkId = artworkId
        self.artist = artist
        self.path = path
        self.bitrate = bitrate
        self.comment = comment
        self.year = year
        self.rating = rating
        self.bpm = bpm
        self.duration = duration
        self.parentId = parentId
        self.mainId = mainId
        self.label1 = label1
        self.label2 = label2
    }
}
public typealias Item = Items
func fieldNumber(_ args: [Field], _ index: Int) throws -> Int {
    guard args.indices.contains(index), let value = args[index] as? any NumberField else {
        throw DJLinkError("Expected number field at argument \(index)")
    }
    return value.value
}
func fieldString(_ args: [Field], _ index: Int) throws -> String {
    guard args.indices.contains(index), let value = args[index] as? any StringField else {
        throw DJLinkError("Expected string field at argument \(index)")
    }
    return value.value
}
func fieldBinary(_ args: [Field], _ index: Int) throws -> [UInt8] {
    guard args.indices.contains(index), let value = args[index] as? any BinaryField else {
        throw DJLinkError("Expected binary field at argument \(index)")
    }
    return value.value
}
private func itemFieldValue(_ args: [Field], _ index: Int) throws -> RemoteDBItemValue {
    guard args.indices.contains(index) else {
        throw DJLinkError("Cannot read properties of undefined (reading 'value')")
    }
    if let field = args[index] as? any NumberField { return .number(field.value) }
    if let field = args[index] as? any StringField { return .string(field.value) }
    if let field = args[index] as? any BinaryField { return .binary(field.value) }
    throw DJLinkError("Field has no value")
}
public func fieldsToItem(_ args: [Field]) throws -> Items {
    let parentId = try itemFieldValue(args, 0)
    let mainId = try itemFieldValue(args, 1)
    let label1 = try itemFieldValue(args, 3)
    let label2 = try itemFieldValue(args, 5)
    let type = try itemFieldValue(args, 6)
    let artworkId = try itemFieldValue(args, 8)
    var item = Items(type: ItemType(rawValue: -1))
    item.rawValues = ["type": type]
    switch item.type {
    case .path: item.rawValues["path"] = label1
    case .trackTitle:
        item.rawValues["id"] = mainId
        item.rawValues["title"] = label1
        item.rawValues["artworkId"] = artworkId
    case .streamingTrackMetadata:
        item.rawValues["title"] = label1
        item.rawValues["artist"] = label2
    case .albumTitle, .artist, .genre, .label, .key, .originalArtist, .remixer, .folder, .playlist,
        .colorNone, .colorPink, .colorRed, .colorOrange, .colorYellow, .colorGreen, .colorAqua, .colorBlue,
        .colorPurple:
        item.rawValues["id"] = mainId
        item.rawValues["name"] = label1
    case .bitRate: item.rawValues["bitrate"] = mainId
    case .comment: item.rawValues["comment"] = label1
    case .year: item.year = label1.numeric
    case .rating: item.rawValues["rating"] = mainId
    case .tempo: item.bpm = mainId.numeric / 100
    case .duration: item.rawValues["duration"] = mainId
    default:
        if item.type.jsName == nil {
            Telemetry.captureMessage("No item transformer registered for item type \(type.propertyKey)", "error")
        }
        item.rawValues["parentId"] = parentId
        item.rawValues["mainId"] = mainId
        item.rawValues["label1"] = label1
        item.rawValues["label2"] = label2
        item.rawValues["artworkId"] = artworkId
    }
    return item
}
private func remoteDBJSNumber(_ value: String) -> Double {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return 0 }
    for (prefix, radix) in [("0x", 16), ("0b", 2), ("0o", 8)] where trimmed.lowercased().hasPrefix(prefix) {
        return UInt64(trimmed.dropFirst(2), radix: radix).map(Double.init) ?? .nan
    }
    return Double(trimmed) ?? .nan
}
