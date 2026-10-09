public enum GetWaveforms {
    public typealias Options = DBTrackOptions
    @DJLinkActor public static func viaRemote(_ remote: any DBRemoteDatabase, _ opts: Options) async throws
        -> Waveforms?
    {
        guard let conn = try await remote.getDBQuery(opts.deviceId) else { return nil }
        let result = try await conn.query(
            queryDescriptor: opts.queryDescriptor, query: .getWaveformHD, args: .init(trackId: opts.track.id),
            span: opts.span)
        guard case let .waveformHD(hd) = result else { throw DJLinkError("Expected HD waveform query result") }
        if opts.trackType != .streaming { return .init(waveformHd: hd) }
        // Promise.all처럼 두 요청을 모두 시작한 뒤 결과를 기다린다.
        let (previewResult, detailedResult) = try await dbPromiseAll(
            {
                try await conn.query(
                    queryDescriptor: opts.queryDescriptor, query: .getWaveformPreview,
                    args: .init(trackId: opts.track.id), span: opts.span)
            },
            {
                try await conn.query(
                    queryDescriptor: opts.queryDescriptor, query: .getWaveformDetailed,
                    args: .init(trackId: opts.track.id), span: opts.span)
            })
        guard case let .waveformPreview(preview) = previewResult, case let .waveformDetailed(detailed) = detailedResult
        else { throw DJLinkError("Expected waveform query result") }
        let normalPreview: WaveformPreview? =
            preview.allSatisfy { $0.height != nil }
            ? preview.map { .init(height: $0.height!, whiteness: $0.whiteness) } : nil
        return .init(
            waveformHd: hd, waveformPreview: normalPreview, waveformDetailed: detailed,
            rawWaveformPreview: normalPreview == nil ? preview : nil)
    }
    @DJLinkActor public static func viaLocal(
        _ local: any DBLocalDatabase, _ device: Device, _ opts: Options, dependencies: DBDependencies = .init()
    ) async throws -> Waveforms? {
        // 원본의 오류 문구(remote)를 그대로 유지한다.
        guard opts.trackSlot == .usb || opts.trackSlot == .sd else {
            throw DJLinkError("Expected USB or SD slot for remote database query")
        }
        guard try await local.get(opts.deviceId, opts.trackSlot) != nil else { return nil }
        let anlz = try await dependencies.loadAnlz(
            opts.track, "EXT", anlzLoader(device: device, slot: opts.trackSlot, dependencies: dependencies))
        return .init(waveformHd: anlz.waveformHd, waveformColorPreview: anlz.waveformColorPreview)
    }
}
