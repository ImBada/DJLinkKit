public enum GetArtworkThumbnail {
    public typealias Options = DBTrackOptions
    @DJLinkActor public static func viaRemote(_ remote: any DBRemoteDatabase, _ opts: Options) async throws -> [UInt8]?
    {
        guard let conn = try await remote.getDBQuery(opts.deviceId), let artwork = opts.track.artwork else {
            return nil
        }
        let result = try await conn.query(
            queryDescriptor: opts.queryDescriptor, query: .getArtwork, args: .init(artworkId: artwork.id),
            span: opts.span)
        guard case let .artwork(bytes) = result else { throw DJLinkError("Expected artwork query result") }
        return bytes
    }
    @DJLinkActor public static func viaLocal(
        _ local: any DBLocalDatabase, _ device: Device, _ opts: Options, dependencies: DBDependencies = .init()
    ) async throws -> [UInt8]? {
        guard opts.trackSlot == .usb || opts.trackSlot == .sd else {
            throw DJLinkError("Expected USB or SD slot for remote database query")
        }
        guard try await local.get(opts.deviceId, opts.trackSlot) != nil, let path = opts.track.artwork?.path else {
            return nil
        }
        // 원본 await 없는 return fetchFile의 비동기 실패 전파를 유지한다.
        return try await dependencies.fetchFile(device, opts.trackSlot, path, nil, nil)
    }
}
