import Foundation

// Node `Buffer`·`Uint8Array`는 모두 `[UInt8]`로 옮긴다(docs/porting-guide.md).
// 읽기는 Node처럼 범위를 벗어나면 `BufferRangeError`를 던진다. 위치는 늘 컬렉션 처음부터 센다
// (ArraySlice여도 startIndex 기준).

extension RandomAccessCollection where Element == UInt8, Index == Int {
    @inline(__always)
    private func checkOffset(_ offset: Int, _ size: Int) throws(BufferRangeError) {
        guard offset >= 0, offset + size <= count else {
            throw BufferRangeError.offset(offset, size: size, length: count)
        }
    }

    @inline(__always)
    private func byte(_ offset: Int) -> UInt64 {
        UInt64(self[startIndex + offset])
    }

    public func readUInt8(_ offset: Int = 0) throws(BufferRangeError) -> Int {
        try checkOffset(offset, 1)
        return Int(self[startIndex + offset])
    }

    public func readInt8(_ offset: Int = 0) throws(BufferRangeError) -> Int {
        try checkOffset(offset, 1)
        return Int(Int8(bitPattern: self[startIndex + offset]))
    }

    public func readUInt16BE(_ offset: Int = 0) throws(BufferRangeError) -> Int {
        try checkOffset(offset, 2)
        return Int(byte(offset) << 8 | byte(offset + 1))
    }

    public func readUInt16LE(_ offset: Int = 0) throws(BufferRangeError) -> Int {
        try checkOffset(offset, 2)
        return Int(byte(offset) | byte(offset + 1) << 8)
    }

    public func readInt16BE(_ offset: Int = 0) throws(BufferRangeError) -> Int {
        Int(Int16(truncatingIfNeeded: try readUInt16BE(offset)))
    }

    public func readInt16LE(_ offset: Int = 0) throws(BufferRangeError) -> Int {
        Int(Int16(truncatingIfNeeded: try readUInt16LE(offset)))
    }

    public func readUInt24BE(_ offset: Int = 0) throws(BufferRangeError) -> Int {
        try checkOffset(offset, 3)
        return Int(byte(offset) << 16 | byte(offset + 1) << 8 | byte(offset + 2))
    }

    public func readUInt32BE(_ offset: Int = 0) throws(BufferRangeError) -> Int {
        try checkOffset(offset, 4)
        return Int(byte(offset) << 24 | byte(offset + 1) << 16 | byte(offset + 2) << 8 | byte(offset + 3))
    }

    public func readUInt32LE(_ offset: Int = 0) throws(BufferRangeError) -> Int {
        try checkOffset(offset, 4)
        return Int(byte(offset) | byte(offset + 1) << 8 | byte(offset + 2) << 16 | byte(offset + 3) << 24)
    }

    public func readInt32BE(_ offset: Int = 0) throws(BufferRangeError) -> Int {
        Int(Int32(truncatingIfNeeded: try readUInt32BE(offset)))
    }

    public func readInt32LE(_ offset: Int = 0) throws(BufferRangeError) -> Int {
        Int(Int32(truncatingIfNeeded: try readUInt32LE(offset)))
    }

    /// `readBigUInt64BE`
    public func readBigUInt64BE(_ offset: Int = 0) throws(BufferRangeError) -> UInt64 {
        try checkOffset(offset, 8)
        var value: UInt64 = 0
        for i in 0..<8 { value = value << 8 | byte(offset + i) }
        return value
    }

    /// `readBigUInt64LE`
    public func readBigUInt64LE(_ offset: Int = 0) throws(BufferRangeError) -> UInt64 {
        try checkOffset(offset, 8)
        var value: UInt64 = 0
        for i in (0..<8).reversed() { value = value << 8 | byte(offset + i) }
        return value
    }

    public func readBigInt64BE(_ offset: Int = 0) throws(BufferRangeError) -> Int64 {
        Int64(bitPattern: try readBigUInt64BE(offset))
    }

