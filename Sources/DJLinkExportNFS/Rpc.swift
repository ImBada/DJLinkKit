// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-nfs/src/rpc.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
public enum Rpc {
    public static let RPC_VERSION: UInt32 = 2
    public static let MSG_CALL: UInt32 = 0, MSG_REPLY: UInt32 = 1
    public static let MSG_ACCEPTED: UInt32 = 0, MSG_DENIED: UInt32 = 1
    public static let AUTH_NULL: UInt32 = 0, AUTH_UNIX: UInt32 = 1
    public static let CDJ_AUTH_STAMP: UInt32 = 0x967b8703
    public enum accept {
        public static let SUCCESS: UInt32 = 0, PROG_UNAVAIL: UInt32 = 1, PROG_MISMATCH: UInt32 = 2
        public static let PROC_UNAVAIL: UInt32 = 3, GARBAGE_ARGS: UInt32 = 4, SYSTEM_ERR: UInt32 = 5
    }
    public enum reject { public static let RPC_MISMATCH: UInt32 = 0, AUTH_ERROR: UInt32 = 1 }
    public enum RpcError: Error, Equatable, Sendable, CustomStringConvertible {
        case xdr(Xdr.XdrError)
        case notACall(UInt32)
        case version(UInt32)
        public var description: String {
            switch self {
            case let .xdr(error): return error.description
            case let .notACall(kind): return "expected an RPC call, got message type \(kind)"
            case let .version(version): return "unsupported RPC version \(version)"
            }
        }
    }
    public struct Auth: Equatable, Sendable {
        public var flavor: UInt32
        public var body: [UInt8]
        public init(flavor: UInt32, body: [UInt8]) {
            self.flavor = flavor
            self.body = body
        }
        public static func null() -> Auth { Auth(flavor: AUTH_NULL, body: []) }
        fileprivate static func read(_ reader: Xdr.Reader) throws -> Auth {
            try Auth(flavor: reader.u32(), body: reader.opaque())
        }
        fileprivate func write(_ writer: Xdr.Writer) { writer.u32(flavor).opaque(body) }
    }
    public struct Call: Equatable, Sendable {
        public var xid: UInt32, program: UInt32, version: UInt32, procedure: UInt32
        public var credential: Auth, verifier: Auth
        public var arguments: [UInt8]
        public init(
            xid: UInt32, program: UInt32, version: UInt32, procedure: UInt32, credential: Auth, verifier: Auth,
            arguments: [UInt8]
        ) {
            self.xid = xid
            self.program = program
            self.version = version
            self.procedure = procedure
            self.credential = credential
            self.verifier = verifier
            self.arguments = arguments
        }
        public static func decode(_ bytes: [UInt8]) throws -> Call {
            do {
                let reader = Xdr.Reader(bytes)
                let xid = try reader.u32()
                let message_type = try reader.u32()
                guard message_type == MSG_CALL else { throw RpcError.notACall(message_type) }
                let rpc_version = try reader.u32()
                guard rpc_version == RPC_VERSION else { throw RpcError.version(rpc_version) }
                let program = try reader.u32()
                let version = try reader.u32()
                let procedure = try reader.u32()
                let credential = try Auth.read(reader)
                let verifier = try Auth.read(reader)
                return Call(
                    xid: xid, program: program, version: version, procedure: procedure, credential: credential,
                    verifier: verifier, arguments: Array(bytes.dropFirst(reader.position())))
            } catch let error as Xdr.XdrError { throw RpcError.xdr(error) }
        }
        public func reader() -> Xdr.Reader { Xdr.Reader(arguments) }
        public func encode() -> [UInt8] {
            let writer = Xdr.Writer.with_capacity(64 + arguments.count)
            writer.u32(xid).u32(MSG_CALL).u32(RPC_VERSION).u32(program).u32(version).u32(procedure)
            credential.write(writer)
            verifier.write(writer)
            return writer.into_bytes() + arguments
        }
    }
    public static func accepted(_ xid: UInt32, _ status: UInt32) -> Xdr.Writer {
        let writer = Xdr.Writer.with_capacity(64)
        writer.u32(xid).u32(MSG_REPLY).u32(MSG_ACCEPTED)
        Auth.null().write(writer)
        writer.u32(status)
        return writer
    }
    public static func accepted_empty(_ xid: UInt32, _ status: UInt32) -> [UInt8] { accepted(xid, status).into_bytes() }
    public static func program_mismatch(_ xid: UInt32, _ low: UInt32, _ high: UInt32) -> [UInt8] {
        accepted(xid, accept.PROG_MISMATCH).u32(low).u32(high).into_bytes()
    }
    public static func rpc_mismatch(_ xid: UInt32, _ low: UInt32, _ high: UInt32) -> [UInt8] {
        Xdr.Writer.with_capacity(32).u32(xid).u32(MSG_REPLY).u32(MSG_DENIED).u32(reject.RPC_MISMATCH).u32(low).u32(high)
            .into_bytes()
    }
    public struct Reply: Equatable, Sendable {
        public var xid: UInt32, reply_status: UInt32, accept_status: UInt32
        public var results: [UInt8]
        public init(xid: UInt32, reply_status: UInt32, accept_status: UInt32, results: [UInt8]) {
            self.xid = xid
            self.reply_status = reply_status
            self.accept_status = accept_status
            self.results = results
        }
        public static func decode(_ bytes: [UInt8]) throws -> Reply {
            do {
                let reader = Xdr.Reader(bytes)
                let xid = try reader.u32()
                let message_type = try reader.u32()
                guard message_type == MSG_REPLY else { throw RpcError.notACall(message_type) }
                let reply_status = try reader.u32()
                if reply_status == MSG_ACCEPTED { _ = try Auth.read(reader) }
                let accept_status = try reader.u32()
                return Reply(
                    xid: xid, reply_status: reply_status, accept_status: accept_status,
                    results: Array(bytes.dropFirst(reader.position())))
            } catch let error as Xdr.XdrError { throw RpcError.xdr(error) }
        }
        public func is_success() -> Bool { reply_status == MSG_ACCEPTED && accept_status == accept.SUCCESS }
        public func reader() -> Xdr.Reader { Xdr.Reader(results) }
    }
}
