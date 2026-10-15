// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbxport/crates/rbl-db/src/export_info.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 원본의 공개 데이터 필드와 기본값을 그대로 옮겼다.
public struct MyTagRow: Equatable, Sendable {
    public var id: String
    public var seq: Int64
    public var name: String
    public var attribute: Int64
    public var parent: String
    public init(id: String = "", seq: Int64 = 0, name: String = "", attribute: Int64 = 0, parent: String = "") {
        self.id = id
        self.seq = seq
        self.name = name
        self.attribute = attribute
        self.parent = parent
    }
    public static func `default`() -> Self { Self() }
}
