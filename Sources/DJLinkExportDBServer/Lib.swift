// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
import DJLinkExportSupport
import DJLinkKit
// 원본: crates/rbl-dbserver/src/lib.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

public enum kind {
    public static let SETUP: UInt16 = 0x0000
    public static let TEARDOWN: UInt16 = 0x0100
    public static let ROOT_MENU: UInt16 = 0x1000
    public static let GENRE_MENU: UInt16 = 0x1001
    public static let ARTIST_MENU: UInt16 = 0x1002
    public static let ALBUM_MENU: UInt16 = 0x1003
    public static let TRACK_MENU: UInt16 = 0x1004
    public static let CONTENT_TRACKS: UInt16 = 0x1200
    public static let BPM_MENU: UInt16 = 0x1006
    public static let RATING_MENU: UInt16 = 0x1007
    public static let RELEASE_DECADES: UInt16 = 0x1008
    public static let LABEL_MENU: UInt16 = 0x100a
    public static let LEGACY_KEY_MENU: UInt16 = 0x100b
    public static let COLOR_MENU: UInt16 = 0x100d
    public static let TIME_MENU: UInt16 = 0x1010
    public static let BITRATE_MENU: UInt16 = 0x1011
    public static let HISTORY_MENU: UInt16 = 0x1012
    public static let FILE_NAME_MENU: UInt16 = 0x1013
    public static let KEY_MENU: UInt16 = 0x1014
    public static let MATCHING_TRACKS: UInt16 = 0x1017
    public static let ORIGINAL_ARTIST_MENU: UInt16 = 0x1302
    public static let ORIGINAL_ARTIST_ALBUMS: UInt16 = 0x1402
    public static let ORIGINAL_ARTIST_ALBUM_TRACKS: UInt16 = 0x1502
    public static let REMIXER_MENU: UInt16 = 0x1602
    public static let REMIXER_ALBUMS: UInt16 = 0x1702
    public static let REMIXER_ALBUM_TRACKS: UInt16 = 0x1802
    public static let GENRE_ARTISTS: UInt16 = 0x1101
    public static let ARTIST_ALBUMS: UInt16 = 0x1102
    public static let ALBUM_TRACKS: UInt16 = 0x1103
    public static let PLAYLIST_MENU: UInt16 = 0x1105
    public static let BPM_RANGES: UInt16 = 0x1106
    public static let RATING_TRACKS: UInt16 = 0x1107
    public static let RELEASE_YEARS: UInt16 = 0x1108
    public static let LABEL_ARTISTS: UInt16 = 0x110a
    public static let LEGACY_KEY_TRACKS: UInt16 = 0x110b
    public static let COLOR_TRACKS: UInt16 = 0x110d
    public static let TIME_TRACKS: UInt16 = 0x1110
    public static let BITRATE_TRACKS: UInt16 = 0x1111
    public static let HISTORY_TRACKS: UInt16 = 0x1112
    public static let RELATED_KEYS: UInt16 = 0x1114
    public static let GENRE_ARTIST_ALBUMS: UInt16 = 0x1201
    public static let ARTIST_ALBUM_TRACKS: UInt16 = 0x1202
    public static let BPM_TRACKS: UInt16 = 0x1206
    public static let RELEASE_YEAR_TRACKS: UInt16 = 0x1208
    public static let LABEL_ARTIST_ALBUMS: UInt16 = 0x120a
    public static let GENRE_ARTIST_ALBUM_TRACKS: UInt16 = 0x1301
    public static let LABEL_ARTIST_ALBUM_TRACKS: UInt16 = 0x130a
    public static let KEY_TRACKS: UInt16 = 0x1214
    public static let SEARCH: UInt16 = 0x1300
    public static let SEARCH_TRACK: UInt16 = 0x1500
    public static let SORT_MENU: UInt16 = 0x1400
    public static let YEARS: UInt16 = 0x1708
    public static let MONTHS: UInt16 = 0x1808
    public static let DAYS: UInt16 = 0x1908
    public static let DATE_TRACKS: UInt16 = 0x1a08
    public static let METADATA: UInt16 = 0x2002
    public static let HOT_CUE_BANK: UInt16 = 0x2001
    public static let HOT_CUE_BANK_CUES: UInt16 = 0x2101
    public static let CHANGE_HOT_CUE_BANK: UInt16 = 0x2201
    public static let ARTWORK: UInt16 = 0x2003
    public static let CONTENT_ARTWORK: UInt16 = 0x2103
    public static let WAVEFORM_PREVIEW: UInt16 = 0x2004
    public static let SAVE_WAVEFORM: UInt16 = 0x2005
    // PLAN §9/#20: 공개 alphatheta-connect 클라이언트와 CDJ-2000nexus가 쓰는 레거시 큐 읽기.
    public static let CUES: UInt16 = 0x2104
    public static let TRACK_INFO: UInt16 = 0x2102
    public static let BEAT_GRID: UInt16 = 0x2204
    public static let SAVE_GRID_OFFSET: UInt16 = 0x2605
    public static let SAVE_CUE: UInt16 = 0x2105
    public static let SAVE_VBR: UInt16 = 0x2205
    public static let SAVE_EXTENDED_CUE: UInt16 = 0x2705
    public static let GRID_OFFSET: UInt16 = 0x2804
    public static let DELIVERY_INFO: UInt16 = 0x2602
    public static let VBR: UInt16 = 0x2504
    public static let WAVEFORM_DETAIL: UInt16 = 0x2904
    public static let EXTENDED_CUES: UInt16 = 0x2b04
    public static let ANLZ_TAG: UInt16 = 0x2c04
    public static let ANLZ_TAG_2EX: UInt16 = 0x2d04
    public static let RENDER: UInt16 = 0x3000
    public static let USER_INFO: UInt16 = 0x3006
    public static let TRACK_BPM: UInt16 = 0x3008
    public static let ITEM_POSITION: UInt16 = 0x3100
    public static let INSERT_HISTORY: UInt16 = 0x3001
    public static let DELETE_HISTORY: UInt16 = 0x3101
    public static let DELETE_HISTORY_TRACK: UInt16 = 0x3401
    public static let SET_ON_AIR: UInt16 = 0x3201
    public static let TAG_LIST: UInt16 = 0x100f
    public static let CHANGE_TAG: UInt16 = 0x3002
    public static let CLEAR_TAGS: UInt16 = 0x3202
    public static let CHANGE_RATING: UInt16 = 0x2107
    public static let FILTER_SWITCH: UInt16 = 0x3007
    public static let FILTER_GET: UInt16 = 0x3107
    public static let FILTER_SET: UInt16 = 0x3207
    public static let MY_TAG: UInt16 = 0x1015
    public static let MY_TAG_ON_TRACK: UInt16 = 0x1315
    public static let FILTER_MY_TAG: UInt16 = 0x3307
    public static let FILTER_MY_TAG_ITEM: UInt16 = 0x3407
    public static let BROWSE_TYPE: UInt16 = 0x3303
    public static let TRACK_PLAY_STATE: UInt16 = 0x3b03
    public static let LEGACY_KEY_TO_NEW_KEY: UInt16 = 0x3a03
    public static let CONTENT_NEW_KEY: UInt16 = 0x3d03
    public static let REKORDBOX_MOBILE: UInt16 = 0x3e03
    public static let FILTER_REPLY: UInt16 = 0x4004
    public static let MENU_HEADER: UInt16 = 0x4000
    public static let RENDER_HEADER: UInt16 = 0x4001
    public static let ARTWORK_REPLY: UInt16 = 0x4002
    public static let ERROR: UInt16 = 0x4003
    public static let MENU_ITEM: UInt16 = 0x4101
    public static let MENU_FOOTER: UInt16 = 0x4201
    public static let WAVEFORM_PREVIEW_REPLY: UInt16 = 0x4402
    public static let VBR_REPLY: UInt16 = 0x4502
    public static let BEAT_GRID_REPLY: UInt16 = 0x4602
    public static let HOT_CUE_BANK_REPLY: UInt16 = 0x4702
    public static let CUES_REPLY: UInt16 = HOT_CUE_BANK_REPLY
    public static let REKORDBOX_MOBILE_REPLY: UInt16 = 0x4b02
    public static let WAVEFORM_DETAIL_REPLY: UInt16 = 0x4a02
    public static let USER_INFO_REPLY: UInt16 = 0x4d02
    public static let EXTENDED_CUES_REPLY: UInt16 = 0x4e02
    public static let ANLZ_TAG_REPLY: UInt16 = 0x4f02
    public static func name(_ value: UInt16) -> String {
        switch value {
        case SETUP: return "setup"
        case TEARDOWN: return "teardown"
        case ROOT_MENU: return "root menu"
        case GENRE_MENU: return "genre menu"
        case GENRE_ARTISTS: return "genre's artists"
        case GENRE_ARTIST_ALBUMS: return "genre artist's albums"
        case GENRE_ARTIST_ALBUM_TRACKS: return "genre artist's album tracks"
        case ARTIST_MENU: return "artist menu"
        case ALBUM_MENU: return "album menu"
        case TRACK_MENU: return "track menu"
        case CONTENT_TRACKS: return "content tracks"
        case BPM_MENU: return "BPM menu"
        case BPM_RANGES: return "BPM ranges"
        case BPM_TRACKS: return "BPM tracks"
        case RATING_MENU: return "rating menu"
        case RATING_TRACKS: return "rating tracks"
        case RELEASE_DECADES: return "release decades"
        case RELEASE_YEARS: return "release years"
        case RELEASE_YEAR_TRACKS: return "release-year tracks"
        case LABEL_MENU: return "label menu"
        case LEGACY_KEY_MENU: return "legacy key menu"
        case LABEL_ARTISTS: return "label's artists"
        case LEGACY_KEY_TRACKS: return "legacy key's tracks"
        case LABEL_ARTIST_ALBUMS: return "label artist's albums"
        case LABEL_ARTIST_ALBUM_TRACKS: return "label artist's album tracks"
        case COLOR_MENU: return "color menu"
        case COLOR_TRACKS: return "color tracks"
        case TIME_MENU: return "time menu"
        case TIME_TRACKS: return "time tracks"
        case BITRATE_MENU: return "bitrate menu"
        case BITRATE_TRACKS: return "bitrate tracks"
        case FILE_NAME_MENU: return "file-name menu"
        case MATCHING_TRACKS: return "matching tracks"
        case HISTORY_MENU: return "history menu"
        case KEY_MENU: return "key menu"
        case ARTIST_ALBUMS: return "artist's albums"
        case ALBUM_TRACKS: return "album's tracks"
        case PLAYLIST_MENU: return "playlist menu"
        case HISTORY_TRACKS: return "history's tracks"
        case INSERT_HISTORY: return "insert history"
        case DELETE_HISTORY: return "delete history"
        case DELETE_HISTORY_TRACK: return "delete history track"
        case SET_ON_AIR: return "set on-air"
        case RELATED_KEYS: return "related keys"
        case ARTIST_ALBUM_TRACKS: return "artist's album tracks"
        case KEY_TRACKS: return "key's tracks"
        case SEARCH: return "search"
        case SORT_MENU: return "sort menu"
        case YEARS: return "years"
        case MONTHS: return "months"
        case DAYS: return "days"
        case DATE_TRACKS: return "date's tracks"
        case METADATA: return "metadata"
        case DELIVERY_INFO: return "delivery info"
        case USER_INFO: return "user info"
        case USER_INFO_REPLY: return "user info reply"
        case ARTWORK: return "artwork"
        case CONTENT_ARTWORK: return "content artwork"
        case WAVEFORM_PREVIEW: return "waveform preview"
        case TRACK_INFO: return "track info"
        case BEAT_GRID: return "beat grid"
        case SAVE_GRID_OFFSET: return "save grid offset"
        case SAVE_CUE: return "save cue"
        case SAVE_VBR: return "save VBR"
        case SAVE_EXTENDED_CUE: return "save extended cue"
        case GRID_OFFSET: return "grid offset"
        case VBR: return "VBR"
        case WAVEFORM_DETAIL: return "waveform detail"
        case CUES: return "cues"
        case EXTENDED_CUES: return "extended cues"
        case ANLZ_TAG: return "anlz tag (EXT)"
        case ANLZ_TAG_2EX: return "anlz tag (2EX)"
        case RENDER: return "render"
        case ITEM_POSITION: return "item position"
        case TAG_LIST: return "tag list"
        case CHANGE_TAG: return "change tag"
        case CLEAR_TAGS: return "clear tags"
        case CHANGE_RATING: return "change rating"
        case FILTER_SWITCH: return "filter switch"
        case FILTER_GET: return "filter properties"
        case FILTER_SET: return "set filter properties"
        case MY_TAG: return "my tag"
        case MY_TAG_ON_TRACK: return "my tags on track"
        case FILTER_MY_TAG: return "set my tag filter"
        case FILTER_MY_TAG_ITEM: return "tick my tag filter item"
        case BROWSE_TYPE: return "browse type"
        case LEGACY_KEY_TO_NEW_KEY: return "legacy-to-new key id"
        case TRACK_PLAY_STATE: return "track play state"
        case CONTENT_NEW_KEY: return "content new key id"
        case SEARCH_TRACK: return "search track"
        case MENU_HEADER: return "menu header"
        case RENDER_HEADER: return "render header"
        case ARTWORK_REPLY: return "artwork reply"
        case ERROR: return "error"
        case MENU_ITEM: return "menu item"
        case MENU_FOOTER: return "menu footer"
        case WAVEFORM_PREVIEW_REPLY: return "waveform preview reply"
        case VBR_REPLY: return "VBR reply"
        case BEAT_GRID_REPLY: return "beat grid reply"
        case WAVEFORM_DETAIL_REPLY: return "waveform detail reply"
        case EXTENDED_CUES_REPLY: return "extended cues reply"
        case ANLZ_TAG_REPLY: return "anlz tag reply"
        default: return String(format: "kind 0x%04x", value)
        }
    }
}

