// 원본 src/remotedb/fields.ts. 표준 UInt8·UInt16·UInt32·String과 충돌하는 형만 접두사를 붙인다.
public enum FieldType: UInt8, Sendable {
    case uint8 = 0x0f, uint16 = 0x10, uint32 = 0x11, binary = 0x14, string = 0x26
    public var jsName: String {
        switch self {
        case .uint8: "UInt8"
        case .uint16: "UInt16"
        case .uint32: "UInt32"
        case .binary: "Binary"
        case .string: "String"
        }
    }
}
public protocol BaseField: Sendable {
    var type: FieldType { get }
    var data: [UInt8] { get }
    var buffer: [UInt8] { get }
}
public typealias Field = any BaseField
public protocol NumberField: BaseField { var value: Int { get } }
public protocol StringField: BaseField { var value: String { get } }
public protocol BinaryField: BaseField { var value: [UInt8] { get } }
public struct RemoteDBUInt8: NumberField {
    public static let type = FieldType.uint8
    public var type: FieldType { Self.type }
    public let value: Int
    public let data: [UInt8]
    public init(_ value: Int) {
        self.value = value
        self.data = [UInt8(value)]
    }
    public init(_ data: [UInt8]) throws {
        value = try data.readUInt8()
        self.data = data
    }
    public var buffer: [UInt8] { [type.rawValue] + data }
}
public struct RemoteDBUInt16: NumberField {
    public static let type = FieldType.uint16
    public var type: FieldType { Self.type }
    public let value: Int
    public let data: [UInt8]
    public init(_ value: Int) {
        self.value = value
        var data = [UInt8].alloc(2)
        data.writeUInt16BE(value)
        self.data = data
    }
    public init(_ data: [UInt8]) throws {
        value = try data.readUInt16BE()
        self.data = data
    }
    public var buffer: [UInt8] { [type.rawValue] + data }
}
public struct RemoteDBUInt32: NumberField {
    public static let type = FieldType.uint32
    public var type: FieldType { Self.type }
    public let value: Int
    public let data: [UInt8]
    public init(_ value: Int) {
        self.value = value
        var data = [UInt8].alloc(4)
        data.writeUInt32BE(value)
        self.data = data
    }
    public init(_ data: [UInt8]) throws {
        value = try data.readUInt32BE()
        self.data = data
    }
    public var buffer: [UInt8] { [type.rawValue] + data }
}
private func makeVariableBuffer(_ type: FieldType, _ data: [UInt8], _ lengthHeader: Int? = nil) -> [UInt8] {
    var header = [UInt8].alloc(5)
    header[0] = type.rawValue
    header.writeUInt32BE(lengthHeader ?? data.count, 1)
    return header + data
}
public struct RemoteDBString: StringField {
    public static let type = FieldType.string
    public var type: FieldType { Self.type }
    public let value: String
    public let data: [UInt8]
    public init(_ value: String) {
        self.value = value
        data = [UInt8](value + "\0", encoding: .utf16be)
    }
    public init(_ data: [UInt8]) throws {
        guard data.count % 2 == 0 else { throw DJLinkError("Buffer size must be a multiple of 16-bits") }
        self.data = data
        value = data.subarray(0, -2).toString(.utf16be)
    }
    public var buffer: [UInt8] { makeVariableBuffer(type, data, data.count / 2) }
}
public struct RemoteDBBinary: BinaryField {
    public static let type = FieldType.binary
    public var type: FieldType { Self.type }
    public let value: [UInt8]
    public var data: [UInt8] { value }
    public init(_ value: [UInt8]) { self.value = value }
    public var buffer: [UInt8] { makeVariableBuffer(type, data) }
}
@DJLinkActor
public func readField(_ stream: any TCPConnection, _ expect: FieldType) async throws -> Field {
    func read(_ bytes: Int) async throws -> [UInt8] {
        guard let data = try await stream.read(bytes) else { throw DJLinkError("Expected buffer from stream read") }
        return data
    }
    let typeData = try await read(1)
    guard let byte = typeData.first, let type = FieldType(rawValue: byte) else {
        throw DJLinkError("Unknown field type")
    }
    guard type == expect else { throw DJLinkError("Expected \(expect.jsName) but got \(type.jsName)") }
    let count: Int
    switch type {
    case .uint8: count = 1
    case .uint16: count = 2
    case .uint32: count = 4
    case .binary, .string:
        let length = try await read(4).readUInt32BE()
        count = type == .string ? length * 2 : length
    }
    let data = count == 0 ? [] : try await read(count)
    switch type {
    case .uint8: return try RemoteDBUInt8(data)
    case .uint16: return try RemoteDBUInt16(data)
    case .uint32: return try RemoteDBUInt32(data)
    case .binary: return RemoteDBBinary(data)
    case .string: return try RemoteDBString(data)
    }
}
