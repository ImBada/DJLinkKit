public enum GetPlaylist {
    public struct Options: Sendable {
        public var playlist: Playlist?
        public var deviceId: DeviceID
        public var mediaSlot: MediaSlot
        public var span: TelemetrySpan?
        public init(deviceId: DeviceID, mediaSlot: MediaSlot, playlist: Playlist? = nil, span: TelemetrySpan? = nil) {
            self.playlist = playlist
            self.deviceId = deviceId
            self.mediaSlot = mediaSlot
            self.span = span
        }
    }
    @DJLinkActor public static func viaRemote(_ remote: any DBRemoteDatabase, _ opts: Options) async throws
        -> PlaylistContents?
    {
        guard let conn = try await remote.getDBQuery(opts.deviceId) else { return nil }
        let descriptor = QueryDescriptor(menuTarget: .main, trackSlot: opts.mediaSlot, trackType: .rb)
        let result = try await conn.query(
            queryDescriptor: descriptor, query: .menuPlaylist,
            args: .init(id: opts.playlist?.id, isFolderRequest: opts.playlist?.isFolder ?? true), span: opts.span)
        guard case let .playlist(playlist) = result else { throw DJLinkError("Expected playlist query result") }
        let entries = playlist.trackEntries
        let cursor = DBPlaylistCursor(count: entries.count) { index in
            // 원본 remote 메뉴 항목의 id는 곡 번호다. 로컬 entry의 row id와 구별한다.
            try dbTrackResult(
                await conn.query(
                    queryDescriptor: descriptor, query: .getMetadata, args: .init(trackId: entries[index].id),
                    span: opts.span))
        }
        return .init(
            playlists: playlist.playlists, folders: playlist.folders, tracks: cursor.tracks(),
            totalTracks: entries.count)
    }
    @DJLinkActor public static func viaLocal(_ local: any DBLocalDatabase, _ opts: Options) async throws
        -> PlaylistContents?
    {
        guard opts.mediaSlot == .usb || opts.mediaSlot == .sd else {
            throw DJLinkError("Expected USB or SD slot for local database query")
        }
        guard let orm = try await local.get(opts.deviceId, opts.mediaSlot) else { return nil }
        let result = try orm.findPlaylist(opts.playlist?.id)
        let entries = result.trackEntries
        let cursor = DBPlaylistCursor(count: entries.count) { index in
            // 원본은 없어진 곡에서 null을 yield할 수 있지만 지정된 Stream<Track>에는 담을 수 없다.
            guard let track = try orm.findTrack(entries[index].trackId) else {
                throw DJLinkError("Playlist track \(entries[index].trackId) not found")
            }
            return track
        }
        return .init(
            playlists: result.playlists, folders: result.folders, tracks: cursor.tracks(), totalTracks: entries.count)
    }
}

// 원본 async generator처럼 next가 불릴 때 곡을 조회한다. 순회마다 새 커서(처음부터)를 만든다.
@DJLinkActor private final class DBPlaylistCursor {
    private let count: Int
    private let lookup: @DJLinkActor @Sendable (Int) async throws -> Track

    init(count: Int, lookup: @escaping @DJLinkActor @Sendable (Int) async throws -> Track) {
        self.count = count
        self.lookup = lookup
    }

    func tracks() -> PlaylistTracks {
        let count = count
        let lookup = lookup
        return PlaylistTracks {
            let position = DBPlaylistPosition()
            return AsyncThrowingStream(unfolding: {
                guard let index = await position.take(below: count) else { return nil }
                return try await lookup(index)
            })
        }
    }
}

/// 한 번의 순회가 어디까지 왔는지.
@DJLinkActor private final class DBPlaylistPosition {
    private var index = 0

    nonisolated init() {}

    func take(below count: Int) -> Int? {
        guard index < count else { return nil }
        defer { index += 1 }
        return index
    }
}
