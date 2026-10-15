import DJLinkExportSupport
import DJLinkKit
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-dbserver/src/item.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

public enum item_type {
    public static let FOLDER: UInt32 = 0x01
    public static let ALBUM: UInt32 = 0x02
    public static let GENRE: UInt32 = 0x06
    public static let ARTIST: UInt32 = 0x07
    public static let PLAYLIST: UInt32 = 0x08
    public static let RATING: UInt32 = 0x0a
    public static let DURATION: UInt32 = 0x0b
    public static let TEMPO: UInt32 = 0x0d
    public static let LABEL: UInt32 = 0x0e
    public static let KEY: UInt32 = 0x0f
    public static let BIT_RATE: UInt32 = 0x10
    public static let YEAR: UInt32 = 0x11
    public static let COLOUR: UInt32 = 0x13
    public static let COLOR_PINK: UInt32 = 0x14
    public static let COLOR_RED: UInt32 = 0x15
    public static let COLOR_ORANGE: UInt32 = 0x16
    public static let COLOR_YELLOW: UInt32 = 0x17
    public static let COLOR_GREEN: UInt32 = 0x18
    public static let COLOR_AQUA: UInt32 = 0x19
    public static let COLOR_BLUE: UInt32 = 0x1a
    public static let COLOR_PURPLE: UInt32 = 0x1b
    public static let COMMENT: UInt32 = 0x23
    public static let HISTORY: UInt32 = 0x24
    public static let ORIGINAL_ARTIST: UInt32 = 0x28
    public static let REMIXER: UInt32 = 0x29
    public static let DATE_ADDED: UInt32 = 0x2e
    public static let FILE_TYPE: UInt32 = 0x12
    public static let DELIVERY_TEXT_36: UInt32 = 0x36
    public static let DELIVERY_TEXT_37: UInt32 = 0x37
    public static let DELIVERY_ID: UInt32 = 0x4f
    public static let TITLE: UInt32 = 0x04
    public static let TRACK: UInt32 = 0x2304
    public static let ALL: UInt32 = 0xa0
    public static let INFO_UNKNOWN: UInt32 = 0x2f
    public static let HOT_CUE_BANK: UInt32 = 0x2b
    public static let MY_TAG: UInt32 = 0x4a
    public static let MY_TAG_TICKED: UInt32 = 0x4b
    public static let MY_TAG_HEADING: UInt32 = 0x01
    public static let PATH: UInt32 = 0x00
    public static let MENU_GENRE: UInt32 = 0x80
    public static let MENU_ARTIST: UInt32 = 0x81
    public static let MENU_ALBUM: UInt32 = 0x82
    public static let MENU_TRACK: UInt32 = 0x83
    public static let MENU_PLAYLIST: UInt32 = 0x84
    public static let MENU_BPM: UInt32 = 0x85
    public static let MENU_RATING: UInt32 = 0x86
    public static let MENU_YEAR: UInt32 = 0x87
    public static let MENU_REMIXER: UInt32 = 0x88
    public static let MENU_LABEL: UInt32 = 0x89
    public static let MENU_ORIGINAL_ARTIST: UInt32 = 0x8a
    public static let MENU_KEY: UInt32 = 0x8b
    public static let MENU_DATE_ADDED: UInt32 = 0x8c
    public static let MENU_COLOR: UInt32 = 0x8e
    public static let MENU_SEARCH: UInt32 = 0x91
    public static let MENU_TIME: UInt32 = 0x92
    public static let MENU_BITRATE: UInt32 = 0x93
    public static let MENU_FILE_NAME: UInt32 = 0x94
    public static let MENU_HISTORY: UInt32 = 0x95
    public static let MENU_DJ_PLAY_COUNT: UInt32 = 0x97
    public static let MENU_HOT_CUE_BANK: UInt32 = 0x98
    public static let MENU_DEFAULT: UInt32 = 0xa1
    public static let MENU_ALPHABET: UInt32 = 0xa2
    public static let MENU_MATCHING: UInt32 = 0xaa
}

