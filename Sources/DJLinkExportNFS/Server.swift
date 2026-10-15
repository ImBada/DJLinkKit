// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
import DJLinkExportSupport
import DJLinkKit
// 원본: crates/rbl-nfs/src/lib.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public let REKORDBOX_PORTMAP_PORT: UInt16 = 50111
public let STANDARD_PORTMAP_PORT: UInt16 = 111
public let NFS_PORT: UInt16 = 2049
public let PROGRAM_PORTMAP: UInt32 = 100000
public let PROGRAM_MOUNT: UInt32 = 100005
public let PROGRAM_NFS: UInt32 = 100003
public let PROGRAM_NLM: UInt32 = 100021
public let PROGRAM_NSM: UInt32 = 100024
public let VERSION_PORTMAP: UInt32 = 2
public let VERSION_MOUNT: UInt32 = 1
public let VERSION_NFS: UInt32 = 2
public let IPPROTO_TCP: UInt32 = 6
public let IPPROTO_UDP: UInt32 = 17
public let MAX_NAME = 255
public enum portmap_proc { public static let NULL: UInt32 = 0, SET: UInt32 = 1, UNSET: UInt32 = 2, GETPORT: UInt32 = 3 }
public enum mount_proc {
    public static let NULL: UInt32 = 0, MNT: UInt32 = 1, DUMP: UInt32 = 2, UMNT: UInt32 = 3, UMNTALL: UInt32 = 4,
        EXPORT: UInt32 = 5, EXPORTALL: UInt32 = 6
}
public enum nfs_proc {
    public static let NULL: UInt32 = 0, GETATTR: UInt32 = 1, SETATTR: UInt32 = 2, LOOKUP: UInt32 = 4,
        READLINK: UInt32 = 5, READ: UInt32 = 6
    public static let WRITE: UInt32 = 8, CREATE: UInt32 = 9, REMOVE: UInt32 = 10, RENAME: UInt32 = 11,
        LINK: UInt32 = 12, SYMLINK: UInt32 = 13
    public static let MKDIR: UInt32 = 14, RMDIR: UInt32 = 15, READDIR: UInt32 = 16, STATFS: UInt32 = 17
}
public enum nfs_status {
    public static let OK: UInt32 = 0, PERM: UInt32 = 1, NOENT: UInt32 = 2, IO: UInt32 = 5, ACCES: UInt32 = 13
    public static let NOTDIR: UInt32 = 20, ISDIR: UInt32 = 21, ROFS: UInt32 = 30, NAMETOOLONG: UInt32 = 63,
        STALE: UInt32 = 70
}
public func call_name(_ program: UInt32, _ procedure: UInt32) -> String {
    let name: String
    let procedures: [UInt32: String]
    switch program {
    case PROGRAM_PORTMAP:
        name = "portmap"
        procedures = [0: "NULL", 3: "GETPORT"]
    case PROGRAM_MOUNT:
        name = "mount"
        procedures = [0: "NULL", 1: "MNT", 2: "DUMP", 3: "UMNT", 4: "UMNTALL", 5: "EXPORT"]
    case PROGRAM_NFS:
        name = "nfs"
        procedures = [
            0: "NULL", 1: "GETATTR", 2: "SETATTR", 4: "LOOKUP", 5: "READLINK", 6: "READ", 8: "WRITE", 9: "CREATE",
            10: "REMOVE", 11: "RENAME", 12: "LINK", 13: "SYMLINK", 14: "MKDIR", 15: "RMDIR", 16: "READDIR",
            17: "STATFS",
        ]
    default: return "program \(program) procedure \(procedure)"
    }
    return procedures[procedure].map { "\(name) \($0)" } ?? "\(name) procedure \(procedure)"
}
public struct Receiver: Equatable, Sendable {
    fileprivate var token: UInt64
    private init(_ token: UInt64) { self.token = token }
    @DJLinkActor private static var next: UInt64 = 1
    @DJLinkActor public init() {
        token = Self.next
        Self.next &+= 1
    }
    fileprivate static let unnamed = Receiver(0)
}
private struct ReplyKey: Equatable {
    var receiver: Receiver, from: Address4, port: UInt16, head: [UInt8]
}

