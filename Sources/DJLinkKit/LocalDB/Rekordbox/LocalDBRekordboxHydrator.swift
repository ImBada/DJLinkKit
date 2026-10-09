import Foundation

@DJLinkActor public final class RekordboxHydrator {
    private let orm: MetadataORM
    private let onProgress: @DJLinkActor (HydrationProgress) -> Void
    private let reader: LocalDBPdbReader
    private let clock: any DJLinkClock
    public init(
        orm: MetadataORM, onProgress: (@DJLinkActor (HydrationProgress) -> Void)? = nil,
        reader: @escaping LocalDBPdbReader = readLocalDBPdb, clock: any DJLinkClock = SystemClock.shared
    ) {
        self.orm = orm
        self.onProgress = onProgress ?? { _ in }
        self.reader = reader
        self.clock = clock
    }
    public func hydrateFromPdb(_ pdbData: [UInt8], span: TelemetrySpan? = nil) async throws {
        let tx =
            span?.startChild(.init(op: "hydrateFromPdb"))
            ?? Telemetry.startTransaction(.init(name: "hydrateFromPdb"))
        let parseTx = tx.startChild(.init(op: "parsePdbData"))
        parseTx.setData("size", pdbData.count)
        let tables = try reader(pdbData)
        parseTx.finish()
        let hydrateTx = tx.startChild(.init(op: "hydration"))
        // 원본 Promise.all처럼 표 작업을 모두 시작하고 첫 오류를 바로 돌려준다.
        if !tables.isEmpty {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                var remaining = tables.count
                var settled = false
                for table in tables {
                    Task { @DJLinkActor in
                        do {
                            try await hydrateFromTable(table, span: hydrateTx)
                            remaining -= 1
                            if remaining == 0 && !settled {
                                settled = true
                                continuation.resume()
                            }
                        } catch {
                            if !settled {
                                settled = true
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }
        }
        hydrateTx.finish()
        tx.finish()
    }
    public func hydrateFromTable(_ table: LocalDBPdbTable, span: TelemetrySpan) async throws {
        let tableName = pdbTables[table.type]
        let tx = span.startChild(.init(op: "hydrateFromTable", description: tableName?.rawValue))
        guard let tableName else { return }
        let totalItems = table.rows.count
        tx.setData("items", totalItems)
        try orm.beginTransaction()
        do {
            for (i, bytes) in table.rows.enumerated() {
                var row = PdbRowReader(bytes)
                switch table.type {
                case 0:
                    let pdbRow = try PdbRows.track(&row)
                    try orm.insertEntity(tableName, createTrack(pdbRow), pdbRow: pdbRow)
                case 2: try orm.insertEntity(tableName, PdbRows.artist(&row))
                case 3: try orm.insertEntity(tableName, PdbRows.album(&row))
                case 5: try orm.insertEntity(tableName, PdbRows.key(&row))
                case 6: try orm.insertEntity(tableName, PdbRows.color(&row))
                case 7: try orm.insertEntity(tableName, PdbRows.playlistTree(&row))
                case 8:
                    // 원본 undefined는 NULL로 묶이고 INTEGER PRIMARY KEY가 id를 부여한다.
                    try orm.insertEntity(tableName, PdbRows.playlistEntry(row))
                case 13: try orm.insertEntity(tableName, PdbRows.artwork(&row))
                default:
                    let entity = try PdbRows.idName(&row)
                    try orm.insertEntity(tableName, ["id": .int(entity.id), "name": .text(entity.name)])
                }
                let complete = i + 1
                if complete % 100 == 0 || complete == totalItems {
                    onProgress(.init(table: tableName.rawValue, total: totalItems, complete: complete))
                    await withCheckedContinuation { continuation in
                        _ = clock.setTimeout(.milliseconds(0)) { continuation.resume() }
                    }
                }
            }
        } catch {
            try orm.commit()
            throw error
        }
        try orm.commit()
        tx.finish()
    }
}
@DJLinkActor public func hydrateDatabase(
    _ options: HydrationOptions, reader: @escaping LocalDBPdbReader = readLocalDBPdb,
    clock: any DJLinkClock = SystemClock.shared
) async throws {
    let hydrator = RekordboxHydrator(
        orm: options.orm, onProgress: options.onProgress, reader: reader, clock: clock)
    try await hydrator.hydrateFromPdb(options.pdbData, span: options.span)
}
