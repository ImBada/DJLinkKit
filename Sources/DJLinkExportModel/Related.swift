// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-index/src/related.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 원본의 관련 키·반/두 배 템포·재생 이력 순위를 옮겼다.
import Foundation

func round_even(_ x: Double) -> UInt32 { UInt32(min(max(x, 0).rounded(.toNearestOrEven), Double(UInt32.max))) }
func bpm_window(_ centre_x100: UInt32, _ diff: UInt32) -> (UInt32, UInt32) {
    let pct = Double(diff) * 0.01
    let centre = Double(centre_x100)
    return (round_even(centre * (1 - pct)), round_even(centre * (pct + 1)))
}
func related_bpm_matches(_ centre_x100: UInt32, _ theirs_x100: UInt32, _ diff: UInt32, _ half_double: Bool) -> Bool {
    func within(_ centre: UInt32) -> Bool {
        let (low, high) = bpm_window(centre, diff)
        return low <= theirs_x100 && theirs_x100 <= high
    }
    if within(centre_x100) { return true }
    if !half_double { return false }
    return within(round_even(Double(centre_x100) * 0.5)) || within(sat_mul(centre_x100, 2))
}
func keys_go_together(_ a: UInt32, _ b: UInt32) -> Bool {
    if a == .max || b == .max { return false }
    if a == b || a ^ 1 == b { return true }
    return a & 1 == b & 1 && ((a + 2) % 24 == b || (b + 2) % 24 == a)
}
extension Library {
    public func related_rows(_ track: Row, _ criterion: RelatedCriterion) -> [Row] {
        let at = Int(track)
        guard at < len() else { return [] }
        let rows = (0..<len()).compactMap(Row.init(exactly:))
        switch criterion {
        case .bpmAndKey:
            let bpm = bpm_x100.at(at) ?? 0
            let key = self.key.at(at).map { camelot_rank(keys.name($0)) } ?? .max
            if bpm == 0 && key == .max { return [] }
            return rows.filter { r in
                if r == track { return false }
                let other = Int(r)
                if bpm != 0 && !related_bpm_matches(bpm, bpm_x100.at(other) ?? 0, 5, true) { return false }
                if key != .max && !keys_go_together(key, self.key.at(other).map { camelot_rank(keys.name($0)) } ?? .max)
                {
                    return false
                }
                return true
            }
        case .sameGenreRecent:
            let genre = self.genre.at(at) ?? 0
            if genre == 0 { return [] }
            let since = SmartDate.today().days_ago(30).days()
            return rows.filter { r in
                r != track && self.genre.at(Int(r)) == genre
                    && SmartDate.parse(date_added.get(Int(r))).map { $0.days() >= since } ?? false
            }
        case .sameArtist:
            let artist = self.artist.at(at) ?? 0
            if artist == 0 { return [] }
            return rows.filter { $0 != track && self.artist.at(Int($0)) == artist }
        case .suggestion:
            let followed = followed_in_history(track)
            return followed.isEmpty ? related_rows(track, .bpmAndKey) : followed
        }
    }
    func followed_in_history(_ track: Row) -> [Row] {
        var count: [Row: (UInt32, Int)] = [:]
        for (session, members) in histories().members.enumerated() {
            for (a, b) in zip(members, members.dropFirst()) where a == track && b != track {
                var entry = count[b] ?? (0, 0)
                entry.0 += 1
                entry.1 = session
                count[b] = entry
            }
        }
        return count.sorted { a, b in a.value == b.value ? a.key < b.key : a.value > b.value }.map(\.key)
    }
}
