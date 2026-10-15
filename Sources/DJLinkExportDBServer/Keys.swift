// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-dbserver/src/keys.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
public enum keys {
    public static let NAMES = [
        "Abm", "B", "Ebm", "F#", "Bbm", "Db", "Fm", "Ab", "Cm", "Eb", "Gm", "Bb", "Dm", "F", "Am", "C", "Em", "G", "Bm",
        "D", "F#m", "A", "Dbm", "E",
    ]
    public static func name(_ id: UInt32) -> String { (1...24).contains(id) ? NAMES[Int(id - 1)] : "" }
    public static func related(_ id: UInt32, _ distance: UInt32) -> [UInt32] {
        guard (1...24).contains(id) else { return [] }
        let index = id - 1
        let hour = index / 2
        let minor = index % 2 == 0
        func at(_ hour: UInt32, _ minor: Bool) -> UInt32 { (hour % 12) * 2 + (minor ? 0 : 1) + 1 }
        var out = [id]
        if distance >= 1 { out.append(at(hour, !minor)) }
        if distance >= 2 { out += [at((hour + 11) % 12, minor), at(hour + 1, minor)] }
        return out
    }
    public static func related_text(_ id: UInt32, _ distance: UInt32) -> String {
        related(id, distance).map { name($0) }.joined(separator: ", ")
    }
}
