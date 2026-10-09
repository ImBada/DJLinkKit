import Foundation

// 원본 localdb/orm.ts. 메모리 SQLite의 내부 연결만 SQLCipher C API로 바꿨다.
public enum Table: String, Sendable, CaseIterable {
    case artist, album, genre, color, label, key, artwork, playlist
    case playlistEntry = "playlist_entry"
    case track
}
@DJLinkActor public final class MetadataORM: DatabaseAdapter {
    public let type: DatabaseType = .pdb
    private let conn: CipherDatabase
    private var inTransaction = false
    public init() throws {
        conn = try CipherDatabase(path: ":memory:", key: nil as CipherKey?, mode: .create)
        try conn.execute(generateSchema())
    }
    public func close() { conn.close() }
    public func beginTransaction() throws {
        if !inTransaction {
            try conn.execute("BEGIN TRANSACTION")
            inTransaction = true
        }
    }
    public func commit() throws {
        if inTransaction {
            try conn.execute("COMMIT")
            inTransaction = false
        }
    }
    public func insertEntity(_ table: Table, _ object: LocalDBRow) throws {
        let fields = object.keys.sorted()
        let columns = fields.map(localDBSnakeCase).joined(separator: ", ")
        let slots = fields.map { _ in "?" }.joined(separator: ", ")
        try conn.run(
            "insert into \(table.rawValue) (\(columns)) values (\(slots))", fields.map { object[$0]! })
    }
    public func insertEntity<T: NamedEntity>(_ table: Table, _ object: T) throws {
        try insertEntity(table, ["id": .int(object.id), "name": .text(object.name)])
    }
    public func insertEntity(_ table: Table, _ object: Artwork) throws {
        try insertEntity(
            table, ["id": .int(object.id), "path": object.path.map { .text($0) } ?? .null])
    }
    public func insertEntity(_ table: Table, _ object: Playlist) throws {
        try insertEntity(
            table,
            [
                "id": .int(object.id), "name": .text(object.name),
                "isFolder": .int(object.isFolder ? 1 : 0),
                "parentId": object.parentId.map { .int($0) } ?? .null,
            ])
    }
    public func insertEntity(_ table: Table, _ object: PlaylistEntryWithFKs) throws {
        try insertEntity(
            table,
            [
                "id": .int(object.id), "sortIndex": .int(object.sortIndex),
                "playlistId": .int(object.playlistId), "trackId": .int(object.trackId),
            ])
    }
    public func insertEntity(_ table: Table, _ object: TrackWithFKs, pdbRow: LocalDBRow? = nil) throws {
        var row: LocalDBRow = [:]
        row["id"] = .int(object.id)
        row["title"] = .text(object.title)
        row["duration"] = .int(object.duration)
        row["bitrate"] = object.bitrate.map { .int($0) } ?? .null
        row["tempo"] = .real(object.tempo)
        row["rating"] = .int(object.rating)
        row["comment"] = .text(object.comment)
        row["filePath"] = .text(object.filePath)
        row["fileName"] = .text(object.fileName)
        row["trackNumber"] = object.trackNumber.map { .int($0) } ?? .null
        row["discNumber"] = object.discNumber.map { .int($0) } ?? .null
        row["sampleRate"] = object.sampleRate.map { .int($0) } ?? .null
        row["sampleDepth"] = object.sampleDepth.map { .int($0) } ?? .null
        row["playCount"] = object.playCount.map { .int($0) } ?? .null
        row["year"] = object.year.map { .int($0) } ?? .null
        row["mixName"] = object.mixName.map { .text($0) } ?? .null
        row["autoloadHotcues"] = .int(object.autoloadHotcues == true ? 1 : 0)
        row["kuvoPublic"] = .int(object.kuvoPublic == true ? 1 : 0)
        row["fileSize"] = object.fileSize.map { .int($0) } ?? .null
        row["analyzePath"] = object.analyzePath.map { .text($0) } ?? .null
        row["releaseDate"] = object.releaseDate.map { .text($0) } ?? .null
        row["analyzeDate"] =
            object.analyzeDate.map { .text(localDBISOString($0)) } ?? .null
        row["dateAdded"] =
            object.dateAdded.map { .text(localDBISOString($0)) } ?? .null
        row["artworkId"] = object.artworkId.map { .int($0) } ?? .null
        row["artistId"] = object.artistId.map { .int($0) } ?? .null
        row["originalArtistId"] = object.originalArtistId.map { .int($0) } ?? .null
        row["remixerId"] = object.remixerId.map { .int($0) } ?? .null
        row["composerId"] = object.composerId.map { .int($0) } ?? .null
        row["albumId"] = object.albumId.map { .int($0) } ?? .null
        row["labelId"] = object.labelId.map { .int($0) } ?? .null
        row["genreId"] = object.genreId.map { .int($0) } ?? .null
        row["colorId"] = object.colorId.map { .int($0) } ?? .null
        row["keyId"] = object.keyId.map { .int($0) } ?? .null
        if let pdbRow {
            // 생략된 text는 원본 바인딩처럼 NULL로 둔다. NOT NULL 제약 오류도 그대로 전달한다.
            for (source, target) in [
                ("title", "title"), ("mixName", "mixName"), ("comment", "comment"),
                ("filePath", "filePath"), ("filename", "fileName"),
                ("releaseDate", "releaseDate"), ("analyzePath", "analyzePath"),
            ] {
                if pdbRow[source] == .null {
                    row[target] = .null
                }
            }
        }
        try insertEntity(table, row)
    }
    public func findTrack(_ id: Int) throws -> Track? {
        guard let raw = try conn.rows("select * from track where id = ?", [.int(id)]).first else {
            return nil
        }
        let row = Dictionary(uniqueKeysWithValues: raw.map { (localDBCamelCase($0.key), $0.value) })
        var track = Track(
            id: row.int("id") ?? 0, title: row.string("title") ?? "", duration: row.int("duration") ?? 0,
            tempo: row.double("tempo") ?? 0, rating: row.int("rating") ?? 0,
            comment: row.string("comment") ?? "", filePath: row.string("filePath") ?? "",
            fileName: row.string("fileName") ?? "")
        track.bitrate = row.int("bitrate")
        track.trackNumber = row.int("trackNumber")
        track.discNumber = row.int("discNumber")
        track.sampleRate = row.int("sampleRate")
        track.sampleDepth = row.int("sampleDepth")
        track.playCount = row.int("playCount")
        track.year = row.int("year")
        track.mixName = row.string("mixName")
        track.autoloadHotcues = (row.int("autoloadHotcues") ?? 0) != 0
        track.kuvoPublic = (row.int("kuvoPublic") ?? 0) != 0
        track.fileSize = row.int("fileSize")
        track.analyzePath = row.string("analyzePath")
        track.releaseDate = row.string("releaseDate")
        track.analyzeDate =
            row.string("analyzeDate").map(localDBParseDate) ?? Date(timeIntervalSince1970: 0)
        track.dateAdded =
            row.string("dateAdded").map(localDBParseDate) ?? Date(timeIntervalSince1970: 0)
        if let fk = row.int("artworkId"),
            let relation = try conn.rows("select * from artwork where id = ?", [.int(fk)]).first
        {
            track.artwork = Artwork(id: relation.int("id") ?? 0, path: relation.string("path"))
        }
        if let fk = row.int("artistId"),
            let relation = try conn.rows("select * from artist where id = ?", [.int(fk)]).first
        {
            track.artist = Artist(id: relation.int("id") ?? 0, name: relation.string("name") ?? "")
        }
        if let fk = row.int("originalArtistId"),
            let relation = try conn.rows("select * from artist where id = ?", [.int(fk)]).first
        {
            track.originalArtist = Artist(
                id: relation.int("id") ?? 0, name: relation.string("name") ?? "")
        }
        if let fk = row.int("remixerId"),
            let relation = try conn.rows("select * from artist where id = ?", [.int(fk)]).first
        {
            track.remixer = Artist(id: relation.int("id") ?? 0, name: relation.string("name") ?? "")
        }
        if let fk = row.int("composerId"),
            let relation = try conn.rows("select * from artist where id = ?", [.int(fk)]).first
        {
            track.composer = Artist(id: relation.int("id") ?? 0, name: relation.string("name") ?? "")
        }
        if let fk = row.int("albumId"),
            let relation = try conn.rows("select * from album where id = ?", [.int(fk)]).first
        {
            track.album = Album(id: relation.int("id") ?? 0, name: relation.string("name") ?? "")
        }
        if let fk = row.int("labelId"),
            let relation = try conn.rows("select * from label where id = ?", [.int(fk)]).first
        {
            track.label = Label(id: relation.int("id") ?? 0, name: relation.string("name") ?? "")
        }
        if let fk = row.int("genreId"),
            let relation = try conn.rows("select * from genre where id = ?", [.int(fk)]).first
        {
            track.genre = Genre(id: relation.int("id") ?? 0, name: relation.string("name") ?? "")
        }
        if let fk = row.int("colorId"),
            let relation = try conn.rows("select * from color where id = ?", [.int(fk)]).first
        {
            track.color = Color(id: relation.int("id") ?? 0, name: relation.string("name") ?? "")
        }
        if let fk = row.int("keyId"),
            let relation = try conn.rows("select * from key where id = ?", [.int(fk)]).first
        {
            track.key = Key(id: relation.int("id") ?? 0, name: relation.string("name") ?? "")
        }
        return track
    }
    public func findPlaylist(_ playlistId: Int? = nil) throws -> PlaylistQueryResult {
        let condition = playlistId == nil ? "parent_id is ?" : "parent_id = ?"
        let rows = try conn.rows(
            "select * from playlist where \(condition)", [playlistId.map { .int($0) } ?? .null]
        ).map { row in
            Playlist(
                id: row.int("id") ?? 0, name: row.string("name") ?? "",
                isFolder: (row.int("is_folder") ?? 0) != 0, parentId: row.int("parent_id"))
        }
        let entries = try conn.rows(
            "select * from playlist_entry where playlist_id = ?", [playlistId.map { .int($0) } ?? .null]
        ).map { row in
            PlaylistEntryWithFKs(
                id: row.int("id") ?? 0, sortIndex: row.int("sort_index") ?? 0,
                playlistId: row.int("playlist_id") ?? 0, trackId: row.int("track_id") ?? 0)
        }
        return .init(
            folders: rows.filter(\.isFolder), playlists: rows.filter { !$0.isFolder },
            trackEntries: entries)
    }
}
func localDBSnakeCase(_ string: String) -> String {
    string.enumerated().map { i, c in c.isUppercase ? (i > 0 ? "_" : "") + c.lowercased() : String(c)
    }.joined()
}
func localDBCamelCase(_ string: String) -> String {
    let parts = string.split(separator: "_")
    return (parts.first.map(String.init) ?? "")
        + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
}
