// 원본 Pick<Track, 'analyzePath'> 모양. 전체 Track 없이도 분석 경로만 넘길 수 있다.
public protocol LocalDBAnlzTrackSource: Sendable { var analyzePath: String? { get } }
extension Track: LocalDBAnlzTrackSource {}
extension TrackWithFKs: LocalDBAnlzTrackSource {}
public struct LocalDBAnlzTrackReference: LocalDBAnlzTrackSource {
    public var analyzePath: String?
    public init(analyzePath: String?) { self.analyzePath = analyzePath }
}

public typealias AnlzResolver = @DJLinkActor (String) async throws -> [UInt8]
public typealias LocalDBAnlzReader = @Sendable ([UInt8]) throws -> [LocalDBAnlzSection]
public struct AnlzResponseDAT: Equatable, Sendable {
    public var beatGrid: BeatGrid?
    public var cueAndLoops: [CueAndLoop]?
    public var waveformPreview: WaveformPreviewData?
    public var waveformTiny: WaveformPreviewData?
    public init(
        beatGrid: BeatGrid? = nil, cueAndLoops: [CueAndLoop]? = nil,
        waveformPreview: WaveformPreviewData? = nil, waveformTiny: WaveformPreviewData? = nil
    ) {
        self.beatGrid = beatGrid
        self.cueAndLoops = cueAndLoops
        self.waveformPreview = waveformPreview
        self.waveformTiny = waveformTiny
    }
}
public struct AnlzResponseEXT: Equatable, Sendable {
    public var waveformHd: WaveformHD?
    public var extendedCues: [ExtendedCue]?
    public var songStructure: SongStructure?
    public var waveformDetail: [UInt8]?
    public var waveformColorPreview: [UInt8]?
    public init(
        waveformHd: WaveformHD? = nil, extendedCues: [ExtendedCue]? = nil,
        songStructure: SongStructure? = nil, waveformDetail: [UInt8]? = nil,
        waveformColorPreview: [UInt8]? = nil
    ) {
        self.waveformHd = waveformHd
        self.extendedCues = extendedCues
        self.songStructure = songStructure
        self.waveformDetail = waveformDetail
        self.waveformColorPreview = waveformColorPreview
    }
}
public struct AnlzResponse2EX: Equatable, Sendable {
    public var waveform3BandPreview: Waveform3BandPreview?
    public var waveform3BandDetail: Waveform3BandDetail?
    public var vocalConfig: VocalConfig?
    public init(
        waveform3BandPreview: Waveform3BandPreview? = nil,
        waveform3BandDetail: Waveform3BandDetail? = nil, vocalConfig: VocalConfig? = nil
    ) {
        self.waveform3BandPreview = waveform3BandPreview
        self.waveform3BandDetail = waveform3BandDetail
        self.vocalConfig = vocalConfig
    }
}
public struct AnlzResponse: Equatable, Sendable {
    public var DAT = AnlzResponseDAT()
    public var EXT = AnlzResponseEXT()
    public var EX2 = AnlzResponse2EX()
    public var beatGrid: BeatGrid? {
        get { DAT.beatGrid }
        set { DAT.beatGrid = newValue }
    }
    public var cueAndLoops: [CueAndLoop]? {
        get { DAT.cueAndLoops }
        set { DAT.cueAndLoops = newValue }
    }
    public var waveformPreview: WaveformPreviewData? {
        get { DAT.waveformPreview }
        set { DAT.waveformPreview = newValue }
    }
    public var waveformTiny: WaveformPreviewData? {
        get { DAT.waveformTiny }
        set { DAT.waveformTiny = newValue }
    }
    public var waveformHd: WaveformHD? {
        get { EXT.waveformHd }
        set { EXT.waveformHd = newValue }
    }
    public var extendedCues: [ExtendedCue]? {
        get { EXT.extendedCues }
        set { EXT.extendedCues = newValue }
    }
    public var songStructure: SongStructure? {
        get { EXT.songStructure }
        set { EXT.songStructure = newValue }
    }
    public var waveformDetail: [UInt8]? {
        get { EXT.waveformDetail }
        set { EXT.waveformDetail = newValue }
    }
    public var waveformColorPreview: [UInt8]? {
        get { EXT.waveformColorPreview }
        set { EXT.waveformColorPreview = newValue }
    }
    public var waveform3BandPreview: Waveform3BandPreview? {
        get { EX2.waveform3BandPreview }
        set { EX2.waveform3BandPreview = newValue }
    }
    public var waveform3BandDetail: Waveform3BandDetail? {
        get { EX2.waveform3BandDetail }
        set { EX2.waveform3BandDetail = newValue }
    }
    public var vocalConfig: VocalConfig? {
        get { EX2.vocalConfig }
        set { EX2.vocalConfig = newValue }
    }
    public init() {}
}
public struct AnlzType<Response: Sendable>: Sendable {
    let extensionName: String
    let extract: @Sendable (AnlzResponse) -> Response
}
extension AnlzType where Response == AnlzResponseDAT {
    public static var dat: Self { .init(extensionName: "DAT", extract: { $0.DAT }) }
}
extension AnlzType where Response == AnlzResponseEXT {
    public static var ext: Self { .init(extensionName: "EXT", extract: { $0.EXT }) }
}
extension AnlzType where Response == AnlzResponse2EX {
    public static var ex2: Self { .init(extensionName: "2EX", extract: { $0.EX2 }) }
}
public struct HydrationProgress: Equatable, Sendable {
    public var table: String
    public var total: Int
    public var complete: Int
    public init(table: String, total: Int, complete: Int) {
        self.table = table
        self.total = total
        self.complete = complete
    }
}
@DJLinkActor public struct HydrationOptions {
    public var orm: MetadataORM
    public var pdbData: [UInt8]
    public var span: TelemetrySpan?
    public var onProgress: (@DJLinkActor (HydrationProgress) -> Void)?
    public init(
        orm: MetadataORM, pdbData: [UInt8], span: TelemetrySpan? = nil,
        onProgress: (@DJLinkActor (HydrationProgress) -> Void)? = nil
    ) {
        self.orm = orm
        self.pdbData = pdbData
        self.span = span
        self.onProgress = onProgress
    }
}
