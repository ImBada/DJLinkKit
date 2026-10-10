extension MetadataConnect {
    /// Interface for reading file data at arbitrary offsets.
    /// This allows extracting metadata from remote files by reading only the necessary bytes.
    public protocol FileReader: Sendable {
        /// Total file size in bytes
        var size: Int { get }
        /// File extension (without dot), e.g., 'mp3', 'flac', 'm4a'
        var `extension`: String { get }
        /// Read bytes from the file at a given offset
        func read(_ offset: Int, _ length: Int) async throws -> [UInt8]
    }

    /// Standard picture types from ID3v2 / FLAC specs
    ///
    /// 선(wire)에서 읽는 숫자라서 모르는 값도 담는 구조체로 옮겼다(원본은 숫자 enum).
    public struct PictureType: RawRepresentable, Hashable, Sendable {
        public var rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let other = PictureType(rawValue: 0)
        public static let fileIcon32x32 = PictureType(rawValue: 1)
        public static let otherFileIcon = PictureType(rawValue: 2)
        public static let frontCover = PictureType(rawValue: 3)
        public static let backCover = PictureType(rawValue: 4)
        public static let leafletPage = PictureType(rawValue: 5)
        public static let media = PictureType(rawValue: 6)
        public static let leadArtist = PictureType(rawValue: 7)
        public static let artist = PictureType(rawValue: 8)
        public static let conductor = PictureType(rawValue: 9)
        public static let band = PictureType(rawValue: 10)
        public static let composer = PictureType(rawValue: 11)
        public static let lyricist = PictureType(rawValue: 12)
        public static let recordingLocation = PictureType(rawValue: 13)
        public static let duringRecording = PictureType(rawValue: 14)
        public static let duringPerformance = PictureType(rawValue: 15)
        public static let movieScreenCapture = PictureType(rawValue: 16)
        public static let brightColoredFish = PictureType(rawValue: 17)
        public static let illustration = PictureType(rawValue: 18)
        public static let bandLogotype = PictureType(rawValue: 19)
        public static let publisherLogotype = PictureType(rawValue: 20)
    }

    /// MIME types supported for artwork
    public enum ArtworkMimeType: String, Sendable {
        case jpeg = "image/jpeg"
        case png = "image/png"
        case gif = "image/gif"
    }

    /// Extracted metadata from an audio file
    public struct ExtractedMetadata: Equatable, Sendable {
        /// Track title
        public var title: String?
        /// Artist name
        public var artist: String?
        /// Album name
        public var album: String?
        /// Genre
        public var genre: String?
        /// Record label / publisher
        public var label: String?
        /// Release year
        public var year: Int?
        /// Beats per minute
        public var bpm: Double?
        /// Musical key (e.g., "Am", "C#m", "5A")
        public var key: String?
        /// Artwork image data
        public var artwork: [UInt8]?
        /// MIME type of the artwork
        public var artworkMimeType: ArtworkMimeType?

        public init(
            title: String? = nil,
            artist: String? = nil,
            album: String? = nil,
            genre: String? = nil,
            label: String? = nil,
            year: Int? = nil,
            bpm: Double? = nil,
            key: String? = nil,
            artwork: [UInt8]? = nil,
            artworkMimeType: ArtworkMimeType? = nil
        ) {
            self.title = title
            self.artist = artist
            self.album = album
            self.genre = genre
            self.label = label
            self.year = year
            self.bpm = bpm
            self.key = key
            self.artwork = artwork
            self.artworkMimeType = artworkMimeType
        }
    }

    /// Parser function signature
    public typealias MetadataParser = @Sendable (any FileReader) async throws -> ExtractedMetadata?
}