@DJLinkActor
public final class Server {
    let logger: any Logger
    private let clock: any DJLinkClock
    private var exported: Exports
    private var nfs_port: UInt16, mount_port: UInt16
    private var export_host: String?
    private var up: AtomicUInt8?
    private var mounts: [[UInt8]: [Address4]] = [:]
    private var replies: [(ReplyKey, [UInt8])] = []
    public init(
        _ exports: Exports, _ nfs_port: UInt16, _ mount_port: UInt16, logger: any Logger = noopLogger,
        clock: any DJLinkClock = SystemClock.shared
    ) {
        exported = exports.clone()
        self.nfs_port = nfs_port
        self.mount_port = mount_port
        self.logger = logger
        self.clock = clock
    }
    public static func new(
        _ exports: Exports, _ nfs_port: UInt16, _ mount_port: UInt16, logger: any Logger = noopLogger,
        clock: any DJLinkClock = SystemClock.shared
    ) -> Server { Server(exports, nfs_port, mount_port, logger: logger, clock: clock) }
    @discardableResult public func with_gate(_ up: AtomicUInt8) -> Server {
        self.up = up
        return self
    }
    @discardableResult public func with_export_host(_ host: String) -> Server {
        export_host = host
        return self
    }
    private func is_up() -> Bool { up.map { $0.load() != 0 } ?? true }
    private func allows(_ host: Address4) -> Bool {
        guard let group = export_host, let slash = group.firstIndex(of: "/"),
            let ip = parse_ipv4(String(group[..<slash])),
            let mask = parse_ipv4(String(group[group.index(after: slash)...]))
        else { return true }
        return (host.integerValue ^ ip.integerValue) & mask.integerValue == 0
    }
    public func mounted_hosts() -> [Address4] {
        Array(Set(mounts.values.flatMap { $0 })).sorted { $0.integerValue < $1.integerValue }
    }
    public func is_mounted(_ host: Address4) -> Bool { mounts.values.contains { $0.contains(host) } }
    public func exports() -> Exports { exported }
    public func handle(_ datagram: [UInt8]) -> [UInt8]? { handle_from(datagram, try! Address4("127.0.0.1"), 0) }
    public func handle_from(_ datagram: [UInt8], _ from: Address4, _ port: UInt16) -> [UInt8]? {
        handle_on(datagram, from, port, .unnamed)
    }
    public func handle_on(_ datagram: [UInt8], _ from: Address4, _ port: UInt16, _ receiver: Receiver) -> [UInt8]? {
        let key =
            datagram.count >= 24
            ? ReplyKey(receiver: receiver, from: from, port: port, head: Array(datagram.prefix(24))) : nil
        if let key, let previous = replies.first(where: { $0.0 == key }) {
            logger.trace("call seen before; its reply sent again", from.address, port)
            return previous.1
        }
        guard let reply = answer(datagram, from) else { return nil }
        if let key {
            if replies.count >= 20 { replies.removeFirst() }
            replies.append((key, reply))
        }
        return reply
    }
    private func answer(_ datagram: [UInt8], _ from: Address4) -> [UInt8]? {
        let call: Rpc.Call
        do { call = try Rpc.Call.decode(datagram) } catch let Rpc.RpcError.version(version) {
            guard let xid = try? Xdr.Reader(datagram).u32() else { return nil }
            logger.warn("RPC call of a version this server does not speak", xid, version)
            return Rpc.rpc_mismatch(xid, Rpc.RPC_VERSION, Rpc.RPC_VERSION)
        } catch {
            logger.debug("datagram is not an RPC call; ignored", String(describing: error), datagram.count)
            return nil
        }
        logger.trace("RPC call", call.xid, call_name(call.program, call.procedure), call.version, call.arguments.count)
        let reply: [UInt8]
        switch call.program {
        case PROGRAM_PORTMAP: reply = portmap(call, from)
        case PROGRAM_MOUNT: reply = mount(call, from)
        case PROGRAM_NFS: reply = nfs(call)
        case PROGRAM_NLM, PROGRAM_NSM:
            logger.debug("lock-manager call; dropped without a reply", call.xid, call.program)
            return nil
        default:
            logger.warn("RPC call for a program this server does not have", call.xid, call.program)
            reply = Rpc.accepted_empty(call.xid, Rpc.accept.PROG_UNAVAIL)
        }
        logger.trace("RPC reply", call.xid, reply.count)
        return reply
    }
    private func portmap(_ call: Rpc.Call, _ from: Address4) -> [UInt8] {
        guard call.version == VERSION_PORTMAP else {
            return Rpc.program_mismatch(call.xid, VERSION_PORTMAP, VERSION_PORTMAP)
        }
        switch call.procedure {
        case portmap_proc.NULL: return Rpc.accepted_empty(call.xid, Rpc.accept.SUCCESS)
        case portmap_proc.SET, portmap_proc.UNSET:
            if from != (try! Address4("127.0.0.1")) {
                return Rpc.accepted(call.xid, Rpc.accept.SUCCESS).u32(0).into_bytes()
            }
            return Rpc.accepted_empty(call.xid, Rpc.accept.PROC_UNAVAIL)
        case 4:
            let writer = Rpc.accepted(call.xid, Rpc.accept.SUCCESS)
            for (program, version, port) in [
                (PROGRAM_PORTMAP, VERSION_PORTMAP, REKORDBOX_PORTMAP_PORT), (PROGRAM_NFS, VERSION_NFS, nfs_port),
                (PROGRAM_MOUNT, VERSION_MOUNT, mount_port),
            ] {
                writer.some().u32(program).u32(version).u32(IPPROTO_UDP).u32(UInt32(port))
            }
            return writer.none().into_bytes()
        case portmap_proc.GETPORT:
            let reader = call.reader()
            guard let program = try? reader.u32(), let version = try? reader.u32(),
                let protocolValue = try? reader.u32()
            else { return Rpc.accepted_empty(call.xid, Rpc.accept.GARBAGE_ARGS) }
            let port: UInt16 =
                protocolValue == IPPROTO_UDP
                ? (program == PROGRAM_NFS && version == VERSION_NFS
                    ? nfs_port : (program == PROGRAM_MOUNT && version == VERSION_MOUNT ? mount_port : 0)) : 0
            logger.trace("portmap GETPORT answered", call.xid, program, protocolValue, port)
            return Rpc.accepted(call.xid, Rpc.accept.SUCCESS).u32(UInt32(port)).into_bytes()
        default: return Rpc.accepted_empty(call.xid, Rpc.accept.PROC_UNAVAIL)
        }
    }
    private func mount(_ call: Rpc.Call, _ from: Address4) -> [UInt8] {
        guard call.version == VERSION_MOUNT else { return Rpc.program_mismatch(call.xid, VERSION_MOUNT, VERSION_MOUNT) }
        switch call.procedure {
        case mount_proc.NULL: return Rpc.accepted_empty(call.xid, Rpc.accept.SUCCESS)
        case mount_proc.UMNT, mount_proc.UMNTALL:
            let path: String?
            if call.procedure == mount_proc.UMNT {
                guard let decoded = try? call.reader().utf16() else {
                    return Rpc.accepted_empty(call.xid, Rpc.accept.SUCCESS)
                }
                path = decoded
            } else {
                path = nil
            }
            for export in Array(mounts.keys) where path == nil || Array(path!.utf8) == export {
                if mounts[export]?.contains(from) == true {
                    mounts[export]?.removeAll { $0 == from }
                    logger.info(
                        "player unmounted an export", call.xid, from.address, String(decoding: export, as: UTF8.self))
                }
            }
            return Rpc.accepted_empty(call.xid, Rpc.accept.SUCCESS)
        case mount_proc.MNT:
            guard let path = try? call.reader().utf16() else {
                logger.warn("mount request with an unreadable path", call.xid)
                return Rpc.accepted_empty(call.xid, Rpc.accept.GARBAGE_ARGS)
            }
            let writer = Rpc.accepted(call.xid, Rpc.accept.SUCCESS)
            let vfs = is_up() ? exported.get(path) : nil
            if let vfs, let handle = vfs.handle(vfs.root()), allows(from) {
                if !(mounts[Array(path.utf8)] ?? []).contains(from) {
                    mounts[Array(path.utf8), default: []].append(from)
                }
                logger.info(
                    "player mounted an export", call.xid, from.address, path, mounts.values.reduce(0) { $0 + $1.count },
                    handle.description)
                writer.u32(nfs_status.OK).opaque_fixed(handle.as_bytes())
            } else {
                if vfs?.handle(vfs?.root() ?? 0) != nil {
                    logger.warn("mount from outside the export's subnet; refused", call.xid, from.address, path)
                } else {
                    logger.warn(
                        "mount of a path that is not exported", call.xid, from.address, path, is_up(), exported.names())
                }
                writer.u32(nfs_status.ACCES)
            }
            return writer.into_bytes()
        case mount_proc.EXPORT, mount_proc.EXPORTALL:
            logger.debug("export list asked for", call.xid, exported.names(), export_host ?? "-", is_up())
            let writer = Rpc.accepted(call.xid, Rpc.accept.SUCCESS)
            for name in is_up() ? exported.names() : [] {
                writer.some().utf16(name)
                if let host = export_host { writer.some().string(host).none() } else { writer.none() }
            }
            return writer.none().into_bytes()
        default:
            logger.warn("mount procedure this server does not have", call.xid, call.procedure)
            return Rpc.accepted_empty(call.xid, Rpc.accept.PROC_UNAVAIL)
        }
    }
    private func nfs(_ call: Rpc.Call) -> [UInt8] {
        guard call.version == VERSION_NFS else { return Rpc.program_mismatch(call.xid, VERSION_NFS, VERSION_NFS) }
        switch call.procedure {
        case nfs_proc.NULL: return Rpc.accepted_empty(call.xid, Rpc.accept.SUCCESS)
        case nfs_proc.GETATTR: return getattr(call)
        case nfs_proc.LOOKUP: return lookup(call)
        case nfs_proc.READ: return read(call)
        case nfs_proc.READDIR: return readdir(call)
        case nfs_proc.STATFS: return statfs(call)
        case nfs_proc.SETATTR, nfs_proc.WRITE, nfs_proc.CREATE, nfs_proc.REMOVE, nfs_proc.RENAME, nfs_proc.MKDIR,
            nfs_proc.RMDIR:
            return Self.status_only(call.xid, nfs_status.STALE)
        case nfs_proc.LINK, nfs_proc.SYMLINK, nfs_proc.READLINK: return Self.status_only(call.xid, nfs_status.ACCES)
        default: return Rpc.accepted_empty(call.xid, Rpc.accept.PROC_UNAVAIL)
        }
    }
    private static func status_only(_ xid: UInt32, _ status: UInt32) -> [UInt8] {
        Rpc.accepted(xid, Rpc.accept.SUCCESS).u32(status).into_bytes()
    }
    private func locate(_ handle: Handle) -> (Vfs, Int)? {
        for name in exported.names() {
            if let vfs = exported.get(name), let index = vfs.node_of(handle) { return (vfs, index) }
        }
        return nil
    }
    private static func read_handle(_ reader: Xdr.Reader) -> Handle? {
        (try? reader.opaque_fixed(HANDLE_LEN)).flatMap(Handle.from_slice)
    }
    private func getattr(_ call: Rpc.Call) -> [UInt8] {
        guard let handle = Self.read_handle(call.reader()) else {
            return Rpc.accepted_empty(call.xid, Rpc.accept.GARBAGE_ARGS)
        }
        guard let (vfs, index) = locate(handle) else {
            logger.warn("getattr of a stale handle", call.xid, handle.description)
            return Self.status_only(call.xid, nfs_status.STALE)
        }
        guard let attributes = vfs.attributes(index) else { return Self.status_only(call.xid, nfs_status.STALE) }
        let writer = Rpc.accepted(call.xid, Rpc.accept.SUCCESS).u32(nfs_status.OK)
        write_attributes(writer, attributes)
        return writer.into_bytes()
    }
    private func lookup(_ call: Rpc.Call) -> [UInt8] {
        let reader = call.reader()
        guard let handle = Self.read_handle(reader), let name = try? reader.utf16() else {
            return Rpc.accepted_empty(call.xid, Rpc.accept.GARBAGE_ARGS)
        }
        if name.utf8.count > MAX_NAME {
            logger.warn("lookup of a name too long", call.xid, name.utf8.count)
            return Self.status_only(call.xid, nfs_status.NAMETOOLONG)
        }
        guard let (vfs, parent) = locate(handle) else {
            logger.warn("lookup under a stale handle", call.xid, name, handle.description)
            return Self.status_only(call.xid, nfs_status.STALE)
        }
        guard vfs.kind(parent) == .directory else {
            logger.warn("lookup under a file, not a directory", call.xid, name)
            return Self.status_only(call.xid, nfs_status.NOTDIR)
        }
        guard let index = vfs.child(parent, name), let child = vfs.handle(index), let attributes = vfs.attributes(index)
        else {
            logger.debug("lookup found nothing", call.xid, vfs.name(parent) ?? "", name)
            return Self.status_only(call.xid, nfs_status.NOENT)
        }
        logger.trace("lookup found a node", call.xid, name, attributes.size)
        let writer = Rpc.accepted(call.xid, Rpc.accept.SUCCESS).u32(nfs_status.OK).opaque_fixed(child.as_bytes())
        write_attributes(writer, attributes)
        return writer.into_bytes()
    }
    private func read(_ call: Rpc.Call) -> [UInt8] {
        let reader = call.reader()
        guard let handle = Self.read_handle(reader), let offset = try? reader.u32(), let count = try? reader.u32()
        else { return Rpc.accepted_empty(call.xid, Rpc.accept.GARBAGE_ARGS) }
        guard let (vfs, index) = locate(handle) else {
            logger.warn("read through a stale handle", call.xid, offset, count, handle.description)
            return Self.status_only(call.xid, nfs_status.STALE)
        }
        if vfs.kind(index) == .directory {
            logger.warn("read of a directory", call.xid)
            return Self.status_only(call.xid, nfs_status.ISDIR)
        }
        guard let source = vfs.source(index) else {
            logger.warn("read of a node with no file behind it", call.xid)
            return Self.status_only(call.xid, nfs_status.STALE)
        }
        let wanted = min(Int(count), MAX_READ)
        if offset == 0 { logger.debug("player started reading a file", call.xid, source) }
        guard !source.utf8.contains(0) else { return Self.status_only(call.xid, nfs_status.IO) }
        // 원본 Mutex의 open→seek→read→stat→close 범위를 액터 위 동기 호출로 보존한다.
        let file: FileHandle
        do { file = try FileHandle(forReadingFrom: URL(fileURLWithPath: source)) } catch {
            logger.warn("open for read failed", call.xid, source, String(describing: error))
            return Self.status_only(call.xid, nfs_status.IO)
        }
        let started = clock.now()
        let data: [UInt8]
        do { data = try read_at(file, UInt64(offset), wanted) } catch {
            logger.warn("read failed", call.xid, source, offset, wanted, String(describing: error))
            try? file.close()
            return Self.status_only(call.xid, nfs_status.IO)
        }
        guard !data.isEmpty else {
            logger.trace("read at the end of the file; IO, as rekordbox answers", call.xid, offset)
            try? file.close()
            return Self.status_only(call.xid, nfs_status.IO)
        }
        guard let attributes = vfs.attributes(index) else {
            try? file.close()
            return Self.status_only(call.xid, nfs_status.STALE)
        }
        try? file.close()
        logger.trace(
            "read served", call.xid, offset, wanted, data.count, clock.now().timeIntervalSince(started) * 1000000)
        let writer = Rpc.accepted(call.xid, Rpc.accept.SUCCESS).u32(nfs_status.OK)
        write_attributes(writer, attributes)
        return writer.opaque(data).into_bytes()
    }
    private func readdir(_ call: Rpc.Call) -> [UInt8] {
        let reader = call.reader()
        guard let handle = Self.read_handle(reader), let cookie = try? reader.u32(), let count = try? reader.u32()
        else { return Rpc.accepted_empty(call.xid, Rpc.accept.GARBAGE_ARGS) }
        guard let (vfs, index) = locate(handle) else {
            logger.warn("readdir of a stale handle", call.xid, handle.description)
            return Self.status_only(call.xid, nfs_status.STALE)
        }
        guard vfs.kind(index) == .directory else { return Self.status_only(call.xid, nfs_status.NOTDIR) }
        let children = vfs.children(index)
        let start: Int
        if cookie == 0 {
            start = 0
        } else if let position = children.firstIndex(where: { vfs.attributes($0)?.fileid == cookie }) {
            start = position + 1
        } else {
            logger.warn("readdir cookie names no child; IO", call.xid, cookie)
            return Self.status_only(call.xid, nfs_status.IO)
        }
        let writer = Rpc.accepted(call.xid, Rpc.accept.SUCCESS).u32(nfs_status.OK)
        let budget = min(max(Int(count), 512), 8192)
        var at = start
        while at < children.count {
            guard let name = vfs.wire_name(children[at]), let attributes = vfs.attributes(children[at]) else { break }
            let entry_len = 4 + 4 + 4 + Xdr.padded(name.utf16.count * 2) + 4
            if writer.len() + entry_len + 8 > budget { break }
            at += 1
            writer.some().u32(attributes.fileid).utf16(name).u32(attributes.fileid)
        }
        logger.trace(
            "readdir served", call.xid, vfs.name(index) ?? "", cookie, at - start, children.count, at >= children.count)
        return writer.none().u32(at >= children.count ? 1 : 0).into_bytes()
    }
    private func statfs(_ call: Rpc.Call) -> [UInt8] {
        guard let handle = Self.read_handle(call.reader()) else {
            return Rpc.accepted_empty(call.xid, Rpc.accept.GARBAGE_ARGS)
        }
        guard let (vfs, index) = locate(handle) else {
            logger.warn("statfs of a stale handle", call.xid, handle.description)
            return Self.status_only(call.xid, nfs_status.STALE)
        }
        let host = host_statfs(vfs.source(index) ?? vfs.export_name()) ?? (UInt32(MAX_READ), 4096, 0, 0, 0)
        return Rpc.accepted(call.xid, Rpc.accept.SUCCESS).u32(nfs_status.OK).u32(host.0).u32(host.1).u32(host.2).u32(
            host.3
        ).u32(host.4).into_bytes()
    }
}
private func host_statfs(_ path: String) -> (UInt32, UInt32, UInt32, UInt32, UInt32)? {
    guard !path.utf8.contains(0) else { return nil }
    #if canImport(Darwin)
        var value = statfs()
        guard path.withCString({ statfs($0, &value) }) == 0 else { return nil }
        return (
            UInt32(truncatingIfNeeded: value.f_iosize), UInt32(truncatingIfNeeded: value.f_bsize),
            UInt32(truncatingIfNeeded: value.f_blocks), UInt32(truncatingIfNeeded: value.f_bfree),
            UInt32(truncatingIfNeeded: value.f_bavail)
        )
    #elseif canImport(Glibc)
        var value = statvfs()
        guard path.withCString({ Glibc.statvfs($0, &value) }) == 0 else { return nil }
        return (
            UInt32(truncatingIfNeeded: value.f_bsize), UInt32(truncatingIfNeeded: value.f_bsize),
            UInt32(truncatingIfNeeded: value.f_blocks), UInt32(truncatingIfNeeded: value.f_bfree),
            UInt32(truncatingIfNeeded: value.f_bavail)
        )
    #else
        return nil
    #endif
}
private func write_attributes(_ writer: Xdr.Writer, _ attributes: Attributes) {
    let stat = attributes.stat
    writer.u32(attributes.kind == .directory ? 2 : 1).u32(stat.mode).u32(stat.nlink).u32(stat.uid).u32(stat.gid)
        .u32(UInt32(exactly: attributes.size) ?? .max).u32(stat.blocksize).u32(stat.rdev).u32(stat.blocks).u32(2).u32(
            attributes.fileid)
    for seconds in [stat.accessed, stat.modified, stat.changed] { writer.u32(seconds).u32(0) }
}
private func read_at(_ file: FileHandle, _ offset: UInt64, _ len: Int) throws -> [UInt8] {
    try file.seek(toOffset: offset)
    var out: [UInt8] = []
    out.reserveCapacity(len)
    while out.count < len {
        let data = try file.read(upToCount: len - out.count) ?? Data()
        if data.isEmpty { break }
        out += data
    }
    return out
}
public func split_export(_ path: String) -> (String, String)? {
    let chars = Array(path.unicodeScalars)
    guard chars.count >= 3, chars[1] == ":" else {
        return path.hasPrefix("/")
            ? (
                "/",
                String(String.UnicodeScalarView(path.unicodeScalars.dropFirst())).replacingOccurrences(
                    of: "\\", with: "/")
            ) : nil
    }
    guard chars[2] == "/" || chars[2] == "\\" else { return nil }
    let drive = chars[0].value >= 97 && chars[0].value <= 122 ? UnicodeScalar(chars[0].value - 32)! : chars[0]
    return (
        "/\(drive)/", String(String.UnicodeScalarView(chars.dropFirst(3))).replacingOccurrences(of: "\\", with: "/")
    )
}

private func parse_ipv4(_ text: String) -> Address4? {
    let groups = text.components(separatedBy: ".")
    guard groups.count == 4,
        groups.allSatisfy({
            !$0.isEmpty && ($0.count == 1 || !$0.hasPrefix("0")) && $0.utf8.allSatisfy { (48...57).contains($0) }
        })
    else { return nil }
    return try? Address4(text)
}
