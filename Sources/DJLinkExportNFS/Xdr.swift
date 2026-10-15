// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-nfs/src/xdr.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

public enum Xdr {
    public static let MAX_FIELD: UInt32 = 1 << 20
    public static func padded(_ len: Int) -> Int { ((len + 3) / 4) * 4 }
    public enum XdrError: Error, Equatable, Sendable, CustomStringConvertible {
        case short(at: Int, wanted: Int, len: Int)
        case absurd(UInt32)
        case oddUtf16(Int)
        public var description: String {
            switch self {
            case let .short(at, wanted, len): return "wanted \(wanted) bytes at offset \(at), buffer holds \(len)"
            case let .absurd(len): return "declared length \(len) is larger than any message we accept"
            case let .oddUtf16(len): return "a UTF-16 name had an odd byte length (\(len))"
            }
        }
    }
    // 원본의 가변 커서를 참조로 표현하여 임시 reader에도 같은 순서로 읽는다.
    public final class Reader {
        private let bytes: [UInt8]
        private var at = 0
        public init(_ bytes: [UInt8]) { self.bytes = bytes }
        public static func new(_ bytes: [UInt8]) -> Reader { Reader(bytes) }
        public func position() -> Int { at }
        public func remaining() -> Int { bytes.count - at }
        private func take(_ len: Int) throws -> [UInt8] {
            let (end, overflow) = at.addingReportingOverflow(len)
            guard !overflow, len >= 0, end <= bytes.count else {
                throw XdrError.short(at: at, wanted: len, len: bytes.count)
            }
            let out = Array(bytes[at..<end])
            at = end
            return out
        }
        public func u32() throws -> UInt32 { try take(4).reduce(0) { ($0 << 8) | UInt32($1) } }
        public func opaque_fixed(_ len: Int) throws -> [UInt8] {
            let out = try take(len)
            _ = try take(Xdr.padded(len) - len)
            return out
        }
        public func opaque() throws -> [UInt8] {
            let len = try u32()
            guard len <= MAX_FIELD else { throw XdrError.absurd(len) }
            return try opaque_fixed(Int(len))
        }
        public func string() throws -> String { String(decoding: try opaque(), as: UTF8.self) }
        public func utf16() throws -> String {
            let raw = try opaque()
            guard raw.count % 2 == 0 else { throw XdrError.oddUtf16(raw.count) }
            let units = stride(from: 0, to: raw.count, by: 2).map { UInt16(raw[$0]) | (UInt16(raw[$0 + 1]) << 8) }
            return String(decoding: units, as: UTF16.self)
        }
        public func skip_opaque() throws { _ = try opaque() }
    }
    public final class Writer {
        private var bytes: [UInt8] = []
        public init() {}
        public static func new() -> Writer { Writer() }
        public static func with_capacity(_ capacity: Int) -> Writer {
            let writer = Writer()
            writer.bytes.reserveCapacity(capacity)
            return writer
        }
        public func into_bytes() -> [UInt8] { bytes }
        public func as_slice() -> [UInt8] { bytes }
        public func len() -> Int { bytes.count }
        public func is_empty() -> Bool { bytes.isEmpty }
        @discardableResult public func u32(_ value: UInt32) -> Writer {
            bytes += [
                UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value),
            ]
            return self
        }
        private func pad_to_boundary() {
            if bytes.count % 4 != 0 { bytes += Array(repeating: 0, count: 4 - bytes.count % 4) }
        }
        @discardableResult public func opaque_fixed(_ value: [UInt8]) -> Writer {
            bytes += value
            pad_to_boundary()
            return self
        }
        @discardableResult public func opaque(_ value: [UInt8]) -> Writer {
            u32(UInt32(exactly: value.count) ?? 0)
            return opaque_fixed(value)
        }
        @discardableResult public func string(_ text: String) -> Writer { opaque(Array(text.utf8)) }
        @discardableResult public func utf16(_ text: String) -> Writer {
            opaque(text.utf16.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] })
        }
        @discardableResult public func some() -> Writer { u32(1) }
        @discardableResult public func none() -> Writer { u32(0) }
    }
}
