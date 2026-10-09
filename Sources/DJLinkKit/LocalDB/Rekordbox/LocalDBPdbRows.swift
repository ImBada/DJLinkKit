// DJCrate PdbRows.swift의 칸 리더. localdb의 원본 칸 이름으로 내보낸다.
import Foundation

/// 행 하나의 칸 읽기. 행 밖을 읽으면 `LocalDBPdbError.readFailed`(그 행만 문제 목록에 넣는다).
/// 읽은 문자열의 종류·오프셋은 `strings`에 남겨 통계를 낸다.
struct PdbRowReader {
    struct DecodedString {
        var kind: PdbStringKind
        var offset: Int
        var length: Int
    }

    let data: [UInt8]
    private let bytes: [UInt8]
    private(set) var strings: [DecodedString] = []
    /// 먼 오프셋 모양(0x0064·0x0084·0x0684)으로 읽었는지. 쓰는 쪽이 `pdbFarOffsetRows`로 막을 수 있게 보고서에 센다
    private(set) var farShape = false

    init(_ data: [UInt8]) {
        self.data = data
        bytes = [UInt8](data)
    }

    var count: Int { bytes.count }

    func require(_ length: Int) throws {
        guard bytes.count >= length else {
            throw LocalDBPdbError.readFailed(detail: "pdb row \(bytes.count) bytes, needs \(length)")
        }
    }

    func u8(_ at: Int) throws -> Int {
        try require(at + 1)
        return Int(bytes[at])
    }

    func u16(_ at: Int) throws -> Int {
        try require(at + 2)
        return Int(bytes[at]) | Int(bytes[at + 1]) << 8
    }

    func u32(_ at: Int) throws -> Int64 {
        try require(at + 4)
        return (0..<4).reduce(Int64(0)) { $0 | Int64(bytes[at + $1]) << (8 * $1) }
    }

    /// id 칸(0 = 없음 → nil)
    func reference(_ at: Int) throws -> Int? {
        let value = Int(try u32(at))
        return value == 0 ? nil : value
    }

    mutating func markFarShape() {
        farShape = true
    }

    mutating func string(_ at: Int, isrcAllowed: Bool = false) throws -> (
        value: String?, kind: PdbStringKind
    ) {
        let decoded = try PdbStringDecoder.decode(data, at: at, isrcAllowed: isrcAllowed)
        strings.append(DecodedString(kind: decoded.kind, offset: at, length: decoded.value?.utf16.count ?? 0))
        return (decoded.value, decoded.kind)
    }
}

enum PdbRows {
    static func track(_ row: inout PdbRowReader) throws -> LocalDBRow {
        let fixedSize = 0x5E + 2 * 21
        try row.require(fixedSize)
        var result: LocalDBRow = [:]
        result["id"] = .int(Int(try row.u32(72)))
        result["trackNumber"] = .int(Int(try row.u32(52)))
        result["discNumber"] = .int(Int(try row.u16(76)))
        result["duration"] = .int(Int(try row.u16(84)))
        result["sampleRate"] = .int(Int(try row.u32(8)))
        result["sampleDepth"] = .int(Int(try row.u16(82)))
        result["bitrate"] = .int(Int(try row.u32(48)))
        result["tempo"] = .int(Int(try row.u32(56)))
        result["playCount"] = .int(Int(try row.u16(78)))
        result["year"] = .int(Int(try row.u16(80)))
        result["rating"] = .int(Int(try row.u8(89)))
        result["fileSize"] = .int(Int(try row.u32(16)))
        result["artworkId"] = .int(Int(try row.u32(28)))
        result["artistId"] = .int(Int(try row.u32(68)))
        result["originalArtistId"] = .int(Int(try row.u32(36)))
        result["remixerId"] = .int(Int(try row.u32(44)))
        result["composerId"] = .int(Int(try row.u32(12)))
        result["albumId"] = .int(Int(try row.u32(64)))
        result["labelId"] = .int(Int(try row.u32(40)))
        result["genreId"] = .int(Int(try row.u32(60)))
        result["colorId"] = .int(Int(try row.u8(88)))
        result["keyId"] = .int(Int(try row.u32(32)))
        let fields: [(String, Int)] = [
            ("title", 17), ("mixName", 12), ("comment", 16), ("filePath", 20),
            ("filename", 19), ("releaseDate", 11), ("analyzeDate", 15), ("dateAdded", 10),
            ("analyzePath", 14), ("autoloadHotcues", 7), ("kuvoPublic", 6),
        ]
        for (name, index) in fields {
            let offset = try row.u16(0x5E + 2 * index)
            result[name] = try row.string(offset).value.map { .text($0) } ?? .null
        }
        return result
    }
    static func idName(_ row: inout PdbRowReader) throws -> (id: Int, name: String) {
        (Int(try row.u32(0)), try row.string(4).value ?? "")
    }
    static func artist(_ row: inout PdbRowReader) throws -> Artist {
        let offset = try row.u16(0) == 0x0064 ? row.u16(0x0A) : row.u8(0x09)
        return .init(id: Int(try row.u32(4)), name: try row.string(offset).value ?? "")
    }
    static func album(_ row: inout PdbRowReader) throws -> Album {
        let offset = try row.u8(0x15)
        return .init(id: Int(try row.u32(0x0C)), name: try row.string(offset).value ?? "")
    }
    static func key(_ row: inout PdbRowReader) throws -> Key {
        .init(id: Int(try row.u32(0)), name: try row.string(8).value ?? "")
    }
    static func color(_ row: inout PdbRowReader) throws -> Color {
        .init(id: try row.u16(5), name: try row.string(8).value ?? "")
    }
    static func playlistTree(_ row: inout PdbRowReader) throws -> LocalDBRow {
        [
            "id": .int(Int(try row.u32(12))),
            "name": try row.string(20).value.map { .text($0) } ?? .null,
            "isFolder": .int(try row.u32(16) != 0 ? 1 : 0),
            "parentId": try row.reference(0).map { .int($0) } ?? .null,
        ]
    }
    static func artwork(_ row: inout PdbRowReader) throws -> LocalDBRow {
        [
            "id": .int(Int(try row.u32(0))),
            "path": try row.string(4).value.map { .text($0) } ?? .null,
        ]
    }
    static func playlistEntry(_ row: PdbRowReader) throws -> LocalDBRow {
        [
            "id": .null, "sortIndex": .int(Int(try row.u32(0))),
            "playlistId": .int(Int(try row.u32(8))), "trackId": .int(Int(try row.u32(4))),
        ]
    }
}
