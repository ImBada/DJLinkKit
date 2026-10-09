// DJCrate PdbTable.swift(MIT)에서 읽기에 필요한 부분을 옮겼다.
import Foundation

/// `export.pdb` 표 번호(파일 머리 표 포인터의 type)
public enum PdbTableType: Int, CaseIterable, Sendable {
    case tracks = 0
    case genres = 1
    case artists = 2
    case albums = 3
    case labels = 4
    case keys = 5
    case colors = 6
    case
        playlistTree = 7
    case playlistEntries = 8
    case unknown9 = 9
    case unknown10 = 10
    case
        historyPlaylists = 11
    case historyEntries = 12
    case artwork = 13
    case unknown14 = 14
    case unknown15 = 15
    case
        columns = 16
    case category = 17
    case sort = 18
    case history19 = 19

    /// 보고서·lab 출력에 쓰는 이름
    public var name: String {
        switch self {
        case .tracks: "tracks"
        case .genres: "genres"
        case .artists: "artists"
        case .albums: "albums"
        case .labels: "labels"
        case .keys: "keys"
        case .colors: "colors"
        case .playlistTree: "playlist_tree"
        case .playlistEntries: "playlist_entries"
        case .unknown9: "unknown9"
        case .unknown10: "unknown10"
        case .historyPlaylists: "history_playlists"
        case .historyEntries: "history_entries"
        case .artwork: "artwork"
        case .unknown14: "unknown14"
        case .unknown15: "unknown15"
        case .columns: "columns"
        case .category: "category"
        case .sort: "sort"
        case .history19: "history19"
        }
    }
}

/// `exportExt.pdb` 표 번호
public enum PdbExtTableType: Int, CaseIterable, Sendable {
    case unknown0 = 0
    case unknown1, unknown2
    case tags = 3
    case tagTracks = 4
    case unknown5, unknown6
    case myTagProperty = 7
    case unknown8

    public var name: String {
        switch self {
        case .tags: "tags"
        case .tagTracks: "tag_tracks"
        case .myTagProperty: "my_tag_property"
        default: "unknown\(rawValue)"
        }
    }
}

/// Device Library 파일 둘
public enum PdbFileKind: String, Sendable, Hashable {
    case export, exportExt

    public var fileName: String {
        switch self {
        case .export: "export.pdb"
        case .exportExt: "exportExt.pdb"
        }
    }

    /// 파일 머리 num_tables. 이 수가 아니면 읽지 않는다
    public var tableCount: Int {
        switch self {
        case .export: PdbTableType.allCases.count
        case .exportExt: PdbExtTableType.allCases.count
        }
    }

    /// 보고서 표 이름. exportExt 표는 "exportExt." 접두어를 붙여 export 표와 섞이지 않게 한다
    public func tableName(_ type: UInt32) -> String {
        switch self {
        case .export: PdbTableType(rawValue: Int(type))?.name ?? "type\(type)"
        case .exportExt: "exportExt." + (PdbExtTableType(rawValue: Int(type))?.name ?? "type\(type)")
        }
    }

    /// 행 0x00 subtype·0x02 index_shift가 있는 표(index_shift는 자리 × 0x20이라 해석에 쓰지 않는다)
    public func rowHasIndexShift(_ type: UInt32) -> Bool {
        switch self {
        case .export:
            [PdbTableType.tracks, .artists, .albums, .history19].map { UInt32($0.rawValue) }.contains(
                type)
        case .exportExt:
            [PdbExtTableType.tags, .myTagProperty].map { UInt32($0.rawValue) }.contains(type)
        }
    }

    init?(tableCount: UInt32) {
        switch Int(tableCount) {
        case PdbFileKind.export.tableCount: self = .export
        case PdbFileKind.exportExt.tableCount: self = .exportExt
        default: return nil
        }
    }
}
