// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-index/tests/smartlists.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportModel

private func tracks() -> [TestTrack] {
    [
        TestTrack(
            id: 1, title: "Alpha", artist: "Daft Punk", album: "Discovery", album_artist: "Daft Punk",
            original_artist: "Sister Sledge", composer: "Thomas Bangalter", remixer: "", mix_name: "Album Mix",
            comment: "peak time", bpm_x100: 12_300, length_sec: 300, rating: 5, date_added: "2026-09-01", key: "Am",
            color: 1, path: "/m/alpha.mp3", genre: "House", year: 2001, play_count: 12),
        TestTrack(
            id: 2, title: "Beta", artist: "Bicep", album: "Isles", album_artist: "Bicep", original_artist: "",
            composer: "Bicep", remixer: "Four Tet", mix_name: "Club Mix", comment: "", bpm_x100: 12_800,
            length_sec: 420, rating: 3, date_added: "2026-06-15", key: "F#m", color: 6, path: "/m/beta.mp3",
            genre: "Electronica", year: 2021, play_count: 0),
        TestTrack(
            id: 3, title: "Gamma", artist: "Ben Böhmer", album: "Begin Again", album_artist: "Ben Böhmer",
            original_artist: "", composer: "Ben Böhmer", remixer: "", mix_name: "Original Mix", comment: "opener",
            bpm_x100: 12_200, length_sec: 250, rating: 4, date_added: "2024-01-10", key: "Am", color: 0,
            path: "/m/gamma.mp3", genre: "Melodic House", year: 2021, play_count: 3),
    ]
}
private func rule(_ logic: UInt8, _ conditions: [(String, UInt8, String, String, String)]) -> String {
    var xml = "<NODE Id=\"1\" LogicalOperator=\"\(logic)\" AutomaticUpdate=\"1\">"
    for (property, op, left, right, unit) in conditions {
        xml +=
            "<CONDITION PropertyName=\"\(property)\" Operator=\"\(op)\" ValueUnit=\"\(unit)\" ValueLeft=\"\(left)\" ValueRight=\"\(right)\"/>"
    }
    xml += "</NODE>"
    return xml
}
private func rows_of(_ lib: Library, _ xml: String) throws -> [UInt64] {
    let rule = try #require(SmartRule.parse(xml))
    return rule.evaluate_on(lib, SmartDate(year: 2026, month: 9, day: 17)).map { lib.ids[Int($0)] }
}
@Suite("smartlists") struct SmartlistsTests {
    @Test("text_conditions_compare_without_case_or_accents")
    func text_conditions_compare_without_case_or_accents() throws {
        let lib = library_from(tracks())
        #expect(try rows_of(lib, rule(1, [("genre", 8, "house", "", "")])) == [1, 3])
        #expect(try rows_of(lib, rule(1, [("artist", 1, "ben bohmer", "", "")])) == [3])
        #expect(try rows_of(lib, rule(1, [("name", 10, "B", "", "")])) == [2])
        #expect(try rows_of(lib, rule(1, [("album", 11, "S", "", "")])) == [2])
        #expect(try rows_of(lib, rule(1, [("albumArtist", 1, "bicep", "", "")])) == [2])
        #expect(try rows_of(lib, rule(1, [("originalArtist", 8, "sister", "", "")])) == [1])
        #expect(try rows_of(lib, rule(1, [("producer", 1, "bicep", "", "")])) == [2])
        #expect(try rows_of(lib, rule(1, [("remixedBy", 8, "four", "", "")])) == [2])
        #expect(try rows_of(lib, rule(1, [("mixName", 10, "club", "", "")])) == [2])
        #expect(try rows_of(lib, rule(1, [("comments", 9, "peak", "", "")])) == [3])
        #expect(try rows_of(lib, rule(1, [("fileName", 8, "gamma", "", "")])) == [3])
        #expect(try rows_of(lib, rule(1, [("key", 1, "Am", "", "")])) == [1, 3])
    }
    @Test("number_conditions_read_the_columns") func number_conditions_read_the_columns() throws {
        let lib = library_from(tracks())
        #expect(try rows_of(lib, rule(1, [("bpm", 5, "12200", "12500", "")])) == [1, 3])
        #expect(try rows_of(lib, rule(1, [("bpm", 3, "12500", "", "")])) == [2])
        #expect(try rows_of(lib, rule(1, [("rating", 3, "3", "", "")])) == [1, 3])
        #expect(try rows_of(lib, rule(1, [("rating", 1, "3", "", "")])) == [2])
        #expect(try rows_of(lib, rule(1, [("duration", 4, "5:00", "", "")])) == [3])
        #expect(try rows_of(lib, rule(1, [("year", 1, "2021", "", "")])) == [2, 3])
        #expect(try rows_of(lib, rule(1, [("counter", 2, "0", "", "")])) == [1, 3])
        #expect(try rows_of(lib, rule(1, [("grouping", 1, "6", "", "")])) == [2])
        // 이름으로 저장된 색(rbx 1.6.0의 자유 입력 Color 조건)은 rekordbox처럼 getIntAttribute로 읽어 0, 색 없음이다.
        #expect(try rows_of(lib, rule(1, [("grouping", 1, "Pink", "", "")])) == [3])
        #expect(try rows_of(lib, rule(1, [("grouping", 1, "0", "", "")])) == [3])
    }
    @Test("date_conditions_count_back_from_today") func date_conditions_count_back_from_today() throws {
        let lib = library_from(tracks())
        #expect(try rows_of(lib, rule(1, [("stockDate", 6, "1", "", "month")])) == [1])
        #expect(try rows_of(lib, rule(1, [("stockDate", 6, "6", "", "months")])) == [UInt64]())
        #expect(try rows_of(lib, rule(1, [("stockDate", 7, "1", "", "year")])) == [1, 2, 3])
        #expect(try rows_of(lib, rule(1, [("stockDate", 3, "2026-01-01", "", "")])) == [1, 2])
        #expect(try rows_of(lib, rule(1, [("stockDate", 5, "2024-01-01", "2026-07-01", "")])) == [2, 3])
    }
    @Test("all_and_any_combine_and_invalid_rules_admit_nothing")
    func all_and_any_combine_and_invalid_rules_admit_nothing() throws {
        let lib = library_from(tracks())
        let both = rule(1, [("genre", 8, "house", "", ""), ("rating", 1, "5", "", "")])
        #expect(try rows_of(lib, both) == [1])
        let either = rule(2, [("genre", 8, "electronica", "", ""), ("rating", 1, "5", "", "")])
        #expect(try rows_of(lib, either) == [1, 2])
        // My Tag는 "contains"와 "does not contain"만 답한다. 이 곡들은 태그가 없으므로 "="는 아무것도 받지 않고 규칙은 이해된다.
        let tagged = rule(1, [("myTag", 1, "7", "", "")])
        #expect(try rows_of(lib, tagged).isEmpty)
        #expect(try #require(SmartRule.parse(tagged)).unsupported() == 0)
        let unknown = rule(1, [("hotCueCount", 1, "7", "", "")])
        #expect(try rows_of(lib, unknown).isEmpty)
        #expect(try #require(SmartRule.parse(unknown)).unsupported() == 1)
        #expect(try rows_of(lib, "<NODE LogicalOperator=\"1\"/>").isEmpty)
        #expect(try rows_of(lib, "<NODE LogicalOperator=\"2\"/>").isEmpty)
        #expect(
            try rows_of(lib, "<NODE LogicalOperator=\"1\"><CONDITION PropertyName=\"genre\" Operator=\"99\"/></NODE>")
                .isEmpty)
        #expect(
            SmartRule.parse(
                "<CONDITION PropertyName=\"genre\" Operator=\"1\" ValueLeft=\"House\"/><NODE LogicalOperator=\"1\"/>")
                == nil)
    }
    @Test("a_smart_playlist_opens_as_a_view_and_sorts_and_searches_like_any_other")
    func a_smart_playlist_opens_as_a_view_and_sorts_and_searches_like_any_other() {
        let lib = library_from(tracks())
        let index = add_smart_playlist(lib, "Housey", rule(1, [("genre", 8, "house", "", "")]))
        #expect(lib.playlists().is_smart(index))
        #expect(!lib.playlists().is_folder(index))
        #expect(lib.playlists().smart_rule(index) != nil)

        let view = lib.open_view(
            ViewSpec(source: .smartPlaylist(index), sort: .title, descending: true, query: "", filter: TrackFilter()))
        #expect(view.rows.map { lib.ids[Int($0)] } == [3, 1])

        let narrowed = lib.open_view(
            ViewSpec(
                source: .smartPlaylist(index), sort: .trackNo, descending: false, query: "gamma", filter: TrackFilter()
            ))
        #expect(narrowed.rows.count == 1)

        // 파싱되지 않는 규칙은 아무것도 없는 재생목록이다.
        let broken = add_smart_playlist(lib, "Broken", "not xml at all")
        #expect(lib.source_rows(.smartPlaylist(broken)).isEmpty)
    }
}
