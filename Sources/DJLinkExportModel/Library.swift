// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbxport/crates/rbl-index/src/lib.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 데이터베이스를 열지 않고 메모리 컬럼으로 받는 원본의 색인이다.
import Foundation

public typealias Row = UInt32
public let NO_ID: UInt32 = .max
public let ATTRIBUTE_FOLDER: UInt8 = 1
public let ATTRIBUTE_SMART: UInt8 = 4

public final class Library: @unchecked Sendable {
    public var count: Int = 0
    public var ids: [UInt64] = []
    public var title: StrColumn = StrColumn()
    public var title_folded: StrColumn = StrColumn()
    public var comment: StrColumn = StrColumn()
    public var search_extra: [StrColumn] = [StrColumn](repeating: StrColumn(), count: 5)
    public var folder_path: StrColumn = StrColumn()
    public var file_name: StrColumn = StrColumn()
    public var analysis_path: StrColumn = StrColumn()
    public var artwork_path: StrColumn = StrColumn()
    public var date_added: StrColumn = StrColumn()
    public var release_date: StrColumn = StrColumn()
    public var date_created: StrColumn = StrColumn()
    public var lyricist: StrColumn = StrColumn()
    public var message: StrColumn = StrColumn()
    public var artist: [UInt32] = []
    public var album: [UInt32] = []
    public var genre: [UInt32] = []
    public var label: [UInt32] = []
    public var key: [UInt32] = []
    public var bpm_x100: [UInt32] = []
    public var length_sec: [UInt32] = []
    public var rating: [UInt8] = []
    public var color: [UInt8] = []
    public var play_count: [UInt16] = []
    public var analysed: [UInt8] = []
    public var bitrate: [UInt32] = []
    public var sample_rate: [UInt32] = []
    public var file_size: [UInt64] = []
    public var year: [UInt16] = []
    public var track_number: [UInt32] = []
    public var disc_no: [UInt16] = []
    public var file_type: [UInt8] = []
    public var bit_depth: [UInt16] = []
    public var publish: [UInt8] = []
    public var artists: Interner = Interner()
    public var albums: Interner = Interner()
    public var genres: Interner = Interner()
    public var labels: Interner = Interner()
    public var keys: Interner = Interner()
    public var artist_ids: [UInt32] = []
    public var album_ids: [UInt32] = []
    public var genre_ids: [UInt32] = []
    public var label_ids: [UInt32] = []
    public var ranks: [[UInt32]] = []
    public var search: StrColumn = StrColumn()
    public var my_tags_column: [TagCategory] = []
    public var my_tag_bounds: [UInt32] = []
    public var my_tag_keys_column: [Int32] = []
    public var cloud_paths: [(Row, StoredPath)] = []
    let lock = NSRecursiveLock()
    var playlist_tree = Playlists()
    var history_tree = Playlists()
    var tag_rows: [Row] = []
    var cue_table = Cues()
    var by_id: [UInt64: Row]?
    var by_path: [UInt64: [Row]]?
    var file_created_cache: [Int64?]?
    var file_created_rank_cache: [UInt32]?
    public init() {}
    public static func `default`() -> Library { Library() }
    public func clone() -> Library {
        lock.lock()
        defer { lock.unlock() }
        let copy = Library()
        copy.count = count
        copy.ids = ids
        copy.title = title
        copy.title_folded = title_folded
        copy.comment = comment
        copy.search_extra = search_extra
        copy.folder_path = folder_path
        copy.file_name = file_name
        copy.analysis_path = analysis_path
        copy.artwork_path = artwork_path
        copy.date_added = date_added
        copy.release_date = release_date
        copy.date_created = date_created
        copy.lyricist = lyricist
        copy.message = message
        copy.artist = artist
        copy.album = album
        copy.genre = genre
        copy.label = label
        copy.key = key
        copy.bpm_x100 = bpm_x100
        copy.length_sec = length_sec
        copy.rating = rating
        copy.color = color
        copy.play_count = play_count
        copy.analysed = analysed
        copy.bitrate = bitrate
        copy.sample_rate = sample_rate
        copy.file_size = file_size
        copy.year = year
        copy.track_number = track_number
        copy.disc_no = disc_no
        copy.file_type = file_type
        copy.bit_depth = bit_depth
        copy.publish = publish
        copy.artists = artists
        copy.albums = albums
        copy.genres = genres
        copy.labels = labels
        copy.keys = keys
        copy.artist_ids = artist_ids
        copy.album_ids = album_ids
        copy.genre_ids = genre_ids
        copy.label_ids = label_ids
        copy.ranks = ranks
        copy.search = search
        copy.my_tags_column = my_tags_column
        copy.my_tag_bounds = my_tag_bounds
        copy.my_tag_keys_column = my_tag_keys_column
        copy.cloud_paths = cloud_paths
        copy.playlist_tree = playlist_tree
        copy.history_tree = history_tree
        copy.tag_rows = tag_rows
        copy.cue_table = cue_table
        copy.by_id = by_id
        copy.by_path = by_path
        copy.file_created_cache = file_created_cache
        copy.file_created_rank_cache = file_created_rank_cache
        return copy
    }
}

