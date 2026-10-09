import DJLinkKit

// 원본 passive/localdb.ts가 쓰는 src/localdb의 MetadataORM·hydrateDatabase·OneLibraryAdapter를 잇는 실제 구현.

/// DJLinkKit의 `DatabaseAdapter`를 패시브 쪽 모양으로 감싼다.
@DJLinkActor
final class PassiveDatabaseAdapterBridge: PassiveLocalDBAdapter {
    let base: any DatabaseAdapter

    init(_ base: any DatabaseAdapter) {
        self.base = base
    }

    var type: PassiveLocalDBType {
        switch base.type {
        case .oneLibrary: .oneLibrary
        case .pdb: .pdb
        }
    }

    func findTrack(id: Int) throws -> Track? {
        try base.findTrack(id)
    }

    func findPlaylist(playlistId: Int?) throws -> PassiveLocalDBPlaylistQueryResult {
        let result = try base.findPlaylist(playlistId)
        return PassiveLocalDBPlaylistQueryResult(
            folders: result.folders,
            playlists: result.playlists,
            trackEntries: result.trackEntries
        )
    }

    func close() {
        base.close()
    }
}

/// 기본 백엔드. `configurePassiveLocalDBBackend`나 생성자의 `backend:`로 바꿀 수 있다.
@DJLinkActor
public final class DJLinkKitPassiveLocalDBBackend: PassiveLocalDBBackend {
    public nonisolated init() {}

    public func makeMetadataORM() throws -> any PassiveLocalDBAdapter {
        PassiveDatabaseAdapterBridge(try MetadataORM())
    }

    public func hydrateDatabase(
        orm: any PassiveLocalDBAdapter,
        pdbData: [UInt8],
        span: TelemetrySpan,
        onProgress: @escaping @DJLinkActor (PassiveLocalDBHydrationProgress) -> Void
    ) async throws {
        guard let bridge = orm as? PassiveDatabaseAdapterBridge, let metadataORM = bridge.base as? MetadataORM else {
            throw DJLinkError("Expected MetadataORM")
        }
        try await DJLinkKit.hydrateDatabase(
            HydrationOptions(orm: metadataORM, pdbData: pdbData, span: span) { progress in
                onProgress(
                    PassiveLocalDBHydrationProgress(
                        table: progress.table,
                        total: progress.total,
                        complete: progress.complete
                    )
                )
            }
        )
    }

    public func makeOneLibraryAdapter(tempFile: String) throws -> any PassiveLocalDBAdapter {
        PassiveDatabaseAdapterBridge(try OneLibraryAdapter(dbPath: tempFile))
    }
}
