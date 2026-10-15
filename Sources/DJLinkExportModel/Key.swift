// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-index/src/key.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 원본의 클래식 이름과 Camelot 바퀴 정렬이다.
import Foundation

public enum Ordering: Int, Sendable { case less = -1, equal = 0, greater = 1 }
private let MINOR = ["Abm", "Ebm", "Bbm", "Fm", "Cm", "Gm", "Dm", "Am", "Em", "Bm", "F#m", "Dbm"]
private let MAJOR = ["B", "F#", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E"]
private func canonical(_ name: String) -> String {
    let text = modelTrim(name)
    return [
        "G#m": "Abm", "D#m": "Ebm", "A#m": "Bbm", "C#m": "Dbm", "Gbm": "F#m", "Gb": "F#", "C#": "Db", "G#": "Ab",
        "D#": "Eb", "A#": "Bb",
    ][text] ?? text
}
public func camelot_rank(_ name: String) -> UInt32 {
    let name = canonical(name)
    if let i = MINOR.firstIndex(of: name) { return UInt32(i * 2) }
    if let i = MAJOR.firstIndex(of: name) { return UInt32(i * 2 + 1) }
    let bytes = Array(name.utf8)
    if let letter = bytes.last, [UInt8(65), 66, 97, 98].contains(letter), bytes.count > 1,
        let n = UInt32(String(decoding: bytes.dropLast(), as: UTF8.self)), (1...12).contains(n)
    {
        return (n - 1) * 2 + (letter == 66 || letter == 98 ? 1 : 0)
    }
    return .max
}
public func cmp_names(_ left: String, _ right: String) -> Ordering {
    if left.isEmpty { return right.isEmpty ? .equal : .greater }
    if right.isEmpty { return .less }
    let lhs = left.utf8.map { (65...90).contains($0) ? $0 + 32 : $0 }
    let rhs = right.utf8.map { (65...90).contains($0) ? $0 + 32 : $0 }
    if lhs == rhs { return .equal }
    return lhs.lexicographicallyPrecedes(rhs) ? .less : .greater
}
