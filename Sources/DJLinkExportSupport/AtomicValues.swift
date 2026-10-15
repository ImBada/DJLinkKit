// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// rbxport의 Arc<Atomic*> 공유 상태를 직렬 DJLinkActor 위의 참조로 옮긴다.
import DJLinkKit

@DJLinkActor
public final class AtomicUInt8 {
    public var value: UInt8
    public init(_ value: UInt8 = 0) { self.value = value }
    public func load() -> UInt8 { value }
    public func store(_ value: UInt8) { self.value = value }
}

@DJLinkActor
public final class AtomicBool {
    public var value: Bool
    public init(_ value: Bool = false) { self.value = value }
    public func load() -> Bool { value }
    public func store(_ value: Bool) { self.value = value }
}
