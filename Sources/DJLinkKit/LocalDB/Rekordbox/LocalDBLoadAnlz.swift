@DJLinkActor public func loadAnlz(
    _ track: any LocalDBAnlzTrackSource, type: String, anlzResolver: AnlzResolver,
    reader: LocalDBAnlzReader = readLocalDBAnlz
) async throws -> AnlzResponse {
    let path = "\(track.analyzePath ?? "undefined").\(type)"
    let sections = try reader(await anlzResolver(path))
    var result = AnlzResponse()
    for section in sections {
        switch section.fourcc {
        case "PQTZ": result.DAT.beatGrid = makeBeatGrid(section)
        // PLAN §9: 원본은 태그마다 덮어써서 핫 큐(1)·메모리(0) 목록 중 마지막 태그만 남았다.
        // 같은 종류 태그를 파일 순서대로 잇는다. 태그가 하나면 결과가 같고, 없으면 nil이다.
        case "PCOB": result.DAT.cueAndLoops = (result.DAT.cueAndLoops ?? []) + makeCueAndLoop(section)
        case "PCO2": result.EXT.extendedCues = (result.EXT.extendedCues ?? []) + makeExtendedCues(section)
        case "PWAV": result.DAT.waveformPreview = makeWaveformPreview(section)
        case "PWV2": result.DAT.waveformTiny = makeWaveformPreview(section)
        case "PWV3": result.EXT.waveformDetail = section.entries
        case "PWV4": result.EXT.waveformColorPreview = section.entries
        case "PWV5": result.EXT.waveformHd = try makeWaveformHd(section)
        case "PSSI": result.EXT.songStructure = makeSongStructure(section)
        case "PWV6": result.EX2.waveform3BandPreview = makeWaveform3BandPreview(section)
        case "PWV7": result.EX2.waveform3BandDetail = makeWaveform3BandDetail(section)
        case "PWVC": result.EX2.vocalConfig = makeVocalConfig(section)
        default: break
        }
    }
    return result
}
@DJLinkActor public func loadAnlz<Response>(
    _ track: any LocalDBAnlzTrackSource, type: AnlzType<Response>, anlzResolver: AnlzResolver,
    reader: LocalDBAnlzReader = readLocalDBAnlz
) async throws -> Response {
    type.extract(
        try await loadAnlz(track, type: type.extensionName, anlzResolver: anlzResolver, reader: reader))
}
