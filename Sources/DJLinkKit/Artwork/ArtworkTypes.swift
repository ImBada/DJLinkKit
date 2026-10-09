/// Extracted artwork from an audio file
public struct ExtractedArtwork: Equatable, Sendable {
    /// 원본의 `'image/jpeg' | 'image/png' | 'image/gif'`
    public enum MimeType: String, Sendable {
        case jpeg = "image/jpeg"
        case png = "image/png"
        case gif = "image/gif"
    }

    public var data: [UInt8]
    public var mimeType: MimeType
    public var width: Int?
    public var height: Int?
    public var pictureType: PictureType?

    public init(
        data: [UInt8],
        mimeType: MimeType,
        width: Int? = nil,
        height: Int? = nil,
        pictureType: PictureType? = nil
    ) {
        self.data = data
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.pictureType = pictureType
    }
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

/// Interface for reading file data at arbitrary offsets.
///
/// 원본에서는 이 `FileReader`가 metadata-connect의 `FileReader`와 모양이 같아 서로 넘겨 쓴다.
/// Swift에서도 양쪽으로 넘길 수 있게 같은 프로토콜의 다른 이름으로 둔다(alphatheta-connect가
/// 이 형을 `ArtworkFileReader`라는 이름으로 내보낸다).
public typealias ArtworkFileReader = MetadataConnect.FileReader
