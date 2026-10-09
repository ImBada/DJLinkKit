public struct MessageType: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let introduce = Self(rawValue: 0x0000)
    public static let disconnect = Self(rawValue: 0x0100)
    public static let renderMenu = Self(rawValue: 0x3000)
    public static let menuRoot = Self(rawValue: 0x1000)
    public static let menuGenre = Self(rawValue: 0x1001)
    public static let menuArtist = Self(rawValue: 0x1002)
    public static let menuAlbum = Self(rawValue: 0x1003)
    public static let menuTrack = Self(rawValue: 0x1004)
    public static let menuBPM = Self(rawValue: 0x1006)
    public static let menuRating = Self(rawValue: 0x1007)
    public static let menuYear = Self(rawValue: 0x1008)
    public static let menuLabel = Self(rawValue: 0x100a)
    public static let menuColor = Self(rawValue: 0x100d)
    public static let menuTime = Self(rawValue: 0x1010)
    public static let menuBitrate = Self(rawValue: 0x1011)
    public static let menuHistory = Self(rawValue: 0x1012)
    public static let menuFilename = Self(rawValue: 0x1013)
    public static let menuKey = Self(rawValue: 0x1014)
    public static let menuOriginalArtist = Self(rawValue: 0x1302)
    public static let menuRemixer = Self(rawValue: 0x1602)
    public static let menuPlaylist = Self(rawValue: 0x1105)
    public static let menuArtistsOfGenre = Self(rawValue: 0x1101)
    public static let menuAlbumsOfArtist = Self(rawValue: 0x1102)
    public static let menuTracksOfAlbum = Self(rawValue: 0x1103)
    public static let menuTracksOfRating = Self(rawValue: 0x1107)
    public static let menuYearsOfDecade = Self(rawValue: 0x1108)
    public static let menuArtistsOfLabel = Self(rawValue: 0x110a)
    public static let menuTracksOfColor = Self(rawValue: 0x110d)
    public static let menuTracksOfTime = Self(rawValue: 0x1110)
    public static let menuTracksOfHistory = Self(rawValue: 0x1112)
    public static let menuDistancesOfKey = Self(rawValue: 0x1114)
    public static let menuAlbumsOfOriginalArtist = Self(rawValue: 0x1402)
    public static let menuAlbumsOfRemixer = Self(rawValue: 0x1702)
    public static let menuAlbumsOfGenreAndArtist = Self(rawValue: 0x1201)
    public static let menuTracksOfArtistAndAlbum = Self(rawValue: 0x1202)
    public static let menuTracksOfBPMPercentRange = Self(rawValue: 0x1206)
    public static let menuTracksOfDecadeAndYear = Self(rawValue: 0x1208)
    public static let menuAlbumsOfLabelAndArtist = Self(rawValue: 0x120a)
    public static let menuTracksNearKey = Self(rawValue: 0x1214)
    public static let menuTracksOfOriginalArtistAndAlbum = Self(rawValue: 0x1502)
    public static let menuTracksOfRemixerAndAlbum = Self(rawValue: 0x1802)
    public static let menuTracksOfGenreArtistAndAlbum = Self(rawValue: 0x1301)
    public static let menuTracksOfLabelArtistAndAlbum = Self(rawValue: 0x130a)
    public static let menuSearch = Self(rawValue: 0x1300)
    public static let menuFolder = Self(rawValue: 0x2006)
    public static let getMetadata = Self(rawValue: 0x2002)
    public static let getArtwork = Self(rawValue: 0x2003)
    public static let getWaveformPreview = Self(rawValue: 0x2004)
    public static let getTrackInfo = Self(rawValue: 0x2102)
    public static let getGenericMetadata = Self(rawValue: 0x2202)
    public static let getCueAndLoops = Self(rawValue: 0x2104)
    public static let getBeatGrid = Self(rawValue: 0x2204)
    public static let getWaveformDetailed = Self(rawValue: 0x2904)
    public static let getAdvCueAndLoops = Self(rawValue: 0x2b04)
    public static let getWaveformHD = Self(rawValue: 0x2c04)
    public static let success = Self(rawValue: 0x4000)
    public static let `error` = Self(rawValue: 0x4003)
    public static let artwork = Self(rawValue: 0x4002)
    public static let menuItem = Self(rawValue: 0x4101)
    public static let menuHeader = Self(rawValue: 0x4001)
    public static let menuFooter = Self(rawValue: 0x4201)
    public static let beatGrid = Self(rawValue: 0x4602)
    public static let cueAndLoop = Self(rawValue: 0x4702)
    public static let waveformPreview = Self(rawValue: 0x4402)
    public static let waveformDetailed = Self(rawValue: 0x4a02)
    public static let advCueAndLoops = Self(rawValue: 0x4e02)
    public static let waveformHD = Self(rawValue: 0x4f02)
    public var jsName: String? {
        switch rawValue {
        case 0x0000: "Introduce"
        case 0x0100: "Disconnect"
        case 0x3000: "RenderMenu"
        case 0x1000: "MenuRoot"
        case 0x1001: "MenuGenre"
        case 0x1002: "MenuArtist"
        case 0x1003: "MenuAlbum"
        case 0x1004: "MenuTrack"
        case 0x1006: "MenuBPM"
        case 0x1007: "MenuRating"
        case 0x1008: "MenuYear"
        case 0x100a: "MenuLabel"
        case 0x100d: "MenuColor"
        case 0x1010: "MenuTime"
        case 0x1011: "MenuBitrate"
        case 0x1012: "MenuHistory"
        case 0x1013: "MenuFilename"
        case 0x1014: "MenuKey"
        case 0x1302: "MenuOriginalArtist"
        case 0x1602: "MenuRemixer"
        case 0x1105: "MenuPlaylist"
        case 0x1101: "MenuArtistsOfGenre"
        case 0x1102: "MenuAlbumsOfArtist"
        case 0x1103: "MenuTracksOfAlbum"
        case 0x1107: "MenuTracksOfRating"
        case 0x1108: "MenuYearsOfDecade"
        case 0x110a: "MenuArtistsOfLabel"
        case 0x110d: "MenuTracksOfColor"
        case 0x1110: "MenuTracksOfTime"
        case 0x1112: "MenuTracksOfHistory"
        case 0x1114: "MenuDistancesOfKey"
        case 0x1402: "MenuAlbumsOfOriginalArtist"
        case 0x1702: "MenuAlbumsOfRemixer"
        case 0x1201: "MenuAlbumsOfGenreAndArtist"
        case 0x1202: "MenuTracksOfArtistAndAlbum"
        case 0x1206: "MenuTracksOfBPMPercentRange"
        case 0x1208: "MenuTracksOfDecadeAndYear"
        case 0x120a: "MenuAlbumsOfLabelAndArtist"
        case 0x1214: "MenuTracksNearKey"
        case 0x1502: "MenuTracksOfOriginalArtistAndAlbum"
        case 0x1802: "MenuTracksOfRemixerAndAlbum"
        case 0x1301: "MenuTracksOfGenreArtistAndAlbum"
        case 0x130a: "MenuTracksOfLabelArtistAndAlbum"
        case 0x1300: "MenuSearch"
        case 0x2006: "MenuFolder"
        case 0x2002: "GetMetadata"
        case 0x2003: "GetArtwork"
        case 0x2004: "GetWaveformPreview"
        case 0x2102: "GetTrackInfo"
        case 0x2202: "GetGenericMetadata"
        case 0x2104: "GetCueAndLoops"
        case 0x2204: "GetBeatGrid"
        case 0x2904: "GetWaveformDetailed"
        case 0x2b04: "GetAdvCueAndLoops"
        case 0x2c04: "GetWaveformHD"
        case 0x4000: "Success"
        case 0x4003: "Error"
        case 0x4002: "Artwork"
        case 0x4101: "MenuItem"
        case 0x4001: "MenuHeader"
        case 0x4201: "MenuFooter"
        case 0x4602: "BeatGrid"
        case 0x4702: "CueAndLoop"
        case 0x4402: "WaveformPreview"
        case 0x4a02: "WaveformDetailed"
        case 0x4e02: "AdvCueAndLoops"
        case 0x4f02: "WaveformHD"
        default: nil
        }
    }
}
public typealias ControlRequest = MessageType
public typealias MenuRequest = MessageType
public typealias DataRequest = MessageType
public typealias Response = MessageType
public typealias Request = MessageType
public typealias Query = MessageType
public func getMessageName(_ type: MessageType) -> String? { type.jsName }
public func getQueryName(_ query: Query) -> String? { query.jsName }
