import Foundation

// 원본 src/entities.ts

/// Represents a track with both database fields and ANLZ analysis data.
///
/// onelibrary-connect의 `Track<EntityFK.WithRelations>`에 ANLZ 칸(`beatGrid`, `waveformHd`)을 더한 것.
/// onelibrary-connect 쪽(`OneLibraryAdapter`)이 돌려줄 때는 ANLZ 칸이 nil이다(원본에서 undefined).
public struct Track: Equatable, Sendable {
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
    /// Int로 담을 수 없는 원본 RemoteDB 연도(number)를 보존한다.
    public var rawYear: Double? = nil
    public var mixName: String?
    public var autoloadHotcues: Bool?
    public var kuvoPublic: Bool?
    public var fileSize: Int?
    public var analyzePath: String?
    public var releaseDate: String?
    public var analyzeDate: Date?
    public var dateAdded: Date?
    public var artwork: Artwork?
    public var artist: Artist?
    public var originalArtist: Artist?
    public var remixer: Artist?
    public var composer: Artist?
    public var album: Album?
    public var label: Label?
    public var genre: Genre?
    public var color: Color?
    public var key: Key?
    /// Embedded cue and loop information from the database
    public var cueAndLoops: [CueAndLoop]?
    /// Embedded beat grid information (from ANLZ files)
    public var beatGrid: BeatGrid?
    /// Embedded HD Waveform information (from ANLZ files)
    public var waveformHd: WaveformHD?

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
        artwork: Artwork? = nil,
        artist: Artist? = nil,
        originalArtist: Artist? = nil,
        remixer: Artist? = nil,
        composer: Artist? = nil,
        album: Album? = nil,
        label: Label? = nil,
        genre: Genre? = nil,
        color: Color? = nil,
        key: Key? = nil,
        cueAndLoops: [CueAndLoop]? = nil,
        beatGrid: BeatGrid? = nil,
        waveformHd: WaveformHD? = nil
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
        self.artwork = artwork
        self.artist = artist
        self.originalArtist = originalArtist
        self.remixer = remixer
        self.composer = composer
        self.album = album
        self.label = label
        self.genre = genre
        self.color = color
        self.key = key
        self.cueAndLoops = cueAndLoops
        self.beatGrid = beatGrid
        self.waveformHd = waveformHd
    }
}
