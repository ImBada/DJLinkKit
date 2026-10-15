// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-dbserver/src/filter.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

public let MY_TAG_AND: UInt8 = 16
public let MY_TAG_OR: UInt8 = 17
let MY_TAG_FILTER_LIMIT = 50
let MY_TAG_TICK_LIMIT = 4096
public struct MyTagCondition: Equatable, Sendable {
    public var flags: UInt8 = 0
    public var mode: UInt8 = MY_TAG_AND
    public var tags: [UInt32] = []
    public init(flags: UInt8 = 0, mode: UInt8 = MY_TAG_AND, tags: [UInt32] = []) {
        self.flags = flags
        self.mode = mode
        self.tags = tags
    }
    public func enabled() -> Bool { flags & 1 != 0 }
    func applies() -> Bool { enabled() && (1...MY_TAG_FILTER_LIMIT).contains(tags.count) }
    func matches(_ track: [UInt32]) -> Bool {
        guard !track.isEmpty else { return false }
        switch mode {
        case MY_TAG_AND: return tags.allSatisfy { track.contains($0) }
        case MY_TAG_OR: return tags.contains { track.contains($0) }
        default: return false
        }
    }
}
private struct Condition: Sendable {
    var flags: UInt8
    var op: UInt8
    var values: [UInt32]
}
public struct TrackFilter: Sendable {
    public var enabled = false
    private var conditions: [UInt16: Condition] = [
        6: Condition(flags: 0, op: 6, values: [12000, 12000]), 7: Condition(flags: 0, op: 0, values: [0, 0]),
        12: Condition(flags: 0, op: 17, values: [1]), 15: Condition(flags: 0, op: 17, values: [0]),
    ]
    private var my_tags: [UInt32: MyTagCondition] = [:]
    public init() {}
    public mutating func update(_ property: UInt32, _ bytes: [UInt8]) -> Bool {
        guard let property = UInt16(exactly: property), conditions[property] != nil, bytes.count >= 4 else {
            return false
        }
        let count = Int(le16(bytes, 2))
        let op = bytes[1]
        guard count <= 24, bytes.count == 4 + count * 4, op <= 7 || op == 16 || op == 17 else { return false }
        conditions[property] = Condition(flags: bytes[0], op: op, values: (0..<count).map { le32(bytes, 4 + $0 * 4) })
        return true
    }
    public func my_tag_condition(_ category: UInt32) -> MyTagCondition { my_tags[category] ?? MyTagCondition() }
    public mutating func set_my_tag_condition(_ category: UInt32, _ flags: UInt8, _ mode: UInt8) {
        var c = my_tag_condition(category)
        c.flags = flags
        c.mode = mode
        my_tags[category] = c
    }
    public mutating func tick_my_tag(_ category: UInt32, _ tag: UInt32, _ on: Bool) -> Bool {
        var c = my_tag_condition(category)
        if !on {
            if let at = c.tags.firstIndex(of: tag) { c.tags.remove(at: at) }
            my_tags[category] = c
            return true
        }
        if c.tags.contains(tag) { return true }
        guard c.tags.count < MY_TAG_TICK_LIMIT else { return false }
        c.tags.append(tag)
        my_tags[category] = c
        return true
    }
    public mutating func clear_my_tags(_ category: UInt32) {
        var c = my_tag_condition(category)
        c.tags = []
        my_tags[category] = c
    }
    public func has_my_tag_conditions() -> Bool { my_tags.values.contains { $0.applies() } }
    public func matches_my_tags(_ track: [UInt32]) -> Bool {
        my_tags.values.filter { $0.applies() }.allSatisfy { $0.matches(track) }
    }
    public func encode() -> [UInt8] {
        var out: [UInt8] = []
        for property in conditions.keys.sorted() {
            let c = conditions[property]!
            let payload_len = UInt32(20 + c.values.count * 4)
            out +=
                dbLE(payload_len + 8) + dbLE(UInt32(1)) + Array("FCND".utf8) + dbBE(UInt32(20)) + dbBE(payload_len)
                + dbBE(UInt16(0)) + dbBE(property) + [c.flags, c.op] + dbBE(UInt16(c.values.count))
            for value in c.values { out += dbBE(value) }
        }
        return out
    }
    public func matches(_ bpm: UInt32, _ key: UInt32, _ rating: UInt32, _ colour: UInt32) -> Bool {
        if !enabled { return true }
        return conditions.allSatisfy { property, c in
            if c.flags & 1 == 0 { return true }
            let value: UInt32
            switch property {
            case 6: value = bpm
            case 7: value = rating
            case 12: value = key
            case 15: value = colour
            default: return true
            }
            guard let first = c.values.first else { return false }
            let second = c.values.count > 1 ? c.values[1] : 0
            let inside = value >= first && value <= second
            switch c.op {
            case 0: return value == first
            case 1: return value != first
            case 2: return value > first
            case 3: return value >= first
            case 4: return value < first
            case 5: return value <= first
            case 6: return inside
            case 7: return !inside
            case 16: return c.values.allSatisfy { $0 == value }
            case 17: return c.values.contains(value)
            default: return false
            }
        }
    }
}
