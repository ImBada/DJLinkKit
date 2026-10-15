// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbxport/crates/rbl-index/src/view.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 원본의 순위 기반 정렬과 검색 뷰다.
import Foundation

public enum SortColumn: Int, CaseIterable, Sendable {
    case trackNo, title, artist, album, genre, label, comment, key, bpm, duration, rating, playCount, dateAdded,
        releaseDate, keyCamelot, size, year, sampleRate, bitrate, color, fileName, location, composer, albumArtist,
        remixer, originalArtist, mixName, discNo, trackNumber, fileType, bitDepth, lyricist, dateCreated,
        publishTrackInfo, message, fileCreated
    public static let ALL: [Self] = [
        .trackNo, .title, .artist, .album, .genre, .label, .comment, .key, .bpm, .duration, .rating, .playCount,
        .dateAdded, .releaseDate, .keyCamelot, .size, .year, .sampleRate, .bitrate, .color, .fileName, .location,
        .composer, .albumArtist, .remixer, .originalArtist, .mixName, .discNo, .trackNumber, .fileType, .bitDepth,
        .lyricist, .dateCreated, .publishTrackInfo, .message,
    ]
    public func rank_slot() -> Int { rawValue }
    public func extra_slot() -> Int? {
        switch self {
        case .composer: return 0
        case .albumArtist: return 1
        case .remixer: return 2
        case .originalArtist: return 3
        case .mixName: return 4
        default: return nil
        }
    }
}
public enum RelatedCriterion: Equatable, Sendable { case bpmAndKey, sameGenreRecent, sameArtist, suggestion }
public enum TrackSource: Equatable, Sendable {
    case collection, playlist(Int), playlistFolder(Int), history(Int), smartPlaylist(Int), related(
        track: Row, criterion: RelatedCriterion), tagList
}
public enum SearchField: String, Codable, Sendable {
    case all, title, artist, album, genre, year, bpm, composer, albumArtist, remixer, label, comment, originalArtist,
        mixName
    public static func `default`() -> Self { .all }
    func index() -> Int? {
        switch self {
        case .all: return nil
        case .title: return 0
        case .artist: return 1
        case .album: return 2
        case .genre: return 3
        case .year: return 4
        case .bpm: return 5
        case .composer: return 6
        case .albumArtist: return 7
        case .remixer: return 8
        case .label: return 9
        case .comment: return 10
        case .originalArtist: return 11
        case .mixName: return 12
        }
    }
}
public struct ViewSpec: Sendable {
    public var source: TrackSource
    public var sort: SortColumn
    public var descending: Bool
    public var query: String
    public var filter: TrackFilter
    public init(
        source: TrackSource, sort: SortColumn, descending: Bool = false, query: String = "",
        filter: TrackFilter = TrackFilter()
    ) {
        self.source = source
        self.sort = sort
        self.descending = descending
        self.query = query
        self.filter = filter
    }
}
public struct View: Sendable {
    public var rows: [Row]
    var playlist_track_nos: [UInt32]?
    public init(rows: [Row], playlist_track_nos: [UInt32]? = nil) {
        self.rows = rows
        self.playlist_track_nos = playlist_track_nos
    }
    public func len() -> Int { rows.count }
    public func is_empty() -> Bool { rows.isEmpty }
    public func window(_ offset: Int, _ len: Int) -> [Row] {
        let start = min(offset, rows.count)
        let (sum, overflow) = start.addingReportingOverflow(len)
        let end = min(overflow ? Int.max : sum, rows.count)
        return Array(rows[start..<end])
    }
    // 원본 usize::MAX 입력도 표현할 수 있도록 부호 없는 경계를 함께 제공한다.
    public func window(_ offset: UInt, _ len: UInt) -> [Row] { window(Int(clamping: offset), Int(clamping: len)) }
    public func track_no_at(_ position: Int) -> UInt32 {
        if let number = playlist_track_nos?.at(position) { return number }
        let (next, overflow) = position.addingReportingOverflow(1)
        return overflow ? .max : UInt32(exactly: next) ?? .max
    }
}
func utf8_less(_ a: String, _ b: String) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }
extension Library {
    public func open_view(_ spec: ViewSpec) -> View { open_view_scoped(spec, .all) }
    public func open_view_scoped(_ spec: ViewSpec, _ field: SearchField) -> View {
        let playlist_numbers: Bool = {
            if case .playlist = spec.source { return true }
            return false
        }()
        var rows = source_rows(spec.source).enumerated().map { ($0.element, UInt32(exactly: $0.offset + 1) ?? .max) }
        let query = fold(modelTrim(spec.query))
        if !query.isEmpty { rows.removeAll { !row_matches_in($0.0, query, field) } }
        if !spec.filter.is_empty() {
            let compiled = spec.filter.compile()
            rows.removeAll { !compiled.matches(self, $0.0) }
        }
        if spec.sort == .trackNo {
            if spec.descending { rows.reverse() }
        } else if let rank = rank_of(spec.sort) {
            rows.sort { a, b in
                let x = rank.at(Int(a.0)) ?? 0
                let y = rank.at(Int(b.0)) ?? 0
                return spec.descending ? x > y : x < y
            }
        }
        return View(rows: rows.map(\.0), playlist_track_nos: playlist_numbers ? rows.map(\.1) : nil)
    }
    public func refine(_ previous: View, _ query: String) -> View {
        let folded = fold(modelTrim(query))
        if folded.isEmpty { return previous }
        let matched = previous.rows.enumerated().filter { row_matches($0.element, folded) }
        return View(
            rows: matched.map(\.element),
            playlist_track_nos: previous.playlist_track_nos.map { numbers in
                matched.compactMap { numbers.at($0.offset) }
            })
    }
    func row_matches(_ row: Row, _ folded_query: String) -> Bool { row_matches_in(row, folded_query, .all) }
    func row_matches_in(_ row: Row, _ folded_query: String, _ field: SearchField) -> Bool {
        let all = search.get(Int(row))
        let hay =
            field.index().map {
                all.split(separator: "\t", omittingEmptySubsequences: false).map(String.init).at($0) ?? ""
            } ?? all
        return folded_query.split(whereSeparator: \.isWhitespace).allSatisfy { hay.contains($0) }
    }
    public func sort_rows(_ rows: inout [Row], _ column: SortColumn, _ descending: Bool) {
        guard let rank = rank_of(column) else { return }
        rows.sort { a, b in
            let x = rank.at(Int(a)) ?? 0
            let y = rank.at(Int(b)) ?? 0
            return descending ? x > y : x < y
        }
    }
    func rank_of(_ column: SortColumn) -> [UInt32]? {
        column == .fileCreated ? file_created_rank() : ranks.at(column.rank_slot())
    }
    public func ids_in_range(_ view: View, _ from: Int, _ to: Int) -> [UInt64] {
        let lo = min(from, to)
        let hi = min(max(from, to), max(view.rows.count - 1, 0))
        guard lo <= hi, lo >= 0, hi < view.rows.count else { return [] }
        return view.rows[lo...hi].compactMap { ids.at(Int($0)) }
    }
    public func build_ranks() { rebuild_ranks(SortColumn.ALL) }
    public func rebuild_ranks(_ columns: [SortColumn]) {
        if ranks.count > SortColumn.ALL.count { ranks.removeLast(ranks.count - SortColumn.ALL.count) }
        if ranks.count < SortColumn.ALL.count {
            ranks += [[UInt32]](repeating: [], count: SortColumn.ALL.count - ranks.count)
        }
        for column in columns {
            let rank = column_rank(column)
            if ranks.indices.contains(column.rank_slot()) { ranks[column.rank_slot()] = rank }
        }
    }
    public func build_indexes() {
        // 원본과 다름: Swift 런타임의 공유 컬럼 접근은 직렬로 구축한다. 결과 순위·검색 값은 같다.
        build_ranks()
        build_search()
    }
    func column_rank(_ column: SortColumn) -> [UInt32] {
        var order = (0..<count).compactMap(Row.init(exactly:))
        if let text_key = column_text_key(column) {
            // 원본의 sort_by_cached_key처럼 정렬 키를 행마다 한 번만 만든다. 동률은 행 순서다.
            var keys = [[UInt8]](repeating: [], count: count)
            for row in order { keys[Int(row)] = Array(text_key(row).utf8) }
            order.sort { a, b in
                let x = keys[Int(a)]
                let y = keys[Int(b)]
                return x == y ? a < b : x.lexicographicallyPrecedes(y)
            }
        } else {
            let compare = column_comparator(column)
            order.sort { a, b in
                let ordering = compare(a, b)
                return ordering == .equal ? a < b : ordering == .less
            }
        }
        var rank = [UInt32](repeating: 0, count: count)
        for (position, row) in order.enumerated() { rank[Int(row)] = UInt32(exactly: position) ?? .max }
        return rank
    }
    /// 문자열 열의 정렬 키. 문자열이 아닌 열은 nil이다.
    func column_text_key(_ column: SortColumn) -> ((Row) -> String)? {
        switch column {
        case .title: return { self.title_folded.get(Int($0)) }
        case .artist: return { self.artists.folded(self.artist.at(Int($0)) ?? NO_ID) }
        case .album: return { self.albums.folded(self.album.at(Int($0)) ?? NO_ID) }
        case .genre: return { self.genres.folded(self.genre.at(Int($0)) ?? NO_ID) }
        case .label: return { self.labels.folded(self.label.at(Int($0)) ?? NO_ID) }
        case .comment, .composer, .albumArtist, .remixer, .originalArtist, .mixName, .lyricist, .message:
            return { fold(self.sort_text($0, column)) }
        case .fileName, .location: return { fold_smart(self.sort_text($0, column)) }
        case .dateAdded, .releaseDate, .dateCreated: return { self.sort_text($0, column) }
        default: return nil
        }
    }
    /// 문자열이 아닌 열의 비교자. 행마다 드는 값은 비교자를 만들 때 한 번만 읽는다.
    func column_comparator(_ column: SortColumn) -> (Row, Row) -> Ordering {
        switch column {
        case .trackNo: return { _, _ in .equal }
        case .key:
            let names = (0..<count).map { key_name(Row(truncatingIfNeeded: $0)) }
            return { a, b in cmp_names(names[Int(a)], names[Int(b)]) }
        case .keyCamelot:
            let names = (0..<count).map { key_name(Row(truncatingIfNeeded: $0)) }
            let ranks = names.map(camelot_rank)
            return { a, b in
                let x = ranks[Int(a)]
                let y = ranks[Int(b)]
                return x == y ? cmp_names(names[Int(a)], names[Int(b)]) : x < y ? .less : .greater
            }
        case .fileCreated:
            let created = file_created_all()
            return { a, b in
                let x = created.at(Int(a)) ?? nil
                let y = created.at(Int(b)) ?? nil
                if x == y { return .equal }
                if x == nil { return .less }
                if y == nil { return .greater }
                return x! < y! ? .less : .greater
            }
        default:
            return { a, b in
                let x = self.sort_number(a, column)
                let y = self.sort_number(b, column)
                return x == y ? .equal : x < y ? .less : .greater
            }
        }
    }
    func sort_text(_ row: Row, _ column: SortColumn) -> String {
        let row = Int(row)
        if let slot = column.extra_slot() { return search_extra.at(slot)?.get(row) ?? "" }
        switch column {
        case .comment: return comment.get(row)
        case .fileName: return file_name.get(row)
        case .location: return folder_path.get(row)
        case .lyricist: return lyricist.get(row)
        case .message: return message.get(row)
        case .dateAdded: return date_added.get(row)
        case .releaseDate: return release_date.get(row)
        case .dateCreated: return date_created.get(row)
        default: return ""
        }
    }
    func sort_number(_ row: Row, _ column: SortColumn) -> UInt64 {
        let row = Int(row)
        switch column {
        case .bpm: return UInt64(bpm_x100.at(row) ?? 0)
        case .duration: return UInt64(length_sec.at(row) ?? 0)
        case .rating: return UInt64(rating.at(row) ?? 0)
        case .playCount: return UInt64(play_count.at(row) ?? 0)
        case .size: return file_size.at(row) ?? 0
        case .year: return UInt64(year.at(row) ?? 0)
        case .sampleRate: return UInt64(sample_rate.at(row) ?? 0)
        case .bitrate: return UInt64(bitrate.at(row) ?? 0)
        case .color: return UInt64(color.at(row) ?? 0)
        case .discNo: return UInt64(disc_no.at(row) ?? 0)
        case .trackNumber: return UInt64(track_number.at(row) ?? 0)
        case .fileType: return UInt64(file_type.at(row) ?? 0)
        case .bitDepth: return UInt64(bit_depth.at(row) ?? 0)
        case .publishTrackInfo: return (publish.at(row) ?? 0) == 0 ? 1 : 0
        default: return 0
        }
    }
    public func build_search() { search = search_column() }
    func search_column() -> StrColumn {
        var column = StrColumn.with_capacity(count, count * 64)
        for row in 0..<count { column.push(search_text(row)) }
        return column
    }
    func search_text(_ row: Int) -> String {
        let year = self.year.at(row).flatMap { $0 == 0 ? nil : String($0) } ?? ""
        let bpm = bpm_x100.at(row).flatMap { $0 == 0 ? nil : "\($0 / 100).\(String(format: "%02u", $0 % 100))" } ?? ""
        let values = [
            title.get(row), artists.name(artist.at(row) ?? NO_ID), albums.name(album.at(row) ?? NO_ID),
            genres.name(genre.at(row) ?? NO_ID), year, bpm,
            search_extra[0].get(row), search_extra[1].get(row), search_extra[2].get(row),
            labels.name(label.at(row) ?? NO_ID), comment.get(row), search_extra[3].get(row), search_extra[4].get(row),
        ]
        return values.map { fold($0.replacingOccurrences(of: "\t", with: " ")) }.joined(separator: "\t")
    }
}
