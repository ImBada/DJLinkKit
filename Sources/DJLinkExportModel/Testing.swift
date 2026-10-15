// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbxport/crates/rbl-index/src/testing.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 원본의 데이터베이스 없는 시험 색인 생성기다.
import Foundation

public struct TestTrack: Sendable {
    public var id: UInt64
    public var title: String
    public var artist: String
    public var album: String
    public var album_artist: String
    public var original_artist: String
    public var composer: String
    public var remixer: String
    public var mix_name: String
    public var label: String
    public var comment: String
    public var bpm_x100: UInt32
    public var length_sec: UInt32
    public var rating: UInt8
    public var date_added: String
    public var key: String
    public var color: UInt8
    public var cues: [Cue]
    public var path: String
    public var genre: String
    public var year: UInt16
    public var play_count: UInt16
    public var file_size: UInt64
    public var sample_rate: UInt32
    public var bitrate: UInt32
    public var track_number: UInt32
    public var disc_no: UInt16
    public var file_type: UInt8
    public var bit_depth: UInt16
    public var lyricist: String
    public var date_created: String
    public var publish: Bool
    public var message: String
    public init(
        id: UInt64 = 0, title: String = "", artist: String = "", album: String = "", album_artist: String = "",
        original_artist: String = "", composer: String = "", remixer: String = "", mix_name: String = "",
        label: String = "", comment: String = "", bpm_x100: UInt32 = 0, length_sec: UInt32 = 0, rating: UInt8 = 0,
        date_added: String = "", key: String = "", color: UInt8 = 0, cues: [Cue] = [], path: String = "",
        genre: String = "", year: UInt16 = 0, play_count: UInt16 = 0, file_size: UInt64 = 0, sample_rate: UInt32 = 0,
        bitrate: UInt32 = 0, track_number: UInt32 = 0, disc_no: UInt16 = 0, file_type: UInt8 = 0, bit_depth: UInt16 = 0,
        lyricist: String = "", date_created: String = "", publish: Bool = false, message: String = ""
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.album_artist = album_artist
        self.original_artist = original_artist
        self.composer = composer
        self.remixer = remixer
        self.mix_name = mix_name
        self.label = label
        self.comment = comment
        self.bpm_x100 = bpm_x100
        self.length_sec = length_sec
        self.rating = rating
        self.date_added = date_added
        self.key = key
        self.color = color
        self.cues = cues
        self.path = path
        self.genre = genre
        self.year = year
        self.play_count = play_count
        self.file_size = file_size
        self.sample_rate = sample_rate
        self.bitrate = bitrate
        self.track_number = track_number
        self.disc_no = disc_no
        self.file_type = file_type
        self.bit_depth = bit_depth
        self.lyricist = lyricist
        self.date_created = date_created
        self.publish = publish
        self.message = message
    }
    public static func `default`() -> Self { Self() }
}
public func library_from(_ tracks: [TestTrack]) -> Library {
    let lib = Library()
    for t in tracks {
        lib.ids.append(t.id)
        lib.title.push(t.title)
        lib.title_folded.push(fold(t.title))
        lib.comment.push(t.comment)
        for (column, value) in [t.composer, t.album_artist, t.remixer, t.original_artist, t.mix_name].enumerated() {
            lib.search_extra[column].push(value)
        }
        lib.folder_path.push(t.path)
        // Path::file_name처럼 "."은 건너뛰고, 마지막이 ".."이면 이름이 없다.
        let path = t.path.split(separator: "/", omittingEmptySubsequences: true).filter { $0 != "." }
        lib.file_name.push(path.last.map { $0 == ".." ? "" : String($0) } ?? "")
        lib.analysis_path.push("")
        lib.date_added.push(t.date_added)
        lib.release_date.push("")
        lib.date_created.push(t.date_created)
        lib.lyricist.push(t.lyricist)
        lib.message.push(t.message)
        let artist = lib.artists.push(t.artist)
        let album = lib.albums.push(t.album)
        let genre = lib.genres.push(t.genre)
        let label = lib.labels.push(t.label)
        lib.artist.append(artist)
        lib.album.append(album)
        lib.genre.append(genre)
        lib.label.append(label)
        lib.artist_ids.append(artist + 1)
        lib.album_ids.append(album + 1)
        lib.genre_ids.append(genre + 1)
        lib.label_ids.append(label + 1)
        lib.key.append(lib.keys.push(t.key))
        lib.bpm_x100.append(t.bpm_x100)
        lib.length_sec.append(t.length_sec)
        lib.rating.append(t.rating)
        lib.color.append(t.color)
        lib.play_count.append(t.play_count)
        lib.analysed.append(t.bpm_x100 > 0 ? 1 : 0)
        lib.year.append(t.year)
        lib.bitrate.append(t.bitrate)
        lib.sample_rate.append(t.sample_rate)
        lib.file_size.append(t.file_size)
        lib.track_number.append(t.track_number)
        lib.disc_no.append(t.disc_no)
        lib.file_type.append(t.file_type)
        lib.bit_depth.append(t.bit_depth)
        lib.publish.append(t.publish ? 1 : 0)
    }
    lib.count = tracks.count
    lib.set_cues(Cues.from_per_track(tracks.map(\.cues)))
    lib.set_playlists(Playlists())
    lib.build_ranks()
    lib.build_search()
    return lib
}
@discardableResult public func add_playlist(_ lib: Library, _ name: String, _ rows: [Row]) -> Int {
    add_list(lib, name, rows, false)
}
@discardableResult public func add_folder(_ lib: Library, _ name: String) -> Int { add_list(lib, name, [], true) }
@discardableResult public func add_history(_ lib: Library, _ name: String, _ rows: [Row]) -> Int {
    var histories = lib.histories()
    let index = histories.ids.count
    histories.ids.append(2000 + (UInt64(exactly: index) ?? 0))
    histories.names.push(name)
    histories.parent.append(NO_ID)
    histories.seq.append(UInt32(exactly: index) ?? 0)
    histories.attribute.append(0)
    histories.smart.push("")
    histories.members.append(rows)
    lib.set_histories(histories)
    return index
}
@discardableResult public func add_smart_playlist(_ lib: Library, _ name: String, _ rule: String) -> Int {
    add_list_with(lib, name, [], ATTRIBUTE_SMART, rule)
}
@discardableResult public func add_smart_playlist_with_members(
    _ lib: Library, _ name: String, _ rows: [Row], _ rule: String
) -> Int { add_list_with(lib, name, rows, ATTRIBUTE_SMART, rule) }
private func add_list(_ lib: Library, _ name: String, _ rows: [Row], _ folder: Bool) -> Int {
    add_list_with(lib, name, rows, folder ? ATTRIBUTE_FOLDER : 0, "")
}
private func add_list_with(_ lib: Library, _ name: String, _ rows: [Row], _ attribute: UInt8, _ rule: String) -> Int {
    var playlists = lib.playlists()
    let index = playlists.ids.count
    playlists.ids.append(1000 + (UInt64(exactly: index) ?? 0))
    playlists.names.push(name)
    playlists.parent.append(NO_ID)
    playlists.seq.append(UInt32(exactly: index) ?? 0)
    playlists.attribute.append(attribute)
    playlists.smart.push(rule)
    playlists.members.append(rows)
    lib.set_playlists(playlists)
    return index
}
public func set_my_tags(_ lib: Library, _ categories: [TagCategory]) { lib.set_my_tags(categories) }
public func set_track_my_tags(_ lib: Library, _ pairs: [(Row, Int32)]) { lib.set_track_my_tags(pairs) }
