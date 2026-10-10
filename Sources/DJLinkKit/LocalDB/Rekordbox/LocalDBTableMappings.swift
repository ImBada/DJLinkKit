public let pdbTables: [Int: Table] = [
    0: .track, 1: .genre, 2: .artist, 3: .album, 4: .label, 5: .key, 6: .color, 7: .playlist,
    8: .playlistEntry, 13: .artwork,
]

public enum LocalDBPdbEntity: Equatable, Sendable {
    case track(TrackWithFKs)
    case artist(Artist)
    case album(Album)
    case genre(Genre)
    case color(Color)
    case label(Label)
    case key(Key)
    case artwork(Artwork)
    case playlist(Playlist)
    case playlistEntry(PlaylistEntryWithFKs)
}
// 원본 table-mappings.ts의 크리에이터 표. JS의 서로 다른 반환 형은 판별 합으로 묶는다.
public let pdbEntityCreators: [Int: @Sendable (LocalDBRow) -> LocalDBPdbEntity] = [
    0: { .track(createTrack($0)) },
    1: { .genre(makeIdNameHydrator($0, as: Genre.self)) },
    2: { .artist(makeIdNameHydrator($0, as: Artist.self)) },
    3: { .album(makeIdNameHydrator($0, as: Album.self)) },
    4: { .label(makeIdNameHydrator($0, as: Label.self)) },
    5: { .key(makeIdNameHydrator($0, as: Key.self)) },
    6: { .color(makeIdNameHydrator($0, as: Color.self)) },
    7: { .playlist(createPlaylist($0)) },
    8: { .playlistEntry(createPlaylistEntry($0)) },
    13: { .artwork(createArtworkEntry($0)) },
]
