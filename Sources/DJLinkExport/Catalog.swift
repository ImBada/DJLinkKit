// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-link/src/catalog.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import DJLinkExportANLZ
import DJLinkExportDBServer
import DJLinkExportModel
import DJLinkExportProtocol
import DJLinkKit
import Darwin
import Foundation

public enum KeyNotation: Equatable, Sendable { case classic, alphanumeric }
public enum KeyOrder: Equatable, Sendable { case musical, alphabetical }
@DJLinkActor public protocol Source: AnyObject {
    func library() -> Library?
    func key_notation() -> KeyNotation
    func device_settings() -> DeviceSettings
    func key_order() -> KeyOrder
    func today() -> SmartDate
    func sorts() -> [Sort]
    func root_categories() -> [RootCategory]
    func track_column() -> TrackColumn
    func share_root() -> String
    func details(_ id: String) -> DJLinkExportModel.TrackDetails?
    func matching_ids(_ seed: UInt32) -> [UInt32]
    func artist_role_names(_ role: ArtistRole) -> [(UInt32, String)]
    func artist_role_track_ids(_ role: ArtistRole, _ artist: UInt32) -> [UInt32]
    func hot_cue_banks(_ parent: UInt32?) -> [DJLinkExportModel.HotCueBank]
    func hot_cue_bank_cues(_ bank: UInt32) -> [DJLinkExportModel.HotCueBankCue]
    func hot_cue_bank_track_ids(_ bank: UInt32) -> [UInt32]
    func my_tags() -> [DJLinkExportModel.MyTagRow]
    func edit(_ edit: Edit) -> Bool
    func new_link_history() -> UInt32?
    func add_to_history(_ history: UInt32, _ track: UInt32) -> Bool
    func remove_from_history(_ history: UInt32, _ track: UInt32) -> Bool
}
extension Source {
    public func key_notation() -> KeyNotation { .alphanumeric }
    public func device_settings() -> DeviceSettings {
        DeviceSettings(key_display: key_notation() == .classic ? .classic : .alphanumeric)
    }
    public func key_order() -> KeyOrder { .musical }
    public func today() -> SmartDate { SmartDate.today() }
    public func sorts() -> [Sort] { Sort.DEFAULTS }
    public func root_categories() -> [RootCategory] { RootCategory.defaults() }
    public func track_column() -> TrackColumn { .comment }
    public func matching_ids(_ seed: UInt32) -> [UInt32] { [] }
    public func artist_role_names(_ role: ArtistRole) -> [(UInt32, String)] { [] }
    public func artist_role_track_ids(_ role: ArtistRole, _ artist: UInt32) -> [UInt32] { [] }
    public func hot_cue_banks(_ parent: UInt32?) -> [DJLinkExportModel.HotCueBank] { [] }
    public func hot_cue_bank_cues(_ bank: UInt32) -> [DJLinkExportModel.HotCueBankCue] { [] }
    public func hot_cue_bank_track_ids(_ bank: UInt32) -> [UInt32] { [] }
    public func my_tags() -> [DJLinkExportModel.MyTagRow] { [] }
    public func edit(_ edit: Edit) -> Bool { false }
    public func new_link_history() -> UInt32? { nil }
    public func add_to_history(_ history: UInt32, _ track: UInt32) -> Bool { false }
    public func remove_from_history(_ history: UInt32, _ track: UInt32) -> Bool { false }
}
@DJLinkActor public final class Played {
    private var tracks: Set<UInt32> = []
    public init() {}
    public static func `default`() -> Played { Played() }
    public func clone() -> Played { self }
    public func mark(_ track: UInt32) { tracks.insert(track) }
    public func contains(_ track: UInt32) -> Bool { tracks.contains(track) }
}
private struct QueryCacheEntry {
    weak var library: Library?
    var today: SmartDate, query: DJLinkExportDBServer.Query, rows: [DJLinkExportDBServer.Row]
}
private struct ArtworkCacheEntry {
    weak var library: Library?
    var row: UInt32, bytes: [UInt8]
}
private struct BrowseCache {
    var queries: [QueryCacheEntry] = [], artwork: [ArtworkCacheEntry] = []
    var artwork_bytes = 0
}
private struct Parsed { var row: UInt32, dat: Anlz?, ext: Anlz?, two_ex: Anlz? }
private struct LinkHistory {
    var session: UInt32?, last: UInt32 = 0
    func session_in(_ library: Library) -> UInt32? {
        session.flatMap { library.histories().index_of(UInt64($0)) == nil ? nil : $0 }
    }
}
private func catalogAt<T>(_ values: [T], _ at: Int) -> T? { values.indices.contains(at) ? values[at] : nil }
private func catalogLess(_ a: String, _ b: String) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }
private let MAX_ARTWORK: UInt64 = 4 * 1024 * 1024
private let MEDIUM_ARTWORK_SUFFIX = "_m"
private let ANALYSIS_CACHE = 32
private let QUERY_CACHE = 24
private let ARTWORK_CACHE_BYTES = 32 * 1024 * 1024

