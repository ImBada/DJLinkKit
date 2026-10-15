import DJLinkExportSupport
import DJLinkKit
// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-dbserver/src/session.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

public let DEVICE: UInt8 = 0x11
public typealias UnsupportedCommandReporter = @DJLinkActor (UInt32, UInt16, UInt8) -> Void
@DJLinkActor public final class CatalogHandler: Handler {
    private let catalog: any Catalog
    private var device: AtomicUInt8
    private var unsupported_command_reporter: UnsupportedCommandReporter?
    public init(_ catalog: any Catalog) {
        self.catalog = catalog
        device = AtomicUInt8(DEVICE)
    }
    public static func new(_ catalog: any Catalog) -> CatalogHandler { CatalogHandler(catalog) }
    @discardableResult public func with_device(_ device: AtomicUInt8) -> Self {
        self.device = device
        return self
    }
    @discardableResult public func with_unsupported_command_reporter(_ reporter: @escaping UnsupportedCommandReporter)
        -> Self
    {
        unsupported_command_reporter = reporter
        return self
    }
    public func open() -> any Session {
        LinkSession(catalog).as_device(device.load()).with_unsupported_command_reporter(unsupported_command_reporter)
    }
    public func open_ready() -> (any Session)? {
        let device = device.load()
        guard device != 0 else { return nil }
        return LinkSession(catalog).as_device(device).with_unsupported_command_reporter(unsupported_command_reporter)
    }
    public func serving() -> Bool { device.load() != 0 }
}
private enum Menu {
    case root([Item]), sortOptions([Sort]), selectors([Item]), keys, relatedKeys(UInt32), library(
        query: Query, rows: [Row]), metadata(TrackDetails), trackInfo(TrackDetails), deliveryInfo(TrackDetails), empty
    func len() -> UInt32 {
        switch self {
        case let .root(i), let .selectors(i): return UInt32(exactly: i.count) ?? .max
        case let .sortOptions(s): return UInt32(s.count)
        case .keys: return UInt32(DJLinkExportDBServer.keys.NAMES.count)
        case .relatedKeys: return 3
        case let .library(_, r): return UInt32(exactly: r.count) ?? .max
        case .metadata: return 16
        case .trackInfo: return 7
        case .deliveryInfo: return 13
        case .empty: return 0
        }
    }
}
@DJLinkActor public final class LinkSession: Session {
    private let catalog: any Catalog
    private var menus: [UInt8: Menu] = [:]
    private var player: UInt8 = 0
    private var extended = true
    private var filter = TrackFilter()
    private var device = DEVICE
    private var unsupported_command_reporter: UnsupportedCommandReporter?
    public init(_ catalog: any Catalog) { self.catalog = catalog }
    public static func new(_ catalog: any Catalog) -> LinkSession { LinkSession(catalog) }
    @discardableResult public func as_device(_ device: UInt8) -> Self {
        self.device = device
        return self
    }
    @discardableResult func with_unsupported_command_reporter(_ reporter: UnsupportedCommandReporter?) -> Self {
        unsupported_command_reporter = reporter
        return self
    }
    private func unsupported_command(_ m: Message) -> [Message] {
        unsupported_command_reporter?(m.transaction, m.kind, player)
        return [.new(m.transaction, kind.ERROR, [.number(UInt32(m.kind))])]
    }
    private static func number(_ m: Message, _ i: Int) -> UInt32 {
        guard m.arguments.indices.contains(i), case let .number(n) = m.arguments[i] else { return 0 }
        return n
    }
    private static func text(_ m: Message, _ i: Int) -> String {
        guard m.arguments.indices.contains(i), case let .string(s) = m.arguments[i] else { return "" }
        return s
    }
    private static func menu_location(_ m: Message) -> UInt8 { UInt8(truncatingIfNeeded: number(m, 0) >> 16) }
    private func menu(_ m: Message, _ menu: Menu) -> [Message] {
        let count = menu.len()
        menus[Self.menu_location(m)] = menu
        return [menu_header(m.transaction, UInt32(m.kind), count)]
    }
    private func library(_ m: Message, _ query: Query) -> [Message] {
        var rows = catalog.list(query)
        catalog.filter_rows(&rows, filter)
        return menu(m, .library(query: query, rows: rows))
    }
    private func tracks(_ m: Message, _ scope: TrackScope) -> [Message] {
        library(m, .tracks(scope: scope, sort: Sort.from_id(Self.number(m, 1))))
    }
    private func items(
        _ location: UInt8, _ offset: UInt32, _ limit: UInt32, _ column: TrackColumn?, _ use_sort_column: Bool
    ) -> [Item] {
        func window(_ all: [Item]) -> [Item] { Array(all.dropFirst(Int(offset)).prefix(Int(limit))) }
        switch menus[location] ?? .empty {
        case let .root(i), let .selectors(i): return window(i)
        case let .sortOptions(s): return window(sort_menu(s))
        case .keys: return window(catalog.key_ids().map { .named($0, catalog.key_name($0), item_type.KEY) })
        case let .relatedKeys(key):
            return window(
                (UInt32(0)..<3).map { distance in
                    Item(
                        a: distance, id: key,
                        text: keys.related(key, distance).map { catalog.key_name($0) }.joined(separator: ", "),
                        item_type: item_type.KEY)
                })
        case let .library(query, rows):
            return rows.dropFirst(Int(offset)).prefix(Int(limit)).compactMap {
                item(query, $0, column, use_sort_column)
            }
        case let .metadata(t):
            return window(metadata_rows(t, catalog.played(t.row.id), catalog.tagged(t.row.id), !extended))
        case let .trackInfo(t): return window(track_info_rows(t))
        case let .deliveryInfo(t): return window(delivery_rows(t))
        case .empty: return []
        }
    }
    private func render(_ m: Message) -> [Message] {
        let location = Self.menu_location(m)
        let total = menus[location]?.len() ?? 0
        guard let (offset, limit) = render_window(total, Self.number(m, 1), Self.number(m, 2)) else { return [] }
        let column: TrackColumn? = Self.number(m, 6) != 0 && Self.number(m, 7) != 0 ? .from_id(Self.number(m, 7)) : nil
        var out: [Message] = [.new(m.transaction, kind.RENDER_HEADER, [.number(1), .number(offset)])]
        out += items(location, offset, limit, column, m.arguments.count == 6).map { item in
            var row = item
            if !extended && row.item_type == item_type.TRACK {
                row.item_type = item_type.TITLE
                row.text2 = ""
            }
            var reply = row.message(m.transaction)
            if !extended { reply.arguments = Array(reply.arguments.prefix(12)) }
            return reply
        }
        out.append(menu_footer(m.transaction))
        return out
    }
    private func item(_ query: Query, _ row: Row, _ column: TrackColumn?, _ use_sort_column: Bool) -> Item? {
        switch row {
        case let .date(value):
            switch query {
            case .bpmBuckets: return .number(value, item_type.TEMPO)
            case .ratings: return .number(value, item_type.RATING)
            case .bitrates: return .number(value, item_type.BIT_RATE)
            case .durationMinutes: return .number(value, item_type.DURATION)
            case .releaseDecades, .releaseYears: return value == .max ? .all() : .number(value, item_type.YEAR)
            default: return value == .max ? .all() : .date_part(value)
            }
        case let .named(id, name):
            if query == .colors { return .named(id, name, item_type.COLOR_PINK + min(id == 0 ? 0 : id - 1, 7)) }
            if id == .max { return .all() }
            switch query {
            case .artists, .genreArtists, .labelArtists: return .named(id, name, item_type.ARTIST)
            case .albums, .artistAlbums, .genreArtistAlbums, .labelArtistAlbums:
                return .named_twice(id, name, item_type.ALBUM)
            case .histories: return .named(id, name, item_type.HISTORY)
            case .labels: return .named(id, name, item_type.LABEL)
            default: return .named(id, name, item_type.GENRE)
            }
        case let .list(id, name, folder, position): return .list(id, name, folder, position)
        case let .track(id, position):
            guard case let .tracks(scope, sort) = query else { return nil }
            let column = column ?? (use_sort_column ? sort.track_column() : nil)
            var track: TrackRow?
            if scope == .fileName {
                track = catalog.file_name_row(id, column)
            } else {
                track = catalog.track_row(id, column)
            }
            guard var track else { return nil }
            if use_sort_column { track.format_sort_column() }
            let listed = catalog.listed(scope) ? track_flags.LISTED : 0
            let history: Bool
            if case .history = scope { history = true } else { history = false }
            let played = history || catalog.played(id)
            return .track(track, listed | (played ? track_flags.PLAYED : 0) | (catalog.tagged(id) ? 1 : 0), position)
        }
    }
    private static func blob(_ m: Message, _ reply: UInt16, _ blob: [UInt8]?, _ tail: UInt32?) -> [Message] {
        var arguments: [Argument] = [.number(UInt32(m.kind))]
        if let b = blob, !b.isEmpty {
            arguments += [.number(0), .number(UInt32(exactly: b.count) ?? .max), .blob(b)]
        } else {
            arguments += [.number(0x32), .number(0), .blob([])]
        }
        if let tail { arguments.append(.number(tail)) }
        return [.new(m.transaction, reply, arguments)]
    }
    private func analysis(_ m: Message, _ track: UInt32, _ what: Analysis, _ reply: UInt16, _ tail: UInt32?)
        -> [Message]
    { Self.blob(m, reply, catalog.analysis(track, what), tail) }
    private func extended_cue_list(_ m: Message, _ track: UInt32) -> [Message] {
        let b = catalog.analysis(track, .extendedCueList)
        if let b, b.isEmpty {
            return [
                .new(
                    m.transaction, kind.EXTENDED_CUES_REPLY,
                    [.number(UInt32(m.kind)), .number(1), .number(0), .blob([]), .number(0)])
            ]
        }
        return Self.blob(m, kind.EXTENDED_CUES_REPLY, b, b.map { extended_cue_count($0) } ?? 0)
    }
    private func save_extended_cue(_ m: Message) -> [Message] {
        func refuse() -> [Message] { Self.blob(m, kind.EXTENDED_CUES_REPLY, nil, 0) }
        guard m.arguments.count >= 5, case .number = m.arguments[0], case let .number(track) = m.arguments[1],
            case let .number(op) = m.arguments[2], case let .number(length) = m.arguments[3],
            case let .blob(bytes) = m.arguments[4]
        else { return refuse() }
        let record = Array(bytes.prefix(Int(length)))
        guard record.count >= 0x38 else { return refuse() }
        guard let cue = parse_extended_cue(record) else { return extended_cue_list(m, track) }
        return catalog.edit(op != 0 ? .saveCue(track: track, cue: cue) : .deleteCue(track: track, cue: cue))
            ? extended_cue_list(m, track) : refuse()
    }
    private func save_cue(_ m: Message) -> [Message] {
        guard m.arguments.count >= 5, case .number = m.arguments[0], case let .number(track) = m.arguments[1],
            case let .number(op) = m.arguments[2], case let .number(length) = m.arguments[3],
            case let .blob(record) = m.arguments[4], length >= 0x24, record.count >= 0x24
        else { return Self.hot_cue_bank_unavailable(m) }
        var sidecar: [UInt8] = []
        if m.arguments.count >= 7, case let .number(length) = m.arguments[5], case let .blob(bytes) = m.arguments[6] {
            sidecar = Array(bytes.prefix(min(Int(length), 8)))
        }
        guard let cue = parse_legacy_cue(record, sidecar),
            catalog.edit(op != 0 ? .saveCue(track: track, cue: cue) : .deleteCue(track: track, cue: cue))
        else { return Self.hot_cue_bank_unavailable(m) }
        return Self.usb_cue_reply(m, catalog.usb_cues(track))
    }
    private static func analysis_write_refusal(_ m: Message) -> [Message]? {
        func ext(_ value: UInt32, _ expected: String) -> Bool {
            let b = dbLE(value)
            return b[3] == 0 && b.prefix(3).map { (97...122).contains($0) ? $0 - 32 : $0 } == Array(expected.utf8)
        }
        let a = m.arguments
        if m.kind == 0x2805, a.count >= 7, case .number = a[0], case .number = a[1], case let .number(atom) = a[2],
            case let .number(extension_) = a[3], case let .number(reserved) = a[4], case let .number(length) = a[5],
            case .blob = a[6]
        {
            let invalid =
                !(ext(extension_, "DAT") || ext(extension_, "EXT"))
                || ![UInt32(0x3242_5650), 0x3254_5150, 0x5a54_5150].contains(atom) || reserved != 0
                || (1..<12).contains(length)
            return invalid ? [menu_header(m.transaction, UInt32(m.kind), 0x32)] : nil
        }
        if m.kind == 0x2905, a.count >= 8, case .number = a[0], case .number = a[1], case let .number(atom) = a[2],
            case let .number(extension_) = a[3], case let .number(reserved) = a[4], case let .number(length) = a[5],
            case .number = a[6], case .blob = a[7]
        {
            return !ext(extension_, "EXT") || atom != 0x3254_5150 || reserved != 0 || length < 12
                ? [menu_header(m.transaction, UInt32(m.kind), 0x32)] : nil
        }
        return nil
    }
    private static func hot_cue_bank_unavailable(_ m: Message) -> [Message] {
        [
            .new(
                m.transaction, kind.HOT_CUE_BANK_REPLY,
                [
                    .number(UInt32(m.kind)), .number(0x32), .number(0), .blob([]), .number(0x24), .number(0),
                    .number(0), .number(0), .blob([]), .number(0), .blob([]),
                ])
        ]
    }
    private static func hot_cue_bank_reply(_ m: Message, _ cues: [HotCueBankCue]) -> [Message] {
        var records: [UInt8] = []
        var sidecars: [UInt8] = []
        var count: UInt32 = 0
        for cue in cues.filter({ (1...3).contains($0.slot) }).prefix(3) {
            let flags: UInt32 = 0x100 | (cue.out_ms != nil ? 1 : 0) | (UInt32(cue.slot) + 3) << 16
            let in_frame = saturating_mul(cue.in_ms, 3) / 20
            let out_frame = cue.out_ms.map { saturating_mul($0, 3) / 20 } ?? .max
            for word in [
                flags, cue.content, 0, in_frame, out_frame, cue.color, cue.color_table_index, cue.active_loop ? 1 : 0,
                cue.beat_loop_size,
            ] { records += dbLE(word) }
            sidecars += dbLE(cue.in_ms) + dbLE(cue.out_ms ?? .max)
            count += 1
        }
        return [
            .new(
                m.transaction, kind.HOT_CUE_BANK_REPLY,
                [
                    .number(UInt32(m.kind)), .number(0), .number(UInt32(records.count)), .blob(records), .number(0x24),
                    .number(count), .number(0), .number(UInt32(sidecars.count)), .blob(sidecars), .number(0), .blob([]),
                ])
        ]
    }
    private static func usb_cue_reply(_ m: Message, _ cues: [UsbCue]) -> [Message] {
        var records: [UInt8] = []
        var sidecars: [UInt8] = []
        var hot: UInt32 = 0
        var memory: UInt32 = 0
        for cue in cues {
            let flags: UInt32 = 0x100 | (cue.out_ms != nil ? 1 : 0) | UInt32(cue.slot) << 16
            let in_frame = saturating_mul(cue.in_ms, 3) / 20
            let out_ms = cue.out_ms ?? .max
            let out_frame = saturating_mul(out_ms, 3) / 20
            for word in [flags, 0, 0, in_frame, out_frame, 0, cue.color_table_index, 0, 0] { records += dbLE(word) }
            sidecars += dbLE(cue.in_ms) + dbLE(out_ms)
            if cue.slot == 0 { memory += 1 } else { hot += 1 }
        }
        return [
            .new(
                m.transaction, kind.HOT_CUE_BANK_REPLY,
                [
                    .number(UInt32(m.kind)), .number(0), .number(UInt32(records.count)), .blob(records), .number(0x24),
                    .number(hot), .number(memory), .number(UInt32(sidecars.count)), .blob(sidecars), .number(0),
                    .blob([]),
                ])
        ]
    }
    private static func hot_cue_bank_edit(_ m: Message) -> (UInt32, HotCueBankCue)? {
        guard m.arguments.count > 3, case let .blob(bytes) = m.arguments[3], number(m, 2) == 0x24, bytes.count == 0x24
        else { return nil }
        let flags = le32(bytes, 0)
        let raw = UInt8(truncatingIfNeeded: flags >> 16)
        guard raw >= 4, raw <= 6 else { return nil }
        let slot = raw - 3
        var timecode = [UInt8](repeating: 0, count: 8)
        let length = Int(number(m, 4))
        var sidecar: [UInt8]? = length == 0 ? timecode : nil
        if length > 0, length <= 8, m.arguments.count > 5, case let .blob(b) = m.arguments[5], b.count >= length {
            timecode.replaceSubrange(0..<length, with: b.prefix(length))
            sidecar = timecode
        }
        let in_ms = sidecar.map { le32($0, 0) } ?? (saturating_mul(le32(bytes, 12), 20) / 3)
        let out_ms: UInt32? =
            flags & 1 != 0 ? (sidecar.map { le32($0, 4) } ?? (saturating_mul(le32(bytes, 16), 20) / 3)) : nil
        return (
            number(m, 1),
            HotCueBankCue(
                slot: slot, content: le32(bytes, 4), in_ms: in_ms, out_ms: out_ms, color: le32(bytes, 20),
                color_table_index: le32(bytes, 24), active_loop: le32(bytes, 28) != 0, beat_loop_size: le32(bytes, 32),
                cue_microsec: 0)
        )
    }
    private func hot_cue_bank_menu(_ m: Message) -> [Message] {
        guard Self.number(m, 0) & 0xff == 1 else { return Self.hot_cue_bank_unavailable(m) }
        let bank = Self.number(m, 1)
        let mode = Self.number(m, 2)
        let items: [Item]
        if mode == 0 {
            items = catalog.hot_cue_bank_tracks(bank).enumerated().map {
                .track($0.element, 0, UInt32(exactly: $0.offset) ?? .max)
            }
        } else if mode == 1 {
            items = catalog.hot_cue_banks(bank != 0 ? bank : nil).map {
                .named($0.id, $0.name, $0.folder ? item_type.FOLDER : item_type.HOT_CUE_BANK)
            }
        } else {
            items = []
        }
        return menu(m, .selectors(items))
    }
    private func my_tag_menu(_ m: Message) -> [Message] {
        let parent = Self.number(m, 2)
        let selected_only = Self.number(m, 3) != 0
        var rows = catalog.my_tags().filter { $0.parent == parent }
        if parent != 0 {
            let in_use = catalog.my_tags_in_use()
            rows.removeAll { !in_use.contains($0.id) }
        }
        rows.sort { ($0.seq, $0.id) < ($1.seq, $1.id) }
        let ticked = filter.my_tag_condition(parent).tags
        let items: [Item] = rows.enumerated().compactMap { position, tag in
            let c = filter.my_tag_condition(tag.id)
            let on = parent == 0 ? c.enabled() : ticked.contains(tag.id)
            let mode = parent == 0 ? UInt32(c.mode) : 0
            if selected_only && !on { return nil }
            return Item(
                id: tag.id, text: tag.name, item_type: on ? item_type.MY_TAG_TICKED : item_type.MY_TAG, c: mode,
                d: (UInt32(exactly: position) ?? .max) & 0xffff)
        }
        return menu(m, .selectors(items))
    }
    private func my_tags_on_track(_ m: Message) -> [Message] {
        let on_track = catalog.track_my_tags(Self.number(m, 2))
        var items: [Item] = []
        if !on_track.isEmpty {
            let all = catalog.my_tags().sorted { ($0.seq, $0.id) < ($1.seq, $1.id) }
            for category in all.filter({ $0.parent == 0 }) {
                let tags = all.filter { $0.parent == category.id && on_track.contains($0.id) }
                if tags.isEmpty { continue }
                items.append(
                    Item(a: category.id, id: category.id, text: category.name, item_type: item_type.MY_TAG_HEADING))
                items += tags.map { Item(a: category.id, id: $0.id, text: $0.name, item_type: item_type.MY_TAG) }
            }
        }
        return menu(m, .selectors(items))
    }
    private func my_tag_category_exists(_ category: UInt32) -> Bool {
        category != 0 && catalog.my_tags().contains { $0.parent == 0 && $0.id == category }
    }
    private func set_my_tag_filter(_ m: Message) -> [Message] {
        let category = Self.number(m, 2)
        let mode = Self.number(m, 4)
        let valid =
            Self.number(m, 1) == 0 && mode & ~UInt32(1) == UInt32(MY_TAG_AND) && my_tag_category_exists(category)
        if valid {
            filter.set_my_tag_condition(
                category, UInt8(truncatingIfNeeded: Self.number(m, 3)), UInt8(truncatingIfNeeded: mode))
        }
        return [menu_header(m.transaction, UInt32(m.kind), valid ? 0 : 0x32)]
    }
    private func tick_my_tag_filter(_ m: Message) -> [Message] {
        let category = Self.number(m, 2)
        let tag = Self.number(m, 3)
        let on = Self.number(m, 4) != 0
        var valid = Self.number(m, 1) == 0 && !(tag == .max && on) && my_tag_category_exists(category)
        if valid {
            if tag == .max { filter.clear_my_tags(category) } else { valid = filter.tick_my_tag(category, tag, on) }
        }
        return [menu_header(m.transaction, UInt32(m.kind), valid ? 0 : 0x32)]
    }
    private func track_menu(_ m: Message, _ make: (TrackDetails) -> Menu) -> [Message] {
        menu(m, catalog.track(Self.number(m, 1)).map(make) ?? .empty)
    }
    private func with_all(_ m: Message, _ query: Query) -> [Message] {
        var rows = catalog.list(query)
        prepend_all_if_multiple(&rows)
        return menu(m, .library(query: query, rows: rows))
    }
    private func handle_menu(_ m: Message) -> [Message] {
        let n: (Int) -> UInt32 = { Self.number(m, $0) }
        let sort = Sort.from_id(Self.number(m, 1))
        func optional(_ v: UInt32) -> UInt32? { v == .max ? nil : v }
        switch m.kind {
        case kind.ROOT_MENU: return menu(m, .root(root_menu(catalog.root_categories(), n(2))))
        case kind.GENRE_MENU: return library(m, .genres(sort))
        case kind.GENRE_ARTISTS: return with_all(m, .genreArtists(n(2)))
        case kind.GENRE_ARTIST_ALBUMS: return with_all(m, .genreArtistAlbums(genre: n(2), artist: optional(n(3))))
        case kind.GENRE_ARTIST_ALBUM_TRACKS:
            return tracks(m, .genre(genre: n(2), artist: optional(n(3)), album: optional(n(4))))
        case kind.LABEL_MENU: return library(m, .labels(sort))
        case kind.LABEL_ARTISTS: return with_all(m, .labelArtists(n(2)))
        case kind.LABEL_ARTIST_ALBUMS: return with_all(m, .labelArtistAlbums(label: n(2), artist: optional(n(3))))
        case kind.LABEL_ARTIST_ALBUM_TRACKS:
            return tracks(m, .label(label: n(2), artist: optional(n(3)), album: optional(n(4))))
        case kind.ORIGINAL_ARTIST_MENU: return library(m, .artistRoleArtists(.original))
        case kind.ORIGINAL_ARTIST_ALBUMS: return with_all(m, .artistRoleAlbums(role: .original, artist: n(2)))
        case kind.ORIGINAL_ARTIST_ALBUM_TRACKS:
            return tracks(m, .artistRole(role: .original, artist: n(2), album: optional(n(3))))
        case kind.REMIXER_MENU: return library(m, .artistRoleArtists(.remixer))
        case kind.REMIXER_ALBUMS: return with_all(m, .artistRoleAlbums(role: .remixer, artist: n(2)))
        case kind.REMIXER_ALBUM_TRACKS:
            return tracks(m, .artistRole(role: .remixer, artist: n(2), album: optional(n(3))))
        case kind.SORT_MENU: return menu(m, .sortOptions(catalog.sorts()))
        case kind.KEY_MENU, kind.LEGACY_KEY_MENU: return menu(m, .keys)
        case kind.RELATED_KEYS: return menu(m, .relatedKeys(n(2)))
        case kind.ARTIST_MENU: return library(m, .artists(sort))
        case kind.ALBUM_MENU: return library(m, .albums(sort))
        case kind.ARTIST_ALBUMS: return with_all(m, .artistAlbums(n(2)))
        case kind.ARTIST_ALBUM_TRACKS: return tracks(m, .artist(artist: n(2), album: optional(n(3))))
        case kind.ALBUM_TRACKS: return tracks(m, .album(n(2)))
        case kind.TRACK_MENU, kind.CONTENT_TRACKS: return tracks(m, .all)
        case kind.FILE_NAME_MENU: return tracks(m, .fileName)
        case kind.MATCHING_TRACKS: return tracks(m, .matching(n(2)))
        case kind.BPM_MENU: return library(m, .bpmBuckets)
        case kind.BPM_RANGES: return menu(m, .selectors((UInt32(0)...6).map { .number($0, item_type.TEMPO) }))
        case kind.BPM_TRACKS: return tracks(m, .bpm(bpm_x100: n(2), tolerance_pct: min(n(3), 6)))
        case kind.RATING_MENU: return library(m, .ratings)
        case kind.RATING_TRACKS: return tracks(m, .rating(n(2)))
        case kind.BITRATE_MENU: return library(m, .bitrates)
        case kind.BITRATE_TRACKS: return tracks(m, .bitrate(n(2)))
        case kind.COLOR_MENU: return library(m, .colors)
        case kind.COLOR_TRACKS: return tracks(m, .color(n(2)))
        case kind.TIME_MENU: return library(m, .durationMinutes)
        case kind.TIME_TRACKS: return tracks(m, .durationMinute(n(2)))
        case kind.RELEASE_DECADES: return library(m, .releaseDecades)
        case kind.RELEASE_YEARS:
            let query = Query.releaseYears(n(2))
            var rows = catalog.list(query)
            if rows.count > 1 { rows.insert(.date(.max), at: 0) }
            return menu(m, .library(query: query, rows: rows))
        case kind.RELEASE_YEAR_TRACKS: return tracks(m, .releaseYear(decade: n(2), year: optional(n(3))))
        case kind.TAG_LIST: return tracks(m, .tagList)
        case kind.MY_TAG: return my_tag_menu(m)
        case kind.MY_TAG_ON_TRACK: return my_tags_on_track(m)
        case kind.KEY_TRACKS: return tracks(m, .key(key: n(2), distance: min(n(3), 2)))
        case kind.LEGACY_KEY_TRACKS: return tracks(m, .key(key: n(2), distance: 0))
        case kind.PLAYLIST_MENU: return n(3) == 1 ? library(m, .folder(n(2))) : tracks(m, .playlist(n(2)))
        case kind.HISTORY_MENU: return library(m, .histories)
        case kind.HISTORY_TRACKS: return tracks(m, .history(n(2)))
        case kind.YEARS: return library(m, .years)
        case kind.MONTHS:
            let query = Query.months(n(2))
            return menu(m, .library(query: query, rows: [.date(.max)] + catalog.list(query)))
        case kind.DAYS:
            let query = Query.days(year: n(2), month: n(3))
            return menu(m, .library(query: query, rows: [.date(.max)] + (n(3) == .max ? [] : catalog.list(query))))
        case kind.DATE_TRACKS: return tracks(m, .dateAdded(year: n(2), month: optional(n(3)), day: optional(n(4))))
        case kind.SEARCH, kind.SEARCH_TRACK: return tracks(m, .search(Self.text(m, 3)))
        case kind.METADATA: return track_menu(m, Menu.metadata)
        case kind.TRACK_INFO: return track_menu(m, Menu.trackInfo)
        case kind.DELIVERY_INFO: return track_menu(m, Menu.deliveryInfo)
        default: return unsupported_command(m)
        }
    }
    private func handle_blob(_ m: Message) -> [Message] {
        let track = Self.number(m, 1)
        switch m.kind {
        case kind.USER_INFO: return Self.blob(m, kind.USER_INFO_REPLY, [UInt8](repeating: 0, count: 160), nil)
        case kind.ARTWORK, kind.CONTENT_ARTWORK:
            return Self.blob(
                m, kind.ARTWORK_REPLY,
                m.kind == kind.CONTENT_ARTWORK || m.arguments.count > 2
                    ? catalog.item_artwork(track) : catalog.artwork(track), nil)
        case kind.WAVEFORM_PREVIEW:
            return analysis(m, Self.number(m, 2), .waveformPreview, kind.WAVEFORM_PREVIEW_REPLY, nil)
        case kind.BEAT_GRID:
            return analysis(
                m, track, .beatGrid, kind.BEAT_GRID_REPLY, UInt32(UInt16(bitPattern: catalog.grid_offset(track))))
        case kind.VBR: return analysis(m, track, .vbr, kind.VBR_REPLY, nil)
        case kind.WAVEFORM_DETAIL: return analysis(m, track, .waveformDetail, kind.WAVEFORM_DETAIL_REPLY, nil)
        case kind.EXTENDED_CUES: return extended_cue_list(m, track)
        case kind.ANLZ_TAG, kind.ANLZ_TAG_2EX:
            return analysis(
                m, track, .tag(fourcc: dbLE(Self.number(m, 2)), extension_: Array(dbLE(Self.number(m, 3)).prefix(3))),
                kind.ANLZ_TAG_REPLY, 1)
        default: return []
        }
    }
    public func handle(_ m: Message) -> [Message] {
        let tx = m.transaction
        let n: (Int) -> UInt32 = { Self.number(m, $0) }
        func header(_ value: UInt32) -> [Message] { [menu_header(tx, UInt32(m.kind), value)] }
        switch m.kind {
        case kind.SETUP:
            player = UInt8(exactly: n(0)) ?? 0
            extended = m.arguments.count > 1
            return extended ? [setup_reply(tx, device)] : [menu_header(tx, 0, UInt32(device))]
        case kind.SAVE_EXTENDED_CUE: return save_extended_cue(m)
        case kind.SAVE_CUE: return save_cue(m)
        case kind.TEARDOWN, kind.SET_ON_AIR, 0x3203, 0x3503, kind.SAVE_WAVEFORM, kind.SAVE_VBR: return []
        case 0x2805, 0x2905: return Self.analysis_write_refusal(m) ?? handle_menu(m)
        case 0x3402, 0x3903: return header(0)
        case 0x3c03:
            guard m.arguments.count >= 2, case .number = m.arguments[0], case let .number(value) = m.arguments[1] else {
                return unsupported_command(m)
            }
            return header(value & 0xfe == 0 ? 1 : 0)
        case kind.BROWSE_TYPE: return header(1)
        case kind.TRACK_BPM: return header(catalog.track_row(n(1), nil)?.bpm_x100 ?? 0)
        case kind.TRACK_PLAY_STATE:
            var played = false
            if m.arguments.count >= 2, case let .number(context) = m.arguments[0],
                case let .number(track) = m.arguments[1], (context >> 8) & 0xff == 4
            {
                played = catalog.played(track)
            }
            return header(played ? 2 : 0)
        case kind.LEGACY_KEY_TO_NEW_KEY: return header((1...24).contains(n(1)) ? n(1) : 0)
        case kind.CONTENT_NEW_KEY: return header(catalog.track_row(n(1), nil)?.key ?? 0)
        case kind.REKORDBOX_MOBILE:
            return [.new(tx, kind.REKORDBOX_MOBILE_REPLY, [.number(0), .number(2), .string("")])]
        case kind.HOT_CUE_BANK: return hot_cue_bank_menu(m)
        case kind.HOT_CUE_BANK_CUES:
            guard n(0) & 0xff == 1 else { return Self.hot_cue_bank_unavailable(m) }
            return Self.hot_cue_bank_reply(m, catalog.hot_cue_bank_cues(n(1)))
        case kind.CHANGE_HOT_CUE_BANK:
            guard n(0) & 0xff == 1, let (bank, cue) = Self.hot_cue_bank_edit(m),
                catalog.edit(.hotCueBankCue(bank: bank, cue: cue))
            else { return Self.hot_cue_bank_unavailable(m) }
            return Self.usb_cue_reply(m, catalog.usb_cues(cue.content))
        case kind.GRID_OFFSET: return header(UInt32(UInt16(bitPattern: catalog.grid_offset(n(1)))))
        case kind.SAVE_GRID_OFFSET:
            return header(
                catalog.edit(.gridOffset(track: n(1), offset_ms: Int16(bitPattern: UInt16(truncatingIfNeeded: n(2)))))
                    ? 0 : 1)
        case kind.FILTER_SWITCH:
            filter.enabled = n(1) != 0
            return header(0)
        case kind.FILTER_GET: return Self.blob(m, kind.FILTER_REPLY, filter.encode(), 4)
        case kind.FILTER_SET:
            var valid = false
            if m.arguments.count >= 5, case .number = m.arguments[0], case let .number(property) = m.arguments[1],
                m.arguments[2] == .number(0), case let .number(length) = m.arguments[3],
                case let .blob(bytes) = m.arguments[4], length > 3, bytes.count == Int(length)
            {
                valid = filter.update(property, bytes)
            }
            return header(valid ? 0 : 0x32)
        case kind.FILTER_MY_TAG: return set_my_tag_filter(m)
        case kind.FILTER_MY_TAG_ITEM: return tick_my_tag_filter(m)
        case kind.CHANGE_TAG, kind.CLEAR_TAGS, kind.CHANGE_RATING:
            let track = n(1)
            let value = n(2)
            let edit: Edit?
            if m.kind == kind.CHANGE_TAG, value <= 1 {
                edit = .tag(track: track, add: value == 1)
            } else if m.kind == kind.CLEAR_TAGS {
                edit = .clearTags
            } else if m.kind == kind.CHANGE_RATING, value <= 5 {
                edit = .rating(track: track, stars: UInt8(value))
            } else {
                edit = nil
            }
            return header(edit.map { catalog.edit($0) } == true ? 0 : 1)
        case kind.INSERT_HISTORY, kind.DELETE_HISTORY, kind.DELETE_HISTORY_TRACK:
            let own = n(0) & 0xff == 1
            let target = n(1)
            if m.kind == kind.INSERT_HISTORY {
                if own { _ = catalog.edit(.historyAdd(track: target)) }
                return []
            }
            if m.kind == kind.DELETE_HISTORY {
                if own { _ = catalog.edit(.historyDelete(history: target)) }
                return []
            }
            guard own else { return [] }
            return header(catalog.edit(.historyRemove(track: target)) ? 0 : .max)
        case kind.RENDER: return render(m)
        case kind.ITEM_POSITION:
            let id = n(1)
            let location = Self.menu_location(m)
            let position: Int?
            if case let .library(_, rows)? = menus[location] {
                position = rows.firstIndex { row in
                    switch row {
                    case let .named(v, _), let .list(v, _, _, _), let .track(v, _), let .date(v): return v == id
                    }
                }
            } else {
                position = items(location, 0, .max, nil, false).firstIndex { $0.id == id }
            }
            return header(position.flatMap { UInt32(exactly: $0) } ?? .max)
        case kind.ARTWORK, kind.CONTENT_ARTWORK, kind.WAVEFORM_PREVIEW, kind.BEAT_GRID, kind.VBR, kind.WAVEFORM_DETAIL,
            kind.EXTENDED_CUES, kind.ANLZ_TAG, kind.ANLZ_TAG_2EX, kind.USER_INFO:
            return handle_blob(m)
        default: return handle_menu(m)
        }
    }
}
func render_window(_ total: UInt32, _ offset: UInt32, _ count: UInt32) -> (UInt32, UInt32)? {
    if offset == .max { return nil }
    if total == 0 { return (0, 0) }
    let count = min(max(count, 1), total)
    let offset = offset >= total ? total - 1 : saturating_add(offset, count) > total ? total - count : offset
    return (offset, count)
}
func prepend_all_if_multiple(_ rows: inout [Row]) {
    if rows.count > 1 { rows.insert(.named(id: .max, name: ""), at: 0) }
}
func extended_cue_count(_ blob: [UInt8]) -> UInt32 {
    var offset = 0
    var count: UInt32 = 0
    while offset + 4 <= blob.count {
        let n = Int(le32(blob, offset))
        if n < 4 { break }
        offset += n
        count += 1
    }
    return count
}
func frames_to_ms(_ frames: UInt32) -> UInt32 {
    let v = (Double(frames) * Double(bitPattern: 0x401a_aaaa_aaaa_aaab)).rounded(.up)
    return v >= Double(UInt32.max) ? .max : UInt32(v)
}
func hot_kind(_ slot: UInt16) -> UInt8 { UInt8(exactly: slot + (slot > 3 ? 1 : 0)) ?? 0 }
func parse_extended_cue(_ record: [UInt8]) -> PlayerCue? {
    let slot = le16(record, 4)
    let shape = record.count > 6 ? record[6] : 0
    let timebase = le16(record, 0xa)
    guard slot <= 8, [UInt8(1), 2].contains(shape), [UInt16(75), 150, 1000].contains(timebase) else { return nil }
    let looped = shape == 2
    let in_ms: UInt32
    let out_ms: UInt32?
    if timebase == 1000 {
        in_ms = le32(record, 0xc)
        out_ms = looped ? le32(record, 0x10) : nil
    } else {
        let scale: UInt32 = timebase == 75 ? 2 : 1
        in_ms = frames_to_ms(le32(record, 0xc) &* scale)
        out_ms = looped ? frames_to_ms((le32(record, 0x10) &* scale) &+ 1) : nil
    }
    let kind = slot != 0 ? hot_kind(slot) : looped ? UInt8(le16(record, 0x18) & 4) : 0
    let default_ = looped ? HOT_LOOP_DEFAULT : HOT_CUE_DEFAULT
    var cue = PlayerCue(
        kind: kind, in_ms: in_ms, out_ms: out_ms, colour: nil, hot_colour: .index(default_), comment: "", beat_loop: nil
    )
    let options = Int(le32(record, 0x34))
    if options == 0 || record.count < options + 0x38 { return cue }
    if record.count > 0x3a, record[0x3a] >= 1, record[0x3a] <= 8 { cue.colour = record[0x3a] - 1 }
    let numerator = le16(record, 0x42)
    let denominator = le16(record, 0x44)
    if numerator != 0 && denominator != 0 { cue.beat_loop = BeatLoop(numerator, denominator) }
    let comment_len = Int(le16(record, 0x48))
    if comment_len != 0, record.count >= 0x4a + comment_len {
        var units: [UInt16] = []
        for i in 0..<max(max(comment_len / 2, 1) - 1, 0) {
            let u = le16(record, 0x4a + i * 2)
            if u == 0 { break }
            units.append(u)
        }
        cue.comment = String(decoding: units, as: UTF16.self)
    }
    if slot != 0 {
        let tail = 0x4a + comment_len
        var code: UInt8 = 0
        var rgb: [UInt8] = [0, 0, 0]
        if record.count >= tail + 8 {
            let wanted = min(Int(le32(record, tail)), 0x2c)
            func byte(_ i: Int) -> UInt8 { i < wanted && tail + 4 + i < record.count ? record[tail + 4 + i] : 0 }
            code = byte(0)
            rgb = [byte(1), byte(2), byte(3)]
        }
        cue.hot_colour = code != 0 ? .index(min(code, 64)) : rgb == [0, 0, 0] ? .index(default_) : .rgb(rgb)
    }
    return cue
}
func parse_legacy_cue(_ record: [UInt8], _ sidecar: [UInt8]) -> PlayerCue? {
    let flags = le32(record, 0)
    guard flags < 0x4_0000 else { return nil }
    let looped = flags & 1 != 0
    let active = looped && flags & 0x200 != 0
    let slot = UInt16(exactly: flags >> 16) ?? 0
    let kind: UInt8 = active ? 4 : UInt8(exactly: slot) ?? 0
    var side = [UInt8](repeating: 0, count: 8)
    side.replaceSubrange(0..<min(sidecar.count, 8), with: sidecar.prefix(8))
    let in_ms: UInt32
    let out_ms: UInt32
    if le32(side, 0) != 0 {
        in_ms = le32(side, 0)
        out_ms = le32(side, 4)
    } else {
        in_ms = frames_to_ms(le32(record, 0xc))
        out_ms = frames_to_ms(le32(record, 0x10) &+ 1)
    }
    return PlayerCue(
        kind: kind, in_ms: in_ms, out_ms: looped ? out_ms : nil, colour: nil,
        hot_colour: .index(looped ? HOT_LOOP_DEFAULT : HOT_CUE_DEFAULT), comment: "", beat_loop: nil)
}
func metadata_rows(_ t: TrackDetails, _ played: Bool, _ tagged: Bool, _ legacy: Bool) -> [Item] {
    let title = Item.track(t.row, (played ? track_flags.PLAYED : 0) | (tagged ? 1 : 0), 0)
    let artist = Item.line(1, t.artist_id, t.artist, item_type.ARTIST)
    let album = Item.line(1, t.album_id, t.album, item_type.ALBUM)
    let duration = Item.line(0, t.duration_s, "", item_type.DURATION)
    let tempo = Item.line(0, t.row.bpm_x100, "", item_type.TEMPO)
    let key = Item.line(1, t.key_id, t.key_name, item_type.KEY)
    let rating = Item.line(0, t.rating, "", item_type.RATING)
    let colour = Item.line(0, t.colour, "", item_type.COLOUR)
    let genre = Item.line(0, t.genre_id, t.genre, item_type.GENRE)
    let date_added = Item.line(1, t.row.id, t.date_added, item_type.DATE_ADDED)
    let comment = Item.line(0, t.row.id, t.comment, item_type.COMMENT)
    let year = Item.line(0, t.year, "", item_type.YEAR)
    let bitrate = Item.line(0, t.bit_rate_kbps, "", item_type.BIT_RATE)
    let label = Item.line(0, t.label_id, t.label, item_type.LABEL)
    let original_artist = Item.line(0, 0, t.original_artist, item_type.ORIGINAL_ARTIST)
    let remixer = Item.line(0, 0, t.remixer, item_type.REMIXER)
    return legacy
        ? [
            title, artist, album, duration, tempo, comment, key, rating, colour, genre, date_added, bitrate, year,
            label, original_artist, remixer,
        ]
        : [
            title, artist, album, duration, tempo, key, rating, colour, genre, date_added, comment, year, bitrate,
            label, original_artist, remixer,
        ]
}
func delivery_rows(_ t: TrackDetails) -> [Item] {
    [
        .line(0, 0, "", item_type.DELIVERY_TEXT_36), .line(0, t.artist_id, t.artist, item_type.ARTIST),
        .line(0, t.key_id, "", item_type.KEY), .line(0, t.duration_s, "", item_type.DURATION),
        Item(
            a: t.row.id, id: t.row.id, text: t.row.title, item_type: item_type.TITLE, flags: track_flags.LISTED,
            c: t.row.id, e: 0x100, f: t.row.bpm_x100), .line(0, t.row.id, t.comment, item_type.COMMENT),
        .line(0, t.album_id, t.album, item_type.ALBUM), .line(0, t.row.bpm_x100, "", item_type.TEMPO),
        .line(0, t.row.id, "", item_type.DELIVERY_TEXT_37), .line(0, t.label_id, t.label, item_type.LABEL),
        .line(0, t.file_type, "", item_type.FILE_TYPE), .line(0, t.genre_id, t.genre, item_type.GENRE),
        Item(a: t.row.id, item_type: item_type.DELIVERY_ID, c: 1),
    ]
}
func track_info_rows(_ t: TrackDetails) -> [Item] {
    [
        Item(
            a: 1, id: 1, item_type: item_type.TRACK, e: 0x100, key: t.row.key, art: t.row.key_id, text3: t.row.key_name,
            f: t.row.bpm_x100), .line(0, t.duration_s, "", item_type.DURATION),
        .line(0, t.row.bpm_x100, "", item_type.TEMPO), .line(0, t.row.id, t.comment, item_type.COMMENT),
        .line(t.file_size, t.row.id, t.path, item_type.PATH), .line(0, 1, "", item_type.INFO_UNKNOWN),
        .line(0, t.key_id, t.key_name, item_type.KEY),
    ]
}