    public func readFloatBE(_ offset: Int = 0) throws(BufferRangeError) -> Double {
        Double(Float(bitPattern: UInt32(try readUInt32BE(offset))))
    }

    public func readFloatLE(_ offset: Int = 0) throws(BufferRangeError) -> Double {
        Double(Float(bitPattern: UInt32(try readUInt32LE(offset))))
    }

    public func readDoubleBE(_ offset: Int = 0) throws(BufferRangeError) -> Double {
        Double(bitPattern: try readBigUInt64BE(offset))
    }

    public func readDoubleLE(_ offset: Int = 0) throws(BufferRangeError) -> Double {
        Double(bitPattern: try readBigUInt64LE(offset))
    }

    /// Node `buf.subarray(start, end)`·`buf.slice(start, end)`. 범위는 Node처럼 잘라 맞추고(음수는 끝에서 센다)
    /// 처음부터 세는 새 배열을 돌려준다.
    public func subarray(_ start: Int = 0, _ end: Int? = nil) -> [UInt8] {
        let length = count
        func clamp(_ value: Int) -> Int {
            value < 0 ? Swift.max(length + value, 0) : Swift.min(value, length)
        }
        let lower = clamp(start)
        let upper = clamp(end ?? length)
        guard lower < upper else { return [] }
        return Array(self[(startIndex + lower)..<(startIndex + upper)])
    }

    /// Node `buf.toString(encoding, start, end)`.
    public func toString(_ encoding: NodeEncoding = .utf8, _ start: Int = 0, _ end: Int? = nil) -> String {
        let bytes = subarray(start, end)
        return encoding.decode(bytes)
    }

    /// Node `buf.indexOf(byte, byteOffset)`. 없으면 -1.
    public func indexOf(_ value: UInt8, _ byteOffset: Int = 0) -> Int {
        var i = Swift.max(byteOffset < 0 ? count + byteOffset : byteOffset, 0)
        while i < count {
            if self[startIndex + i] == value { return i }
            i += 1
        }
        return -1
    }

    /// Node `buf.indexOf(value, byteOffset)`에서 `value`가 바이트 열(`Buffer`·`Uint8Array`)일 때. 없으면 -1.
    /// 빈 `value`는 Node처럼 `byteOffset`(길이를 넘으면 길이)을 돌려준다.
    public func indexOf<Needle: Collection>(_ value: Needle, _ byteOffset: Int = 0) -> Int
    where Needle.Element == UInt8 {
        let needle = Array(value)
        var start = byteOffset < 0 ? Swift.max(count + byteOffset, 0) : byteOffset
        if needle.isEmpty { return Swift.min(start, count) }
        while start + needle.count <= count {
            var matched = true
            for j in 0..<needle.count where self[startIndex + start + j] != needle[j] {
                matched = false
                break
            }
            if matched { return start }
            start += 1
        }
        return -1
    }

    /// JS `buf[index]`. 범위 밖(음수 포함)이면 원본의 `undefined` 대신 nil.
    public func at(_ index: Int) -> Int? {
        guard index >= 0, index < count else { return nil }
        return Int(self[startIndex + index])
    }

    /// Node `buf.equals(other)`.
    public func bytesEqual<Other: RandomAccessCollection>(_ other: Other) -> Bool
    where Other.Element == UInt8 {
        elementsEqual(other)
    }
}

extension Array where Element == UInt8 {
    /// `Buffer.alloc(size)`
    public static func alloc(_ size: Int, fill: UInt8 = 0) -> [UInt8] {
        [UInt8](repeating: fill, count: size)
    }

    /// `Buffer.from(string, encoding)`
    public init(_ string: String, encoding: NodeEncoding) {
        self = encoding.encode(string)
    }

    /// `Buffer.concat(list)`
    public static func concat(_ list: [[UInt8]]) -> [UInt8] {
        list.flatMap { $0 }
    }

    /// `buf.set(source, offset)`(`Uint8Array.prototype.set`). 넘치면 멈춘다(Node는 RangeError).
    public mutating func set<Source: Collection>(_ source: Source, _ offset: Int = 0) where Source.Element == UInt8 {
        precondition(offset >= 0 && offset + source.count <= count, "offset is out of bounds")
        replaceSubrange(offset..<(offset + source.count), with: source)
    }

