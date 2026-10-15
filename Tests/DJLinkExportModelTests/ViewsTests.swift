// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-index/tests/views.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportModel

private func track(_ id: UInt64, _ title: String, _ artist: String, _ bpm: UInt32) -> TestTrack {
    TestTrack(id: id, title: title, artist: artist, bpm_x100: bpm, length_sec: 200 + UInt32(truncatingIfNeeded: id))
}
private func sample() -> [TestTrack] {
    [
        track(1, "Zebra", "ARTBAT", 12800), track(2, "apple", "Meduza", 13000), track(3, "Ébano", "Tujamo", 12400),
        track(4, "Banana", "artbat", 0), track(5, "Cherry (Extended Mix)", "Kryder", 14000),
    ]
}
private func spec(_ sort: SortColumn, _ descending: Bool, _ query: String) -> ViewSpec {
    ViewSpec(source: .collection, sort: sort, descending: descending, query: query)
}
private func ordered<T>(_ lib: Library, _ column: SortColumn, _ descending: Bool, _ value: (Int) -> T) -> [T] {
    lib.open_view(spec(column, descending, "")).rows.map { value(Int($0)) }
}
@Suite struct ViewsTests {
    @Test("sorts_keys_by_their_names_with_the_sharps_apart_and_blanks_last")
    func sorts_keys_by_their_names_with_the_sharps_apart_and_blanks_last() {
        let keyed: [(UInt64, String)] = [(1, "Fm"), (2, "F#"), (3, ""), (4, "F"), (5, "F#m"), (6, "Abm"), (7, "A")]
        let lib = library_from(keyed.map { TestTrack(id: $0.0, title: "t", key: $0.1) })
        let view = lib.open_view(spec(.key, false, ""))
        #expect(view.rows.map { lib.key_name($0) } == ["A", "Abm", "F", "F#", "F#m", "Fm", ""])
    }
    @Test("sorts_keys_round_the_camelot_wheel_for_the_alphanumeric_display")
    func sorts_keys_round_the_camelot_wheel_for_the_alphanumeric_display() {
        let keyed: [(UInt64, String)] = [(1, "A"), (2, "Abm"), (3, "B"), (4, "Ebm"), (5, "E"), (6, "Odd"), (7, "G#m")]
        let lib = library_from(keyed.map { TestTrack(id: $0.0, title: "t", key: $0.1) })
        #expect(
            lib.open_view(spec(.keyCamelot, false, "")).rows.map { lib.key_name($0) } == [
                "Abm", "G#m", "B", "Ebm", "A", "E", "Odd",
            ])
        #expect(lib.key_name(lib.open_view(spec(.keyCamelot, true, "")).rows[0]) == "Odd")
    }
    @Test("sorts_by_title_case_and_accent_insensitively") func sorts_by_title_case_and_accent_insensitively() {
        let lib = library_from(sample())
        #expect(
            lib.open_view(spec(.title, false, "")).rows.map { lib.title.get(Int($0)) } == [
                "apple", "Banana", "Cherry (Extended Mix)", "Ébano", "Zebra",
            ])
    }
    @Test("sorts_by_comment_case_and_accent_insensitively") func sorts_by_comment_case_and_accent_insensitively() {
        let tracks = ["Zebra", "apple", "Ébano", "Banana"].enumerated().map {
            TestTrack(id: UInt64($0.offset + 1), title: "track", comment: $0.element)
        }
        let lib = library_from(tracks)
        #expect(
            lib.open_view(spec(.comment, false, "")).rows.map { lib.comment.get(Int($0)) } == [
                "apple", "Banana", "Ébano", "Zebra",
            ])
    }
    @Test("descending_is_the_exact_reverse_of_ascending") func descending_is_the_exact_reverse_of_ascending() {
        let lib = library_from(sample())
        let asc = lib.open_view(spec(.title, false, ""))
        let desc = lib.open_view(spec(.title, true, ""))
        #expect(asc.rows == Array(desc.rows.reversed()))
    }
    @Test("sorts_numerically_not_lexically") func sorts_numerically_not_lexically() {
        let lib = library_from(sample())
        #expect(
            lib.open_view(spec(.bpm, false, "")).rows.map { lib.bpm_x100[Int($0)] } == [0, 12400, 12800, 13000, 14000])
    }
    @Test("search_is_case_and_accent_insensitive") func search_is_case_and_accent_insensitive() {
        let lib = library_from(sample())
        #expect(lib.open_view(spec(.title, false, "ARTBAT")).len() == 2)
        #expect(lib.open_view(spec(.title, false, "ebano")).len() == 1)
        #expect(lib.open_view(spec(.title, false, "ÉBANO")).len() == 1)
    }
    @Test("search_requires_every_token") func search_requires_every_token() {
        let lib = library_from(sample())
        #expect(lib.open_view(spec(.title, false, "cherry extended")).len() == 1)
        #expect(lib.open_view(spec(.title, false, "cherry zebra")).len() == 0)
    }
    @Test("search_ignores_punctuation") func search_ignores_punctuation() {
        #expect(library_from(sample()).open_view(spec(.title, false, "(extended mix)")).len() == 1)
    }
    @Test("refining_a_view_matches_searching_from_scratch") func refining_a_view_matches_searching_from_scratch() {
        let lib = library_from(sample())
        let broad = lib.open_view(spec(.title, false, "a"))
        let refined = lib.refine(broad, "artbat")
        let direct = lib.open_view(spec(.title, false, "artbat"))
        #expect(refined.rows.sorted() == direct.rows.sorted())
    }
    @Test("clearing_the_query_restores_the_previous_set") func clearing_the_query_restores_the_previous_set() {
        let lib = library_from(sample())
        let broad = lib.open_view(spec(.title, false, "a"))
        #expect(lib.refine(broad, "").rows == broad.rows)
    }
    @Test("window_clamps_instead_of_panicking") func window_clamps_instead_of_panicking() {
        let view = library_from(sample()).open_view(spec(.title, false, ""))
        #expect(view.window(0, 2).count == 2)
        #expect(view.window(3, 100).count == 2)
        #expect(view.window(500, 64).count == 0)
        #expect(view.window(0, 0).count == 0)
        #expect(view.window(UInt.max, 64).count == 0)
    }
    @Test("ids_in_range_works_in_either_direction_and_clamps") func ids_in_range_works_in_either_direction_and_clamps()
    {
        let lib = library_from(sample())
        let view = lib.open_view(spec(.title, false, ""))
        let forward = lib.ids_in_range(view, 1, 3)
        let backward = lib.ids_in_range(view, 3, 1)
        #expect(forward == backward)
        #expect(forward.count == 3)
        #expect(lib.ids_in_range(view, 0, 999).count == 5)
    }
    @Test("a_playlist_view_holds_only_its_own_rows") func a_playlist_view_holds_only_its_own_rows() {
        let lib = library_from(sample())
        let pl = add_playlist(lib, "Set", [4, 0, 2])
        let view = lib.open_view(ViewSpec(source: .playlist(pl), sort: .title))
        #expect(view.rows.map { lib.title.get(Int($0)) } == ["Cherry (Extended Mix)", "Ébano", "Zebra"])
    }
    @Test("searching_within_a_playlist_stays_within_it") func searching_within_a_playlist_stays_within_it() {
        let lib = library_from(sample())
        let pl = add_playlist(lib, "Set", [0, 1])
        let view = lib.open_view(ViewSpec(source: .playlist(pl), sort: .title, query: "artbat"))
        #expect(view.len() == 1)
    }
    @Test("an_unknown_playlist_index_yields_an_empty_view_rather_than_panicking")
    func an_unknown_playlist_index_yields_an_empty_view_rather_than_panicking() {
        #expect(library_from(sample()).open_view(ViewSpec(source: .playlist(999), sort: .title)).is_empty())
    }
    @Test("an_empty_library_sorts_and_searches_without_panicking")
    func an_empty_library_sorts_and_searches_without_panicking() {
        let lib = library_from([])
        let view = lib.open_view(spec(.title, false, ""))
        #expect(view.is_empty())
        #expect(lib.open_view(spec(.bpm, true, "anything")).is_empty())
        #expect(lib.ids_in_range(view, 0, 10).isEmpty)
        #expect(view.window(0, 64).count == 0)
    }
    @Test("every_sort_column_produces_a_full_permutation") func every_sort_column_produces_a_full_permutation() {
        let lib = library_from(sample())
        for column in SortColumn.ALL {
            for descending in [false, true] {
                let view = lib.open_view(spec(column, descending, ""))
                #expect(Set(view.rows).count == 5)
            }
        }
    }
    @Test("hot_cue_letters_follow_rekordbox_s_kind_numbering") func hot_cue_letters_follow_rekordbox_s_kind_numbering()
    {
        func letter(_ kind: UInt8) -> Character? { Cue(kind: kind).hot_letter() }
        #expect(letter(0) == nil)
        #expect(letter(1) == "A")
        #expect(letter(2) == "B")
        #expect(letter(3) == "C")
        #expect(letter(4) == nil)
        #expect(letter(5) == "D")
        #expect(letter(6) == "E")
        #expect(letter(9) == "H")
        #expect(letter(10) == "I")
        #expect(letter(17) == "P")
        #expect(letter(18) == nil)
        #expect(letter(255) == nil)
    }
    @Test("a_letter_round_trips_through_the_kind_it_is_stored_as")
    func a_letter_round_trips_through_the_kind_it_is_stored_as() throws {
        for code: UInt32 in 65...80 {
            let letter = Character(Unicode.Scalar(code)!)
            let kind = try #require(Cue.kind_of_letter(letter))
            #expect(kind != 4)
            #expect(Cue(kind: kind).hot_letter() == letter)
        }
        #expect(Cue.kind_of_letter("a") == 1)
        #expect(Cue.kind_of_letter("Q") == nil)
        #expect(Cue.kind_of_letter("1") == nil)
        #expect(Cue.kind_of_letter("é") == nil)
    }
    @Test("a_memory_cue_is_distinguishable_from_a_hot_one") func a_memory_cue_is_distinguishable_from_a_hot_one() {
        #expect(Cue(kind: 0).is_memory())
        #expect(!Cue(kind: 1).is_memory())
    }
    @Test("a_playlist_keeps_its_own_order_when_sorting_is_off")
    func a_playlist_keeps_its_own_order_when_sorting_is_off() {
        let lib = library_from(sample())
        let members: [Row] = [4, 1, 3, 0]
        add_playlist(lib, "Set", members)
        let natural = ViewSpec(source: .playlist(0), sort: .trackNo)
        #expect(lib.open_view(natural).rows == members)
        var backwards = natural
        backwards.descending = true
        #expect(lib.open_view(backwards).rows == [0, 3, 1, 4])
        var by_title = natural
        by_title.sort = .title
        #expect(lib.open_view(by_title).rows != members)
    }
    @Test("the_collection_in_its_own_order_is_the_row_order") func the_collection_in_its_own_order_is_the_row_order() {
        #expect(library_from(sample()).open_view(spec(.trackNo, false, "")).rows == [0, 1, 2, 3, 4])
    }
    @Test("numeric_detail_columns_sort_by_number_with_blanks_first")
    func numeric_detail_columns_sort_by_number_with_blanks_first() {
        let values: [UInt16] = [10, 9, 100, 0]
        let tracks = values.enumerated().map { index, value in
            TestTrack(
                id: UInt64(index + 1), title: "t", year: value, file_size: UInt64(value) * 1_000_000_000,
                sample_rate: UInt32(value), bitrate: UInt32(value), track_number: UInt32(value), disc_no: value,
                bit_depth: value)
        }
        let lib = library_from(tracks)
        let checks: [(SortColumn, (Int) -> UInt64)] = [
            (.size, { lib.file_size[$0] / 1_000_000_000 }), (.year, { UInt64(lib.year[$0]) }),
            (.sampleRate, { UInt64(lib.sample_rate[$0]) }), (.bitrate, { UInt64(lib.bitrate[$0]) }),
            (.discNo, { UInt64(lib.disc_no[$0]) }), (.trackNumber, { UInt64(lib.track_number[$0]) }),
            (.bitDepth, { UInt64(lib.bit_depth[$0]) }),
        ]
        for (column, value) in checks {
            #expect(ordered(lib, column, false, value) == [0, 9, 10, 100])
            #expect(ordered(lib, column, true, value) == [100, 10, 9, 0])
        }
    }
    @Test("the_tag_track_number_is_not_the_views_own_order") func the_tag_track_number_is_not_the_views_own_order() {
        let values: [UInt32] = [3, 1, 2]
        let lib = library_from(
            values.enumerated().map { TestTrack(id: UInt64($0.offset + 1), title: "t", track_number: $0.element) })
        #expect(lib.open_view(spec(.trackNo, false, "")).rows == [0, 1, 2])
        #expect(lib.open_view(spec(.trackNumber, false, "")).rows == [1, 2, 0])
    }
    @Test("colour_sorts_in_palette_order_not_by_name") func colour_sorts_in_palette_order_not_by_name() {
        let values: [UInt8] = [8, 0, 2, 1]
        let lib = library_from(
            values.enumerated().map { TestTrack(id: UInt64($0.offset + 1), title: "t", color: $0.element) })
        #expect(ordered(lib, .color, false) { lib.color[$0] } == [0, 1, 2, 8])
    }
    @Test("file_type_sorts_by_rekordbox_s_code_not_its_name") func file_type_sorts_by_rekordbox_s_code_not_its_name() {
        let values: [UInt8] = [12, 1, 11, 5, 4]
        let lib = library_from(
            values.enumerated().map { TestTrack(id: UInt64($0.offset + 1), title: "t", file_type: $0.element) })
        #expect(ordered(lib, .fileType, false) { lib.file_type[$0] } == [1, 4, 5, 11, 12])
    }
    @Test("publish_track_information_puts_ticked_tracks_first")
    func publish_track_information_puts_ticked_tracks_first() {
        let lib = library_from(
            [false, true, false, true].enumerated().map {
                TestTrack(id: UInt64($0.offset + 1), title: "t", publish: $0.element)
            })
        #expect(lib.open_view(spec(.publishTrackInfo, false, "")).rows == [1, 3, 0, 2])
        #expect(lib.open_view(spec(.publishTrackInfo, true, "")).rows == [2, 0, 3, 1])
    }
    @Test("detail_text_columns_fold_case_and_accents_with_blanks_first")
    func detail_text_columns_fold_case_and_accents_with_blanks_first() {
        let words = ["Zebra", "", "apple", "Ébano"]
        let lib = library_from(
            words.enumerated().map { index, word in
                TestTrack(
                    id: UInt64(index + 1), title: "t", album_artist: word, original_artist: word, composer: word,
                    remixer: word, mix_name: word, lyricist: word, message: word)
            })
        for column: SortColumn in [.composer, .albumArtist, .remixer, .originalArtist, .mixName, .lyricist, .message] {
            #expect(ordered(lib, column, false) { words[$0] } == ["", "apple", "Ébano", "Zebra"])
        }
    }
    @Test("location_keeps_a_folders_tracks_together") func location_keeps_a_folders_tracks_together() {
        let paths = ["/m/AB/a.mp3", "/m/A/z.mp3", "/m/a/b.mp3"]
        let lib = library_from(
            paths.enumerated().map { TestTrack(id: UInt64($0.offset + 1), title: "t", path: $0.element) })
        #expect(ordered(lib, .location, false) { paths[$0] } == ["/m/a/b.mp3", "/m/A/z.mp3", "/m/AB/a.mp3"])
        #expect(ordered(lib, .fileName, false) { lib.file_name.get($0) } == ["a.mp3", "b.mp3", "z.mp3"])
    }
    @Test("date_created_sorts_as_the_date_reads") func date_created_sorts_as_the_date_reads() {
        let dates = ["2024-11-02", "", "2023-01-30", "2024-02-15"]
        let lib = library_from(
            dates.enumerated().map { TestTrack(id: UInt64($0.offset + 1), title: "t", date_created: $0.element) })
        #expect(ordered(lib, .dateCreated, false) { dates[$0] } == ["", "2023-01-30", "2024-02-15", "2024-11-02"])
    }
}
