// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/src/grid.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import DJLinkKit

public enum Grid {
    public enum Edit: Equatable, Sendable {
        case nudge(Int32), double, halve
        case downbeat(time_ms: UInt32), tempo(bpm_x100: UInt16, anchor_ms: UInt32), tap(bpm: Double, anchor_ms: UInt32)
        case stretch(by_ms: Int32, time_ms: UInt32), align(time_ms: UInt32)
    }
    public static let MIN_BPM_X100: UInt16 = 4000, MAX_BPM_X100: UInt16 = 49900
    private static let MAX_BEATS = 1 << 20
    public static func tempo_x100(_ beats: [Beat]) -> UInt16 { beats.first?.tempo_x100 ?? 0 }
    public static func nearest_index(_ beats: [Beat], _ time_ms: UInt32) -> Int? {
        var at: Int?
        var distance = UInt64.max
        for (i, beat) in beats.enumerated() {
            let d = beat.time_ms > time_ms ? beat.time_ms - time_ms : time_ms - beat.time_ms
            if UInt64(d) < distance {
                at = i
                distance = UInt64(d)
            }
        }
        return at
    }
    private static func start_index(_ beats: [Beat], _ from_ms: UInt32?) -> Int {
        from_ms.flatMap { nearest_index(beats, $0) } ?? 0
    }
    private static func number(_ offset: Int64) -> UInt16 { UInt16((offset % 4 + 4) % 4 + 1) }
    private static func renumber(_ beats: inout [Beat], _ at: Int, _ value: UInt16) {
        for i in beats.indices { beats[i].beat_number = number(Int64(i) - Int64(at) + Int64(value) - 1) }
    }
    private static func rounded(_ value: Double) -> UInt32 {
        UInt32(min(max(value.rounded(.toNearestOrEven), 0), Double(UInt32.max)))
    }
    private static func sub(_ a: UInt32, _ b: UInt32) -> UInt32 { a >= b ? a - b : 0 }
    private static func add(_ a: UInt32, _ b: UInt32) -> UInt32 {
        let (v, o) = a.addingReportingOverflow(b)
        return o ? .max : v
    }
    private static func stretch_interval(_ beats: [Beat], _ start: Int, _ time_ms: UInt32, _ by_ms: Int32) -> Double? {
        guard beats.indices.contains(start), var target = nearest_index(beats, time_ms) else { return nil }
        let first = beats[start]
        if target == start && time_ms >= first.time_ms { target += 1 }
        guard target > start, beats.indices.contains(target), let count = UInt32(exactly: target - start) else {
            return nil
        }
        return (Double(beats[target].time_ms) + Double(min(max(by_ms, -120), 120)) - Double(first.time_ms))
            / Double(count)
    }
    public static func validate(_ beats: [Beat], _ from_ms: UInt32?, _ edit: Edit) throws {
        let tail = beats.dropFirst(start_index(beats, from_ms))
        let valid: Bool
        switch edit {
        case .double: valid = tail.allSatisfy { (2000...24950).contains($0.tempo_x100) }
        case .halve: valid = tail.allSatisfy { $0.tempo_x100 >= 8000 }
        case let .tempo(bpm, _): valid = (MIN_BPM_X100...MAX_BPM_X100).contains(bpm)
        case let .tap(bpm, _): valid = bpm >= 40 && bpm < 500
        case let .stretch(by, ms):
            valid =
                stretch_interval(beats, start_index(beats, from_ms), ms, by).map {
                    (60000.0 / 499.0...1500.0).contains($0)
                } ?? true
        default: valid = true
        }
        if !valid { throw DJLinkError("The beat-grid tempo must be between 40 and 499 BPM.") }
    }
    public static func is_dynamic_from(_ beats: [Beat], _ from_ms: UInt32?) -> Bool {
        let tail = beats.dropFirst(start_index(beats, from_ms))
        guard let first = tail.first else { return false }
        return tail.contains { $0.tempo_x100 != first.tempo_x100 }
    }
    private static func fit(_ input: [Beat], _ end_ms: UInt32) -> [Beat] {
        var beats = input.filter { $0.time_ms <= end_ms }
        guard !beats.isEmpty else { return beats }
        if beats.count == 1 {
            let first = beats[0]
            if first.time_ms == 0 { return beats }
            while beats.count < MAX_BEATS {
                let last = beats[beats.count - 1]
                let (next, overflow) = last.time_ms.addingReportingOverflow(first.time_ms)
                if overflow || next > end_ms { break }
                var b = last
                b.time_ms = next
                b.beat_number = number(Int64(last.beat_number))
                beats.append(b)
            }
            return beats
        }
        let interval = sub(beats[1].time_ms, beats[0].time_ms)
        if interval > 0 && beats[0].time_ms >= interval {
            var first = beats[0]
            first.time_ms -= interval
            first.beat_number = number(Int64(first.beat_number) - 2)
            beats.insert(first, at: 0)
        }
        while beats.count < MAX_BEATS {
            let n = beats.count
            let last = beats[n - 1]
            let interval = sub(last.time_ms, beats[n - 2].time_ms)
            let (next, overflow) = last.time_ms.addingReportingOverflow(interval)
            if overflow || interval == 0 || next > end_ms { break }
            var b = last
            b.time_ms = next
            b.beat_number = number(Int64(last.beat_number))
            beats.append(b)
        }
        return beats
    }
    private static func move_by(_ beats: [Beat], _ start: Int, _ by: Int64, _ end_ms: UInt32) -> [Beat] {
        fit(
            beats.enumerated().compactMap { i, b in
                guard let time = UInt32(exactly: Int64(b.time_ms) + (i >= start ? by : 0)), time <= end_ms else {
                    return nil
                }
                var out = b
                out.time_ms = time
                return out
            }, end_ms)
    }
    private static func respace(_ beats: [Beat], _ start: Int, _ interval: Double, _ bpm: UInt16, _ end_ms: UInt32)
        -> [Beat]
    {
        let anchor = beats[start].time_ms
        return fit(
            beats.enumerated().map { i, b in
                if i < start { return b }
                var out = b
                out.time_ms = add(anchor, rounded(Double(UInt32(exactly: i - start) ?? .max) * interval))
                out.tempo_x100 = bpm
                return out
            }, end_ms)
    }
    public static func apply_with_duration(_ beats: [Beat], _ from_ms: UInt32?, _ edit: Edit, _ end_ms: UInt32)
        -> [Beat]
    {
        guard !beats.isEmpty else { return beats }
        do { try validate(beats, from_ms, edit) } catch { return beats }
        let start = start_index(beats, from_ms)
        switch edit {
        case let .nudge(ms): return move_by(beats, start, Int64(ms), end_ms)
        case let .align(time_ms), let .downbeat(time_ms):
            let at = nearest_index(beats, time_ms) ?? 0
            var out = move_by(beats, start, Int64(time_ms) - Int64(beats[at].time_ms), end_ms)
            if case .downbeat = edit, let at = nearest_index(out, time_ms) { renumber(&out, at, 1) }
            return out
        case let .stretch(by, ms):
            guard let interval = stretch_interval(beats, start, ms, by) else { return beats }
            let bpm = UInt16(exactly: rounded(6000000.0 / interval)) ?? MAX_BPM_X100
            return respace(beats, start, interval, bpm, end_ms)
        case let .tempo(bpm, _): return respace(beats, start, 6000000.0 / Double(bpm), bpm, end_ms)
        case let .tap(bpm, anchor):
            let tempo = UInt16(exactly: rounded(bpm * 100)) ?? MAX_BPM_X100
            let out = respace(beats, start, 60000.0 / bpm, tempo, end_ms)
            return apply_with_duration(out, from_ms, .downbeat(time_ms: anchor), end_ms)
        case .double:
            var out = Array(beats.prefix(start))
            for i in start..<beats.count {
                let beat = beats[i]
                let tempo = beat.tempo_x100 * 2
                var b = beat
                b.tempo_x100 = tempo
                out.append(b)
                let interval =
                    i + 1 < beats.count
                    ? sub(beats[i + 1].time_ms, beat.time_ms)
                    : i > start ? sub(beat.time_ms, beats[i - 1].time_ms) : sub(end_ms, beat.time_ms)
                if interval > 1 {
                    b.time_ms = add(beat.time_ms, interval / 2)
                    out.append(b)
                }
            }
            renumber(&out, start, beats[start].beat_number % 2 == 1 ? 1 : 3)
            return fit(out, end_ms)
        case .halve:
            var out = Array(beats.prefix(start))
            let original = beats[start].beat_number
            let skip = original % 2 == 0 ? 1 : 0
            for at in stride(from: start + skip, to: beats.count, by: 2) {
                var b = beats[at]
                b.tempo_x100 /= 2
                out.append(b)
            }
            renumber(&out, start, original == 1 || original == 4 ? 1 : 4)
            return fit(out, end_ms)
        }
    }
    public static func apply(_ beats: [Beat], _ edit: Edit) -> [Beat] { apply_from(beats, nil, edit) }
    public static func apply_from(_ beats: [Beat], _ from_ms: UInt32?, _ edit: Edit) -> [Beat] {
        apply_with_duration(beats, from_ms, edit, beats.last?.time_ms ?? 0)
    }
}