    // 쓰기는 우리가 만든 고정 크기 버퍼에만 하므로 범위를 넘으면 멈춘다.

    public mutating func writeUInt8(_ value: Int, _ offset: Int = 0) {
        self[offset] = UInt8(truncatingIfNeeded: value)
    }

    public mutating func writeUInt16BE(_ value: Int, _ offset: Int = 0) {
        self[offset] = UInt8(truncatingIfNeeded: value >> 8)
        self[offset + 1] = UInt8(truncatingIfNeeded: value)
    }

    public mutating func writeUInt16LE(_ value: Int, _ offset: Int = 0) {
        self[offset] = UInt8(truncatingIfNeeded: value)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    public mutating func writeUInt32BE(_ value: Int, _ offset: Int = 0) {
        for i in 0..<4 { self[offset + i] = UInt8(truncatingIfNeeded: value >> (24 - 8 * i)) }
    }

    public mutating func writeUInt32LE(_ value: Int, _ offset: Int = 0) {
        for i in 0..<4 { self[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
    }

    public mutating func writeInt32BE(_ value: Int, _ offset: Int = 0) {
        writeUInt32BE(value, offset)
    }

    public mutating func writeBigUInt64BE(_ value: UInt64, _ offset: Int = 0) {
        for i in 0..<8 { self[offset + i] = UInt8(truncatingIfNeeded: value >> (56 - 8 * UInt64(i))) }
    }

    /// `buf.fill(value, start, end)`
    public mutating func fill(_ value: UInt8, _ start: Int = 0, _ end: Int? = nil) {
        let upper = Swift.min(end ?? count, count)
        guard start < upper else { return }
        for i in start..<upper { self[i] = value }
    }

    /// Foundation 경계(파일·소켓)에서 쓴다.
    public var data: Data { Data(self) }
}

extension Data {
    /// Foundation 경계에서 `[UInt8]`로 바꾼다.
    public var bytes: [UInt8] { [UInt8](self) }
}

/// Node `BufferEncoding`과 iconv-lite에서 쓰는 인코딩.
public enum NodeEncoding: Sendable {
    case ascii
    case latin1
    case utf8
    case utf16le
    case utf16be
    case hex

    func decode(_ bytes: [UInt8]) -> String {
        switch self {
        case .ascii:
            // Node는 'ascii'를 읽을 때 상위 비트를 버린다.
            return String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0 & 0x7f) }))
        case .latin1:
            return String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
        case .utf8:
            return String(decoding: bytes, as: UTF8.self)
        case .utf16le:
            let units = stride(from: 0, to: bytes.count - 1, by: 2).map {
                UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8
            }
            return String(decoding: units, as: UTF16.self)
        case .utf16be:
            let units = stride(from: 0, to: bytes.count - 1, by: 2).map {
                UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1])
            }
            return String(decoding: units, as: UTF16.self)
        case .hex:
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    func encode(_ string: String) -> [UInt8] {
        switch self {
        case .ascii, .latin1:
            // Node는 UTF-16 코드 단위의 아래 8비트를 쓴다.
            return string.utf16.map { UInt8(truncatingIfNeeded: $0) }
        case .utf8:
            return Array(string.utf8)
        case .utf16le:
            return string.utf16.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }
        case .utf16be:
            return string.utf16.flatMap { [UInt8(truncatingIfNeeded: $0 >> 8), UInt8(truncatingIfNeeded: $0)] }
        case .hex:
            var result: [UInt8] = []
            var chars = Array(string.utf8)
            if chars.count % 2 == 1 { chars.removeLast() }
            var i = 0
            while i + 1 < chars.count {
                guard let byte = UInt8(String(decoding: chars[i...i + 1], as: UTF8.self), radix: 16) else { break }
                result.append(byte)
                i += 2
            }
            return result
        }
    }
}
