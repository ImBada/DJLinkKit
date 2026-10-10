import DJLinkKit

// 원본 passive/localdb.ts가 쓰는 src/localdb의 MetadataORM·hydrateDatabase·OneLibraryAdapter를 잇는 실제 구현.

/// 기본 백엔드. `configurePassiveLocalDBBackend`나 생성자의 `backend:`로 바꿀 수 있다.
@DJLinkActor
public final class DJLinkKitPassiveLocalDBBackend: PassiveLocalDBBackend {
    public nonisolated init() {}

    public func makeMetadataORM() throws -> any DatabaseAdapter {
        try MetadataORM()
    }

    public func hydrateDatabase(
        orm: any DatabaseAdapter,
        pdbData: [UInt8],
        span: TelemetrySpan,
        onProgress: @escaping @DJLinkActor (PassiveLocalDBHydrationProgress) -> Void
    ) async throws {
        guard let metadataORM = orm as? MetadataORM else {
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

    public func makeOneLibraryAdapter(tempFile: String) throws -> any DatabaseAdapter {
        try OneLibraryAdapter(dbPath: tempFile)
    }
}
