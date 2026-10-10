public struct TrackAnalysis: Equatable, Sendable {
    public var extendedCues: [ExtendedCue]?
    public var songStructure: SongStructure?
    public var waveformColorPreview: [UInt8]?
    public var waveformHd: WaveformHD?
    public var waveform3BandPreview: Waveform3BandPreview?
    public var waveform3BandDetail: Waveform3BandDetail?
    public var vocalConfig: VocalConfig?
    public init(
        extendedCues: [ExtendedCue]? = nil, songStructure: SongStructure? = nil, waveformColorPreview: [UInt8]? = nil,
        waveformHd: WaveformHD? = nil, waveform3BandPreview: Waveform3BandPreview? = nil,
        waveform3BandDetail: Waveform3BandDetail? = nil, vocalConfig: VocalConfig? = nil
    ) {
        self.extendedCues = extendedCues
        self.songStructure = songStructure
        self.waveformColorPreview = waveformColorPreview
        self.waveformHd = waveformHd
        self.waveform3BandPreview = waveform3BandPreview
        self.waveform3BandDetail = waveform3BandDetail
        self.vocalConfig = vocalConfig
    }
}
public enum GetTrackAnalysis {
    public typealias Options = DBTrackOptions
    @DJLinkActor public static func viaLocal(
        _ local: any DBLocalDatabase, _ device: Device, _ opts: Options, dependencies: DBDependencies = .init()
    ) async throws -> TrackAnalysis? {
        guard opts.trackSlot == .usb || opts.trackSlot == .sd else {
            throw DJLinkError("Expected USB or SD slot for local database query")
        }
        guard try await local.get(opts.deviceId, opts.trackSlot) != nil else { return nil }
        let resolver = anlzLoader(device: device, slot: opts.trackSlot, dependencies: dependencies)
        let (ext, twox) = try await dbPromiseAll(
            {
                try await dependencies.loadAnlz(opts.track, "EXT", resolver)
            },
            {
                try? await dependencies.loadAnlz(opts.track, "2EX", resolver)
            })
        return .init(
            extendedCues: ext.extendedCues, songStructure: ext.songStructure,
            waveformColorPreview: ext.waveformColorPreview, waveformHd: ext.waveformHd,
            waveform3BandPreview: twox?.EX2.waveform3BandPreview, waveform3BandDetail: twox?.EX2.waveform3BandDetail,
            vocalConfig: twox?.EX2.vocalConfig)
    }
}
