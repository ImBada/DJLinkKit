// 원본 onelibrary-connect/src/schema.ts
public struct ContentRow: Equatable, Sendable {
    public var content_id: Int
    public var title: String?
    public var titleForSearch: String?
    public var subtitle: String?
    public var bpmx100: Int?
    public var length: Int?
    public var trackNo: Int?
    public var discNo: Int?
    public var artist_id_artist: Int?
    public var artist_id_remixer: Int?
    public var artist_id_originalArtist: Int?
    public var artist_id_composer: Int?
    public var artist_id_lyricist: Int?
    public var album_id: Int?
    public var genre_id: Int?
    public var label_id: Int?
    public var key_id: Int?
    public var color_id: Int?
    public var image_id: Int?
    public var djComment: String?
    public var rating: Int?
    public var releaseYear: Int?
    public var releaseDate: String?
    public var dateCreated: String?
    public var dateAdded: String?
    public var path: String?
    public var fileName: String?
    public var fileSize: Int?
    public var fileType: Int?
    public var bitrate: Int?
    public var bitDepth: Int?
    public var samplingRate: Int?
    public var isrc: String?
    public var djPlayCount: Int?
    public var isHotCueAutoLoadOn: Int?
    public var isKuvoDeliverStatusOn: Int?
    public var kuvoDeliveryComment: String?
    public var masterDbId: Int?
    public var masterContentId: Int?
    public var analysisDataFilePath: String?
    public var analysedBits: Int?
    public var contentLink: Int?
    public var hasModified: Int?
    public var cueUpdateCount: Int?
    public var analysisDataUpdateCount: Int?
    public var informationUpdateCount: Int?
    public init(
        content_id: Int, title: String? = nil, titleForSearch: String? = nil, subtitle: String? = nil,
        bpmx100: Int? = nil, length: Int? = nil, trackNo: Int? = nil, discNo: Int? = nil,
        artist_id_artist: Int? = nil, artist_id_remixer: Int? = nil,
        artist_id_originalArtist: Int? = nil, artist_id_composer: Int? = nil,
        artist_id_lyricist: Int? = nil, album_id: Int? = nil, genre_id: Int? = nil,
        label_id: Int? = nil, key_id: Int? = nil, color_id: Int? = nil, image_id: Int? = nil,
        djComment: String? = nil, rating: Int? = nil, releaseYear: Int? = nil,
        releaseDate: String? = nil, dateCreated: String? = nil, dateAdded: String? = nil,
        path: String? = nil, fileName: String? = nil, fileSize: Int? = nil, fileType: Int? = nil,
        bitrate: Int? = nil, bitDepth: Int? = nil, samplingRate: Int? = nil, isrc: String? = nil,
        djPlayCount: Int? = nil, isHotCueAutoLoadOn: Int? = nil, isKuvoDeliverStatusOn: Int? = nil,
        kuvoDeliveryComment: String? = nil, masterDbId: Int? = nil, masterContentId: Int? = nil,
        analysisDataFilePath: String? = nil, analysedBits: Int? = nil, contentLink: Int? = nil,
        hasModified: Int? = nil, cueUpdateCount: Int? = nil, analysisDataUpdateCount: Int? = nil,
        informationUpdateCount: Int? = nil
    ) {
        self.content_id = content_id
        self.title = title
        self.titleForSearch = titleForSearch
        self.subtitle = subtitle
        self.bpmx100 = bpmx100
        self.length = length
        self.trackNo = trackNo
        self.discNo = discNo
        self.artist_id_artist = artist_id_artist
        self.artist_id_remixer = artist_id_remixer
        self.artist_id_originalArtist = artist_id_originalArtist
        self.artist_id_composer = artist_id_composer
        self.artist_id_lyricist = artist_id_lyricist
        self.album_id = album_id
        self.genre_id = genre_id
        self.label_id = label_id
        self.key_id = key_id
        self.color_id = color_id
        self.image_id = image_id
        self.djComment = djComment
        self.rating = rating
        self.releaseYear = releaseYear
        self.releaseDate = releaseDate
        self.dateCreated = dateCreated
        self.dateAdded = dateAdded
        self.path = path
        self.fileName = fileName
        self.fileSize = fileSize
        self.fileType = fileType
        self.bitrate = bitrate
        self.bitDepth = bitDepth
        self.samplingRate = samplingRate
        self.isrc = isrc
        self.djPlayCount = djPlayCount
        self.isHotCueAutoLoadOn = isHotCueAutoLoadOn
        self.isKuvoDeliverStatusOn = isKuvoDeliverStatusOn
        self.kuvoDeliveryComment = kuvoDeliveryComment
        self.masterDbId = masterDbId
        self.masterContentId = masterContentId
        self.analysisDataFilePath = analysisDataFilePath
        self.analysedBits = analysedBits
        self.contentLink = contentLink
        self.hasModified = hasModified
        self.cueUpdateCount = cueUpdateCount
        self.analysisDataUpdateCount = analysisDataUpdateCount
        self.informationUpdateCount = informationUpdateCount
    }
}
public struct ArtistRow: Equatable, Sendable {
    public var artist_id: Int
    public var name: String?
    public var nameForSearch: String?
    public init(artist_id: Int, name: String? = nil, nameForSearch: String? = nil) {
        self.artist_id = artist_id
        self.name = name
        self.nameForSearch = nameForSearch
    }
}
public struct AlbumRow: Equatable, Sendable {
    public var album_id: Int
    public var name: String?
    public var artist_id: Int?
    public var image_id: Int?
    public var isComplation: Int?
    public var nameForSearch: String?
    public init(
        album_id: Int, name: String? = nil, artist_id: Int? = nil, image_id: Int? = nil,
        isComplation: Int? = nil, nameForSearch: String? = nil
    ) {
        self.album_id = album_id
        self.name = name
        self.artist_id = artist_id
        self.image_id = image_id
        self.isComplation = isComplation
        self.nameForSearch = nameForSearch
    }
}
public struct GenreRow: Equatable, Sendable {
    public var genre_id: Int
    public var name: String?
    public init(genre_id: Int, name: String? = nil) {
        self.genre_id = genre_id
        self.name = name
    }
}
public struct KeyRow: Equatable, Sendable {
    public var key_id: Int
    public var name: String?
    public init(key_id: Int, name: String? = nil) {
        self.key_id = key_id
        self.name = name
    }
}
public struct ColorRow: Equatable, Sendable {
    public var color_id: Int
    public var name: String?
    public init(color_id: Int, name: String? = nil) {
        self.color_id = color_id
        self.name = name
    }
}
public struct LabelRow: Equatable, Sendable {
    public var label_id: Int
    public var name: String?
    public init(label_id: Int, name: String? = nil) {
        self.label_id = label_id
        self.name = name
    }
}
public struct ImageRow: Equatable, Sendable {
    public var image_id: Int
    public var path: String?
    public init(image_id: Int, path: String? = nil) {
        self.image_id = image_id
        self.path = path
    }
}
public struct CueRow: Equatable, Sendable {
    public var cue_id: Int
    public var content_id: Int?
    public var kind: Int?
    public var colorTableIndex: Int?
    public var cueComment: String?
    public var isActiveLoop: Int?
    public var beatLoopNumerator: Int?
    public var beatLoopDenominator: Int?
    public var inUsec: Int?
    public var outUsec: Int?
    public var in150FramePerSec: Int?
    public var out150FramePerSec: Int?
    public var inMpegFrameNumber: Int?
    public var outMpegFrameNumber: Int?
    public var inMpegAbs: Int?
    public var outMpegAbs: Int?
    public var inDecodingStartFramePosition: Int?
    public var outDecodingStartFramePosition: Int?
    public var inFileOffsetInBlock: Int?
    public var OutFileOffsetInBlock: Int?
    public var inNumberOfSampleInBlock: Int?
    public var outNumberOfSampleInBlock: Int?
    public init(
        cue_id: Int, content_id: Int? = nil, kind: Int? = nil, colorTableIndex: Int? = nil,
        cueComment: String? = nil, isActiveLoop: Int? = nil, beatLoopNumerator: Int? = nil,
        beatLoopDenominator: Int? = nil, inUsec: Int? = nil, outUsec: Int? = nil,
        in150FramePerSec: Int? = nil, out150FramePerSec: Int? = nil, inMpegFrameNumber: Int? = nil,
        outMpegFrameNumber: Int? = nil, inMpegAbs: Int? = nil, outMpegAbs: Int? = nil,
        inDecodingStartFramePosition: Int? = nil, outDecodingStartFramePosition: Int? = nil,
        inFileOffsetInBlock: Int? = nil, OutFileOffsetInBlock: Int? = nil,
        inNumberOfSampleInBlock: Int? = nil, outNumberOfSampleInBlock: Int? = nil
    ) {
        self.cue_id = cue_id
        self.content_id = content_id
        self.kind = kind
        self.colorTableIndex = colorTableIndex
        self.cueComment = cueComment
        self.isActiveLoop = isActiveLoop
        self.beatLoopNumerator = beatLoopNumerator
        self.beatLoopDenominator = beatLoopDenominator
        self.inUsec = inUsec
        self.outUsec = outUsec
        self.in150FramePerSec = in150FramePerSec
        self.out150FramePerSec = out150FramePerSec
        self.inMpegFrameNumber = inMpegFrameNumber
        self.outMpegFrameNumber = outMpegFrameNumber
        self.inMpegAbs = inMpegAbs
        self.outMpegAbs = outMpegAbs
        self.inDecodingStartFramePosition = inDecodingStartFramePosition
        self.outDecodingStartFramePosition = outDecodingStartFramePosition
        self.inFileOffsetInBlock = inFileOffsetInBlock
        self.OutFileOffsetInBlock = OutFileOffsetInBlock
        self.inNumberOfSampleInBlock = inNumberOfSampleInBlock
        self.outNumberOfSampleInBlock = outNumberOfSampleInBlock
    }
}
public struct PlaylistRow: Equatable, Sendable {
    public var playlist_id: Int
    public var sequenceNo: Int?
    public var name: String?
    public var image_id: Int?
    public var attribute: Int?
    public var playlist_id_parent: Int?
    public init(
        playlist_id: Int, sequenceNo: Int? = nil, name: String? = nil, image_id: Int? = nil,
        attribute: Int? = nil, playlist_id_parent: Int? = nil
    ) {
        self.playlist_id = playlist_id
        self.sequenceNo = sequenceNo
        self.name = name
        self.image_id = image_id
        self.attribute = attribute
        self.playlist_id_parent = playlist_id_parent
    }
}
public struct PlaylistContentRow: Equatable, Sendable {
    public var playlist_id: Int
    public var content_id: Int
    public var sequenceNo: Int
    public init(playlist_id: Int, content_id: Int, sequenceNo: Int) {
        self.playlist_id = playlist_id
        self.content_id = content_id
        self.sequenceNo = sequenceNo
    }
}
public struct PropertyRow: Equatable, Sendable {
    public var deviceName: String?
    public var dbVersion: String?
    public var numberOfContents: Int?
    public var createdDate: String?
    public var backGroundColorType: Int?
    public var myTagMasterDBID: Int?
    public init(
        deviceName: String? = nil, dbVersion: String? = nil, numberOfContents: Int? = nil,
        createdDate: String? = nil, backGroundColorType: Int? = nil, myTagMasterDBID: Int? = nil
    ) {
        self.deviceName = deviceName
        self.dbVersion = dbVersion
        self.numberOfContents = numberOfContents
        self.createdDate = createdDate
        self.backGroundColorType = backGroundColorType
        self.myTagMasterDBID = myTagMasterDBID
    }
}
public struct MyTagRow: Equatable, Sendable {
    public var myTag_id: Int
    public var sequenceNo: Int?
    public var name: String?
    public var attribute: Int?
    public var myTag_id_parent: Int?
    public init(
        myTag_id: Int, sequenceNo: Int? = nil, name: String? = nil, attribute: Int? = nil,
        myTag_id_parent: Int? = nil
    ) {
        self.myTag_id = myTag_id
        self.sequenceNo = sequenceNo
        self.name = name
        self.attribute = attribute
        self.myTag_id_parent = myTag_id_parent
    }
}
public struct MyTagContentRow: Equatable, Sendable {
    public var myTag_id: Int
    public var content_id: Int
    public init(myTag_id: Int, content_id: Int) {
        self.myTag_id = myTag_id
        self.content_id = content_id
    }
}
public struct HistoryRow: Equatable, Sendable {
    public var history_id: Int
    public var sequenceNo: Int?
    public var name: String?
    public var attribute: Int?
    public var history_id_parent: Int?
    public init(
        history_id: Int, sequenceNo: Int? = nil, name: String? = nil, attribute: Int? = nil,
        history_id_parent: Int? = nil
    ) {
        self.history_id = history_id
        self.sequenceNo = sequenceNo
        self.name = name
        self.attribute = attribute
        self.history_id_parent = history_id_parent
    }
}
public struct HistoryContentRow: Equatable, Sendable {
    public var history_id: Int
    public var content_id: Int
    public var sequenceNo: Int
    public init(history_id: Int, content_id: Int, sequenceNo: Int) {
        self.history_id = history_id
        self.content_id = content_id
        self.sequenceNo = sequenceNo
    }
}
public struct HotCueBankListRow: Equatable, Sendable {
    public var hotCueBankList_id: Int
    public var sequenceNo: Int?
    public var name: String?
    public var image_id: Int?
    public var attribute: Int?
    public var hotCueBankList_id_parent: Int?
    public init(
        hotCueBankList_id: Int, sequenceNo: Int? = nil, name: String? = nil, image_id: Int? = nil,
        attribute: Int? = nil, hotCueBankList_id_parent: Int? = nil
    ) {
        self.hotCueBankList_id = hotCueBankList_id
        self.sequenceNo = sequenceNo
        self.name = name
        self.image_id = image_id
        self.attribute = attribute
        self.hotCueBankList_id_parent = hotCueBankList_id_parent
    }
}
public struct HotCueBankListCueRow: Equatable, Sendable {
    public var hotCueBankList_id: Int
    public var cue_id: Int
    public var sequenceNo: Int
    public init(hotCueBankList_id: Int, cue_id: Int, sequenceNo: Int) {
        self.hotCueBankList_id = hotCueBankList_id
        self.cue_id = cue_id
        self.sequenceNo = sequenceNo
    }
}
public struct MenuItemRow: Equatable, Sendable {
    public var menuItem_id: Int
    public var kind: Int?
    public var name: String?
    public init(menuItem_id: Int, kind: Int? = nil, name: String? = nil) {
        self.menuItem_id = menuItem_id
        self.kind = kind
        self.name = name
    }
}
public struct CategoryRow: Equatable, Sendable {
    public var category_id: Int
    public var menuItem_id: Int?
    public var sequenceNo: Int?
    public var isVisible: Int?
    public init(
        category_id: Int, menuItem_id: Int? = nil, sequenceNo: Int? = nil, isVisible: Int? = nil
    ) {
        self.category_id = category_id
        self.menuItem_id = menuItem_id
        self.sequenceNo = sequenceNo
        self.isVisible = isVisible
    }
}
public struct SortRow: Equatable, Sendable {
    public var sort_id: Int
    public var menuItem_id: Int?
    public var sequenceNo: Int?
    public var isVisible: Int?
    public var isSelectedAsSubColumn: Int?
    public init(
        sort_id: Int, menuItem_id: Int? = nil, sequenceNo: Int? = nil, isVisible: Int? = nil,
        isSelectedAsSubColumn: Int? = nil
    ) {
        self.sort_id = sort_id
        self.menuItem_id = menuItem_id
        self.sequenceNo = sequenceNo
        self.isVisible = isVisible
        self.isSelectedAsSubColumn = isSelectedAsSubColumn
    }
}
public struct RecommendedLikeRow: Equatable, Sendable {
    public var content_id_1: Int
    public var content_id_2: Int
    public var rating: Int?
    public var createdDate: Int?
    public init(content_id_1: Int, content_id_2: Int, rating: Int? = nil, createdDate: Int? = nil) {
        self.content_id_1 = content_id_1
        self.content_id_2 = content_id_2
        self.rating = rating
        self.createdDate = createdDate
    }
}
public enum CueKind {
    public static let MEMORY_CUE = 0
    public static let HOT_CUE = 1
}
public enum PlaylistAttribute {
    public static let PLAYLIST = 0
    public static let FOLDER = 1
}
public enum MyTagAttribute {
    public static let TAG = 0
    public static let FOLDER = 1
}
public enum MenuItemKind {
    public static let GENRE = 128
    public static let ARTIST = 129
    public static let ALBUM = 130
    public static let TRACK = 131
    public static let PLAYLIST = 132
    public static let BPM = 133
    public static let RATING = 134
    public static let YEAR = 135
    public static let REMIXER = 136
    public static let LABEL = 137
    public static let ORIGINAL_ARTIST = 138
    public static let KEY = 139
    public static let DATE_ADDED = 140
    public static let CUE = 141
    public static let COLOR = 142
    public static let FOLDER = 144
    public static let SEARCH = 145
    public static let TIME = 146
    public static let BITRATE = 147
    public static let FILE_NAME = 148
    public static let HISTORY = 149
    public static let COMMENTS = 150
    public static let DJ_PLAY_COUNT = 151
    public static let HOT_CUE_BANK = 152
    public static let DEFAULT = 161
    public static let ALPHABET = 162
    public static let MATCHING = 170
}
