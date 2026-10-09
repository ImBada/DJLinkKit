public enum GetFile {
    public typealias Options = DBTrackOptions
    @DJLinkActor public static func viaRemote(_ remote: any DBRemoteDatabase, _ device: Device, _ opts: Options)
        -> [UInt8]?
    {
        (opts.logger ?? noopLogger).error("Getting a file from Rekordbox via ProDJ-Link is not yet supported.")
        return nil
    }
    @DJLinkActor public static func viaLocal(
        _ local: any DBLocalDatabase, _ device: Device, _ opts: Options, dependencies: DBDependencies = .init()
    ) async throws -> [UInt8]? {
        guard opts.trackSlot == .usb || opts.trackSlot == .sd else {
            throw DJLinkError("Expected USB or SD or RB slot for remote database query")
        }
        guard try await local.get(opts.deviceId, opts.trackSlot) != nil else { return nil }
        let logger = opts.logger ?? noopLogger
        // 원본은 try 안에서 await 없이 Promise를 반환하므로 비동기 실패는 catch되지 않는다.
        return try await dependencies.fetchFile(
            device, opts.trackSlot, opts.track.filePath,
            { progress in logger.trace("%d %d", progress.read, progress.total) }, 8192)
    }
}
