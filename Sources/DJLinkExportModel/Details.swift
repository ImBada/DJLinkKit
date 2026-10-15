// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbxport/crates/rbl-db/src/details.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 원본의 공개 데이터 필드와 기본값을 그대로 옮겼다.
public struct TrackDetails: Equatable, Sendable {
    public var id: String
    public var my_tags: [String]
    public var title: String
    public var artist_id: UInt32
    public var artist: String
    public var album_id: UInt32
    public var album: String
    public var album_artist: String
    public var original_artist_id: UInt32
    public var original_artist: String
    public var composer: String
    public var remixer_id: UInt32
    public var remixer: String
    public var lyricist: String
    public var genre_id: UInt32
    public var genre: String
    public var label_id: UInt32
    public var label: String
    public var key_id: UInt32
    public var key: String
    public var comment: String
    public var mix_name: String
    public var message: String
    public var color: String
    public var rating: UInt8
    public var bpm_x100: UInt32
    public var duration_sec: UInt32
    public var year: UInt32
    public var track_number: UInt32
    public var disc_number: UInt32
    public var play_count: UInt32
    public var file_type: UInt32
    public var file_size: UInt64
    public var bitrate: UInt32
    public var sample_rate: UInt32
    public var bit_depth: UInt32
    public var date_created: String
    public var release_date: String
    public var path: String
    public var hot_cue_auto_load: Bool
    public var publish: Bool
    public init(
        id: String = "", my_tags: [String] = [], title: String = "", artist_id: UInt32 = 0, artist: String = "",
        album_id: UInt32 = 0, album: String = "", album_artist: String = "", original_artist_id: UInt32 = 0,
        original_artist: String = "", composer: String = "", remixer_id: UInt32 = 0, remixer: String = "",
        lyricist: String = "", genre_id: UInt32 = 0, genre: String = "", label_id: UInt32 = 0, label: String = "",
        key_id: UInt32 = 0, key: String = "", comment: String = "", mix_name: String = "", message: String = "",
        color: String = "", rating: UInt8 = 0, bpm_x100: UInt32 = 0, duration_sec: UInt32 = 0, year: UInt32 = 0,
        track_number: UInt32 = 0, disc_number: UInt32 = 0, play_count: UInt32 = 0, file_type: UInt32 = 0,
        file_size: UInt64 = 0, bitrate: UInt32 = 0, sample_rate: UInt32 = 0, bit_depth: UInt32 = 0,
        date_created: String = "", release_date: String = "", path: String = "", hot_cue_auto_load: Bool = false,
        publish: Bool = false
    ) {
        self.id = id
        self.my_tags = my_tags
        self.title = title
        self.artist_id = artist_id
        self.artist = artist
        self.album_id = album_id
        self.album = album
        self.album_artist = album_artist
        self.original_artist_id = original_artist_id
        self.original_artist = original_artist
        self.composer = composer
        self.remixer_id = remixer_id
        self.remixer = remixer
        self.lyricist = lyricist
        self.genre_id = genre_id
        self.genre = genre
        self.label_id = label_id
        self.label = label
        self.key_id = key_id
        self.key = key
        self.comment = comment
        self.mix_name = mix_name
        self.message = message
        self.color = color
        self.rating = rating
        self.bpm_x100 = bpm_x100
        self.duration_sec = duration_sec
        self.year = year
        self.track_number = track_number
        self.disc_number = disc_number
        self.play_count = play_count
        self.file_type = file_type
        self.file_size = file_size
        self.bitrate = bitrate
        self.sample_rate = sample_rate
        self.bit_depth = bit_depth
        self.date_created = date_created
        self.release_date = release_date
        self.path = path
        self.hot_cue_auto_load = hot_cue_auto_load
        self.publish = publish
    }
    public static func `default`() -> Self { Self() }
}
public struct HotCueBank: Equatable, Sendable {
    public var id: UInt32
    public var name: String
    public var folder: Bool
    public init(id: UInt32 = 0, name: String = "", folder: Bool = false) {
        self.id = id
        self.name = name
        self.folder = folder
    }
    public static func `default`() -> Self { Self() }
}
public struct HotCueBankCue: Equatable, Sendable {
    public var slot: UInt8
    public var content: UInt32
    public var in_ms: UInt32
    public var out_ms: UInt32?
    public var color: UInt32
    public var color_table_index: UInt32
    public var active_loop: Bool
    public var beat_loop_size: UInt32
    public var cue_microsec: UInt32
    public init(
        slot: UInt8 = 0, content: UInt32 = 0, in_ms: UInt32 = 0, out_ms: UInt32? = nil, color: UInt32 = 0,
        color_table_index: UInt32 = 0, active_loop: Bool = false, beat_loop_size: UInt32 = 0, cue_microsec: UInt32 = 0
    ) {
        self.slot = slot
        self.content = content
        self.in_ms = in_ms
        self.out_ms = out_ms
        self.color = color
        self.color_table_index = color_table_index
        self.active_loop = active_loop
        self.beat_loop_size = beat_loop_size
        self.cue_microsec = cue_microsec
    }
    public static func `default`() -> Self { Self() }
}