@DJLinkActor public final class IndexCatalog: DJLinkExportDBServer.Catalog {
    private let source: any Source, played_set: Played
    private var analysis_cache: [Parsed] = [], browse = BrowseCache(), link_history = LinkHistory()
    public init(_ source: any Source, _ played: Played) {
        self.source = source
        played_set = played
    }
    public static func new(_ source: any Source, _ played: Played) -> IndexCatalog { IndexCatalog(source, played) }
    private func history_edit(_ edit: Edit) -> Bool {
        guard let library = source.library() else { return false }
        switch edit {
        case let .historyAdd(track):
            let session: UInt32
            if let existing = link_history.session_in(library) {
                if link_history.last == track { return true }
                session = existing
            } else {
                guard let new = source.new_link_history() else { return false }
                link_history = LinkHistory(session: new, last: 0)
                session = new
            }
            let added = source.add_to_history(session, track)
            if added {
                link_history.last = track
                played_set.mark(track)
            }
            return added
        case let .historyRemove(track):
            guard let session = link_history.session_in(library), source.remove_from_history(session, track) else {
                return false
            }
            link_history.last =
                source.library().flatMap { library in
                    let lists = library.histories()
                    guard let index = lists.index_of(UInt64(session)), let row = catalogAt(lists.members, index)?.last
                    else { return nil }
                    return Self.track_id(library, row)
                } ?? 0
            return true
        case let .historyDelete(named):
            if named == .max || link_history.session == named { link_history = LinkHistory() }
            return true
        default: return false
        }
    }
    private static func wire_my_tags(_ library: Library, _ row: UInt32) -> [UInt32] {
        library.my_tag_keys(Int(row)).map { UInt32(bitPattern: $0) }
    }
    private static func row_of(_ library: Library, _ id: UInt32) -> UInt32? { library.row_of_id(UInt64(id)) }
    static func item_row(_ library: Library, _ id: UInt32) -> UInt32? {
        if let row = row_of(library, id) { return row }
        let album = dense_id(library.album_ids, id)
        guard album != NO_ID else { return nil }
        return library.album.enumerated().first { $0.element == album && !library.artwork_path.get($0.offset).isEmpty }
            .flatMap { UInt32(exactly: $0.offset) }
    }
    private func artwork_at(_ library: Library, _ row: UInt32) -> [UInt8]? {
        if let at = browse.artwork.firstIndex(where: { $0.row == row && $0.library === library }) {
            let hit = browse.artwork.remove(at: at)
            browse.artwork.append(hit)
            return hit.bytes
        }
        browse.artwork.removeAll { $0.library !== library }
        browse.artwork_bytes = browse.artwork.reduce(0) { $0 + $1.bytes.count }
        let relative = library.artwork_path.get(Int(row))
        guard !relative.isEmpty else { return nil }
        let share = source.share_root()
        guard
            let path = [medium_artwork(relative), relative].compactMap({ resolve_under(share, $0) }).first(where: {
                path in catalogMetadata(path).map { $0.st_mode & S_IFMT == S_IFREG } ?? false
            }), let meta = catalogMetadata(path), UInt64(max(meta.st_size, 0)) <= MAX_ARTWORK,
            let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        else { return nil }
        let bytes = Array(data)
        while browse.artwork_bytes + bytes.count > ARTWORK_CACHE_BYTES && !browse.artwork.isEmpty {
            let evicted = browse.artwork.removeFirst()
            browse.artwork_bytes -= evicted.bytes.count
        }
        if bytes.count <= ARTWORK_CACHE_BYTES {
            browse.artwork_bytes += bytes.count
            browse.artwork.append(ArtworkCacheEntry(library: library, row: row, bytes: bytes))
        }
        return bytes
    }
    private func cached_list(_ library: Library, _ query: DJLinkExportDBServer.Query) -> [DJLinkExportDBServer.Row] {
        let today = source.today()
        switch query {
        case .histories, .tracks(scope: .history(_), sort: _), .tracks(scope: .tagList, sort: _):
            return list_uncached(library, query, today)
        default: break
        }
        if let at = browse.queries.firstIndex(where: {
            $0.query == query && $0.today == today && $0.library === library
        }) {
            let hit = browse.queries.remove(at: at)
            browse.queries.append(hit)
            return hit.rows
        }
        browse.queries.removeAll { $0.today != today || $0.library !== library }
        let rows = list_uncached(library, query, today)
        if browse.queries.count >= QUERY_CACHE { browse.queries.removeFirst() }
        browse.queries.append(QueryCacheEntry(library: library, today: today, query: query, rows: rows))
        return rows
    }
    private func list_uncached(_ library: Library, _ query: DJLinkExportDBServer.Query, _ today: SmartDate)
        -> [DJLinkExportDBServer.Row]
    {
        switch query {
        case .bpmBuckets: return library.bpm_buckets().map(DJLinkExportDBServer.Row.date)
        case .ratings: return library.ratings().map(DJLinkExportDBServer.Row.date)
        case .bitrates: return library.bitrates().map(DJLinkExportDBServer.Row.date)
        case .colors: return library.color_ids().map { .named(id: $0, name: color_name($0)) }
        case .durationMinutes: return library.duration_minute_buckets().map(DJLinkExportDBServer.Row.date)
        case .releaseDecades: return library.release_decades().map(DJLinkExportDBServer.Row.date)
        case let .releaseYears(decade): return library.release_years(decade).map(DJLinkExportDBServer.Row.date)
        case .genres: return Self.named(library.genre, library.genres, library.genre_ids)
        case let .genreArtists(genre): return Self.genre_artists(library, genre)
        case let .genreArtistAlbums(genre, artist): return Self.genre_albums(library, genre, artist)
        case .labels: return Self.named(library.label, library.labels, library.label_ids)
        case let .labelArtists(label): return Self.label_artists(library, label)
        case let .labelArtistAlbums(label, artist): return Self.label_albums(library, label, artist)
        case let .artistRoleArtists(role):
            return source.artist_role_names(role).filter { !$0.1.isEmpty }.map { .named(id: $0.0, name: $0.1) }
        case let .artistRoleAlbums(role, artist): return role_albums(library, role, artist)
        case .artists: return Self.named(library.artist, library.artists, library.artist_ids)
        case .albums: return Self.named(library.album, library.albums, library.album_ids)
        case let .artistAlbums(artist): return Self.artist_albums(library, artist)
        case let .folder(parent): return Self.folder(library.playlists(), parent)
        case .histories: return histories(library)
        case .years: return Self.date_parts(library, "", 0..<4, true)
        case let .months(year): return Self.date_parts(library, date_prefix(year, nil, nil), 5..<7, false)
        case let .days(year, month): return Self.date_parts(library, date_prefix(year, month, nil), 8..<10, false)
        case let .tracks(scope, sort): return tracks(library, scope, sort, source.key_order(), today)
        }
    }
    private static func track_id(_ library: Library, _ row: UInt32) -> UInt32? {
        catalogAt(library.ids, Int(row)).flatMap { UInt32(exactly: $0) }
    }
    private static func key_id(_ library: Library, _ row: UInt32) -> UInt32 { player_key_id(library.key_name(row)) }
    private func displayed_key_name(_ library: Library, _ row: UInt32) -> String {
        let name = library.key_name(row)
        if source.key_notation() == .classic { return name }
        let key = player_key_id(name)
        return key == 0 ? "" : camelot_name(key)
    }
    private static func dense_id(_ ids: [UInt32], _ wire: UInt32) -> UInt32 {
        ids.firstIndex(of: wire).flatMap(UInt32.init(exactly:)) ?? NO_ID
    }
    private static func wire_id(_ ids: [UInt32], _ dense: UInt32) -> UInt32 {
        dense == NO_ID ? 0 : catalogAt(ids, Int(dense)) ?? 0
    }
    private static func sort_column(_ sort: Sort, _ scope: TrackScope, _ key_order: KeyOrder) -> SortColumn? {
        switch sort {
        case .default:
            switch scope {
            case .fileName, .playlist, .history, .tagList: return nil
            default: return album_constrained(scope) ? nil : .title
            }
        case .alphabet: return .title
        case .artist: return .artist
        case .album: return .album
        case .bpm: return .bpm
        case .rating: return .rating
        case .genre: return .genre
        case .label: return .label
        case .dateAdded: return .dateAdded
        case .djPlayCount: return .playCount
        case .key: return key_order == .alphabetical ? .key : .keyCamelot
        }
    }
    private func scope_rows(_ library: Library, _ scope: TrackScope, _ today: SmartDate) -> [(UInt32, UInt32)] {
        let all = (0..<library.len()).compactMap(UInt32.init(exactly:)).map { ($0, UInt32(0)) }
        switch scope {
        case .all: return all
        case .fileName: return library.filename_rows().map { ($0, 0) }
        case let .matching(seed):
            return source.matching_ids(seed).compactMap { id in library.row_of_id(UInt64(id)).map { ($0, 0) } }
        case let .bpm(bpm, tolerance): return all.filter { library.bpm_matches($0.0, bpm, tolerance) }
        case let .rating(rating): return all.filter { library.rating_matches($0.0, rating) }
        case let .bitrate(bitrate): return all.filter { library.bitrate_matches($0.0, bitrate) }
        case let .color(color): return all.filter { library.color_matches($0.0, color) }
        case let .durationMinute(minute): return all.filter { library.duration_minute_matches($0.0, minute) }
        case let .releaseYear(decade, year):
            return all.filter { pair in
                if let year { return library.release_year_matches(pair.0, year) }
                guard let value = catalogAt(library.year, Int(pair.0)) else { return false }
                let y = UInt32(value)
                return y != 0 && y <= 2999 && y / 10 * 10 == decade
            }
        case .tagList:
            return library.tag_list().enumerated().map { ($0.element, UInt32(exactly: $0.offset + 1) ?? .max) }
        case let .genre(genre, artist, album):
            let genre = Self.dense_id(library.genre_ids, genre)
            let artist = artist.map { Self.dense_id(library.artist_ids, $0) }
            let album = album.map { Self.dense_id(library.album_ids, $0) }
            return all.filter {
                let at = Int($0.0)
                return catalogAt(library.genre, at) == genre
                    && (artist.map { catalogAt(library.artist, at) == $0 } ?? true)
                    && (album.map { catalogAt(library.album, at) == $0 } ?? true)
            }
        case let .label(label, artist, album):
            let label = Self.dense_id(library.label_ids, label)
            let artist = artist.map { Self.dense_id(library.artist_ids, $0) }
            let album = album.map { Self.dense_id(library.album_ids, $0) }
            return all.filter {
                let at = Int($0.0)
                return catalogAt(library.label, at) == label
                    && (artist.map { catalogAt(library.artist, at) == $0 } ?? true)
                    && (album.map { catalogAt(library.album, at) == $0 } ?? true)
            }
        case let .artistRole(role, artist, album):
            let album = album.map { Self.dense_id(library.album_ids, $0) }
            return source.artist_role_track_ids(role, artist).compactMap { library.row_of_id(UInt64($0)) }.filter {
                row in album.map { catalogAt(library.album, Int(row)) == $0 } ?? true
            }.map { ($0, 0) }
        case let .artist(artist, album):
            let artist = Self.dense_id(library.artist_ids, artist)
            let album = album.map { Self.dense_id(library.album_ids, $0) }
            return all.filter { pair in
                catalogAt(library.artist, Int(pair.0)) == artist
                    && (album.map { catalogAt(library.album, Int(pair.0)) == $0 } ?? true)
            }
        case let .album(album):
            let album = Self.dense_id(library.album_ids, album)
            return all.filter { catalogAt(library.album, Int($0.0)) == album }
        case let .key(key, distance):
            let wanted = Set(DJLinkExportDBServer.keys.related(key, distance))
            return all.filter { wanted.contains(Self.key_id(library, $0.0)) }
        case let .playlist(id):
            let lists = library.playlists()
            guard let index = lists.index_of(UInt64(id)) else { return [] }
            let rows =
                lists.is_smart(index)
                ? library.source_rows_unlocked_on(lists, .smartPlaylist(index), today)
                : catalogAt(lists.members, index) ?? []
            return rows.enumerated().map { ($0.element, UInt32(exactly: $0.offset + 1) ?? .max) }
        case let .history(id):
            let lists = library.histories()
            guard let index = lists.index_of(UInt64(id)) else { return [] }
            return (catalogAt(lists.members, index) ?? []).enumerated().map {
                ($0.element, UInt32(exactly: $0.offset + 1) ?? .max)
            }
        case let .dateAdded(year, month, day):
            let prefix = date_prefix(year, month, day)
            return all.filter { library.date_added.get(Int($0.0)).hasPrefix(prefix) }
        case let .search(text):
            return library.open_view(
                ViewSpec(
                    source: .collection, sort: .title, descending: false, query: text,
                    filter: DJLinkExportModel.TrackFilter())
            ).rows.map { ($0, 0) }
        }
    }
    private func tracks(
        _ library: Library, _ scope: TrackScope, _ sort: Sort, _ key_order: KeyOrder, _ today: SmartDate
    ) -> [DJLinkExportDBServer.Row] {
        var rows = scope_rows(library, scope, today)
        if track_number_visible(scope) {
            for at in rows.indices {
                rows[at].1 =
                    Self.track_id(library, rows[at].0).flatMap { source.details(String($0)) }?.track_number ?? 0
            }
        }
        if album_constrained(scope) && sort == .default {
            rows.sort { a, b in
                if (a.1 == 0) != (b.1 == 0) { return a.1 != 0 }
                if a.1 != b.1 { return a.1 < b.1 }
                return a.0 < b.0
            }
        }
        if let column = Self.sort_column(sort, scope, key_order) {
            var order = rows.map(\.0)
            library.sort_rows(&order, column, false)
            var positions: [UInt32: UInt32] = [:]
            for (row, position) in rows { positions[row] = position }
            rows = order.map { ($0, positions[$0] ?? 0) }
        }
        return rows.compactMap { row, position in Self.track_id(library, row).map { .track(id: $0, position: position) }
        }
    }
    private static func named(_ column: [UInt32], _ interner: Interner, _ wire_ids: [UInt32]) -> [DJLinkExportDBServer
        .Row]
    {
        let used = Set(column)
        var ids = (0..<interner.len()).compactMap(UInt32.init(exactly:)).filter {
            used.contains($0) && !interner.name($0).isEmpty
        }
        ids.sort { a, b in
            let left = interner.folded(a)
            let right = interner.folded(b)
            return left.utf8.elementsEqual(right.utf8) ? a < b : catalogLess(left, right)
        }
        return ids.map { .named(id: wire_id(wire_ids, $0), name: interner.name($0)) }
    }
    private static func artist_albums(_ library: Library, _ artist: UInt32) -> [DJLinkExportDBServer.Row] {
        let dense = dense_id(library.artist_ids, artist)
        let albums = zip(library.artist, library.album).filter { $0.0 == dense }.map(\.1)
        return album_rows(library, albums)
    }
    private static func album_rows(_ library: Library, _ albums: [UInt32]) -> [DJLinkExportDBServer.Row] {
        func name(_ id: UInt32) -> String { id == NO_ID ? "unknown" : library.albums.folded(id) }
        let sorted = Set(albums).sorted { a, b in
            let l = name(a)
            let r = name(b)
            return l.utf8.elementsEqual(r.utf8) ? a < b : catalogLess(l, r)
        }
        return sorted.filter { $0 == NO_ID || !library.albums.name($0).isEmpty }.map {
            .named(id: wire_id(library.album_ids, $0), name: $0 == NO_ID ? "Unknown" : library.albums.name($0))
        }
    }
    private static func genre_artists(_ library: Library, _ genre: UInt32) -> [DJLinkExportDBServer.Row] {
        let dense = dense_id(library.genre_ids, genre)
        let artists = zip(library.genre, library.artist).filter { $0.0 == dense && $0.1 != NO_ID }.map(\.1)
        return named(artists, library.artists, library.artist_ids)
    }
    private static func genre_albums(_ library: Library, _ genre: UInt32, _ artist: UInt32?) -> [DJLinkExportDBServer
        .Row]
    {
        let dense = dense_id(library.genre_ids, genre)
        let artistID = artist.map { dense_id(library.artist_ids, $0) }
        let selected = (0..<min(library.genre.count, library.artist.count, library.album.count)).filter { at in
            library.genre[at] == dense && (artistID.map { library.artist[at] == $0 } ?? true)
        }.map { library.album[$0] }.filter { artist != nil || $0 != NO_ID }
        return album_rows(library, selected)
    }
    private static func label_artists(_ library: Library, _ label: UInt32) -> [DJLinkExportDBServer.Row] {
        let dense = dense_id(library.label_ids, label)
        let artists = zip(library.label, library.artist).filter { $0.0 == dense && $0.1 != NO_ID }.map(\.1)
        return named(artists, library.artists, library.artist_ids)
    }
    private static func label_albums(_ library: Library, _ label: UInt32, _ artist: UInt32?) -> [DJLinkExportDBServer
        .Row]
    {
        let dense = dense_id(library.label_ids, label)
        let artistID = artist.map { dense_id(library.artist_ids, $0) }
        let selected = (0..<min(library.label.count, library.artist.count, library.album.count)).filter { at in
            library.label[at] == dense && (artistID.map { library.artist[at] == $0 } ?? true)
        }.map { library.album[$0] }.filter { artist != nil || $0 != NO_ID }
        return album_rows(library, selected)
    }
    private func role_albums(_ library: Library, _ role: ArtistRole, _ artist: UInt32) -> [DJLinkExportDBServer.Row] {
        Self.album_rows(
            library,
            source.artist_role_track_ids(role, artist).compactMap { library.row_of_id(UInt64($0)) }.compactMap {
                catalogAt(library.album, Int($0))
            })
    }
    private static func folder(_ lists: Playlists, _ parent: UInt32) -> [DJLinkExportDBServer.Row] {
        let index: UInt32
        if parent == 0 {
            index = NO_ID
        } else {
            guard let at = lists.index_of(UInt64(parent)) else { return [] }
            index = UInt32(exactly: at) ?? NO_ID
        }
        let children = (0..<lists.len()).filter { catalogAt(lists.parent, $0) == index }.sorted { a, b in
            if lists.is_folder(a) != lists.is_folder(b) { return lists.is_folder(a) }
            return (catalogAt(lists.seq, a) ?? 0) < (catalogAt(lists.seq, b) ?? 0)
        }
        return children.compactMap { at in
            guard let raw = catalogAt(lists.ids, at), let id = UInt32(exactly: raw) else { return nil }
            return .list(
                id: id, name: lists.name(at), folder: lists.is_folder(at), position: catalogAt(lists.seq, at) ?? 0)
        }
    }
    private func histories(_ library: Library) -> [DJLinkExportDBServer.Row] {
        guard let session = link_history.session_in(library) else { return [] }
        let lists = library.histories()
        guard let index = lists.index_of(UInt64(session)) else { return [] }
        return [.named(id: session, name: lists.name(index))]
    }
    private static func date_parts(_ library: Library, _ prefix: String, _ range: Range<Int>, _ newest: Bool)
        -> [DJLinkExportDBServer.Row]
    {
        let values: [UInt32] = (0..<library.len()).compactMap { row in
            let date = library.date_added.get(row)
            let bytes = Array(date.utf8)
            guard date.hasPrefix(prefix), bytes.count >= range.upperBound,
                let text = String(bytes: bytes[range], encoding: .utf8)
            else { return nil }
            return UInt32(text)
        }
        var sorted = Set(values).sorted()
        if newest { sorted.reverse() }
        return sorted.filter { $0 != 0 }.map(DJLinkExportDBServer.Row.date)
    }
    private func parsed(_ library: Library, _ row: UInt32) -> Parsed? {
        if let at = analysis_cache.firstIndex(where: { $0.row == row }) {
            let hit = analysis_cache.remove(at: at)
            analysis_cache.append(hit)
            return hit
        }
        let relative = library.analysis_path.get(Int(row))
        guard !relative.isEmpty else { return nil }
        let path = DJLinkExportANLZ.resolve(source.share_root(), relative)
        let parsed = Parsed(
            row: row, dat: try? Anlz.read(path), ext: try? Anlz.read(DJLinkExportANLZ.sibling(path, "EXT")),
            two_ex: try? Anlz.read(DJLinkExportANLZ.sibling(path, "2EX")))
        if analysis_cache.count >= ANALYSIS_CACHE { analysis_cache.removeFirst() }
        analysis_cache.append(parsed)
        return parsed
    }
    public func forget_analysis() { analysis_cache.removeAll() }
    public func root_categories() -> [RootCategory] { source.root_categories() }
    public func sorts() -> [Sort] { source.sorts() }
    public func key_ids() -> [UInt32] {
        var ids = Array(UInt32(1)...24)
        if source.key_order() == .alphabetical {
            ids.sort {
                DJLinkExportModel.cmp_names(DJLinkExportDBServer.keys.name($0), DJLinkExportDBServer.keys.name($1))
                    == .less
            }
        }
        return ids
    }
    public func key_name(_ id: UInt32) -> String {
        source.key_notation() == .classic
            ? DJLinkExportDBServer.keys.name(id) : (1...24).contains(id) ? camelot_name(id) : ""
    }
    public func list(_ query: DJLinkExportDBServer.Query) -> [DJLinkExportDBServer.Row] {
        guard let library = source.library() else { return [] }
        return cached_list(library, query)
    }
    public func track_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? {
        guard let library = source.library(), let row = Self.row_of(library, id) else { return nil }
        let at = Int(row)
        let configured = source.track_column()
        let column = column ?? configured
        let details = source.details(String(id))
        let key = Self.key_id(library, row)
        let key_name = displayed_key_name(library, row)
        let (secondary, value) = secondary_column(library, row, column, column == configured, key_name, details)
        return TrackRow(
            id: id, title: library.title.get(at), secondary_text: secondary, column: column, column_value: value,
            key: key, key_id: library.key_name(row).isEmpty ? 0 : details?.key_id ?? 0, key_name: key_name,
            bpm_x100: catalogAt(library.bpm_x100, at) ?? 0)
    }
    public func file_name_row(_ id: UInt32, _ column: TrackColumn?) -> TrackRow? {
        guard let library = source.library(), let row = Self.row_of(library, id), var item = track_row(id, column)
        else { return nil }
        item.title = library.file_name.get(Int(row))
        return item
    }
    public func track(_ id: UInt32) -> DJLinkExportDBServer.TrackDetails? {
        guard let library = source.library(), let row = Self.row_of(library, id) else { return nil }
        let at = Int(row)
        let path = library.folder_path.get(at)
        let details = source.details(String(id))
        func lookup(_ column: [UInt32], _ ids: [UInt32]) -> UInt32 {
            catalogAt(column, at).map { Self.wire_id(ids, $0) } ?? 0
        }
        let size: UInt64
        if let declared = details?.file_size, declared > 0 {
            size = declared
        } else {
            size = catalogMetadata(path).map { UInt64(max($0.st_size, 0)) } ?? 0
        }
        guard let item = track_row(id, nil) else { return nil }
        return DJLinkExportDBServer.TrackDetails(
            row: item, comment: library.comment.get(at), key_id: details?.key_id ?? 0, key_name: item.key_name,
            artist_id: lookup(library.artist, library.artist_ids), artist: library.artist_name(row),
            album_id: lookup(library.album, library.album_ids), album: library.album_name(row),
            duration_s: catalogAt(library.length_sec, at) ?? 0, rating: UInt32(catalogAt(library.rating, at) ?? 0),
            colour: UInt32(catalogAt(library.color, at) ?? 0), genre_id: lookup(library.genre, library.genre_ids),
            genre: library.genre_name(row), date_added: library.date_added.get(at), year: details?.year ?? 0,
            bit_rate_kbps: details?.bitrate ?? 0, label_id: lookup(library.label, library.label_ids),
            label: library.label_name(row), original_artist: details?.original_artist ?? "",
            remixer: details?.remixer ?? "", path: path, file_size: UInt32(exactly: size) ?? .max,
            file_type: details?.file_type ?? 0)
    }
    public func artwork(_ id: UInt32) -> [UInt8]? {
        guard let library = source.library(), id >= 2 else { return nil }
        return artwork_at(library, id - 2)
    }
    public func item_artwork(_ id: UInt32) -> [UInt8]? {
        guard let library = source.library(), let row = Self.item_row(library, id) else { return nil }
        return artwork_at(library, row)
    }
    public func analysis(_ track: UInt32, _ what: DJLinkExportDBServer.Analysis) -> [UInt8]? {
        guard let library = source.library(), let row = Self.row_of(library, track) else { return nil }
        switch what {
        case .vbr: return vbr_compatibility_blob()
        case .extendedCueList: return extended_cues_blob(library.cues_of(row).map(ExtendedCue.from)).0
        default:
            guard let parsed = parsed(library, row) else { return nil }
            let analysis = Analysis(dat: parsed.dat, ext: parsed.ext, two_ex: parsed.two_ex)
            switch what {
            case .beatGrid: return analysis.beat_grid()
            case .waveformPreview: return analysis.waveform_preview()
            case .waveformDetail: return analysis.waveform_detail()
            case let .tag(fourcc, ext): return analysis.tag(fourcc, ext)
            case .vbr, .extendedCueList: return nil
            }
        }
    }
    public func hot_cue_banks(_ parent: UInt32?) -> [DJLinkExportDBServer.HotCueBank] {
        source.hot_cue_banks(parent).map {
            DJLinkExportDBServer.HotCueBank(id: $0.id, name: $0.name, folder: $0.folder)
        }
    }
    public func hot_cue_bank_cues(_ bank: UInt32) -> [DJLinkExportDBServer.HotCueBankCue] {
        source.hot_cue_bank_cues(bank).map {
            DJLinkExportDBServer.HotCueBankCue(
                slot: $0.slot, content: $0.content, in_ms: $0.in_ms, out_ms: $0.out_ms, color: $0.color,
                color_table_index: $0.color_table_index, active_loop: $0.active_loop, beat_loop_size: $0.beat_loop_size,
                cue_microsec: $0.cue_microsec)
        }
    }
    public func hot_cue_bank_tracks(_ bank: UInt32) -> [TrackRow] {
        source.hot_cue_bank_track_ids(bank).compactMap { track_row($0, nil) }
    }
    public func usb_cues(_ track: UInt32) -> [UsbCue] {
        guard let library = source.library(), let row = Self.row_of(library, track) else { return [] }
        return library.cues_of(row).compactMap { cue in
            let slot = cue.hot_letter().map { UInt8($0.unicodeScalars.first!.value - 65 + 1) } ?? 0
            guard slot <= 3 else { return nil }
            return UsbCue(
                slot: slot, in_ms: cue.position_ms, out_ms: cue.out_ms > cue.position_ms ? cue.out_ms : nil,
                color_table_index: UInt32(cue.colour))
        }
    }
    public func grid_offset(_ track: UInt32) -> Int16 {
        guard let library = source.library(), let row = Self.row_of(library, track), let parsed = parsed(library, row)
        else { return 0 }
        return parsed.dat?.grid_offset() ?? 0
    }
    public func edit(_ edit: Edit) -> Bool {
        switch edit {
        case .historyAdd, .historyRemove, .historyDelete: return history_edit(edit)
        default: break
        }
        let success = source.edit(edit)
        if success, case .gridOffset = edit { forget_analysis() }
        return success
    }
    public func tagged(_ track: UInt32) -> Bool {
        guard let lib = source.library(), let row = Self.row_of(lib, track) else { return false }
        return lib.tag_list().contains(row)
    }
    public func listed(_ scope: TrackScope) -> Bool {
        if case let .playlist(id) = scope {
            guard let library = source.library() else { return true }
            let lists = library.playlists()
            guard let index = lists.index_of(UInt64(id)) else { return true }
            return !lists.is_smart(index)
        }
        switch scope {
        case .genre, .label, .artist, .album, .tagList: return true
        default: return false
        }
    }
    public func filter_rows(_ rows: inout [DJLinkExportDBServer.Row], _ filter: DJLinkExportDBServer.TrackFilter) {
        guard filter.enabled else { return }
        guard let lib = source.library() else {
            rows.removeAll()
            return
        }
        let tags = filter.has_my_tag_conditions()
        rows.removeAll { item in
            guard case let .track(id, _) = item else { return false }
            guard let row = Self.row_of(lib, id) else { return true }
            let at = Int(row)
            return
                !(filter.matches(lib.bpm_x100[at], Self.key_id(lib, row), UInt32(lib.rating[at]), UInt32(lib.color[at]))
                && (!tags || filter.matches_my_tags(Self.wire_my_tags(lib, row))))
        }
    }
    public func my_tags() -> [DJLinkExportDBServer.MyTag] {
        source.my_tags().map {
            DJLinkExportDBServer.MyTag(
                id: wire_my_tag_id($0.id), parent: wire_my_tag_id($0.parent), seq: UInt32(exactly: $0.seq) ?? 0,
                name: $0.name)
        }
    }
    public func track_my_tags(_ track: UInt32) -> [UInt32] {
        guard let lib = source.library(), let row = Self.row_of(lib, track) else { return [] }
        return Self.wire_my_tags(lib, row)
    }
    public func my_tags_in_use() -> Set<UInt32> {
        guard let lib = source.library() else { return [] }
        return Set((0..<lib.bpm_x100.count).flatMap { lib.my_tag_keys($0).map { UInt32(bitPattern: $0) } })
    }
    public func played(_ track: UInt32) -> Bool { played_set.contains(track) }
}
func wire_my_tag_id(_ text: String) -> UInt32 { UInt32(bitPattern: DJLinkExportModel.my_tag_key(text)) }
func album_constrained(_ scope: TrackScope) -> Bool {
    switch scope {
    case .album, .artist(artist: _, album: .some(_)), .genre(genre: _, artist: _, album: .some(_)),
        .label(label: _, artist: _, album: .some(_)):
        return true
    default: return false
    }
}
func track_number_visible(_ scope: TrackScope) -> Bool {
    if album_constrained(scope) { return true }
    if case .matching = scope { return true }
    return false
}
func color_name(_ id: UInt32) -> String {
    [1: "Pink", 2: "Red", 3: "Orange", 4: "Yellow", 5: "Green", 6: "Aqua", 7: "Blue", 8: "Purple"][id] ?? ""
}
func secondary_column(
    _ library: Library, _ row: UInt32, _ column: TrackColumn, _ preserve: Bool, _ key_name: String,
    _ details: DJLinkExportModel.TrackDetails?
) -> (String, UInt32) {
    let at = Int(row)
    let bpm = catalogAt(library.bpm_x100, at) ?? 0
    switch column {
    case .title: return ("", 0)
    case .album: return details.map { ($0.album, $0.album_id) } ?? (library.album_name(row), 0)
    case .genre: return details.map { ($0.genre, $0.genre_id) } ?? (library.genre_name(row), 0)
    case .artist: return details.map { ($0.artist, $0.artist_id) } ?? (library.artist_name(row), 0)
    case .rating:
        let value = UInt32(catalogAt(library.rating, at) ?? 0)
        return (preserve ? String(repeating: "★", count: Int(value)) : "", value)
    case .duration:
        let value = catalogAt(library.length_sec, at) ?? 0
        return (preserve ? String(format: "%u:%02u", value / 60, value % 60) : "", value)
    case .bpm: return (preserve ? format_bpm(bpm) : "", bpm)
    case .label: return details.map { ($0.label, $0.label_id) } ?? (library.label_name(row), 0)
    case .key: return (bpm == 0 || !preserve ? key_name : key_name + " - " + format_bpm(bpm), details?.key_id ?? 0)
    case .bitrate:
        let value = catalogAt(library.bitrate, at) ?? 0
        return (preserve ? format_nonzero(value, " kbps") : "", value)
    case .color:
        let value = UInt32(catalogAt(library.color, at) ?? 0)
        return (color_name(value), value)
    case .comment: return (library.comment.get(at), 0)
    case .originalArtist: return details.map { ($0.original_artist, $0.original_artist_id) } ?? ("", 0)
    case .remixer: return details.map { ($0.remixer, $0.remixer_id) } ?? ("", 0)
    case .djPlayCount:
        let value = UInt32(catalogAt(library.play_count, at) ?? 0)
        return (preserve ? String(value) : "", value)
    case .dateAdded: return (library.date_added.get(at), 0)
    }
}
func format_bpm(_ bpm_x100: UInt32) -> String {
    guard bpm_x100 != 0 else { return "" }
    let (sum, overflow) = bpm_x100.addingReportingOverflow(5)
    let tenths = (overflow ? UInt32.max : sum) / 10
    return "\(tenths / 10).\(tenths % 10) bpm"
}
func format_nonzero(_ value: UInt32, _ suffix: String) -> String { value == 0 ? "" : "\(value)\(suffix)" }
func camelot_name(_ id: UInt32) -> String { "\(id / 2 + id % 2)\(id % 2 == 1 ? "A" : "B")" }
func player_key_id(_ name: String) -> UInt32 {
    let rank = DJLinkExportModel.camelot_rank(name)
    if rank != .max { return rank + 1 }
    let normalized = String(
        String.UnicodeScalarView(
            name.unicodeScalars.map { c in (0xff01...0xff5e).contains(c.value) ? UnicodeScalar(c.value - 0xfee0)! : c })
    )
    return (UInt32(1)...24).first { normalized.utf8.starts(with: DJLinkExportDBServer.keys.name($0).utf8) } ?? 0
}
func date_prefix(_ year: UInt32, _ month: UInt32?, _ day: UInt32?) -> String {
    if let m = month {
        if let d = day { return String(format: "%04u-%02u-%02u", year, m, d) }
        return String(format: "%04u-%02u", year, m)
    }
    return String(format: "%04u", year)
}
func medium_artwork(_ relative: String) -> String {
    let raw = Array(relative.utf8)
    guard let dot = raw.lastIndex(of: 46), !raw[dot...].contains(47), !raw[dot...].contains(92) else { return relative }
    return String(decoding: raw[..<dot], as: UTF8.self) + MEDIUM_ARTWORK_SUFFIX + String(decoding: raw[dot...], as: UTF8.self)
}
func resolve_under(_ share: String, _ relative: String) -> String? {
    let relative = String(String.UnicodeScalarView(relative.unicodeScalars.drop(while: { $0 == "/" || $0 == "\\" })))
    guard !relative.components(separatedBy: CharacterSet(charactersIn: "/\\")).contains("..") else { return nil }
    return share.isEmpty ? relative : share + (share.hasSuffix("/") ? "" : "/") + relative
}
private func catalogMetadata(_ path: String) -> stat? {
    guard !path.utf8.contains(0) else { return nil }
    var value = stat()
    return path.withCString { stat($0, &value) } == 0 ? value : nil
}
