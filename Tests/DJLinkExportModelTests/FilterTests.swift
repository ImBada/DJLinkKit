// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-index/tests/filter.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportModel

private func track(_ id: UInt64, _ bpm: UInt32, _ key: String, _ rating: UInt8, _ color: UInt8) -> TestTrack {
    TestTrack(id: id, title: "t", artist: "a", bpm_x100: bpm, rating: rating, key: key, color: color)
}
/// 여섯 곡: 128이 둘(하나는 127.98), 126·130·140이 하나씩, 분석되지 않은 곡이 하나.
private func sample() -> [TestTrack] {
    [
        track(1, 12800, "Fm", 5, 2),
        track(2, 12798, "A", 3, 0),
        track(3, 12600, "Abm", 0, 5),
        track(4, 13000, "A", 3, 2),
        track(5, 14000, "F#", 1, 0),
        track(6, 0, "", 0, 0),
    ]
}
private func spec(_ filter: TrackFilter) -> ViewSpec {
    ViewSpec(source: .collection, sort: .trackNo, descending: false, query: "", filter: filter)
}
private func ids(_ lib: Library, _ filter: TrackFilter) -> [UInt64] {
    lib.open_view(spec(filter)).rows.map { lib.ids[Int($0)] }
}
private func bpm(_ values: [UInt32], _ pct: UInt8, _ master: UInt32?) -> TrackFilter {
    TrackFilter(bpm: BpmFilter(values: values, tolerance_pct: pct, master_bpm_x100: master))
}
@Suite("filter") struct FilterTests {
    @Test("an_empty_filter_changes_nothing") func an_empty_filter_changes_nothing() {
        let lib = library_from(sample())
        #expect(TrackFilter().is_empty())
        #expect(ids(lib, TrackFilter()) == [1, 2, 3, 4, 5, 6])
    }
    @Test("a_picked_bpm_is_its_whole_number_bucket") func a_picked_bpm_is_its_whole_number_bucket() {
        let lib = library_from(sample())
        // 127.98은 128로 반올림되어 목록이 보여 준 묶음에 그대로 있다.
        #expect(ids(lib, bpm([128], 0, nil)) == [1, 2])
        #expect(ids(lib, bpm([128, 140], 0, nil)) == [1, 2, 5])
        #expect(ids(lib, bpm([999], 0, nil)) == [UInt64]())
    }
    @Test("a_tolerance_widens_a_picked_bpm") func a_tolerance_widens_a_picked_bpm() {
        let lib = library_from(sample())
        // 128 ± 2%는 125.44..130.56이라 126과 130을 받고 140은 받지 않는다.
        #expect(ids(lib, bpm([128], 2, nil)) == [1, 2, 3, 4])
        // ±1%는 126.72..129.28이라 126과 130이 다시 빠진다.
        #expect(ids(lib, bpm([128], 1, nil)) == [1, 2])
    }
    @Test("all_with_a_master_player_is_a_band_around_its_bpm") func all_with_a_master_player_is_a_band_around_its_bpm() {
        let lib = library_from(sample())
        // 128.00 둘레 ±0%는 정확히 128.00뿐이다. 127.98은 아니다.
        #expect(ids(lib, bpm([], 0, 12800)) == [1])
        #expect(ids(lib, bpm([], 2, 12800)) == [1, 2, 3, 4])
        // 133 ± 6%는 125.02..140.98이라 분석된 곡 전부다.
        #expect(ids(lib, bpm([], 6, 13300)) == [1, 2, 3, 4, 5])
    }
    @Test("all_without_a_master_player_is_every_track") func all_without_a_master_player_is_every_track() {
        let lib = library_from(sample())
        // 중심이 없으면 ± 목록은 동작하지 않고, 켠 BPM 열은 분석되지 않은 곡까지 모두 받는다.
        #expect(ids(lib, bpm([], 3, nil)) == [1, 2, 3, 4, 5, 6])
    }
    @Test("keys_match_by_every_id_carrying_the_name") func keys_match_by_every_id_carrying_the_name() {
        let lib = library_from(sample())
        // `A`를 가진 곡이 둘이고, djmdKey처럼 각각 자기 interner id를 가진다.
        let a = lib.key_ids_named(["A"])
        #expect(a.count == 2)
        #expect(ids(lib, TrackFilter(keys: a)) == [2, 4])

        #expect(ids(lib, TrackFilter(keys: [])) == [UInt64]())
        #expect(lib.key_ids_named(["Zm"]).isEmpty)
    }
    @Test("ratings_and_colours_are_sets") func ratings_and_colours_are_sets() {
        let lib = library_from(sample())
        #expect(ids(lib, TrackFilter(ratings: [0, 5])) == [1, 3, 6])
        #expect(ids(lib, TrackFilter(colors: [2])) == [1, 4])
        #expect(ids(lib, TrackFilter(colors: [2, 5])) == [1, 3, 4])
        // 여덟을 넘는 색 id는 패닉이 아니라 그저 맞지 않는다.
        #expect(ids(lib, TrackFilter(colors: [200])) == [UInt64]())
    }
    @Test("ticked_columns_combine_with_and") func ticked_columns_combine_with_and() {
        let lib = library_from(sample())
        let filter = TrackFilter(
            bpm: BpmFilter(values: [128, 130], tolerance_pct: 0, master_bpm_x100: nil),
            keys: lib.key_ids_named(["A"]), ratings: [3], colors: [2])
        #expect(ids(lib, filter) == [4])
    }
    @Test("the_filter_applies_after_the_query_and_within_a_playlist")
    func the_filter_applies_after_the_query_and_within_a_playlist() {
        let lib = library_from(sample())
        let pl = add_playlist(lib, "Set", [4, 0, 2])
        let view = lib.open_view(
            ViewSpec(
                source: .playlist(pl), sort: .trackNo, descending: false, query: "", filter: bpm([128, 140], 0, nil)))
        // 구성원 순서를 지킨다: 5번 곡, 그다음 1번 곡.
        #expect(view.rows.map { lib.ids[Int($0)] } == [5, 1])
    }
    @Test("the_value_lists_count_the_unfiltered_list_in_the_bars_order")
    func the_value_lists_count_the_unfiltered_list_in_the_bars_order() {
        let lib = library_from(sample())
        set_my_tags(lib, [TagCategory(name: "Lexicon Tags", tags: ["Components ▶ Synth"])])
        // 한 곡만 남기는 필터도 목록을 줄여서는 안 된다.
        let values = lib.filter_values(spec(bpm([140], 0, nil)))
        #expect(values.bpms.map(\.value) == [126, 128, 130, 140])
        #expect(values.bpms.map(\.count) == [1, 2, 1, 1])
        // Camelot 순서: 1A Abm, 2B F#, 4A Fm, 11B A. `A`는 두 id의 곡이 한 항목 뒤에 있다.
        #expect(values.keys.map(\.value) == ["Abm", "F#", "Fm", "A"])
        #expect(values.keys.map(\.count) == [1, 1, 1, 2])
        #expect(values.tags.count == 1)
        #expect(values.tags[0].tags == ["Components ▶ Synth"])
    }
    @Test("the_value_lists_follow_the_source_and_query") func the_value_lists_follow_the_source_and_query() {
        let lib = library_from(sample())
        let pl = add_playlist(lib, "Set", [2, 4])
        let values = lib.filter_values(
            ViewSpec(source: .playlist(pl), sort: .title, descending: true, query: "", filter: TrackFilter()))
        #expect(values.bpms.map(\.value) == [126, 140])
        #expect(values.keys.map(\.value) == ["Abm", "F#"])
    }
    // 원본은 디스크 캐시(rbl_index::cache)의 encode/decode를 거친다. 디스크 캐시는 서버 범위 밖이라 옮기지 않았다.
    @Test("a_snapshot_keeps_the_tag_categories", .disabled("디스크 캐시(rbl_index::cache)는 서버 범위 밖이라 옮기지 않았다"))
    func a_snapshot_keeps_the_tag_categories() {}
}
