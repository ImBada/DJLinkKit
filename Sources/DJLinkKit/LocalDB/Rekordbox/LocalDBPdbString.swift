// DJCrate PdbString.swift(MIT)에서 읽기에 필요한 부분을 옮겼다.
import Foundation

/// DeviceSQL 문자열 모양
public enum PdbStringKind: String, Sendable, Hashable, CaseIterable {
    /// 첫 바이트 홀수 `((n+1)<<1)+1` + ASCII n바이트(끝 표시 없음)
    case shortASCII
    /// `40`, u16 길이(머리 4 포함), `00`, ASCII
    case longASCII
    /// `90`, u16 길이(머리 4 포함), `00`, UTF-16LE
    case utf16LE
    /// `90`, u16 길이, `00`, `03`, ASCII, `00`(트랙 ISRC 칸에만)
    case isrc
}

public enum PdbStringDecoder {
    /// 원본 런타임처럼 잘못된 짧은 문자열은 text를 생략하고, ASCII 바이트는 그대로 문자로 만든다.
    public static func decode(_ row: [UInt8], at offset: Int, isrcAllowed: Bool = false) throws -> (
        value: String?, kind: PdbStringKind, byteLength: Int
    ) {
        guard offset >= 0, offset < row.count else {
            throw failure("offset \(offset) outside row \(row.count)")
        }
        let first = row[offset]
        if first != 0x40 && first != 0x90 {
            let length = (Int(first) - 1) / 2 - 1
            guard first % 2 > 0, length >= 0 else {
                return (nil, .shortASCII, 1)
            }
            guard offset + 1 + length <= row.count else {
                throw failure("short ASCII past row end")
            }
            return (ascii(row[(offset + 1)..<(offset + 1 + length)]), .shortASCII, 1 + length)
        }
        guard offset + 3 <= row.count else {
            throw failure("long string header past row end")
        }
        let length = Int(row[offset + 1]) | Int(row[offset + 2]) << 8
        if first == 0x40 {
            // PLAN §9(#13): 원본 Kaitai 정의는 +3부터 length바이트를 읽었다. rekordbox가 쓴 실제 export(2026-10-16)는
            // UTF-16처럼 length가 머리 4바이트를 포함하고 +4부터 본문이어서, 앞에 NUL이 붙고 다음 문자열 3바이트를 먹었다.
            guard length >= 4, offset + length <= row.count else {
                throw failure("long ASCII length \(length) past row end")
            }
            return (ascii(row[(offset + 4)..<(offset + length)]), .longASCII, length)
        }
        guard length >= 4, offset + length <= row.count else {
            throw failure("long string length \(length) past row end")
        }
        return (decodeUTF16(Array(row[(offset + 4)..<(offset + length)]), littleEndian: true), .utf16LE, length)
    }

    private static func ascii(_ bytes: ArraySlice<UInt8>) -> String {
        String(String.UnicodeScalarView(bytes.map { UnicodeScalar($0) }))
    }

    /// Node 22의 TextDecoder처럼 BOM을 생략하고 짝 없는 서로게이트와 마지막 홀수 바이트를 U+FFFD로 바꾼다.
    static func decodeUTF16(_ bytes: [UInt8], littleEndian: Bool) -> String {
        var units = stride(from: 0, to: bytes.count - bytes.count % 2, by: 2).map {
            littleEndian
                ? UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8
                : UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1])
        }
        if units.first == 0xFEFF {
            units.removeFirst()
        }
        if bytes.count % 2 != 0, let last = units.last, (0xD800...0xDBFF).contains(last) {
            // TextDecoder의 EOF 오류는 대기 중 서로게이트와 홀수 바이트를 한 번에 대체한다.
            units.removeLast()
        }
        var text = String(decoding: units, as: UTF16.self)
        if bytes.count % 2 != 0 {
            text.append("\u{FFFD}")
        }
        return text
    }

    static func failure(_ detail: String) -> LocalDBPdbError {
        .readFailed(detail: "pdb string: \(detail)")
    }
}
