// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-link/src/catalog.rs의 tests
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import DJLinkExportDBServer
import DJLinkExportModel
import DJLinkKit
import Testing

@testable import DJLinkExport

private typealias MenuRow = DJLinkExportDBServer.Row
@DJLinkActor private final class CatalogTestSource: Source {
    var value: Library
    var notation: KeyNotation = .alphanumeric, order: KeyOrder = .musical
    var day: SmartDate?, numbered = false, matching = false, writable = false,
        taggedRows: [DJLinkExportModel.MyTagRow] = []
    init(_ value: Library) { self.value = value }
    func library() -> Library? { value }
    func share_root() -> String { "/nonexistent" }
    func details(_ id: String) -> DJLinkExportModel.TrackDetails? {
        numbered ? DJLinkExportModel.TrackDetails(track_number: id == "10" ? 2 : id == "11" ? 1 : 0) : nil
    }
    func key_notation() -> KeyNotation { notation }
    func key_order() -> KeyOrder { order }
    func today() -> SmartDate { day ?? SmartDate.today() }
    func matching_ids(_ seed: UInt32) -> [UInt32] {
        if matching {
            #expect(seed == 99)
            return [10, 11]
        }
        return []
    }
    func my_tags() -> [DJLinkExportModel.MyTagRow] { taggedRows }
    func new_link_history() -> UInt32? {
        guard writable else { return nil }
        let lib = Library()
        lib.set_histories(value.histories())
        let index = add_history(lib, "LINK HISTORY 2026-09-26", [])
        let id = lib.histories().ids[index]
        value.set_histories(lib.histories())
        return UInt32(exactly: id)
    }
    func add_to_history(_ history: UInt32, _ track: UInt32) -> Bool {
        guard writable else { return false }
        var lists = value.histories()
        guard let index = lists.index_of(UInt64(history)), let row = value.row_of_id(UInt64(track)) else {
            return false
        }
        lists.members[index].append(row)
        value.set_histories(lists)
        return true
    }
    func remove_from_history(_ history: UInt32, _ track: UInt32) -> Bool {
        guard writable else { return false }
        var lists = value.histories()
        guard let index = lists.index_of(UInt64(history)), let row = value.row_of_id(UInt64(track)) else {
            return false
        }
        lists.members[index].removeAll { $0 == row }
        value.set_histories(lists)
        return true
    }
}
@DJLinkActor private func catalogLibrary() -> Library {
    func t(
        _ id: UInt64, _ title: String, _ artist: String, _ album: String, _ genre: String, _ label: String,
        _ key: String, _ bpm: UInt32, _ date: String, _ count: UInt16
    ) -> TestTrack {
        TestTrack(
            id: id, title: title, artist: artist, album: album, label: label, bpm_x100: bpm, date_added: date, key: key,
            path: "/Volumes/SD/RB/x.mp3", genre: genre, play_count: count)
    }
    let lib = library_from([
        t(10, "Zebra", "Bob", "Second", "House", "Zulu", "Am", 12800, "2025-03-04", 2),
        t(11, "Apple", "Alice", "First", "Techno", "Alpha", "Abm", 12000, "2026-01-09", 9),
        t(12, "Mango", "Carol", "Second", "Ambient", "Mike", "B", 13000, "2026-01-20", 5),
    ])
    _ = add_folder(lib, "Crates")
    add_playlist(lib, "Warm up", [2, 0])
    add_history(lib, "HISTORY 2026-09-01", [1])
    add_history(lib, "HISTORY 2026-09-02", [0])
    return lib
}
@DJLinkActor private func catalogFixture() -> IndexCatalog {
    IndexCatalog(CatalogTestSource(catalogLibrary()), Played())
}
private func catalogIDs(_ rows: [MenuRow]) -> [UInt32] {
    rows.map {
        switch $0 {
        case let .track(id, _), let .named(id, _), let .list(id, _, _, _): return id
        case let .date(value): return value
        }
    }
}
@DJLinkActor private func history_menu(_ c: IndexCatalog) throws -> [String] {
    try c.list(.histories).map {
        if case let .named(_, name) = $0 { return name }
        throw CatalogTestError.unexpectedRow
    }
}
private enum CatalogTestError: Error { case unexpectedRow }
@Suite("catalog::tests") @DJLinkActor struct CatalogTests {
    @Test("the_track_menu_is_alphabetical_by_default_and_sorts_on_request")
    func the_track_menu_is_alphabetical_by_default_and_sorts_on_request() {
        let c = catalogFixture()
        let expected: [(Sort, [UInt32])] = [
            (.default, [11, 12, 10]), (.bpm, [11, 10, 12]), (.artist, [11, 10, 12]), (.genre, [12, 10, 11]),
            (.label, [11, 12, 10]), (.dateAdded, [10, 11, 12]), (.djPlayCount, [10, 12, 11]),
        ]
        for (sort, ids) in expected { #expect(catalogIDs(c.list(.tracks(scope: .all, sort: sort))) == ids) }
    }
    @Test("key_notation_and_order_are_independent") func key_notation_and_order_are_independent() throws {
        for notation in [KeyNotation.classic, .alphanumeric] {
            for order in [KeyOrder.musical, .alphabetical] {
                let source = CatalogTestSource(catalogLibrary())
                source.notation = notation
                source.order = order
                let c = IndexCatalog(source, Played())
                #expect(
                    catalogIDs(c.list(.tracks(scope: .all, sort: .key)))
                        == (order == .musical ? [11, 12, 10] : [11, 10, 12]))
                let ids = c.key_ids()
                if order == .musical {
                    #expect(ids == Array(UInt32(1)...24))
                } else {
                    #expect(ids.first.map(DJLinkExportDBServer.keys.name) == "A")
                    #expect(ids.firstIndex(of: 1) == 2)
                }
                let name = notation == .classic ? "Am" : "8A"
                #expect(c.key_name(15) == name)
                let row = try #require(c.track_row(10, .key))
                #expect(row.key_name == name)
                #expect(row.secondary_text == name)
                #expect(try #require(c.track(10)).key_name == name)
            }
        }
    }
    @Test("custom_key_names_keep_their_notation_behavior") func custom_key_names_keep_their_notation_behavior() throws {
        func library() -> Library {
            library_from([
                TestTrack(id: 20, key: "Alpha"), TestTrack(id: 21, key: "Beta Alpha"), TestTrack(id: 22, key: "alpha"),
                TestTrack(id: 23, key: "Ａｌｐｈａ"),
            ])
        }
        let classicSource = CatalogTestSource(library())
        classicSource.notation = .classic
        let classic = IndexCatalog(classicSource, Played())
        for (id, name) in [(UInt32(20), "Alpha"), (21, "Beta Alpha"), (22, "alpha"), (23, "Ａｌｐｈａ")] {
            #expect(try #require(classic.track_row(id, nil)).key_name == name)
        }
        let alphanumeric = IndexCatalog(CatalogTestSource(library()), Played())
        for (id, name) in [(UInt32(20), "11B"), (21, "1B"), (22, ""), (23, "11B")] {
            #expect(try #require(alphanumeric.track_row(id, nil)).key_name == name)
        }
        #expect(try #require(alphanumeric.track(20)).key_name == "11B")
    }
    @Test("key_sort_uses_the_wheel_and_preserves_playlist_positions")
    func key_sort_uses_the_wheel_and_preserves_playlist_positions() {
        #expect(catalogIDs(catalogFixture().list(.tracks(scope: .all, sort: .key))) == [11, 12, 10])
        let lib = catalogLibrary()
        let index = add_playlist(lib, "Keys", [0, 2, 1])
        let playlist = UInt32(lib.playlists().ids[index])
        let c = IndexCatalog(CatalogTestSource(lib), Played())
        #expect(
            c.list(.tracks(scope: .playlist(playlist), sort: .key)) == [
                .track(id: 11, position: 3), .track(id: 12, position: 2), .track(id: 10, position: 1),
            ])
    }
    @Test("artists_and_their_albums_preserve_database_ids") func artists_and_their_albums_preserve_database_ids() {
        let lib = catalogLibrary()
        lib.artist_ids = [5001, 5002, 5003]
        lib.album_ids = [6001, 6002, 6003]
        let c = IndexCatalog(CatalogTestSource(lib), Played())
        #expect(
            c.list(.artists(.default)) == [
                .named(id: 5002, name: "Alice"), .named(id: 5001, name: "Bob"), .named(id: 5003, name: "Carol"),
            ])
        #expect(c.list(.artistAlbums(5002)) == [.named(id: 6002, name: "First")])
        #expect(catalogIDs(c.list(.tracks(scope: .artist(artist: 5002, album: 6002), sort: .default))) == [11])
        #expect(catalogIDs(c.list(.tracks(scope: .artist(artist: 5002, album: nil), sort: .default))) == [11])
        #expect(catalogIDs(c.list(.tracks(scope: .album(6001), sort: .default))) == [10])
    }
    @Test("labels_drill_through_artists_and_albums") func labels_drill_through_artists_and_albums() {
        let c = catalogFixture()
        #expect(catalogIDs(c.list(.labels(.default))) == [2, 3, 1])
        #expect(c.list(.labelArtists(2)) == [.named(id: 2, name: "Alice")])
        #expect(c.list(.labelArtistAlbums(label: 2, artist: 2)) == [.named(id: 2, name: "First")])
        #expect(catalogIDs(c.list(.tracks(scope: .label(label: 2, artist: 2, album: 2), sort: .default))) == [11])
    }
    @Test("a_labels_all_path_keeps_tracks_without_an_album") func a_labels_all_path_keeps_tracks_without_an_album() {
        let lib = catalogLibrary()
        lib.label[2] = lib.label[1]
        lib.artist[2] = lib.artist[1]
        lib.album[2] = NO_ID
        let c = IndexCatalog(CatalogTestSource(lib), Played())
        #expect(catalogIDs(c.list(.labelArtistAlbums(label: 2, artist: nil))) == [2])
        #expect(catalogIDs(c.list(.labelArtistAlbums(label: 2, artist: 2))) == [2, 0])
        #expect(
            catalogIDs(c.list(.tracks(scope: .label(label: 2, artist: 2, album: nil), sort: .default))) == [11, 12])
    }
    @Test("an_albums_default_order_and_positions_use_track_numbers")
    func an_albums_default_order_and_positions_use_track_numbers() {
        let lib = catalogLibrary()
        lib.album[1] = lib.album[0]
        let source = CatalogTestSource(lib)
        source.numbered = true
        let c = IndexCatalog(source, Played())
        #expect(
            c.list(.tracks(scope: .album(1), sort: .default)) == [
                .track(id: 11, position: 1), .track(id: 10, position: 2),
            ])
    }
    @Test("matching_tracks_keep_track_numbers_while_sorting_by_title")
    func matching_tracks_keep_track_numbers_while_sorting_by_title() {
        let source = CatalogTestSource(catalogLibrary())
        source.numbered = true
        source.matching = true
        let c = IndexCatalog(source, Played())
        #expect(
            c.list(.tracks(scope: .matching(99), sort: .default)) == [
                .track(id: 11, position: 1), .track(id: 10, position: 2),
            ])
    }
    @Test("keys_are_camelot_ids_and_related_keys_widen_the_list")
    func keys_are_camelot_ids_and_related_keys_widen_the_list() throws {
        let c = catalogFixture()
        #expect(try #require(c.track_row(11, nil)).key == 1)
        #expect(try #require(c.track_row(12, nil)).key == 2)
        #expect(try #require(c.track_row(10, nil)).key == 15)
        #expect(player_key_id("Alpha") == 22)
        #expect(player_key_id("Beta Alpha") == 2)
        #expect(player_key_id("alpha") == 0)
        #expect(player_key_id("Ａｌｐｈａ") == 22)
        #expect(catalogIDs(c.list(.tracks(scope: .key(key: 1, distance: 0), sort: .default))) == [11])
        #expect(catalogIDs(c.list(.tracks(scope: .key(key: 1, distance: 1), sort: .default))) == [11, 12])
    }
    @Test("playlists_keep_their_own_order_and_number_their_rows")
    func playlists_keep_their_own_order_and_number_their_rows() throws {
        let c = catalogFixture()
        let root = c.list(.folder(0))
        #expect(root.count == 2)
        guard case let .list(warm_up, _, false, _) = root[1] else { throw CatalogTestError.unexpectedRow }
        #expect(
            c.list(.tracks(scope: .playlist(warm_up), sort: .default)) == [
                .track(id: 12, position: 1), .track(id: 10, position: 2),
            ])
        #expect(
            c.list(.tracks(scope: .playlist(warm_up), sort: .alphabet)) == [
                .track(id: 12, position: 1), .track(id: 10, position: 2),
            ])
    }
    @Test("smart_playlists_evaluate_rules_instead_of_stored_membership")
    func smart_playlists_evaluate_rules_instead_of_stored_membership() {
        let lib = catalogLibrary()
        let rule =
            "<NODE Id=\"1\" LogicalOperator=\"1\" AutomaticUpdate=\"1\"><CONDITION PropertyName=\"genre\" Operator=\"1\" ValueUnit=\"\" ValueLeft=\"House\" ValueRight=\"\"/></NODE>"
        let index = add_smart_playlist_with_members(lib, "House", [1], rule)
        let playlist = UInt32(lib.playlists().ids[index])
        let c = IndexCatalog(CatalogTestSource(lib), Played())
        #expect(c.list(.tracks(scope: .playlist(playlist), sort: .default)) == [.track(id: 10, position: 1)])
        #expect(!c.listed(.playlist(playlist)))
    }
    @Test("smart_playlists_use_the_source_date_and_expire_cached_rows")
    func smart_playlists_use_the_source_date_and_expire_cached_rows() {
        let lib = catalogLibrary()
        let rule =
            "<NODE Id=\"1\" LogicalOperator=\"1\" AutomaticUpdate=\"1\"><CONDITION PropertyName=\"stockDate\" Operator=\"6\" ValueUnit=\"day\" ValueLeft=\"1\" ValueRight=\"\"/></NODE>"
        let index = add_smart_playlist_with_members(lib, "Recent", [], rule)
        let playlist = UInt32(lib.playlists().ids[index])
        let source = CatalogTestSource(lib)
        source.day = SmartDate(year: 2026, month: 1, day: 20)
        let c = IndexCatalog(source, Played())
        let query = DJLinkExportDBServer.Query.tracks(scope: .playlist(playlist), sort: .default)
        #expect(catalogIDs(c.list(query)) == [12])
        source.day = SmartDate(year: 2026, month: 1, day: 9)
        #expect(catalogIDs(c.list(query)) == [11, 12])
    }
    @Test("playlist_folders_sort_before_lists_regardless_of_sequence")
    func playlist_folders_sort_before_lists_regardless_of_sequence() {
        let lib = library_from([])
        add_playlist(lib, "First sequence", [])
        add_folder(lib, "Later folder")
        let c = IndexCatalog(CatalogTestSource(lib), Played())
        #expect(
            c.list(.folder(0)) == [
                .list(id: 1001, name: "Later folder", folder: true, position: 1),
                .list(id: 1000, name: "First sequence", folder: false, position: 0),
            ])
    }
    @Test("the_history_menu_holds_only_this_link_sessions_history")
    func the_history_menu_holds_only_this_link_sessions_history() throws {
        let source = CatalogTestSource(catalogLibrary())
        source.writable = true
        let played = Played()
        let c = IndexCatalog(source, played.clone())
        #expect(try history_menu(c) == [])
        #expect(!played.contains(11))
        #expect(c.edit(.historyAdd(track: 11)))
        #expect(played.contains(11))
        #expect(c.edit(.historyAdd(track: 11)))
        #expect(c.edit(.historyAdd(track: 10)))
        #expect(c.edit(.historyAdd(track: 11)))
        #expect(try history_menu(c) == ["LINK HISTORY 2026-09-26"])
        guard case let .named(session, _) = try #require(c.list(.histories).first) else {
            throw CatalogTestError.unexpectedRow
        }
        func tracks(_ c: IndexCatalog) -> [UInt32] {
            catalogIDs(c.list(.tracks(scope: .history(session), sort: .default)))
        }
        #expect(tracks(c) == [11, 10, 11])
        #expect(source.value.histories().len() == 3)
        #expect(c.edit(.historyRemove(track: 11)))
        #expect(tracks(c) == [10])
        #expect(c.edit(.historyAdd(track: 10)))
        #expect(tracks(c) == [10])
        #expect(!c.edit(.historyRemove(track: 999)))
        #expect(c.edit(.historyDelete(history: .max)))
        #expect(try history_menu(c) == [])
        #expect(!c.edit(.historyRemove(track: 10)))
        #expect(c.edit(.historyAdd(track: 12)))
        #expect(played.contains(12))
        guard case let .named(next, _) = try #require(c.list(.histories).first) else {
            throw CatalogTestError.unexpectedRow
        }
        #expect(next != session)
        #expect(c.edit(.historyDelete(history: session)))
        #expect(c.list(.histories).count == 1)
    }
    @Test("a_library_that_cannot_be_written_keeps_the_history_menu_empty")
    func a_library_that_cannot_be_written_keeps_the_history_menu_empty() throws {
        let c = catalogFixture()
        #expect(!c.edit(.historyAdd(track: 11)))
        #expect(try history_menu(c) == [])
    }
    @Test("date_added_walks_years_months_and_days") func date_added_walks_years_months_and_days() {
        let c = catalogFixture()
        #expect(c.list(.years) == [.date(2026), .date(2025)])
        #expect(c.list(.months(2026)) == [.date(1)])
        #expect(c.list(.days(year: 2026, month: 1)) == [.date(9), .date(20)])
        #expect(
            catalogIDs(c.list(.tracks(scope: .dateAdded(year: 2026, month: 1, day: nil), sort: .default))) == [11, 12])
        #expect(catalogIDs(c.list(.tracks(scope: .dateAdded(year: 2026, month: 1, day: 9), sort: .default))) == [11])
    }
    @Test("search_matches_the_browser_search") func search_matches_the_browser_search() {
        let c = catalogFixture()
        #expect(catalogIDs(c.list(.tracks(scope: .search("second"), sort: .default))) == [12, 10])
        #expect(c.list(.tracks(scope: .search("nothing"), sort: .default)) == [])
    }
    @Test("track_details_come_from_the_index_with_the_absolute_path")
    func track_details_come_from_the_index_with_the_absolute_path() throws {
        let c = catalogFixture()
        let d = try #require(c.track(10))
        #expect(d.artist == "Bob")
        #expect(d.album == "Second")
        #expect(d.path == "/Volumes/SD/RB/x.mp3")
        #expect(d.date_added == "2025-03-04")
        #expect(d.row.bpm_x100 == 12800)
        #expect(c.track(99) == nil)
    }
    @Test("a_track_without_analysis_has_no_blobs") func a_track_without_analysis_has_no_blobs() {
        let c = catalogFixture()
        #expect(c.analysis(10, .beatGrid) == nil)
        #expect(c.analysis(10, .vbr) == [UInt8](repeating: 0, count: 1604))
        #expect(c.analysis(10, .extendedCueList) == [])
    }
    @Test("usb_cues_keep_only_the_legacy_hot_slots_and_memory_cues")
    func usb_cues_keep_only_the_legacy_hot_slots_and_memory_cues() throws {
        let lib = catalogLibrary()
        let row = try #require(lib.row_of_id(10))
        lib.set_cues_of(
            row,
            [
                DJLinkExportModel.Cue(position_ms: 1000, out_ms: 2000, kind: 1, colour: 21),
                DJLinkExportModel.Cue(position_ms: 3000, out_ms: 0, kind: 0, colour: 0),
                DJLinkExportModel.Cue(position_ms: 4000, out_ms: 0, kind: 5, colour: 35),
            ])
        let c = IndexCatalog(CatalogTestSource(lib), Played())
        #expect(
            c.usb_cues(10) == [
                UsbCue(slot: 1, in_ms: 1000, out_ms: 2000, color_table_index: 21),
                UsbCue(slot: 0, in_ms: 3000, out_ms: nil, color_table_index: 0),
            ])
    }
    @Test("a_cdj_3000_names_the_track_or_album_whose_artwork_it_wants")
    func a_cdj_3000_names_the_track_or_album_whose_artwork_it_wants() {
        let lib = catalogLibrary()
        for relative in ["", "/PIONEER/Artwork/a/artwork.jpg", "/PIONEER/Artwork/b/artwork.jpg"] {
            lib.artwork_path.push(relative)
        }
        #expect(IndexCatalog.item_row(lib, 12) == 2)
        #expect(IndexCatalog.item_row(lib, 11) == 1)
        #expect(IndexCatalog.item_row(lib, 3) == 2)
        #expect(IndexCatalog.item_row(lib, 2) == 1)
        #expect(IndexCatalog.item_row(lib, 1) == nil)
        #expect(IndexCatalog.item_row(lib, 99) == nil)
    }
    @Test("artwork_is_the_medium_file_beside_the_one_the_library_names")
    func artwork_is_the_medium_file_beside_the_one_the_library_names() {
        #expect(
            medium_artwork("/PIONEER/Artwork/5ba/0a225-f6b2/artwork.jpg")
                == "/PIONEER/Artwork/5ba/0a225-f6b2/artwork_m.jpg")
        #expect(medium_artwork("art.v2.png") == "art.v2_m.png")
        #expect(medium_artwork("/a.b/artwork") == "/a.b/artwork")
    }
    @Test("secondary_numeric_values_are_formatted_like_rekordbox")
    func secondary_numeric_values_are_formatted_like_rekordbox() {
        #expect(format_bpm(11216) == "112.2 bpm")
        #expect(format_bpm(0) == "")
        #expect(camelot_name(5) == "3A")
        #expect(camelot_name(6) == "3B")
        #expect(format_nonzero(320, " kbps") == "320 kbps")
        #expect(format_nonzero(0, " kbps") == "")
    }
    @Test("my_tags_reach_the_server_with_the_ids_a_track_carries")
    func my_tags_reach_the_server_with_the_ids_a_track_carries() {
        let lib = catalogLibrary()
        set_track_my_tags(
            lib, [(0, my_tag_key("108516952")), (0, my_tag_key("3000000000")), (1, my_tag_key("3000000000"))])
        let source = CatalogTestSource(lib)
        source.taggedRows = [
            DJLinkExportModel.MyTagRow(id: "2", seq: 2, name: "Traits", attribute: 1, parent: "root"),
            DJLinkExportModel.MyTagRow(id: "108516952", seq: 1, name: "reese", attribute: 0, parent: "2"),
            DJLinkExportModel.MyTagRow(id: "3000000000", seq: 2, name: "wide", attribute: 0, parent: "2"),
            DJLinkExportModel.MyTagRow(id: "242910998", seq: 3, name: "wubby", attribute: 0, parent: "2"),
        ]
        let c = IndexCatalog(source, Played())
        let tags = c.my_tags()
        #expect(
            tags.map { [$0.id, $0.parent, $0.seq] } == [
                [2, 0, 2], [108516952, 2, 1], [3000000000, 2, 2], [242910998, 2, 3],
            ])
        #expect(c.track_my_tags(10).sorted() == [108516952, 3000000000])
        #expect(c.track_my_tags(12) == [])
        #expect(c.my_tags_in_use() == Set([UInt32(108516952), 3000000000]))
        var filter = DJLinkExportDBServer.TrackFilter()
        filter.enabled = true
        filter.set_my_tag_condition(2, 1, MY_TAG_AND)
        let tickResult0 = filter.tick_my_tag(2, 3000000000, true)
        #expect(tickResult0)
        func all() -> [MenuRow] { c.list(.tracks(scope: .all, sort: .default)) }
        var rows = all()
        c.filter_rows(&rows, filter)
        #expect(catalogIDs(rows) == [11, 10])
        let tickResult1 = filter.tick_my_tag(2, 108516952, true)
        #expect(tickResult1)
        rows = all()
        c.filter_rows(&rows, filter)
        #expect(catalogIDs(rows) == [10])
        filter.set_my_tag_condition(2, 1, MY_TAG_OR)
        rows = all()
        c.filter_rows(&rows, filter)
        #expect(catalogIDs(rows) == [11, 10])
    }
}
