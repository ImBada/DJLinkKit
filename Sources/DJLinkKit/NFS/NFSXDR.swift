// 원본 src/nfs/xdr.ts. 외부 XDR 코드 없이 정렬과 선 자료형을 직접 구현한다.
public func calculatePadding(_ length: Int) -> Int { (4 - length % 4) % 4 }
public struct XDREncoder: Sendable {
    public private(set) var bytes: [UInt8] = []
    public init() {}
    public mutating func uint(_ value: Int) {
        var data = [UInt8].alloc(4)
        data.writeUInt32BE(value)
        bytes += data
    }
    public mutating func opaque(_ value: [UInt8]) {
        bytes += value
        bytes += [UInt8].alloc(calculatePadding(value.count))
    }
    public mutating func variableOpaque(_ value: [UInt8], maximum: Int = Int.max) throws {
        guard value.count <= maximum else {
            throw DJLinkError("XDR Write Error: got \(value.count) bytes, max allowed is \(maximum)")
        }
        uint(value.count)
        opaque(value)
    }
    public mutating func string(_ value: String, encoding: NodeEncoding = .utf8, maximum: Int = Int.max) throws {
        try variableOpaque([UInt8](value, encoding: encoding), maximum: maximum)
    }
    public mutating func remainder(_ value: [UInt8]) { opaque(value) }
}
public struct XDRDecoder: Sendable {
    public let bytes: [UInt8]
    public private(set) var index = 0
    public init(_ bytes: [UInt8]) { self.bytes = bytes }
    public mutating func uint() throws -> Int { try readBytes(4).readUInt32BE() }
    public mutating func int() throws -> Int { try readBytes(4).readInt32BE() }
    public mutating func bool() throws -> Bool {
        switch try int() {
        case 0: false
        case 1: true
        default: throw DJLinkError("invalid XDR bool")
        }
    }
    public mutating func readBytes(_ length: Int) throws -> [UInt8] {
        guard length >= 0, index + length <= bytes.count else {
            throw DJLinkError("attempt to read outside the boundary of the buffer")
        }
        defer { index += length }
        return bytes.subarray(index, index + length)
    }
    public mutating func opaque(_ length: Int) throws -> [UInt8] {
        let data = try readBytes(length)
        let padding = calculatePadding(length)
        if padding > 0 {
            guard index + padding <= bytes.count, bytes[index..<(index + padding)].allSatisfy({ $0 == 0 }) else {
                throw DJLinkError("invalid padding")
            }
            index += padding
        }
        return data
    }
    public mutating func variableOpaque(maximum: Int = Int.max) throws -> [UInt8] {
        let length = try uint()
        guard length <= maximum else {
            throw DJLinkError("XDR Read Error: length \(length) exceeds max allowed \(maximum)")
        }
        return try opaque(length)
    }
    public mutating func string(encoding: NodeEncoding = .utf8, maximum: Int = Int.max) throws -> String {
        if case .utf16le = encoding {
            // 원본 StringUTF16LE는 길이를 signed Int로 읽고 패딩 검사를 건너뛴다.
            let length = try int()
            let data = try readBytes(length)
            index += calculatePadding(length)
            return data.toString(encoding)
        }
        return try variableOpaque(maximum: maximum).toString(encoding)
    }
    public mutating func remainder() -> [UInt8] {
        defer { index = bytes.count }
        return bytes.subarray(index)
    }
}
public protocol XDRValue: Sendable {
    init(fromXDR decoder: inout XDRDecoder) throws
    func encodeXDR(_ encoder: inout XDREncoder) throws
}
extension XDRValue {
    public static func fromXDR(_ bytes: [UInt8]) throws -> Self {
        var decoder = XDRDecoder(bytes)
        let value = try Self(fromXDR: &decoder)
        guard decoder.index == bytes.count else {
            throw DJLinkError("invalid XDR contract typecast - source buffer not entirely consumed")
        }
        return value
    }
    public func toXDR() throws -> [UInt8] {
        var encoder = XDREncoder()
        try encodeXDR(&encoder)
        return encoder.bytes
    }
}
public enum rpc {
    public static let Version = 2
    public enum MessageType: Int, Sendable { case request = 0, response = 1 }
    public enum ResponseStatus: Int, Sendable { case accepted = 0, denied = 1 }
    public enum AcceptStatus: Int, Sendable {
        case success = 0, programUnavailable, programMismatch, processUnavailable, garbageArguments, systemError
    }
    public enum RejectStatus: Int, Sendable { case mismatch = 0, authError = 1 }
    public enum AuthStatus: Int, Sendable {
        case ok = 0, badCredentials, rjectedCredentials, badVerification, rejectedVerification, tooWeak,
            invalidResponse, failed
    }
    public struct UnixAuth: XDRValue {
        public var stamp: Int
        public var name: String
        public var uid: Int
        public var gid: Int
        public var gids: [Int]
        public init(stamp: Int, name: String, uid: Int, gid: Int, gids: [Int]) {
            self.stamp = stamp
            self.name = name
            self.uid = uid
            self.gid = gid
            self.gids = gids
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            stamp = try d.uint()
            name = try d.string(maximum: 255)
            uid = try d.uint()
            gid = try d.uint()
            let count = try d.uint()
            guard count <= 16 else { throw DJLinkError("XDR array exceeds max length") }
            gids = try (0..<count).map { _ in try d.uint() }
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            e.uint(stamp)
            try e.string(name, maximum: 255)
            e.uint(uid)
            e.uint(gid)
            guard gids.count <= 16 else { throw DJLinkError("XDR array exceeds max length") }
            e.uint(gids.count)
            for id in gids { e.uint(id) }
        }
    }
    public struct Auth: XDRValue {
        public var flavor: Int
        public var body: [UInt8]
        public init(flavor: Int, body: [UInt8]) {
            self.flavor = flavor
            self.body = body
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            flavor = try d.uint()
            body = try d.variableOpaque(maximum: 400)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            e.uint(flavor)
            try e.variableOpaque(body, maximum: 400)
        }
    }
    public struct Request: XDRValue {
        public var rpcVersion: Int
        public var program: Int
        public var programVersion: Int
        public var procedure: Int
        public var auth: Auth
        public var verifier: Auth
        public var data: [UInt8]
        public init(
            rpcVersion: Int, programVersion: Int, program: Int, procedure: Int, auth: Auth, verifier: Auth,
            data: [UInt8]
        ) {
            self.rpcVersion = rpcVersion
            self.program = program
            self.programVersion = programVersion
            self.procedure = procedure
            self.auth = auth
            self.verifier = verifier
            self.data = data
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            rpcVersion = try d.uint()
            program = try d.uint()
            programVersion = try d.uint()
            procedure = try d.uint()
            auth = try Auth(fromXDR: &d)
            verifier = try Auth(fromXDR: &d)
            data = d.remainder()
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            e.uint(rpcVersion)
            e.uint(program)
            e.uint(programVersion)
            e.uint(procedure)
            try auth.encodeXDR(&e)
            try verifier.encodeXDR(&e)
            e.remainder(data)
        }
    }
    public struct MismatchInfo: XDRValue {
        public var low: Int
        public var high: Int
        public init(low: Int, high: Int) {
            self.low = low
            self.high = high
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            low = try d.uint()
            high = try d.uint()
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            e.uint(low)
            e.uint(high)
        }
    }
    public enum ResponseData: XDRValue {
        case success([UInt8]), programMismatch(MismatchInfo), failure(AcceptStatus)
        public init(fromXDR d: inout XDRDecoder) throws {
            guard let status = AcceptStatus(rawValue: try d.uint()) else {
                throw DJLinkError("Unknown RPC accept status")
            }
            switch status {
            case .success: self = .success(d.remainder())
            case .programMismatch: self = .programMismatch(try MismatchInfo(fromXDR: &d))
            default: self = .failure(status)
            }
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            switch self {
            case let .success(data):
                e.uint(0)
                e.remainder(data)
            case let .programMismatch(info):
                e.uint(2)
                try info.encodeXDR(&e)
            case let .failure(status): e.uint(status.rawValue)
            }
        }
    }
    public struct AcceptedResponse: XDRValue {
        public var verifier: Auth
        public var response: ResponseData
        public init(verifier: Auth, response: ResponseData) {
            self.verifier = verifier
            self.response = response
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            verifier = try Auth(fromXDR: &d)
            response = try ResponseData(fromXDR: &d)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            try verifier.encodeXDR(&e)
            try response.encodeXDR(&e)
        }
    }
    public enum RejectedResponse: XDRValue {
        case mismatch(MismatchInfo), authError(AuthStatus)
        public init(fromXDR d: inout XDRDecoder) throws {
            switch try d.uint() {
            case 0: self = .mismatch(try MismatchInfo(fromXDR: &d))
            case 1:
                guard let status = AuthStatus(rawValue: try d.uint()) else {
                    throw DJLinkError("Unknown RPC auth status")
                }
                self = .authError(status)
            default: throw DJLinkError("Unknown RPC reject status")
            }
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            switch self {
            case let .mismatch(info):
                e.uint(0)
                try info.encodeXDR(&e)
            case let .authError(status):
                e.uint(1)
                e.uint(status.rawValue)
            }
        }
    }
    public enum Response: XDRValue {
        case accepted(AcceptedResponse), denied
        public init(fromXDR d: inout XDRDecoder) throws {
            switch try d.uint() {
            case 0: self = .accepted(try AcceptedResponse(fromXDR: &d))
            case 1: self = .denied
            default: throw DJLinkError("Unknown RPC response status")
            }
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            switch self {
            case let .accepted(response):
                e.uint(0)
                try response.encodeXDR(&e)
            case .denied: e.uint(1)
            }
        }
    }
    public enum Message: XDRValue {
        case request(Request), response(Response)
        public init(fromXDR d: inout XDRDecoder) throws {
            switch try d.uint() {
            case 0: self = .request(try Request(fromXDR: &d))
            case 1: self = .response(try Response(fromXDR: &d))
            default: throw DJLinkError("Unknown RPC message type")
            }
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            switch self {
            case let .request(request):
                e.uint(0)
                try request.encodeXDR(&e)
            case let .response(response):
                e.uint(1)
                try response.encodeXDR(&e)
            }
        }
    }
    public struct Packet: XDRValue {
        public var xid: Int
        public var message: Message
        public init(xid: Int, message: Message) {
            self.xid = xid
            self.message = message
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            xid = try d.uint()
            message = try Message(fromXDR: &d)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            e.uint(xid)
            try message.encodeXDR(&e)
        }
    }
}
public enum portmap {
    public static let Program = 100000, Version = 2
    public enum Procedure: Int, Sendable { case getPort = 3 }
    public struct GetPort: XDRValue {
        public var program: Int
        public var version: Int
        public var `protocol`: Int
        public var port: Int
        public init(program: Int, version: Int, protocol: Int, port: Int) {
            self.program = program
            self.version = version
            self.protocol = `protocol`
            self.port = port
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            program = try d.uint()
            version = try d.uint()
            self.protocol = try d.uint()
            port = try d.uint()
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            e.uint(program)
            e.uint(version)
            e.uint(self.protocol)
            e.uint(port)
        }
    }
}
public enum mount {
    public static let Program = 100005, Version = 1
    public enum Procedure: Int, Sendable { case mount = 1, export = 5 }
    public typealias Path = String
    public typealias Filehandle = [UInt8]
    public struct MountRequest: XDRValue {
        public var filesystem: String
        public init(filesystem: String) { self.filesystem = filesystem }
        public init(fromXDR d: inout XDRDecoder) throws { filesystem = try d.string(encoding: .utf16le) }
        public func encodeXDR(_ e: inout XDREncoder) throws { try e.string(filesystem, encoding: .utf16le) }
    }
    public final class Groups: XDRValue {
        public let name: String
        public let next: Groups?
        public init(name: String, next: Groups? = nil) {
            self.name = name
            self.next = next
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            name = try d.string(maximum: 255)
            next = try !d.bool() ? nil : Groups(fromXDR: &d)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            try e.string(name, maximum: 255)
            e.uint(next == nil ? 0 : 1)
            try next?.encodeXDR(&e)
        }
    }
    public final class ExportList: XDRValue {
        public let filesystem: String
        public let groups: Groups?
        public let next: ExportList?
        public init(filesystem: String, groups: Groups? = nil, next: ExportList? = nil) {
            self.filesystem = filesystem
            self.groups = groups
            self.next = next
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            filesystem = try d.string(encoding: .utf16le)
            groups = try !d.bool() ? nil : Groups(fromXDR: &d)
            next = try !d.bool() ? nil : ExportList(fromXDR: &d)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            try e.string(filesystem, encoding: .utf16le)
            e.uint(groups == nil ? 0 : 1)
            try groups?.encodeXDR(&e)
            e.uint(next == nil ? 0 : 1)
            try next?.encodeXDR(&e)
        }
    }
    public enum FHStatus: XDRValue {
        case success(Filehandle), failure(Int)
        public init(fromXDR d: inout XDRDecoder) throws {
            let status = try d.uint()
            self = status == 0 ? .success(try d.opaque(32)) : .failure(status)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            switch self {
            case let .success(handle):
                e.uint(0)
                try encodeHandle(handle, &e)
            case let .failure(status): e.uint(status)
            }
        }
    }
    public struct ExportListResponse: XDRValue {
        public var next: ExportList?
        public init(next: ExportList?) { self.next = next }
        public init(fromXDR d: inout XDRDecoder) throws { next = try !d.bool() ? nil : ExportList(fromXDR: &d) }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            e.uint(next == nil ? 0 : 1)
            try next?.encodeXDR(&e)
        }
    }
}
private func encodeHandle(_ handle: [UInt8], _ e: inout XDREncoder) throws {
    guard handle.count == 32 else { throw DJLinkError("XDR Write Error: expected 32 bytes, got \(handle.count)") }
    e.opaque(handle)
}
public enum nfs {
    public static let Program = 100003, Version = 2
    public enum Procedure: Int, Sendable { case lookup = 4, read = 6 }
    public typealias Filename = String
    public typealias Filehandle = [UInt8]
    public typealias NFSData = [UInt8]
    public enum FileType: Int, Sendable {
        case null = 0, regular, directory, block, char, link
        public var name: String {
            switch self {
            case .null: "null"
            case .regular: "regular"
            case .directory: "directory"
            case .block: "block"
            case .char: "char"
            case .link: "link"
            }
        }
    }
    public struct TimeValue: XDRValue {
        public var seconds: Int
        public var useconds: Int
        public init(seconds: Int = 0, useconds: Int = 0) {
            self.seconds = seconds
            self.useconds = useconds
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            seconds = try d.uint()
            useconds = try d.uint()
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            e.uint(seconds)
            e.uint(useconds)
        }
    }
    public struct FileAttributes: XDRValue {
        public var type: FileType
        public var mode: Int
        public var nlink: Int
        public var uid: Int
        public var gid: Int
        public var size: Int
        public var blocksize: Int
        public var rdev: Int
        public var blocks: Int
        public var fsid: Int
        public var fileid: Int
        public var atime: TimeValue
        public var mtime: TimeValue
        public var ctime: TimeValue
        public init(
            type: FileType, mode: Int = 0, nlink: Int = 0, uid: Int = 0, gid: Int = 0, size: Int,
            blocksize: Int = 0, rdev: Int = 0, blocks: Int = 0, fsid: Int = 0, fileid: Int = 0,
            atime: TimeValue = TimeValue(), mtime: TimeValue = TimeValue(), ctime: TimeValue = TimeValue()
        ) {
            self.type = type
            self.mode = mode
            self.nlink = nlink
            self.uid = uid
            self.gid = gid
            self.size = size
            self.blocksize = blocksize
            self.rdev = rdev
            self.blocks = blocks
            self.fsid = fsid
            self.fileid = fileid
            self.atime = atime
            self.mtime = mtime
            self.ctime = ctime
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            guard let type = FileType(rawValue: try d.uint()) else { throw DJLinkError("Unknown NFS file type") }
            self.type = type
            mode = try d.uint()
            nlink = try d.uint()
            uid = try d.uint()
            gid = try d.uint()
            size = try d.uint()
            blocksize = try d.uint()
            rdev = try d.uint()
            blocks = try d.uint()
            fsid = try d.uint()
            fileid = try d.uint()
            atime = try TimeValue(fromXDR: &d)
            mtime = try TimeValue(fromXDR: &d)
            ctime = try TimeValue(fromXDR: &d)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            for value in [type.rawValue, mode, nlink, uid, gid, size, blocksize, rdev, blocks, fsid, fileid] {
                e.uint(value)
            }
            try atime.encodeXDR(&e)
            try mtime.encodeXDR(&e)
            try ctime.encodeXDR(&e)
        }
    }
    public struct DirectoryOpArgs: XDRValue {
        public var handle: Filehandle
        public var filename: String
        public init(handle: Filehandle, filename: String) {
            self.handle = handle
            self.filename = filename
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            handle = try d.opaque(32)
            filename = try d.string(encoding: .utf16le)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            try encodeHandle(handle, &e)
            try e.string(filename, encoding: .utf16le)
        }
    }
    public struct DirectoryOpResponseBody: XDRValue {
        public var handle: Filehandle
        public var attributes: FileAttributes
        public init(handle: Filehandle, attributes: FileAttributes) {
            self.handle = handle
            self.attributes = attributes
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            handle = try d.opaque(32)
            attributes = try FileAttributes(fromXDR: &d)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            try encodeHandle(handle, &e)
            try attributes.encodeXDR(&e)
        }
    }
    public enum DirectoryOpResponse: XDRValue {
        case success(DirectoryOpResponseBody), failure(Int)
        public init(fromXDR d: inout XDRDecoder) throws {
            let status = try d.uint()
            self = status == 0 ? .success(try DirectoryOpResponseBody(fromXDR: &d)) : .failure(status)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            switch self {
            case let .success(body):
                e.uint(0)
                try body.encodeXDR(&e)
            case let .failure(status): e.uint(status)
            }
        }
    }
    public struct ReadArgs: XDRValue {
        public var handle: Filehandle
        public var offset: Int
        public var count: Int
        public var totalCount: Int
        public init(handle: Filehandle, offset: Int, count: Int, totalCount: Int) {
            self.handle = handle
            self.offset = offset
            self.count = count
            self.totalCount = totalCount
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            handle = try d.opaque(32)
            offset = try d.uint()
            count = try d.uint()
            totalCount = try d.uint()
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            try encodeHandle(handle, &e)
            e.uint(offset)
            e.uint(count)
            e.uint(totalCount)
        }
    }
    public struct ReadBody: XDRValue {
        public var attributes: FileAttributes
        public var data: NFSData
        public init(attributes: FileAttributes, data: NFSData) {
            self.attributes = attributes
            self.data = data
        }
        public init(fromXDR d: inout XDRDecoder) throws {
            attributes = try FileAttributes(fromXDR: &d)
            data = try d.variableOpaque(maximum: 8192)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            try attributes.encodeXDR(&e)
            try e.variableOpaque(data, maximum: 8192)
        }
    }
    public enum ReadResponse: XDRValue {
        case success(ReadBody), failure(Int)
        public init(fromXDR d: inout XDRDecoder) throws {
            let status = try d.uint()
            self = status == 0 ? .success(try ReadBody(fromXDR: &d)) : .failure(status)
        }
        public func encodeXDR(_ e: inout XDREncoder) throws {
            switch self {
            case let .success(body):
                e.uint(0)
                try body.encodeXDR(&e)
            case let .failure(status): e.uint(status)
            }
        }
    }
}