public struct Cue: Equatable, Sendable {
    public var id: UInt32
    public var position_ms: UInt32
    public var out_ms: UInt32
    public var kind: UInt8
    public var colour: UInt8
    public init(id: UInt32 = 0, position_ms: UInt32 = 0, out_ms: UInt32 = 0, kind: UInt8 = 0, colour: UInt8 = 0) {
        self.id = id
        self.position_ms = position_ms
        self.out_ms = out_ms
        self.kind = kind
        self.colour = colour
    }
    public static func `default`() -> Self { Self() }
    public static let MEMORY: UInt8 = 0
    public static let ACTIVE_LOOP: UInt8 = 4
    public func hot_letter() -> Character? {
        let slot: UInt32
        switch kind {
        case 1...3: slot = UInt32(kind - 1)
        case 5...17: slot = UInt32(kind - 2)
        default: return nil
        }
        return Character(Unicode.Scalar(65 + slot)!)
    }
    public func is_memory() -> Bool { kind == Self.MEMORY || kind == Self.ACTIVE_LOOP }
    public func is_active_loop() -> Bool { kind == Self.ACTIVE_LOOP }
    public static func kind_of_letter(_ letter: Character) -> UInt8? {
        guard letter.unicodeScalars.count == 1, let scalar = letter.unicodeScalars.first else { return nil }
        let v = scalar.value >= 97 && scalar.value <= 122 ? scalar.value - 32 : scalar.value
        guard (65...80).contains(v) else { return nil }
        let slot = UInt8(v - 65)
        return slot <= 2 ? slot + 1 : slot + 2
    }
}
public struct Cues: Sendable {
    var flat: [Cue] = []
    var index: [UInt32] = []
    public init() {}
    public static func `default`() -> Self { Self() }
    public static func from_per_track(_ per_track: [[Cue]]) -> Self {
        var result = Self()
        for list in per_track {
            result.index.append(UInt32(exactly: result.flat.count) ?? .max)
            result.flat += list.sorted { ($0.position_ms, $0.kind) < ($1.position_ms, $1.kind) }
        }
        result.index.append(UInt32(exactly: result.flat.count) ?? .max)
        return result
    }
    public func of(_ row: Row) -> [Cue] {
        let start = Int(index.at(Int(row)) ?? 0)
        let end = Int(index.at(Int(row) + 1) ?? 0)
        guard start <= end, end <= flat.count else { return [] }
        return Array(flat[start..<end])
    }
    public func hot_letters_of(_ row: Row) -> String { String(Set(of(row).compactMap { $0.hot_letter() }).sorted()) }
    public mutating func replace(_ row: Row, _ tracks: Int, _ cues: [Cue]) {
        if index.count < tracks + 1 {
            index += [UInt32](repeating: UInt32(exactly: flat.count) ?? .max, count: tracks + 1 - index.count)
        }
        guard let a = index.at(Int(row)), let b = index.at(Int(row) + 1) else { return }
        let start = Int(a)
        let end = Int(b)
        guard start <= end, end <= flat.count else { return }
        let sorted = cues.sorted { ($0.position_ms, $0.kind) < ($1.position_ms, $1.kind) }
        let grew = sorted.count - (end - start)
        flat.replaceSubrange(start..<end, with: sorted)
        for i in (Int(row) + 1)..<index.count { index[i] = UInt32(exactly: Int64(index[i]) + Int64(grew)) ?? .max }
    }
    public func len() -> Int { flat.count }
    public func is_empty() -> Bool { flat.isEmpty }
    public func parts() -> ([Cue], [UInt32]) { (flat, index) }
    public static func from_parts(_ cues: [Cue], _ index: [UInt32]) -> Self {
        var value = Self()
        value.flat = cues
        value.index = index
        return value
    }
}
public struct Playlists: Sendable {
    public var ids: [UInt64] = []
    public var names = StrColumn()
    public var parent: [UInt32] = []
    public var seq: [UInt32] = []
    public var attribute: [UInt8] = []
    public var smart = StrColumn()
    public var members: [[Row]] = []
    public init() {}
    public static func `default`() -> Self { Self() }
    public func len() -> Int { ids.count }
    public func is_empty() -> Bool { ids.isEmpty }
    public func is_folder(_ index: Int) -> Bool { attribute.at(index) == ATTRIBUTE_FOLDER }
    public func is_smart(_ index: Int) -> Bool { attribute.at(index) == ATTRIBUTE_SMART }
    public func smart_rule(_ index: Int) -> SmartRule? { is_smart(index) ? SmartRule.parse(smart.get(index)) : nil }
    public func name(_ index: Int) -> String { names.get(index) }
    public func index_of(_ id: UInt64) -> Int? { ids.firstIndex(of: id) }
}
public struct StoredPath: Equatable, Sendable {
    public var folder_path: String
    public var org_folder_path: String
    public var content_link: Int64
    public var service_id: Int64
    public var device_id: String
    public init(
        folder_path: String = "", org_folder_path: String = "", content_link: Int64 = 0, service_id: Int64 = 0,
        device_id: String = ""
    ) {
        self.folder_path = folder_path
        self.org_folder_path = org_folder_path
        self.content_link = content_link
        self.service_id = service_id
        self.device_id = device_id
    }
}
public protocol TrackPathResolving { func resolve(_ stored: StoredPath) -> String }
extension Array {
    func at(_ index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
extension Library {
    public func map_folder_paths(_ map: (String) -> String) {
        var paths = StrColumn.with_capacity(folder_path.len(), folder_path.heap_bytes())
        for row in 0..<folder_path.len() { paths.push(map(folder_path.get(row))) }
        folder_path = paths
        by_path = nil
        forget_file_created()
    }
    public func recheck_cloud_paths(_ paths: any TrackPathResolving) -> Int {
        var changed: [Int: String] = [:]
        for (row, stored) in cloud_paths {
            let r = Int(row)
            let path = paths.resolve(stored)
            if r < folder_path.len(), folder_path.get(r) != path { changed[r] = path }
        }
        guard !changed.isEmpty else { return 0 }
        folder_path.replace_rows(changed)
        by_path = nil
        forget_file_created()
        rebuild_ranks([.location])
        return changed.count
    }
    public func set_count(_ count: Int) { self.count = count }
    public func row_of(_ display_id: String) -> Row? { UInt64(display_id).flatMap { row_of_id($0) } }
    public func row_of_id(_ id: UInt64) -> Row? { row_by_id()[id] }
    func row_by_id() -> [UInt64: Row] {
        lock.lock()
        defer { lock.unlock() }
        if let by_id { return by_id }
        var map: [UInt64: Row] = [:]
        for (row, id) in ids.enumerated() { map[id] = UInt32(exactly: row) ?? .max }
        by_id = map
        return map
    }
    public func cues_of(_ row: Row) -> [Cue] {
        lock.lock()
        defer { lock.unlock() }
        return cue_table.of(row)
    }
    public func cues() -> Cues {
        lock.lock()
        defer { lock.unlock() }
        return cue_table
    }
    public func set_cues_of(_ row: Row, _ cues: [Cue]) {
        lock.lock()
        defer { lock.unlock() }
        cue_table.replace(row, count, cues)
    }
    public func set_cues(_ cues: Cues) {
        lock.lock()
        defer { lock.unlock() }
        cue_table = cues
    }
    public func artwork_path_of(_ display_id: String) -> String? {
        row_of(display_id).map { artwork_path.get(Int($0)) }
    }
    public func audio_path_of(_ display_id: String) -> String? {
        if display_id.hasPrefix("file:") { return String(display_id.dropFirst(5)) }
        return row_of(display_id).map { folder_path.get(Int($0)) }
    }
    public func my_tags() -> [TagCategory] { my_tags_column }
    public func set_my_tags(_ tags: [TagCategory]) { my_tags_column = tags }
    public func my_tag_keys(_ row: Int) -> [Int32] {
        guard let a = my_tag_bounds.at(row), let b = my_tag_bounds.at(row + 1), a <= b,
            Int(b) <= my_tag_keys_column.count
        else { return [] }
        return Array(my_tag_keys_column[Int(a)..<Int(b)])
    }
    public func set_track_my_tags(_ pairs: [(Row, Int32)]) {
        let sorted = pairs.filter { Int($0.0) < count }.sorted { $0 < $1 }
        guard !sorted.isEmpty else {
            my_tag_bounds = []
            my_tag_keys_column = []
            return
        }
        var unique: [(Row, Int32)] = []
        for pair in sorted { if unique.last?.0 != pair.0 || unique.last?.1 != pair.1 { unique.append(pair) } }
        var bounds: [UInt32] = []
        var keys: [Int32] = []
        var next = 0
        for row in 0..<count {
            bounds.append(UInt32(exactly: keys.count) ?? .max)
            while next < unique.count, Int(unique[next].0) == row {
                keys.append(unique[next].1)
                next += 1
            }
        }
        bounds.append(UInt32(exactly: keys.count) ?? .max)
        my_tag_bounds = bounds
        my_tag_keys_column = keys
    }
    public func my_tag_parts() -> ([UInt32], [Int32]) { (my_tag_bounds, my_tag_keys_column) }
    @discardableResult public func set_my_tag_parts(_ bounds: [UInt32], _ keys: [Int32]) -> Bool {
        let valid =
            bounds.isEmpty
            ? keys.isEmpty
            : bounds.count == count + 1 && bounds.first == 0 && bounds.last.map(Int.init) == keys.count
                && zip(bounds, bounds.dropFirst()).allSatisfy { $0 <= $1 }
        guard valid else { return false }
        my_tag_bounds = bounds
        my_tag_keys_column = keys
        return true
    }
    public func playlists() -> Playlists {
        lock.lock()
        defer { lock.unlock() }
        return playlist_tree
    }
    public func set_playlists(_ playlists: Playlists) {
        lock.lock()
        defer { lock.unlock() }
        playlist_tree = playlists
    }
    public func histories() -> Playlists {
        lock.lock()
        defer { lock.unlock() }
        return history_tree
    }
    public func set_histories(_ histories: Playlists) {
        lock.lock()
        defer { lock.unlock() }
        history_tree = histories
    }
    public func tag_list() -> [Row] {
        lock.lock()
        defer { lock.unlock() }
        return tag_rows
    }
    public func set_tag_list(_ rows: [Row]) {
        lock.lock()
        defer { lock.unlock() }
        tag_rows = rows
    }
    public func len() -> Int { count }
    public func is_empty() -> Bool { count == 0 }
    public func unanalysed_rows(_ from: Row) -> [Row] {
        guard Int(from) < count else { return [] }
        return (Int(from)..<count).filter { analysed.at($0) == 0 && !folder_path.get($0).isEmpty }.compactMap(
            Row.init(exactly:))
    }
    public func artist_name(_ row: Row) -> String { artists.name(artist.at(Int(row)) ?? NO_ID) }
    public func album_name(_ row: Row) -> String { albums.name(album.at(Int(row)) ?? NO_ID) }
    public func genre_name(_ row: Row) -> String { genres.name(genre.at(Int(row)) ?? NO_ID) }
    public func label_name(_ row: Row) -> String { labels.name(label.at(Int(row)) ?? NO_ID) }
    public func key_name(_ row: Row) -> String { keys.name(key.at(Int(row)) ?? NO_ID) }
}
extension Library {
    public func heap_bytes() -> Int {
        let vecs =
            ids.capacity * 8
            + (artist.capacity + album.capacity + genre.capacity + label.capacity + key.capacity + bpm_x100.capacity
                + length_sec.capacity + bitrate.capacity + sample_rate.capacity + track_number.capacity) * 4
            + file_size.capacity * 8
            + (artist_ids.capacity + album_ids.capacity + genre_ids.capacity + label_ids.capacity) * 4
            + (year.capacity + play_count.capacity + disc_no.capacity + bit_depth.capacity) * 2
            + file_type.capacity + publish.capacity + rating.capacity + color.capacity + analysed.capacity
        let columns =
            [
                title, title_folded, comment, folder_path, file_name, analysis_path, artwork_path, date_added,
                release_date, date_created, lyricist, message, search,
            ] + search_extra
        let strings = columns.reduce(0) { $0 + $1.heap_bytes() }
        let interners = [artists, albums, genres, labels, keys].reduce(0) { $0 + $1.heap_bytes() }
        let ranks = self.ranks.reduce(0) { $0 + $1.capacity * 4 }
        let table = cues()
        let cues = table.flat.capacity * 16 + table.index.capacity * 4
        let tags =
            my_tags_column.reduce(0) { $0 + $1.name.utf8.count + $1.tags.reduce(0) { $0 + $1.utf8.count } }
            + my_tag_bounds.capacity * 4 + my_tag_keys_column.capacity * 4
        let playlists = self.playlists()
        let lists =
            playlists.ids.capacity * 8 + playlists.names.heap_bytes() + playlists.smart.heap_bytes()
            + playlists.attribute.capacity + playlists.members.reduce(0) { $0 + $1.capacity * 4 }
        // 원본과 다름: Swift String은 capacity를 공개하지 않으므로 태그 문자열은 UTF-8 길이를 센다.
        return vecs + strings + interners + ranks + cues + tags + lists
    }
}
