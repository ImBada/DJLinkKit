// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/src/phrase.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
public enum Mood: Equatable, Sendable { case high, mid, low }
private func mood_of(_ raw: UInt16) -> Mood? {
    switch raw {
    case 1: return .high
    case 2: return .mid
    case 3: return .low
    default: return nil
    }
}
public struct Phrase: Equatable, Sendable {
    public var index: UInt16, beat: UInt16, kind: UInt16, label: String, fill_in: Bool, fill_in_beat: UInt16
    public init(index: UInt16, beat: UInt16, kind: UInt16, label: String, fill_in: Bool, fill_in_beat: UInt16) {
        self.index = index
        self.beat = beat
        self.kind = kind
        self.label = label
        self.fill_in = fill_in
        self.fill_in_beat = fill_in_beat
    }
}
public struct SongStructure: Equatable, Sendable {
    public var mood: Mood, end_beat: UInt16, bank: UInt8, phrases: [Phrase]
    public init(mood: Mood, end_beat: UInt16, bank: UInt8, phrases: [Phrase]) {
        self.mood = mood
        self.end_beat = end_beat
        self.bank = bank
        self.phrases = phrases
    }
}
public enum PhraseEdit: Equatable, Sendable { case cut(beat: UInt16), clear(beat: UInt16) }
private func label_for(_ mood: Mood, _ kind: UInt16, _ k1: UInt8, _ k2: UInt8, _ k3: UInt8) -> String {
    switch mood {
    case .high:
        switch kind {
        case 1: return k1 == 1 ? "INTRO 1" : "INTRO 2"
        case 2: return k2 == 0 ? (k3 == 0 ? "UP 1" : "UP 2") : "UP 3"
        case 3: return "DOWN"
        case 5: return k1 == 1 ? "CHORUS 1" : "CHORUS 2"
        case 6: return k1 == 1 ? "OUTRO 1" : "OUTRO 2"
        default: return ""
        }
    case .low:
        switch kind {
        case 1: return "INTRO"
        case 2...4: return "VERSE 1"
        case 5...7: return "VERSE 2"
        case 8: return "BRIDGE"
        case 9: return "CHORUS"
        case 10: return "OUTRO"
        default: return ""
        }
    case .mid:
        switch kind {
        case 1: return "INTRO"
        case 2...7: return "VERSE \(kind - 1)"
        case 8: return "BRIDGE"
        case 9: return "CHORUS"
        case 10: return "OUTRO"
        default: return ""
        }
    }
}
private let MASK_BASE: [UInt8] = [
    0xcb, 0xe1, 0xee, 0xfa, 0xe5, 0xee, 0xad, 0xee, 0xe9, 0xd2, 0xe9, 0xeb, 0xe1, 0xe9, 0xf3, 0xe8, 0xe9, 0xf4, 0xe1,
]
func phrase_unmask(_ body: inout [UInt8], _ count: UInt16) {
    let add = UInt8(truncatingIfNeeded: count)
    for at in body.indices { body[at] ^= MASK_BASE[at % MASK_BASE.count] &+ add }
}
extension Section {
    public func as_song_structure() -> SongStructure? {
        guard tag == Tag("PSSI") else { return nil }
        let raw = header + payload
        let len_entry = Int(anlzBE32(raw, 0))
        let len_entries = anlzBE16(raw, 4)
        guard len_entry >= 24, raw.count >= 6 else { return nil }
        var body = Array(raw.dropFirst(6))
        let mood: Mood
        if let found = mood_of(anlzBE16(body, 0)) {
            mood = found
        } else {
            phrase_unmask(&body, len_entries)
            guard let found = mood_of(anlzBE16(body, 0)) else { return nil }
            mood = found
        }
        guard body.count >= 14 else { return nil }
        let entries = Array(body.dropFirst(14))
        let count = min(Int(len_entries), entries.count / len_entry)
        let phrases = (0..<count).map { i -> Phrase in
            let entry = Array(entries[(i * len_entry)..<((i + 1) * len_entry)])
            let kind = anlzBE16(entry, 4)
            return Phrase(
                index: anlzBE16(entry, 0), beat: anlzBE16(entry, 2), kind: kind,
                label: label_for(mood, kind, anlzByte(entry, 7), anlzByte(entry, 9), anlzByte(entry, 0x13)),
                fill_in: anlzByte(entry, 0x15) != 0, fill_in_beat: anlzBE16(entry, 0x16))
        }
        return SongStructure(mood: mood, end_beat: anlzBE16(body, 8), bank: anlzByte(body, 0x0c), phrases: phrases)
    }
    public func with_phrase_edit(_ edit: PhraseEdit) -> Section? {
        guard tag == Tag("PSSI") else { return nil }
        let raw = header + payload
        let len_entry = Int(anlzBE32(raw, 0))
        let len_entries = anlzBE16(raw, 4)
        guard len_entry >= 24, raw.count >= 6 else { return nil }
        var body = Array(raw.dropFirst(6))
        if mood_of(anlzBE16(body, 0)) == nil {
            phrase_unmask(&body, len_entries)
            guard mood_of(anlzBE16(body, 0)) != nil else { return nil }
        }
        guard body.count >= 14 else { return nil }
        let preamble = Array(body.prefix(14))
        let count = min(Int(len_entries), (body.count - 14) / len_entry)
        var entries = (0..<count).map { Array(body[(14 + $0 * len_entry)..<(14 + ($0 + 1) * len_entry)]) }
        let beat: UInt16
        switch edit {
        case let .cut(b), let .clear(b): beat = b
        }
        guard let at = entries.lastIndex(where: { anlzBE16($0, 2) <= beat }) else { return nil }
        switch edit {
        case .cut:
            guard anlzBE16(entries[at], 2) != beat else { return nil }
            var second = entries[at]
            anlzPut(&second, 2, beat)
            entries.insert(second, at: at + 1)
        case .clear: entries.remove(at: at)
        }
        for i in entries.indices { anlzPut(&entries[i], 0, UInt16(exactly: i + 1) ?? .max) }
        let out =
            Array(raw.prefix(4)) + anlzBE(UInt16(exactly: entries.count) ?? .max) + preamble + entries.flatMap { $0 }
        let split = min(header.count, out.count)
        return .new("PSSI", Array(out.prefix(split)), Array(out.dropFirst(split)))
    }
    public func with_export_phrase_mask() -> Section {
        guard tag == Tag("PSSI") else { return self }
        var raw = header + payload
        guard raw.count >= 8, mood_of(anlzBE16(raw, 6)) != nil else { return self }
        let count = anlzBE16(raw, 4)
        var body = Array(raw.dropFirst(6))
        phrase_unmask(&body, count)
        raw.replaceSubrange(6..., with: body)
        return .new("PSSI", Array(raw.prefix(header.count)), Array(raw.dropFirst(header.count)))
    }
}
extension Anlz {
    public func with_phrase_edit(_ edit: PhraseEdit) -> [UInt8]? {
        guard let at = sections.firstIndex(where: { $0.tag == Tag("PSSI") }),
            let edited = sections[at].with_phrase_edit(edit)
        else { return nil }
        var copy = sections
        copy[at] = edited
        return Write.render(header_extra, copy)
    }
    public func song_structure() -> SongStructure? { sections.lazy.compactMap { $0.as_song_structure() }.first }
    public func phrases() -> [Phrase]? { song_structure()?.phrases }
}
