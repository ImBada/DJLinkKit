import Foundation

// 원본 onelibrary-connect/src/adapter.ts. 공개 질의와 SQL·빈 값 처리를 그대로 따른다.
@DJLinkActor public final class OneLibraryAdapter: DatabaseAdapter {
    public let type: DatabaseType = .oneLibrary
    private let db: CipherDatabase
    public init(dbPath: String, open: (String) throws -> CipherDatabase = openOneLibraryDb) throws {
        db = try open(dbPath)
    }
    public func close() { db.close() }
    private let trackSQL = """
        SELECT c.*,
                     a.name as artistName,
                     al.name as albumName,
                     g.name as genreName,
                     k.name as keyName,
                     col.name as colorName,
                     lbl.name as labelName,
                     img.path as artworkPath,
                     remix.name as remixerName,
                     orig.name as originalArtistName,
                     comp.name as composerName
              FROM content c
              LEFT JOIN artist a ON c.artist_id_artist = a.artist_id
              LEFT JOIN album al ON c.album_id = al.album_id
              LEFT JOIN genre g ON c.genre_id = g.genre_id
              LEFT JOIN key k ON c.key_id = k.key_id
              LEFT JOIN color col ON c.color_id = col.color_id
              LEFT JOIN label lbl ON c.label_id = lbl.label_id
              LEFT JOIN image img ON c.image_id = img.image_id
              LEFT JOIN artist remix ON c.artist_id_remixer = remix.artist_id
              LEFT JOIN artist orig ON c.artist_id_originalArtist = orig.artist_id
              LEFT JOIN artist comp ON c.artist_id_composer = comp.artist_id
              WHERE c.content_id = ?
        """
    private let allTracksSQL = """
        SELECT c.*,
                     a.name as artistName,
                     al.name as albumName,
                     g.name as genreName,
                     k.name as keyName,
                     col.name as colorName,
                     lbl.name as labelName,
                     img.path as artworkPath,
                     remix.name as remixerName,
                     orig.name as originalArtistName,
                     comp.name as composerName
              FROM content c
              LEFT JOIN artist a ON c.artist_id_artist = a.artist_id
              LEFT JOIN album al ON c.album_id = al.album_id
              LEFT JOIN genre g ON c.genre_id = g.genre_id
              LEFT JOIN key k ON c.key_id = k.key_id
              LEFT JOIN color col ON c.color_id = col.color_id
              LEFT JOIN label lbl ON c.label_id = lbl.label_id
              LEFT JOIN image img ON c.image_id = img.image_id
              LEFT JOIN artist remix ON c.artist_id_remixer = remix.artist_id
              LEFT JOIN artist orig ON c.artist_id_originalArtist = orig.artist_id
              LEFT JOIN artist comp ON c.artist_id_composer = comp.artist_id
        """
    public func findTrack(_ id: Int) throws -> Track? {
        try db.rows(trackSQL, [.int(id)]).first.map(contentToTrack)
    }
    public func findAllTracks() throws -> [Track] { try db.rows(allTracksSQL).map(contentToTrack) }
    private func contentToTrack(_ row: LocalDBRow) -> Track {
        var track = Track(
            id: row.int("content_id") ?? 0, title: row.string("title") ?? "",
            duration: row.int("length") ?? 0,
            tempo: (row.double("bpmx100") ?? 0) / 100, rating: row.int("rating") ?? 0,
            comment: row.string("djComment") ?? "", filePath: row.string("path") ?? "",
            fileName: row.string("fileName") ?? "")
        track.bitrate = row.int("bitrate")
        track.trackNumber = row.int("trackNo")
        track.discNumber = row.int("discNo")
        track.sampleRate = row.int("samplingRate")
        track.sampleDepth = row.int("bitDepth")
        track.playCount = row.int("djPlayCount")
        track.year = row.int("releaseYear")
        track.fileSize = row.int("fileSize")
        track.mixName = row.string("subtitle")
        track.releaseDate = row.string("releaseDate")
        track.autoloadHotcues = (row.int("isHotCueAutoLoadOn") ?? 0) != 0
        track.kuvoPublic = (row.int("isKuvoDeliverStatusOn") ?? 0) != 0
        if let path = row.string("analysisDataFilePath"), !path.isEmpty {
            track.analyzePath = localDBTrimAnalyzePath(path)
        }
        if let date = row.string("dateAdded"), !date.isEmpty {
            track.dateAdded = localDBParseDate(date)
        }
        if let id = row.int("image_id"), id != 0 {
            track.artwork = Artwork(id: id, path: row.string("artworkPath"))
        }
        if let id = row.int("artist_id_artist"), id != 0 {
            track.artist = Artist(id: id, name: row.string("artistName") ?? "")
        }
        if let id = row.int("artist_id_originalArtist"), id != 0 {
            track.originalArtist = Artist(id: id, name: row.string("originalArtistName") ?? "")
        }
        if let id = row.int("artist_id_remixer"), id != 0 {
            track.remixer = Artist(id: id, name: row.string("remixerName") ?? "")
        }
        if let id = row.int("artist_id_composer"), id != 0 {
            track.composer = Artist(id: id, name: row.string("composerName") ?? "")
        }
        if let id = row.int("album_id"), id != 0 {
            track.album = Album(id: id, name: row.string("albumName") ?? "")
        }
        if let id = row.int("label_id"), id != 0 {
            track.label = Label(id: id, name: row.string("labelName") ?? "")
        }
        if let id = row.int("genre_id"), id != 0 {
            track.genre = Genre(id: id, name: row.string("genreName") ?? "")
        }
        if let id = row.int("color_id"), id != 0 {
            track.color = Color(id: id, name: row.string("colorName") ?? "")
        }
        if let id = row.int("key_id"), id != 0 {
            track.key = Key(id: id, name: row.string("keyName") ?? "")
        }
        return track
    }
    public func findCues(_ trackId: Int) throws -> [CueAndLoop] {
        try db.rows("SELECT * FROM cue WHERE content_id = ?", [.int(trackId)]).map { row in
            let input = row.double("inUsec") ?? 0
            let output = row.double("outUsec")
            let offset = input / 1000
            let isLoop = (output ?? 0) > 0
            let length = isLoop ? ((output ?? 0) - input) / 1000 : 0
            let kind = row.int("kind") ?? 0
            let isHotCue = (1...8).contains(kind)
            let button = HotcueButton(rawValue: kind)
            let label = row.string("cueComment")
            let color = row.int("colorTableIndex").map(CueColor.init(rawValue:))
            if isLoop && isHotCue {
                return .hotLoop(
                    .init(offset: offset, label: label, color: color, button: button, length: length))
            }
            if isLoop { return .loop(.init(offset: offset, label: label, color: color, length: length)) }
            if isHotCue {
                return .hotCue(.init(offset: offset, label: label, color: color, button: button))
            }
            return .cuePoint(.init(offset: offset, label: label, color: color))
        }
    }
    private func playlistRowToPlaylist(_ row: LocalDBRow) -> Playlist {
        .init(
            id: row.int("playlist_id") ?? 0, name: row.string("name") ?? "",
            isFolder: row.int("attribute") == 1, parentId: row.int("playlist_id_parent"))
    }
    public func findPlaylistById(_ playlistId: Int) throws -> Playlist? {
        try db.rows("SELECT * FROM playlist WHERE playlist_id = ?", [.int(playlistId)]).first.map(
            playlistRowToPlaylist)
    }
    public func findPlaylist(_ playlistId: Int? = nil) throws -> PlaylistQueryResult {
        let parentCondition =
            playlistId == nil ? "playlist_id_parent IS NULL" : "playlist_id_parent = ?"
        let rows = try db.rows(
            "SELECT * FROM playlist WHERE \(parentCondition)", playlistId.map { [.int($0)] } ?? []
        ).map(playlistRowToPlaylist)
        let entries =
            try playlistId.map {
                try db.rows(
                    "SELECT * FROM playlist_content WHERE playlist_id = ? ORDER BY sequenceNo", [.int($0)])
            } ?? []
        return .init(
            folders: rows.filter(\.isFolder), playlists: rows.filter { !$0.isFolder },
            trackEntries: entries.enumerated().map { i, row in
                .init(
                    id: i, sortIndex: row.int("sequenceNo") ?? 0, playlistId: row.int("playlist_id") ?? 0,
                    trackId: row.int("content_id") ?? 0)
            })
    }
    public func findArtist(_ artistId: Int) throws -> Artist? {
        try db.rows("SELECT * FROM artist WHERE artist_id = ?", [.int(artistId)]).first.map { row in
            .init(id: row.int("artist_id") ?? 0, name: row.string("name") ?? "")
        }
    }
    public func findAlbum(_ albumId: Int) throws -> Album? {
        try db.rows("SELECT * FROM album WHERE album_id = ?", [.int(albumId)]).first.map { row in
            .init(id: row.int("album_id") ?? 0, name: row.string("name") ?? "")
        }
    }
    public func findGenre(_ genreId: Int) throws -> Genre? {
        try db.rows("SELECT * FROM genre WHERE genre_id = ?", [.int(genreId)]).first.map { row in
            .init(id: row.int("genre_id") ?? 0, name: row.string("name") ?? "")
        }
    }
    public func findKey(_ keyId: Int) throws -> Key? {
        try db.rows("SELECT * FROM key WHERE key_id = ?", [.int(keyId)]).first.map { row in
            .init(id: row.int("key_id") ?? 0, name: row.string("name") ?? "")
        }
    }
    public func findColor(_ colorId: Int) throws -> Color? {
        try db.rows("SELECT * FROM color WHERE color_id = ?", [.int(colorId)]).first.map { row in
            .init(id: row.int("color_id") ?? 0, name: row.string("name") ?? "")
        }
    }
    public func findLabel(_ labelId: Int) throws -> Label? {
        try db.rows("SELECT * FROM label WHERE label_id = ?", [.int(labelId)]).first.map { row in
            .init(id: row.int("label_id") ?? 0, name: row.string("name") ?? "")
        }
    }
    public func findArtwork(_ imageId: Int) throws -> Artwork? {
        try db.rows("SELECT * FROM image WHERE image_id = ?", [.int(imageId)]).first.map { row in
            .init(id: row.int("image_id") ?? 0, path: row.string("path"))
        }
    }
    public func findPlaylistContents(_ playlistId: Int) throws -> [Int] {
        try db.rows(
            "SELECT content_id FROM playlist_content WHERE playlist_id = ? ORDER BY sequenceNo",
            [.int(playlistId)]
        ).map { $0.int("content_id") ?? 0 }
    }
    public func findMyTagContents(_ myTagId: Int) throws -> [Int] {
        try db.rows("SELECT content_id FROM myTag_content WHERE myTag_id = ?", [.int(myTagId)]).map {
            $0.int("content_id") ?? 0
        }
    }
    public func findHistoryContents(_ historyId: Int) throws -> [Int] {
        try db.rows(
            "SELECT content_id FROM history_content WHERE history_id = ? ORDER BY sequenceNo",
            [.int(historyId)]
        ).map { $0.int("content_id") ?? 0 }
    }
    public func findHotCueBankListCues(_ bankListId: Int) throws -> [Int] {
        try db.rows(
            "SELECT cue_id FROM hotCueBankList_cue WHERE hotCueBankList_id = ? ORDER BY sequenceNo",
            [.int(bankListId)]
        ).map { $0.int("cue_id") ?? 0 }
    }
    private func myTagRowToMyTag(_ row: LocalDBRow) -> MyTag {
        .init(
            id: row.int("myTag_id") ?? 0, name: row.string("name") ?? "",
            isFolder: row.int("attribute") == 1, parentId: row.int("myTag_id_parent"))
    }
    public func findMyTags(_ parentId: Int? = nil) throws -> (folders: [MyTag], tags: [MyTag]) {
        let condition =
            parentId == nil ? "myTag_id_parent IS NULL OR myTag_id_parent = 0" : "myTag_id_parent = ?"
        let rows = try db.rows(
            "SELECT * FROM myTag WHERE \(condition) ORDER BY sequenceNo",
            parentId.map { [.int($0)] } ?? []
        ).map(myTagRowToMyTag)
        return (rows.filter(\.isFolder), rows.filter { !$0.isFolder })
    }
    public func findMyTagById(_ myTagId: Int) throws -> MyTag? {
        try db.rows("SELECT * FROM myTag WHERE myTag_id = ?", [.int(myTagId)]).first.map(
            myTagRowToMyTag)
    }
    public func findMyTagsForTrack(_ trackId: Int) throws -> [MyTag] {
        try db.rows(
            "SELECT t.* FROM myTag t INNER JOIN myTag_content tc ON t.myTag_id = tc.myTag_id WHERE tc.content_id = ?",
            [.int(trackId)]
        ).map(myTagRowToMyTag)
    }
    public func findHistorySessions() throws -> [HistorySession] {
        try db.rows("SELECT * FROM history ORDER BY sequenceNo").map { row in
            .init(
                id: row.int("history_id") ?? 0, name: row.string("name") ?? "",
                parentId: row.int("history_id_parent"))
        }
    }
    public func findHotCueBankLists() throws -> [HotCueBankList] {
        try db.rows("SELECT * FROM hotCueBankList ORDER BY sequenceNo").map { row in
            .init(
                id: row.int("hotCueBankList_id") ?? 0, name: row.string("name") ?? "",
                parentId: row.int("hotCueBankList_id_parent"))
        }
    }
    public func findMenuItems() throws -> [MenuItem] {
        try db.rows("SELECT * FROM menuItem ORDER BY menuItem_id").map { row in
            .init(
                id: row.int("menuItem_id") ?? 0, kind: row.int("kind") ?? 0, name: row.string("name") ?? "")
        }
    }
    public func findVisibleCategories() throws -> [Category] {
        try db.rows(
            "SELECT c.*, m.name as menuName, m.kind as menuKind FROM category c LEFT JOIN menuItem m ON c.menuItem_id = m.menuItem_id WHERE c.isVisible = 1 ORDER BY c.sequenceNo"
        ).map { row in
            .init(
                id: row.int("category_id") ?? 0, menuItemId: row.int("menuItem_id") ?? 0,
                name: row.string("menuName") ?? "", kind: row.int("menuKind") ?? 0,
                isVisible: (row.int("isVisible") ?? 0) != 0)
        }
    }
    public func findVisibleSortOptions() throws -> [SortOption] {
        try db.rows(
            "SELECT s.*, m.name as menuName, m.kind as menuKind FROM sort s LEFT JOIN menuItem m ON s.menuItem_id = m.menuItem_id WHERE s.isVisible = 1 ORDER BY s.sequenceNo"
        ).map { row in
            .init(
                id: row.int("sort_id") ?? 0, menuItemId: row.int("menuItem_id") ?? 0,
                name: row.string("menuName") ?? "", kind: row.int("menuKind") ?? 0,
                isVisible: (row.int("isVisible") ?? 0) != 0,
                isSelectedAsSubColumn: (row.int("isSelectedAsSubColumn") ?? 0) != 0)
        }
    }
    public func getProperty() throws -> DeviceProperty? {
        try db.rows("SELECT * FROM property LIMIT 1").first.map { row in
            .init(
                deviceName: row.string("deviceName") ?? "", dbVersion: row.string("dbVersion") ?? "",
                numberOfContents: row.int("numberOfContents") ?? 0,
                createdDate: row.string("createdDate") ?? "",
                backgroundColorType: row.int("backGroundColorType") ?? 0)
        }
    }
}
func localDBParseDate(_ text: String) -> Date? {
    let format = ISO8601DateFormatter()
    if text.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil {
        format.formatOptions = [.withFullDate]
        return format.date(from: text)
    }
    if text.range(of: "(?:Z|[+-][0-9]{2}:?[0-9]{2})$", options: .regularExpression) != nil {
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: text) { return date }
        format.formatOptions = [.withInternetDateTime]
        if let date = format.date(from: text) { return date }
    }
    let local = DateFormatter()
    local.locale = Locale(identifier: "en_US_POSIX")
    local.calendar = Calendar(identifier: .gregorian)
    local.timeZone = .current
    for pattern in [
        "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss.SSSXXXXX", "yyyy-MM-dd HH:mm:ssXXXXX",
    ] {
        local.dateFormat = pattern
        if let date = local.date(from: text) { return date }
    }
    return nil
}
func localDBISOString(_ date: Date) -> String {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.string(from: date)
}
