// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/src/cues.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
public struct ExportCue: Equatable, Sendable, Codable {
    public var kind: UInt8, time_ms: UInt32, loop_time_ms: UInt32?, color_id: UInt8, color_code: UInt8, comment: String
    public var active_loop: Bool, loop_numerator: UInt16, loop_denominator: UInt16
    public init(
        kind: UInt8 = 0, time_ms: UInt32 = 0, loop_time_ms: UInt32? = nil, color_id: UInt8 = 0, color_code: UInt8 = 0,
        comment: String = "", active_loop: Bool = false, loop_numerator: UInt16 = 0, loop_denominator: UInt16 = 0
    ) {
        self.kind = kind
        self.time_ms = time_ms
        self.loop_time_ms = loop_time_ms
        self.color_id = color_id
        self.color_code = color_code
        self.comment = comment
        self.active_loop = active_loop
        self.loop_numerator = loop_numerator
        self.loop_denominator = loop_denominator
    }
    public func slot() -> UInt32 { UInt32(kind >= 5 ? kind - 1 : kind) }
}
public enum Cues {
    public static func sections(_ cues: [ExportCue], _ extended: Bool) -> [Section] {
        var out: [Section] = []
        for modern in [false, true] {
            if modern && !extended { continue }
            for hot in [true, false] {
                let list = cues.filter {
                    ($0.kind != 0) == hot && (modern || (extended ? hot && $0.slot() > 3 : $0.slot() <= 3))
                }
                let count = UInt16(exactly: list.count) ?? .max
                var header = [UInt8](repeating: 0, count: modern ? 8 : 12)
                anlzPut(&header, 0, UInt32(hot ? 1 : 0))
                anlzPut(&header, modern ? 4 : 6, count)
                if !modern { anlzPut(&header, 8, hot || count == 0 ? UInt32.max : UInt32(count - 1)) }
                var payload: [UInt8] = []
                for (index, cue) in list.prefix(Int(count)).enumerated() {
                    let comment: [UInt8] = cue.comment.isEmpty ? [] : cue.comment.utf16.flatMap(anlzBE) + [0, 0]
                    let length = modern ? 88 + comment.count : 56
                    var entry = [UInt8](repeating: 0, count: length)
                    entry.replaceSubrange(0..<4, with: Array((modern ? "PCP2" : "PCPT").utf8))
                    anlzPut(&entry, 4, UInt32(modern ? 16 : 28))
                    anlzPut(&entry, 8, UInt32(exactly: length) ?? .max)
                    anlzPut(&entry, 12, cue.slot())
                    let at = modern ? 16 : 28
                    entry[at] = cue.loop_time_ms != nil ? 2 : 1
                    entry.replaceSubrange((at + 1)..<(at + 4), with: [0, 3, 232])
                    anlzPut(&entry, at + 4, cue.time_ms)
                    anlzPut(&entry, at + 8, cue.loop_time_ms ?? .max)
                    if modern {
                        entry[28] = cue.color_id
                        entry[29] = 1
                        anlzPut(&entry, 36, cue.loop_numerator)
                        anlzPut(&entry, 38, cue.loop_denominator)
                        anlzPut(&entry, 40, UInt32(exactly: comment.count) ?? .max)
                        entry.replaceSubrange(44..<(44 + comment.count), with: comment)
                        entry[44 + comment.count] = cue.color_code
                        entry.replaceSubrange(
                            (45 + comment.count)..<(48 + comment.count), with: export_colour(cue.color_code, cue.slot())
                        )
                    } else {
                        anlzPut(&entry, 16, UInt32(cue.active_loop ? 4 : 0))
                        anlzPut(&entry, 20, UInt32(0x10000))
                        anlzPut(&entry, 24, hot || index == 0 ? UInt16.max : UInt16(exactly: index - 1) ?? .max)
                        anlzPut(
                            &entry, 26, hot || index + 1 == Int(count) ? UInt16.max : UInt16(exactly: index + 1) ?? .max
                        )
                    }
                    payload += entry
                }
                out.append(.new(modern ? "PCO2" : "PCOB", header, payload))
            }
        }
        return out
    }
    public static func export_colour(_ code: UInt8, _ slot: UInt32) -> [UInt8] {
        let defaultCode: UInt8
        switch slot {
        case 1, 9: defaultCode = 43
        case 2, 10: defaultCode = 8
        case 3, 11: defaultCode = 23
        case 4, 12: defaultCode = 60
        default: defaultCode = 0
        }
        return cue_colour(code == 0 ? defaultCode : code) ?? [0, 0, 0]
    }
}
