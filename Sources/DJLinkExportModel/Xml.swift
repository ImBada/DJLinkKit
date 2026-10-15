// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbxport/crates/rbl-core/src/xml.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// Rust char와 같은 Unicode scalar 경계에서 작은 XML 문서를 스캔한다.
import Foundation

public enum XmlTag: Sendable, Equatable {
    case open(name: String, attributes: [(String, String)], closed: Bool)
    case close(name: String)
    public func name() -> String {
        switch self {
        case .open(let name, _, _), .close(let name): return name
        }
    }
    public static func == (_ lhs: XmlTag, _ rhs: XmlTag) -> Bool {
        switch (lhs, rhs) {
        case let (.close(a), .close(b)): return a.utf8.elementsEqual(b.utf8)
        case let (.open(a, x, c), .open(b, y, d)):
            return a.utf8.elementsEqual(b.utf8) && c == d && x.count == y.count
                && zip(x, y).allSatisfy { pair in
                    pair.0.0.utf8.elementsEqual(pair.1.0.utf8) && pair.0.1.utf8.elementsEqual(pair.1.1.utf8)
                }
        default: return false
        }
    }
}
func ascii_equal(_ a: String, _ b: String) -> Bool {
    let lower: (UInt8) -> UInt8 = { (65...90).contains($0) ? $0 + 32 : $0 }
    return a.utf8.map(lower) == b.utf8.map(lower)
}
func modelTrim(_ text: String, end: Bool = true) -> String {
    let raw = Array(text.unicodeScalars)
    var first = 0
    var last = raw.count
    while first < last && raw[first].properties.isWhitespace { first += 1 }
    if end { while last > first && raw[last - 1].properties.isWhitespace { last -= 1 } }
    return String(String.UnicodeScalarView(raw[first..<last]))
}
public func tags(_ xml: String) -> [XmlTag] {
    let raw = Array(xml.unicodeScalars)
    var out: [XmlTag] = []
    var at = 0
    func text(_ range: Range<Int>) -> String { String(String.UnicodeScalarView(raw[range])) }
    func has(_ prefix: String) -> Bool { raw.dropFirst(at).starts(with: prefix.unicodeScalars) }
    func find(_ needle: String, _ from: Int) -> Int? {
        let pattern = Array(needle.unicodeScalars)
        guard from <= raw.count, pattern.count <= raw.count - from else { return nil }
        return (from...(raw.count - pattern.count)).first { raw[$0..<($0 + pattern.count)].elementsEqual(pattern) }
    }
    while let start = raw[at...].firstIndex(of: "<") {
        at = start + 1
        if has("?") || has("!") {
            if has("!--") {
                guard let end = find("-->", at + 3) else { break }
                at = end + 3
            } else {
                guard let end = raw[at...].firstIndex(of: ">") else { break }
                at = end + 1
            }
            continue
        }
        if has("/") {
            let after = at + 1
            guard let end = raw[after...].firstIndex(of: ">") else { break }
            out.append(.close(name: modelTrim(text(after..<end))))
            at = end + 1
            continue
        }
        let nameStart = at
        while at < raw.count && !raw[at].properties.isWhitespace && raw[at] != ">" && raw[at] != "/" { at += 1 }
        let name = text(nameStart..<at)
        var attributes: [(String, String)] = []
        var closed = false
        while true {
            while at < raw.count && raw[at].properties.isWhitespace { at += 1 }
            if has("/>") {
                closed = true
                at += 2
                break
            }
            if has(">") {
                at += 1
                break
            }
            if at == raw.count { break }
            guard let eq = raw[at...].firstIndex(of: "=") else {
                // 원본의 값 없는 단어 건너뛰기 절차를 그대로 보존한다.
                while at < raw.count && !raw[at].properties.isWhitespace && raw[at] != ">" && raw[at] != "/" { at += 1 }
                continue
            }
            let key = modelTrim(text(at..<eq))
            at = eq + 1
            while at < raw.count && raw[at].properties.isWhitespace { at += 1 }
            guard at < raw.count, raw[at] == "\"" || raw[at] == "'" else { break }
            let quote = raw[at]
            at += 1
            guard let end = raw[at...].firstIndex(of: quote) else { return out }
            attributes.append((key, unescape(text(at..<end))))
            at = end + 1
        }
        out.append(.open(name: name, attributes: attributes, closed: closed))
    }
    return out
}
public func attribute(_ attributes: [(String, String)], _ name: String) -> String {
    attributes.first { ascii_equal($0.0, name) }?.1 ?? ""
}
public func unescape(_ text: String) -> String {
    let raw = Array(text.unicodeScalars)
    guard raw.contains("&") else { return text }
    var out = ""
    var at = 0
    func append(_ range: Range<Int>) { out.unicodeScalars.append(contentsOf: raw[range]) }
    while let amp = raw[at...].firstIndex(of: "&") {
        append(at..<amp)
        at = amp
        guard let semi = raw[at...].firstIndex(of: ";") else {
            append(at..<raw.count)
            return out
        }
        let entity = String(String.UnicodeScalarView(raw[(at + 1)..<semi]))
        var replacement: UnicodeScalar?
        switch entity {
        case "amp": replacement = "&"
        case "lt": replacement = "<"
        case "gt": replacement = ">"
        case "quot": replacement = "\""
        case "apos": replacement = "'"
        default:
            let units = Array(entity.unicodeScalars)
            if units.first == "#" {
                let number = String(String.UnicodeScalarView(units.dropFirst()))
                let digits = number.hasPrefix("x") ? String(number.dropFirst()) : number
                // Rust의 부호 없는 정수 파서는 '-'를 받지 않는다(Swift는 "-0"을 0으로 읽는다).
                let value = digits.hasPrefix("-") ? nil : UInt32(digits, radix: number.hasPrefix("x") ? 16 : 10)
                replacement = value.flatMap(UnicodeScalar.init)
            }
        }
        if let replacement { out.unicodeScalars.append(replacement) } else { append(at..<(semi + 1)) }
        at = semi + 1
    }
    append(at..<raw.count)
    return out
}
public func escape(_ text: String) -> String {
    var out = ""
    for c in text.unicodeScalars {
        switch c {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        case "'": out += "&apos;"
        default: out.unicodeScalars.append(c)
        }
    }
    return out
}