public let MAGIC: UInt32 = 0x8723_49ae
public let PORT_QUERY: UInt16 = 12_523
public let PORT_QUERY_REQUEST: [UInt8] = [0, 0, 0, 15] + Array("RemoteDBServer\0".utf8)
public let GREETING: [UInt8] = [0x11, 0, 0, 0, 1]
public let SETUP_TXID: UInt32 = 0xffff_fffe
public let SETUP_MAGIC: UInt32 = 0x14
public enum DbError: Error, Equatable, CustomStringConvertible {
    case truncated(wanted: Int, had: Int), badMagic(UInt32), unknownTag(UInt8), tooManyArguments(UInt8)
    public var description: String {
        switch self {
        case let .truncated(wanted, had): return "message is truncated: wanted \(wanted) bytes, had \(had)"
        case let .badMagic(v): return String(format: "not a database message: magic was 0x%08x", v)
        case let .unknownTag(v): return String(format: "unknown argument tag 0x%02x", v)
        case let .tooManyArguments(v): return "message declares \(v) arguments, which is more than twelve"
        }
    }
}
public typealias Result<T> = Swift.Result<T, DbError>

public enum Argument: Equatable, Sendable {
    case number(UInt32), string(String), blob([UInt8])
    public func describe() -> String {
        switch self {
        case let .number(v): return String(v)
        case let .string(s): return dbDebugString(s)
        case let .blob(b): return "<\(b.count) bytes>"
        }
    }
    func arg_tag() -> UInt8 {
        switch self {
        case .number: return 6
        case .string: return 2
        case .blob: return 3
        }
    }
    func encode() -> [UInt8] {
        switch self {
        case let .number(v): return [0x11] + dbBE(v)
        case let .blob(b): return [0x14] + dbBE(UInt32(exactly: b.count) ?? 0) + b
        case let .string(s):
            return [0x26] + dbBE(UInt32(exactly: s.utf16.count + 1) ?? 0) + s.utf16.flatMap { dbBE($0) } + [0, 0]
        }
    }
}
func dbBE<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    (0..<MemoryLayout<T>.size).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
}
func dbLE<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    (0..<MemoryLayout<T>.size).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
}
func be32(_ b: [UInt8], _ at: Int) -> UInt32 {
    (0..<4).reduce(0) { ($0 << 8) | UInt32(at + $1 < b.count ? b[at + $1] : 0) }
}
func le32(_ b: [UInt8], _ at: Int) -> UInt32 {
    guard at >= 0, at + 4 <= b.count else { return 0 }
    return (0..<4).reduce(0) { $0 | UInt32(b[at + $1]) << ($1 * 8) }
}
func le16(_ b: [UInt8], _ at: Int) -> UInt16 {
    guard at >= 0, at + 2 <= b.count else { return 0 }
    return UInt16(b[at]) | UInt16(b[at + 1]) << 8
}
func saturating_add(_ a: UInt32, _ b: UInt32) -> UInt32 {
    let (v, o) = a.addingReportingOverflow(b)
    return o ? .max : v
}
func saturating_mul(_ a: UInt32, _ b: UInt32) -> UInt32 {
    let (v, o) = a.multipliedReportingOverflow(by: b)
    return o ? .max : v
}
public struct Message: Equatable, Sendable {
    public var transaction: UInt32
    public var kind: UInt16
    public var arguments: [Argument]
    public init(transaction: UInt32, kind: UInt16, arguments: [Argument]) {
        self.transaction = transaction
        self.kind = kind
        self.arguments = arguments
    }
    public static func new(_ transaction: UInt32, _ kind: UInt16, _ arguments: [Argument]) -> Self {
        Self(transaction: transaction, kind: kind, arguments: arguments)
    }
    public func encode() -> [UInt8] {
        let args = Array(arguments.prefix(32))
        var out: [UInt8] = [0x11]
        out += dbBE(MAGIC)
        out += [0x11] + dbBE(transaction)
        out += [0x10] + dbBE(kind)
        out += [0x0f, UInt8(args.count), 0x14]
        out += dbBE(UInt32(args.count))
        out += args.map { $0.arg_tag() }
        for a in args {
            if a == .blob([]) { continue }
            out += a.encode()
        }
        return out
    }
    public static func decode(_ bytes: [UInt8]) throws -> (Self, Int) {
        func need(_ n: Int) throws { if n > bytes.count { throw DbError.truncated(wanted: n, had: bytes.count) } }
        try need(20)
        let magic = be32(bytes, 1)
        guard bytes[0] == 0x11, magic == MAGIC, bytes[5] == 0x11, bytes[10] == 0x10, bytes[13] == 0x0f,
            bytes[15] == 0x14
        else { throw DbError.badMagic(magic) }
        let count = Int(bytes[14])
        if count > 32 { throw DbError.tooManyArguments(bytes[14]) }
        let tags = Int(be32(bytes, 16))
        guard tags >= count, tags <= 32 else { throw DbError.badMagic(magic) }
        var at = 20 + tags
        try need(at)
        var args: [Argument] = []
        for declared in bytes[20..<(20 + count)] {
            if declared == 3 && (args.last == nil || args.last == .number(0)) {
                args.append(.blob([]))
                continue
            }
            try need(at + 1)
            let tag = bytes[at]
            at += 1
            switch tag {
            case 0x0f...0x11:
                let width = tag == 0x0f ? 1 : tag == 0x10 ? 2 : 4
                try need(at + width)
                let v = bytes[at..<(at + width)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                args.append(.number(v))
                at += width
            case 0x14:
                let n = Int(be32(bytes, at))
                at += 4
                try need(at + n)
                args.append(.blob(Array(bytes[at..<(at + n)])))
                at += n
            case 0x26:
                let n = Int(be32(bytes, at)) * 2
                at += 4
                try need(at + n)
                var units: [UInt16] = []
                var i = at
                while i < at + n {
                    let u = UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
                    if u == 0 { break }
                    units.append(u)
                    i += 2
                }
                args.append(.string(String(decoding: units, as: UTF16.self)))
                at += n
            default: throw DbError.unknownTag(tag)
            }
        }
        return (Self.new(be32(bytes, 6), UInt16(bytes[11]) << 8 | UInt16(bytes[12]), args), at)
    }
    public static func decode_all(_ bytes: [UInt8]) -> ([Self], Int) {
        var out: [Self] = []
        var at = 0
        while at < bytes.count {
            guard let (message, used) = try? decode(Array(bytes[at...])), used > 0 else { break }
            out.append(message)
            at += used
        }
        return (out, at)
    }
}
public func is_answerable_device(_ device: UInt8) -> Bool { (1...6).contains(device) }
public func setup_request(_ device: UInt8) -> Message {
    .new(SETUP_TXID, kind.SETUP, [.number(UInt32(device)), .number(SETUP_MAGIC)])
}
public func setup_reply(_ transaction: UInt32, _ our_device: UInt8) -> Message {
    .new(transaction, kind.SETUP, [.number(UInt32(our_device)), .number(SETUP_MAGIC)])
}
public func menu_header(_ transaction: UInt32, _ request_kind: UInt32, _ item_count: UInt32) -> Message {
    .new(transaction, kind.MENU_HEADER, [.number(request_kind), .number(item_count)])
}
public func menu_footer(_ transaction: UInt32) -> Message { .new(transaction, kind.MENU_FOOTER, []) }

func dbDebugString(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
        switch scalar.value {
        case 0: out += "\\0"
        case 9: out += "\\t"
        case 10: out += "\\n"
        case 13: out += "\\r"
        case 34: out += "\\\""
        case 92: out += "\\\\"
        default:
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .unassigned:
                out += "\\u{\(String(scalar.value,radix:16))}"
            default: out.unicodeScalars.append(scalar)
            }
        }
    }
    return out + "\""
}
