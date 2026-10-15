// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-anlz/src/vocal.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
public let VOCAL_FRAME_MS = 1000.0 * 2048.0 / 44100.0
public let VOCAL_MAX: UInt8 = 4
extension Section {
    public func as_vocals() -> [UInt8]? {
        guard tag == Tag("PVDI"), header.count >= 12, Int(anlzBE32(header, 8)) == payload.count else { return nil }
        return payload
    }
}
extension Anlz { public func vocals() -> [UInt8]? { sections.lazy.compactMap { $0.as_vocals() }.first } }