public enum track_flags {
    public static let PLAYED: UInt32 = 0x100
    public static let LISTED: UInt32 = 0x0100_0000
}
public struct Item: Equatable, Sendable {
    public var a: UInt32
    public var id: UInt32
    public var text: String
    public var text2: String
    public var item_type: UInt32
    public var flags: UInt32
    public var c: UInt32
    public var d: UInt32
    public var e: UInt32
    public var key: UInt32
    public var art: UInt32
    public var text3: String
    public var f: UInt32
    public init(
        a: UInt32 = 0, id: UInt32 = 0, text: String = "", text2: String = "", item_type: UInt32 = 0, flags: UInt32 = 0,
        c: UInt32 = 0, d: UInt32 = 0, e: UInt32 = 0, key: UInt32 = 0, art: UInt32 = 0, text3: String = "", f: UInt32 = 0
    ) {
        self.a = a
        self.id = id
        self.text = text
        self.text2 = text2
        self.item_type = item_type
        self.flags = flags
        self.c = c
        self.d = d
        self.e = e
        self.key = key
        self.art = art
        self.text3 = text3
        self.f = f
    }
}
public struct TrackRow: Equatable, Sendable {
    public var id: UInt32
    public var title: String
    public var secondary_text: String
    public var column: TrackColumn
    public var column_value: UInt32
    public var key: UInt32
    public var key_id: UInt32
    public var key_name: String
    public var bpm_x100: UInt32
    public init(
        id: UInt32 = 0, title: String = "", secondary_text: String = "", column: TrackColumn = .comment,
        column_value: UInt32 = 0, key: UInt32 = 0, key_id: UInt32 = 0, key_name: String = "", bpm_x100: UInt32 = 0
    ) {
        self.id = id
        self.title = title
        self.secondary_text = secondary_text
        self.column = column
        self.column_value = column_value
        self.key = key
        self.key_id = key_id
        self.key_name = key_name
        self.bpm_x100 = bpm_x100
    }
}
func utf16_len(_ text: String) -> UInt32 { UInt32(exactly: (text.utf16.count + 1) * 2) ?? .max }
extension Item {
    public func message(_ transaction: UInt32) -> Message {
        .new(
            transaction, kind.MENU_ITEM,
            [
                .number(a), .number(id), .number(utf16_len(text)), .string(text), .number(utf16_len(text2)),
                .string(text2), .number(item_type), .number(flags), .number(c), .number(d), .number(e), .number(key),
                .number(art), .number(utf16_len(text3)), .string(text3), .number(f),
            ])
    }
    public static func heading(_ id: UInt32, _ label: String, _ type: UInt32) -> Self {
        Self(id: id, text: "\u{fffa}\(label)\u{fffb}", item_type: type)
    }
    public static func all() -> Self { heading(.max, "ALL", DJLinkExportDBServer.item_type.ALL) }
    public static func named_twice(_ id: UInt32, _ name: String, _ type: UInt32) -> Self {
        Self(id: id, text: name, item_type: type, c: id)
    }
    public static func named(_ id: UInt32, _ name: String, _ type: UInt32) -> Self {
        Self(id: id, text: name, item_type: type)
    }
    public static func list(_ id: UInt32, _ name: String, _ folder: Bool, _ position: UInt32) -> Self {
        Self(
            id: id, text: name,
            item_type: folder ? DJLinkExportDBServer.item_type.FOLDER : DJLinkExportDBServer.item_type.PLAYLIST,
            d: position)
    }
    public static func date_part(_ value: UInt32) -> Self {
        Self(id: value, item_type: DJLinkExportDBServer.item_type.DATE_ADDED)
    }
    public static func track(_ row: TrackRow, _ flags: UInt32, _ position: UInt32) -> Self {
        Self(
            a: row.column == .comment || row.column == .dateAdded ? row.id : row.column_value, id: row.id,
            text: row.title, text2: row.secondary_text, item_type: track_item_type(row.column, row.column_value),
            flags: flags, c: row.id, d: position, e: 0x100, key: row.key, art: row.key_id, text3: row.key_name,
            f: row.bpm_x100)
    }
    public static func line(_ a: UInt32, _ id: UInt32, _ text: String, _ type: UInt32) -> Self {
        Self(a: a, id: id, text: text, item_type: type)
    }
    public static func number(_ id: UInt32, _ type: UInt32) -> Self { Self(id: id, item_type: type) }
}
extension TrackRow {
    public mutating func format_sort_column() {
        let bpm = format_bpm(bpm_x100)
        let key = self.key == 0 ? "" : key_name
        switch column {
        case .bpm: secondary_text = join_secondary(bpm, key)
        case .key: secondary_text = join_secondary(key, bpm)
        default: break
        }
    }
}
func format_bpm(_ bpm_x100: UInt32) -> String {
    guard bpm_x100 != 0 else { return "" }
    let tenths = saturating_add(bpm_x100, 5) / 10
    return "\(tenths/10).\(tenths%10) bpm"
}
func join_secondary(_ primary: String, _ secondary: String) -> String {
    primary.isEmpty ? secondary : secondary.isEmpty ? primary : "\(primary) - \(secondary)"
}
func track_item_type(_ column: TrackColumn, _ value: UInt32) -> UInt32 {
    let secondary: UInt32
    switch column {
    case .title: secondary = 0
    case .album: secondary = item_type.ALBUM
    case .genre: secondary = item_type.GENRE
    case .artist: secondary = item_type.ARTIST
    case .rating: secondary = item_type.RATING
    case .duration: secondary = item_type.DURATION
    case .bpm: secondary = item_type.TEMPO
    case .label: secondary = item_type.LABEL
    case .key: secondary = item_type.KEY
    case .bitrate: secondary = item_type.BIT_RATE
    case .color: secondary = item_type.COLOUR + min(value, 8)
    case .comment: secondary = item_type.COMMENT
    case .originalArtist: secondary = item_type.ORIGINAL_ARTIST
    case .remixer: secondary = item_type.REMIXER
    case .djPlayCount: secondary = 0x2a
    case .dateAdded: secondary = item_type.DATE_ADDED
    }
    return secondary << 8 | item_type.TITLE
}
public func root_menu(_ categories: [RootCategory], _ capabilities: UInt32) -> [Item] {
    var menu: [Item] = []
    var has_hot_cue_bank = false
    for category in categories {
        if category.menu_item_id == 24 { continue }
        let enabled =
            category.menu_item_id == 27
            ? category.disable & 1 == 0 : category.menu_item_id == 22 ? category.disable != 1 : category.disable == 0
        let bit = category.menu_item_id == 22 ? 24 : category.menu_item_id == 0 ? 0 : category.menu_item_id - 1
        if !enabled || bit >= 32 || capabilities & (UInt32(1) << bit) == 0 { continue }
        has_hot_cue_bank = has_hot_cue_bank || category.menu_item_id == 18
        menu.append(.heading(category.id, category.name, category.item_type))
    }
    if capabilities == 0x00ff_ffff && !has_hot_cue_bank {
        menu.append(.heading(23, "HOT CUE BANK", item_type.MENU_HOT_CUE_BANK))
    }
    return menu
}
public func sort_menu(_ sorts: [Sort]) -> [Item] {
    sorts.map { sort in
        switch sort {
        case .default: return .heading(0, "DEFAULT", item_type.MENU_DEFAULT)
        case .alphabet: return .heading(1, "ALPHABET", item_type.MENU_ALPHABET)
        case .artist: return .heading(2, "ARTIST", item_type.MENU_ARTIST)
        case .album: return .heading(3, "ALBUM", item_type.MENU_ALBUM)
        case .bpm: return .heading(4, "BPM", item_type.MENU_BPM)
        case .rating: return .heading(5, "RATING", item_type.MENU_RATING)
        case .genre: return .heading(6, "GENRE", item_type.GENRE)
        case .label: return .heading(0xa, "LABEL", item_type.MENU_LABEL)
        case .key: return .heading(0xc, "KEY", item_type.MENU_KEY)
        case .djPlayCount: return .heading(0x10, "DJ PLAY COUNT", item_type.MENU_DJ_PLAY_COUNT)
        case .dateAdded: return .heading(0x11, "DATE ADDED", item_type.MENU_DATE_ADDED)
        }
    }
}
