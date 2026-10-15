// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-index/src/strings.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// UTF-8 바이트 저장소와 원본의 검색·스마트 문자열 접기를 옮겼다.
import Foundation

public struct StrColumn: Sendable {
    private var bytes: [UInt8] = []
    private var spans: [(UInt32, UInt32)] = []
    public init() {}
    public static func `default`() -> Self { Self() }
    public static func with_capacity(_ rows: Int, _ bytes: Int) -> Self {
        var result = Self()
        result.bytes.reserveCapacity(bytes)
        result.spans.reserveCapacity(rows)
        return result
    }
    public mutating func push(_ s: String) {
        let start = UInt32(exactly: bytes.count) ?? .max
        bytes += s.utf8
        spans.append((start, UInt32(exactly: s.utf8.count) ?? 0))
    }
    public func get(_ row: Int) -> String {
        guard spans.indices.contains(row) else { return "" }
        let (start, len) = spans[row]
        let a = Int(start)
        let b = Int(start) + Int(len)
        guard a <= b, b <= bytes.count else { return "" }
        return String(bytes: bytes[a..<b], encoding: .utf8) ?? ""
    }
    public func len() -> Int { spans.count }
    public func is_empty() -> Bool { spans.isEmpty }
    public mutating func replace_rows(_ values: [Int: String]) {
        var next = Self.with_capacity(len(), bytes.count)
        for row in 0..<len() { next.push(values[row] ?? get(row)) }
        self = next
    }
    public func heap_bytes() -> Int { bytes.capacity + spans.capacity * 8 }
    public func raw() -> ([UInt8], [(UInt32, UInt32)]) { (bytes, spans) }
    public static func from_raw(_ bytes: [UInt8], _ spans: [(UInt32, UInt32)]) -> Self {
        var result = Self()
        result.bytes = bytes
        result.spans = spans
        return result
    }
}
public struct Interner: Sendable {
    private var names = StrColumn()
    private var folded_names = StrColumn()
    public init() {}
    public static func `default`() -> Self { Self() }
    public func parts() -> (StrColumn, StrColumn) { (names, folded_names) }
    public static func from_parts(_ names: StrColumn, _ folded: StrColumn) -> Self {
        var result = Self()
        result.names = names
        result.folded_names = folded
        return result
    }
    public mutating func push(_ name: String) -> UInt32 {
        let id = UInt32(exactly: names.len()) ?? .max
        names.push(name)
        folded_names.push(fold(name))
        return id
    }
    public func name(_ id: UInt32) -> String { id == .max ? "" : names.get(Int(id)) }
    public func folded(_ id: UInt32) -> String { id == .max ? "" : folded_names.get(Int(id)) }
    public func len() -> Int { names.len() }
    public func is_empty() -> Bool { names.is_empty() }
    public func heap_bytes() -> Int { names.heap_bytes() + folded_names.heap_bytes() }
}
private func deaccent(_ ch: Unicode.Scalar) -> String {
    switch ch {
    case "à", "á", "â", "ã", "ä", "å", "À", "Á", "Â", "Ã", "Ä", "Å": return "a"
    case "è", "é", "ê", "ë", "È", "É", "Ê", "Ë": return "e"
    case "ì", "í", "î", "ï", "Ì", "Í", "Î", "Ï": return "i"
    case "ò", "ó", "ô", "õ", "ö", "Ò", "Ó", "Ô", "Õ", "Ö": return "o"
    case "ù", "ú", "û", "ü", "Ù", "Ú", "Û", "Ü": return "u"
    case "ñ", "Ñ": return "n"
    case "ç", "Ç": return "c"
    case "ß": return "ss"
    case "æ", "Æ": return "ae"
    case "ø", "Ø": return "o"
    default: return ""
    }
}
public func fold(_ s: String) -> String {
    var out = ""
    for ch in s.unicodeScalars {
        switch ch.value {
        case 97...122, 48...57, 32: out.unicodeScalars.append(ch)
        case 65...90: out.unicodeScalars.append(Unicode.Scalar(ch.value + 32)!)
        default: out += deaccent(ch)
        }
    }
    // 원본은 deaccent가 모르는 문자도 버린다. 주석과 다른 이 동작을 유지한다.
    return out
}
public func fold_smart(_ s: String) -> String {
    var out = ""
    for original in s.unicodeScalars.prefix(while: { $0.value != 0 }) {
        if (0x0300...0x036f).contains(original.value) { continue }
        let ch: Unicode.Scalar
        switch original.value {
        case 0xff01...0xff5e: ch = Unicode.Scalar(original.value - 0xfee0)!
        case 0x3000: ch = " "
        case 0x30a1...0x30f6: ch = Unicode.Scalar(original.value - 0x60)!
        case 0x03c2: ch = Unicode.Scalar(0x03c3)!
        case 0x212b: ch = "a"
        case 0x0130: ch = "i"
        default: ch = original
        }
        switch ch.value {
        case 65...90: out.unicodeScalars.append(Unicode.Scalar(ch.value + 32)!)
        case 0xfb00: out += "ff"
        case 0xfb01: out += "fi"
        case 0xfb02: out += "fl"
        case 0xfb03: out += "ffi"
        case 0xfb04: out += "ffl"
        case 0xfb05, 0xfb06: out += "st"
        case 0x0153, 0x0152: out += "oe"
        default:
            let d = deaccent(ch)
            out += d.isEmpty ? String(ch).lowercased() : d
        }
    }
    return out
}
