import Foundation

// 원본 localdb/rekordbox/entity-creators.ts. 문자열의 body.text는 리더 경계에서 평평하게 만든다.
public func makeIdNameHydrator<T: NamedEntity>(_ row: LocalDBRow, as: T.Type = T.self) -> T {
    .init(id: row.int("id") ?? 0, name: row.string("name") ?? "")
}
public func createTrack(_ row: LocalDBRow) -> TrackWithFKs {
    var track = TrackWithFKs(
        id: row.int("id") ?? 0, title: row.string("title") ?? "", duration: row.int("duration") ?? 0,
        bitrate: row.int("bitrate"), tempo: (row.double("tempo") ?? 0) / 100,
        rating: row.int("rating") ?? 0,
        comment: row.string("comment") ?? "", filePath: row.string("filePath") ?? "",
        fileName: row.string("filename") ?? "",
        trackNumber: row.int("trackNumber"), discNumber: row.int("discNumber"),
        sampleRate: row.int("sampleRate"), sampleDepth: row.int("sampleDepth"),
        playCount: row.int("playCount"), year: row.int("year"), mixName: row.string("mixName"),
        autoloadHotcues: row.string("autoloadHotcues") == "ON",
        kuvoPublic: row.string("kuvoPublic") == "ON", fileSize: row.int("fileSize"),
        releaseDate: row.string("releaseDate"),
        analyzeDate: row.string("analyzeDate").flatMap(localDBParseDate),
        dateAdded: row.string("dateAdded").flatMap(localDBParseDate))
    if let path = row.string("analyzePath") { track.analyzePath = localDBTrimAnalyzePath(path) }
    func fk(_ name: String) -> Int? { row.int(name).flatMap { $0 == 0 ? nil : $0 } }
    track.artworkId = fk("artworkId")
    track.artistId = fk("artistId")
    track.originalArtistId = fk("originalArtistId")
    track.remixerId = fk("remixerId")
    track.composerId = fk("composerId")
    track.albumId = fk("albumId")
    track.labelId = fk("labelId")
    track.genreId = fk("genreId")
    track.colorId = fk("colorId")
    track.keyId = fk("keyId")
    return track
}
public func createPlaylist(_ row: LocalDBRow) -> Playlist {
    .init(
        id: row.int("id") ?? 0, name: row.string("name") ?? "",
        isFolder: (row.int("rawIsFolder") ?? 0) != 0,
        parentId: row.int("parentId").flatMap { $0 == 0 ? nil : $0 })
}
public func createPlaylistEntry(_ row: LocalDBRow) -> PlaylistEntryWithFKs {
    .init(
        id: row.int("id") ?? 0, sortIndex: row.int("entryIndex") ?? 0,
        playlistId: row.int("playlistId") ?? 0, trackId: row.int("trackId") ?? 0)
}
public func createArtworkEntry(_ row: LocalDBRow) -> Artwork {
    .init(id: row.int("id") ?? 0, path: row.string("path"))
}

// Swift 함수의 형 인자는 반환 함수의 형이나 as: 인자로 정한다.
public func makeIdNameHydrator<T: NamedEntity>(as: T.Type = T.self) -> @Sendable (LocalDBRow) -> T {
    { row in makeIdNameHydrator(row, as: T.self) }
}
