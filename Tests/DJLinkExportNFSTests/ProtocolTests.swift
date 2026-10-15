import DJLinkExportSupport
import DJLinkExportTestSupport
import DJLinkKit
import DJLinkTestSupport
// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-nfs/tests/protocol.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation
import Testing

@testable import DJLinkExportNFS

private typealias Reader = Xdr.Reader
private typealias Writer = Xdr.Writer
private typealias Call = Rpc.Call
private typealias Auth = Rpc.Auth
private typealias Reply = Rpc.Reply
private let nfsPort: UInt16 = 12049
private let mountPort: UInt16 = 12005
private final class TempDir {
    let path: String
    init() throws {
        path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
    func join(_ name: String) -> String { path + "/" + name }
    deinit { try? FileManager.default.removeItem(atPath: path) }
}
private func write(_ path: String, _ bytes: [UInt8]) throws { try Data(bytes).write(to: URL(fileURLWithPath: path)) }
private func mkdir(_ path: String) throws {
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
}
private func symlink(_ target: String, _ link: String) throws {
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
}
private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }
private func word(_ value: UInt32) -> [UInt8] {
    [
        UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
        UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value),
    ]
}
private enum LookupResult: Equatable {
    case ok(Handle), err(UInt32)
    func unwrap() throws -> Handle {
        if case let .ok(handle) = self { return handle }
        throw DJLinkError("lookup failed")
    }
    func unwrap_err() throws -> UInt32 {
        if case let .err(status) = self { return status }
        throw DJLinkError("lookup succeeded")
    }
    func is_ok() -> Bool {
        if case .ok = self { return true }
        return false
    }
}
@DJLinkActor
private var xid: UInt32 = 0x1234
@DJLinkActor
private func fixture() throws -> (TempDir, Server) {
    let dir = try TempDir()
    try write(dir.join("track.mp3"), Array(repeating: 7, count: 40000))
    try write(dir.join("small.dat"), bytes("hello"))
    let vfs = Vfs("/")
    vfs.add_file("Contents/ARTBAT/The Abyss.mp3", dir.join("track.mp3"), 40000, 1700000000)
    vfs.add_file("PIONEER/rekordbox/export.pdb", dir.join("small.dat"), 5, 1700000001)
    vfs.add_dir("PIONEER/USBANLZ")
    let exports = Exports()
    exports.insert(vfs)
    return (dir, Server(exports, nfsPort, mountPort))
}
@DJLinkActor
private func call(_ program: UInt32, _ version: UInt32, _ procedure: UInt32, _ arguments: [UInt8]) -> [UInt8] {
    defer { xid &+= 1 }
    return Call(
        xid: xid, program: program, version: version, procedure: procedure,
        credential: Auth(flavor: Rpc.AUTH_UNIX, body: Array(repeating: 0, count: 8)), verifier: .null(),
        arguments: arguments
    ).encode()
}
@DJLinkActor
private func ask(_ server: Server, _ program: UInt32, _ version: UInt32, _ procedure: UInt32, _ args: [UInt8]) throws
    -> [UInt8]
{ try #require(server.handle(call(program, version, procedure, args))) }
private func ok_reader(_ reply: [UInt8]) throws -> Reader {
    let parsed = try Reply.decode(reply)
    #expect(parsed.is_success())
    #expect(parsed.xid >= 0x1234)
    return parsed.reader()
}
@DJLinkActor
private func mount_root(_ server: Server) throws -> Handle {
    let reply = try ask(server, PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.MNT, Writer().utf16("/").into_bytes())
    let reader = try ok_reader(reply)
    #expect(try reader.u32() == nfs_status.OK)
    return try #require(Handle.from_slice(reader.opaque_fixed(HANDLE_LEN)))
}
@DJLinkActor
private func lookup(_ server: Server, _ parent: Handle, _ name: String) throws -> LookupResult {
    let reply = try ask(
        server, PROGRAM_NFS, VERSION_NFS, nfs_proc.LOOKUP,
        Writer().opaque_fixed(parent.as_bytes()).utf16(name).into_bytes())
    let reader = try ok_reader(reply)
    let status = try reader.u32()
    if status != nfs_status.OK { return .err(status) }
    return .ok(try #require(Handle.from_slice(reader.opaque_fixed(HANDLE_LEN))))
}
@DJLinkActor
private func lookup_path(_ server: Server, _ root: Handle, _ path: String) throws -> LookupResult {
    var at = root
    for part in path.split(separator: "/") {
        switch try lookup(server, at, String(part)) {
        case let .ok(handle): at = handle
        case let .err(status): return .err(status)
        }
    }
    return .ok(at)
}
private func from_hex(_ hex: String) -> [UInt8] {
    let chars = Array(hex)
    return stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...$0 + 1]), radix: 16)! }
}
private let XDJ700_MOUNT_REPLY = "0000000100000001000000010000000000000000000000000000000000000000"
private let XDJ700_FIRST_LOOKUPS = [
    "0000000100000001000000010301000000001b58000000001104010002a33812",
    "0000000100000001000000010301000000001b58000000001104010004450197",
]
private let XDJ700_TAIL_TO_REKORDBOX = "0301000000001b5800000000110401000cce428f"
private func as_xdj700_sends(_ handle: Handle) throws -> Handle {
    var raw = handle.as_bytes()
    raw.replaceSubrange(12..., with: from_hex(XDJ700_TAIL_TO_REKORDBOX))
    return try #require(Handle.from_slice(raw))
}
@DJLinkActor
private func read_whole(_ server: Server, _ handle: Handle) throws -> [UInt8] {
    let PLAYER_READ: UInt32 = 32 * 1024
    var out: [UInt8] = []
    while true {
        let args = Writer().opaque_fixed(handle.as_bytes()).u32(UInt32(out.count)).u32(PLAYER_READ).u32(0)
        let reader = try ok_reader(ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.READ, args.into_bytes()))
        let status = try reader.u32()
        if status == nfs_status.IO { return out }
        #expect(status == nfs_status.OK)
        for _ in 0..<17 { _ = try reader.u32() }
        let chunk = try reader.opaque()
        #expect(!chunk.isEmpty)
        out += chunk
    }
}
@DJLinkActor
private func read_edge_fixture() throws -> (TempDir, Server, Handle, Handle) {
    let dir = try TempDir()
    try write(dir.join("nonempty.dat"), bytes("hello"))
    try write(dir.join("empty.dat"), [])
    let vfs = Vfs("/")
    let file = vfs.add_file("nonempty.dat", dir.join("nonempty.dat"), 5, 1700000000)
    let empty = vfs.add_file("empty.dat", dir.join("empty.dat"), 0, 1700000000)
    let handles = (try #require(vfs.handle(file)), try #require(vfs.handle(empty)))
    let exports = Exports()
    exports.insert(vfs)
    return (dir, Server(exports, nfsPort, mountPort), handles.0, handles.1)
}
private func read_edge_arguments(_ handle: Handle, _ offset: UInt32, _ count: UInt32) -> [UInt8] {
    Writer().opaque_fixed(handle.as_bytes()).u32(offset).u32(count).u32(0).into_bytes()
}
private func read_edge_envelope(_ xid: UInt32, _ accept_status: UInt32) -> [UInt8] {
    [xid, 1, 0, 0, 0, accept_status].flatMap(word)
}
@DJLinkActor
private func assert_read_edge_status(
    _ server: Server, _ handle: Handle, _ offset: UInt32, _ count: UInt32, _ status: UInt32
) throws {
    let request = call(PROGRAM_NFS, VERSION_NFS, nfs_proc.READ, read_edge_arguments(handle, offset, count))
    let xid = try Call.decode(request).xid
    #expect(server.handle(request) == read_edge_envelope(xid, 0) + word(status))
}
@DJLinkActor
private func list(_ server: Server, _ handle: Handle, _ count: UInt32) throws -> [String] {
    var names: [String] = []
    var cookie: UInt32 = 0
    for _ in 0..<100 {
        let args = Writer().opaque_fixed(handle.as_bytes()).u32(cookie).u32(count)
        let reader = try ok_reader(ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.READDIR, args.into_bytes()))
        #expect(try reader.u32() == nfs_status.OK)
        while try reader.u32() == 1 {
            _ = try reader.u32()
            names.append(try reader.utf16())
            cookie = try reader.u32()
        }
        if try reader.u32() == 1 { return names }
    }
    throw DJLinkError("listing never reached the end")
}

@Suite("protocol") @DJLinkActor
struct ProtocolTests {
    @Test("xdr_pads_every_field_to_four_bytes") func xdr_pads_every_field_to_four_bytes() throws {
        for (text, expected) in [("", 4), ("a", 8), ("abc", 8), ("abcd", 8), ("abcde", 12)] {
            let writer = Writer().string(text)
            #expect(writer.len() == expected)
            #expect(try Reader(writer.as_slice()).string() == text)
        }
    }
    @Test("utf16_names_declare_a_byte_length_not_a_character_count")
    func utf16_names_declare_a_byte_length_not_a_character_count() throws {
        let raw = Writer().utf16("PIONEER").into_bytes()
        #expect(Array(raw[0..<4]) == word(14))
        #expect(Array(raw[4..<8]) == [80, 0, 73, 0])
        #expect(try Reader(raw).utf16() == "PIONEER")
    }
    @Test("an_odd_length_utf16_name_is_rejected_rather_than_truncated")
    func an_odd_length_utf16_name_is_rejected_rather_than_truncated() {
        #expect(throws: (any Error).self) { try Reader(Writer().opaque([65, 0, 66]).as_slice()).utf16() }
    }
    @Test("an_absurd_length_does_not_allocate") func an_absurd_length_does_not_allocate() {
        #expect(throws: (any Error).self) { try Reader(word(UInt32.max) + [0, 0, 0, 0]).opaque() }
    }
    @Test("a_truncated_field_is_an_error_at_every_cut") func a_truncated_field_is_an_error_at_every_cut() {
        let raw = Writer().u32(1).utf16("Melodic Techno").opaque([1, 2, 3]).into_bytes()
        for cut in 0..<raw.count {
            #expect(throws: (any Error).self) {
                let reader = Reader(Array(raw.prefix(cut)))
                _ = try reader.u32()
                _ = try reader.utf16()
                _ = try reader.opaque()
            }
        }
    }
    @Test("an_rpc_call_round_trips") func an_rpc_call_round_trips() throws {
        let original = Call(
            xid: 99, program: PROGRAM_NFS, version: VERSION_NFS, procedure: nfs_proc.READ,
            credential: Auth(flavor: Rpc.AUTH_UNIX, body: Array(repeating: 9, count: 12)), verifier: .null(),
            arguments: [1, 2, 3, 4])
        #expect(try Call.decode(original.encode()) == original)
    }
    @Test("a_reply_is_never_mistaken_for_a_call") func a_reply_is_never_mistaken_for_a_call() {
        do {
            _ = try Call.decode(Rpc.accepted_empty(1, Rpc.accept.SUCCESS))
            Issue.record("a reply decoded as a call")
        } catch Rpc.RpcError.notACall(_) {} catch { Issue.record("unexpected error: \(error)") }
    }
    @Test("a_wrong_rpc_version_is_answered_with_the_version_we_speak")
    func a_wrong_rpc_version_is_answered_with_the_version_we_speak() throws {
        var raw = call(PROGRAM_NFS, VERSION_NFS, nfs_proc.NULL, [])
        raw.replaceSubrange(8..<12, with: word(3))
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let parsed = try Reply.decode(#require(server.handle(raw)))
        #expect(parsed.reply_status == Rpc.MSG_DENIED)
        #expect(parsed.accept_status == Rpc.reject.RPC_MISMATCH)
    }
    @Test("garbage_is_dropped_rather_than_answered") func garbage_is_dropped_rather_than_answered() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        #expect(server.handle([]) == nil)
        #expect(server.handle([0, 0, 0]) == nil)
        #expect(server.handle(Array(repeating: 0xff, count: 40)) == nil)
    }
    @Test("an_unknown_program_is_reported_unavailable") func an_unknown_program_is_reported_unavailable() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        #expect(try Reply.decode(ask(server, 999999, 1, 0, [])).accept_status == Rpc.accept.PROG_UNAVAIL)
    }
    @Test("a_wrong_program_version_names_the_version_we_serve")
    func a_wrong_program_version_names_the_version_we_serve() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let parsed = try Reply.decode(ask(server, PROGRAM_NFS, 3, nfs_proc.NULL, []))
        #expect(parsed.accept_status == Rpc.accept.PROG_MISMATCH)
        let reader = parsed.reader()
        #expect(try reader.u32() == VERSION_NFS)
        #expect(try reader.u32() == VERSION_NFS)
    }
    @Test("portmap_reports_where_each_program_listens") func portmap_reports_where_each_program_listens() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        for (program, version, expected) in [
            (PROGRAM_NFS, VERSION_NFS, nfsPort), (PROGRAM_MOUNT, VERSION_MOUNT, mountPort),
        ] {
            let args = Writer().u32(program).u32(version).u32(DJLinkExportNFS.IPPROTO_UDP).u32(0)
            #expect(
                try ok_reader(ask(server, PROGRAM_PORTMAP, VERSION_PORTMAP, portmap_proc.GETPORT, args.into_bytes()))
                    .u32() == UInt32(expected))
        }
    }
    @Test("portmap_reports_zero_for_tcp_and_for_programs_we_do_not_serve")
    func portmap_reports_zero_for_tcp_and_for_programs_we_do_not_serve() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        for (program, protocolValue) in [
            (PROGRAM_NFS, DJLinkExportNFS.IPPROTO_TCP), (100024, DJLinkExportNFS.IPPROTO_UDP),
        ] {
            let args = Writer().u32(program).u32(2).u32(protocolValue).u32(0)
            #expect(
                try ok_reader(ask(server, PROGRAM_PORTMAP, VERSION_PORTMAP, portmap_proc.GETPORT, args.into_bytes()))
                    .u32() == 0)
        }
    }
    @Test("rekordbox_answers_portmap_on_its_own_port") func rekordbox_answers_portmap_on_its_own_port() {
        #expect(REKORDBOX_PORTMAP_PORT == 50111)
        #expect(STANDARD_PORTMAP_PORT == 111)
        #expect(NFS_PORT == 2049)
    }
    @Test("local_dynamic_portmap_registration_is_explicitly_unsupported")
    func local_dynamic_portmap_registration_is_explicitly_unsupported() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        for procedure in [UInt32(1), 2] {
            let args = Writer().u32(PROGRAM_NFS).u32(2).u32(DJLinkExportNFS.IPPROTO_UDP).u32(9999)
            #expect(
                try Reply.decode(ask(server, PROGRAM_PORTMAP, VERSION_PORTMAP, procedure, args.into_bytes()))
                    .accept_status == Rpc.accept.PROC_UNAVAIL)
        }
        let args = Writer().u32(PROGRAM_NFS).u32(2).u32(DJLinkExportNFS.IPPROTO_UDP).u32(0)
        #expect(
            try ok_reader(ask(server, PROGRAM_PORTMAP, VERSION_PORTMAP, portmap_proc.GETPORT, args.into_bytes())).u32()
                == UInt32(nfsPort))
    }
    @Test("getport_matches_program_service_version_and_transport_exactly")
    func getport_matches_program_service_version_and_transport_exactly() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        for (program, version, expected) in [
            (PROGRAM_NFS, VERSION_NFS, nfsPort), (PROGRAM_MOUNT, VERSION_MOUNT, mountPort),
        ] {
            for requested in [UInt32(0), 1, 2, 3, .max] {
                for protocolValue in [DJLinkExportNFS.IPPROTO_UDP, DJLinkExportNFS.IPPROTO_TCP, 0] {
                    let args = Writer().u32(program).u32(requested).u32(protocolValue).u32(0)
                    let request = call(PROGRAM_PORTMAP, VERSION_PORTMAP, portmap_proc.GETPORT, args.into_bytes())
                    let xid = try Call.decode(request).xid
                    let port =
                        requested == version && protocolValue == DJLinkExportNFS.IPPROTO_UDP ? UInt32(expected) : 0
                    #expect(server.handle(request) == Rpc.accepted(xid, Rpc.accept.SUCCESS).u32(port).into_bytes())
                }
            }
        }
    }
    @Test("remote_portmap_registration_returns_false_without_changing_maps")
    func remote_portmap_registration_returns_false_without_changing_maps() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        for from in [try Address4("127.0.0.2"), try Address4("192.168.1.20")] {
            for procedure in [portmap_proc.SET, portmap_proc.UNSET] {
                let args = Writer().u32(PROGRAM_NFS).u32(VERSION_NFS).u32(DJLinkExportNFS.IPPROTO_UDP).u32(9999)
                let request = call(PROGRAM_PORTMAP, VERSION_PORTMAP, procedure, args.into_bytes())
                let xid = try Call.decode(request).xid
                #expect(
                    server.handle_from(request, from, 40000)
                        == Rpc.accepted(xid, Rpc.accept.SUCCESS).u32(0).into_bytes())
            }
        }
        let args = Writer().u32(PROGRAM_NFS).u32(VERSION_NFS).u32(DJLinkExportNFS.IPPROTO_UDP).u32(0)
        #expect(
            try ok_reader(ask(server, PROGRAM_PORTMAP, VERSION_PORTMAP, portmap_proc.GETPORT, args.into_bytes())).u32()
                == UInt32(nfsPort))
    }
    @Test("mount_dump_is_unavailable_and_exportall_is_the_same_bounded_list")
    func mount_dump_is_unavailable_and_exportall_is_the_same_bounded_list() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let request = call(PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.DUMP, [])
        let xid = try Call.decode(request).xid
        #expect(server.handle(request) == Rpc.accepted_empty(xid, Rpc.accept.PROC_UNAVAIL))
        let export = try ask(server, PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.EXPORT, [])
        var export_all = try ask(server, PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.EXPORTALL, [])
        export_all.replaceSubrange(0..<4, with: export[0..<4])
        #expect(export_all == export)
    }
    @Test("malformed_specific_unmount_keeps_every_host_and_export")
    func malformed_specific_unmount_keeps_every_host_and_export() throws {
        let exports = Exports()
        exports.insert(Vfs("/"))
        exports.insert(Vfs("/other"))
        let server = Server(exports, nfsPort, mountPort)
        let first = try Address4("192.168.1.20")
        let second = try Address4("192.168.1.21")
        for from in [first, second] {
            for path in ["/", "/other"] {
                let request = call(PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.MNT, Writer().utf16(path).into_bytes())
                #expect(try ok_reader(#require(server.handle_from(request, from, 40000))).u32() == nfs_status.OK)
            }
        }
        for args in [[UInt8](), [0, 0, 0, 8, 47, 0, 0, 0], [0, 0, 0, 1, 47, 0, 0, 0]] {
            let request = call(PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.UMNT, args)
            let xid = try Call.decode(request).xid
            #expect(server.handle_from(request, first, 40000) == Rpc.accepted_empty(xid, Rpc.accept.SUCCESS))
            #expect(server.is_mounted(first))
            #expect(server.is_mounted(second))
        }
        _ = server.handle_from(
            call(PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.UMNT, Writer().utf16("/").into_bytes()), first, 40000)
        #expect(server.is_mounted(first))
        #expect(server.is_mounted(second))
        _ = server.handle_from(call(PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.UMNTALL, []), first, 40000)
        #expect(!server.is_mounted(first))
        #expect(server.is_mounted(second))
    }
    @Test("duplicate_mounts_are_scoped_to_the_actual_receiving_socket")
    func duplicate_mounts_are_scoped_to_the_actual_receiving_socket() async throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let stop = AtomicBool(false)
        let clock = TestClock()
        let factory = FakeExportSocketFactory(clock: clock)
        // 원본과 다름: 실제 UDP 3개와 blocking worker 2개를 같은 송수신을 하는 가짜와 액터 Task로 대체한다.
        let first = try factory.createUDPSocket(reuseAddr: false)
        let second = try factory.createUDPSocket(reuseAddr: false)
        let peer = try factory.createUDPSocket(reuseAddr: false)
        let first_addr = try await udpBind(first, 0, "127.0.0.1")
        let second_addr = try await udpBind(second, 0, "127.0.0.1")
        _ = try await udpBind(peer, 0, "127.0.0.1")
        let workers = [first, second].map { socket in
            Task { @DJLinkActor in try await Net.serve(server, socket, stop, clock: clock) }
        }
        await clock.waitForTimers(atLeast: 2)
        var responses: [([UInt8], RemoteInfo)] = []
        let listener = peer.onMessage { responses.append(($0, $1)) }
        defer { peer.off(listener) }
        func exchange(_ request: [UInt8], _ receiver: AddressInfo) throws -> [UInt8] {
            responses.removeAll()
            peer.send(request, port: receiver.port, address: receiver.address)
            let response = try #require(responses.first)
            #expect(response.1.address == receiver.address)
            #expect(response.1.port == receiver.port)
            #expect(response.0.count <= 256)
            return response.0
        }
        let mount = call(PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.MNT, Writer().utf16("/").into_bytes())
        let original = try exchange(mount, first_addr)
        #expect(try ok_reader(original).u32() == nfs_status.OK)
        #expect(server.is_mounted(try Address4("127.0.0.1")))
        let unmount = call(PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.UMNTALL, [])
        let xid = try Call.decode(unmount).xid
        #expect(try exchange(unmount, first_addr) == Rpc.accepted_empty(xid, Rpc.accept.SUCCESS))
        #expect(!server.is_mounted(try Address4("127.0.0.1")))
        #expect(try exchange(mount, first_addr) == original)
        #expect(!server.is_mounted(try Address4("127.0.0.1")))
        #expect(try exchange(mount, second_addr) == original)
        #expect(server.is_mounted(try Address4("127.0.0.1")))
        stop.store(true)
        clock.advance(ms: 100)
        for worker in workers { try await worker.value }
    }
    @Test("the_export_list_is_a_terminated_linked_list") func the_export_list_is_a_terminated_linked_list() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let reader = try ok_reader(ask(server, PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.EXPORT, []))
        #expect(try reader.u32() == 1)
        #expect(try reader.utf16() == "/")
        #expect(try reader.u32() == 0)
        #expect(try reader.u32() == 0)
        #expect(reader.remaining() == 0)
    }
    @Test("each_export_offers_the_host_group_a_cdj_checks_itself_against")
    func each_export_offers_the_host_group_a_cdj_checks_itself_against() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        server.with_export_host("192.168.1.14/255.255.255.0")
        let reader = try ok_reader(ask(server, PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.EXPORT, []))
        #expect(try reader.u32() == 1)
        #expect(try reader.utf16() == "/")
        #expect(try reader.u32() == 1)
        #expect(try reader.string() == "192.168.1.14/255.255.255.0")
        #expect(try reader.u32() == 0)
        #expect(try reader.u32() == 0)
        #expect(reader.remaining() == 0)
    }
    @Test("mounting_an_export_that_does_not_exist_says_so") func mounting_an_export_that_does_not_exist_says_so() throws
    {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        #expect(
            try ok_reader(ask(server, PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.MNT, Writer().utf16("/D/").into_bytes()))
                .u32() == nfs_status.ACCES)
    }
    @Test("unmounting_succeeds_even_though_we_hold_no_state") func unmounting_succeeds_even_though_we_hold_no_state()
        throws
    {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        for procedure in [mount_proc.UMNT, mount_proc.UMNTALL, mount_proc.NULL] {
            #expect(try Reply.decode(ask(server, PROGRAM_MOUNT, VERSION_MOUNT, procedure, [])).is_success())
        }
    }
    @Test("a_player_can_walk_from_the_mount_point_to_a_track") func a_player_can_walk_from_the_mount_point_to_a_track()
        throws
    {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        #expect(try lookup_path(server, root, "Contents/ARTBAT/The Abyss.mp3").is_ok())
        #expect(try lookup_path(server, root, "PIONEER/rekordbox/export.pdb").is_ok())
    }
    @Test("a_name_that_is_not_there_is_noent_not_a_guess") func a_name_that_is_not_there_is_noent_not_a_guess() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        #expect(try lookup(server, root, "Nope").unwrap_err() == nfs_status.NOENT)
        let contents = try lookup(server, root, "Contents").unwrap()
        #expect(try lookup(server, contents, "PIONEER").unwrap_err() == nfs_status.NOENT)
    }
    @Test("dot_dot_cannot_climb_out_of_the_export") func dot_dot_cannot_climb_out_of_the_export() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        var at = root
        for _ in 0..<8 { at = try lookup(server, at, "..").unwrap() }
        #expect(at == root)
        #expect(try lookup_path(server, root, "Contents/ARTBAT/../../../../..").unwrap() == root)
    }
    @Test("a_name_containing_a_separator_matches_nothing") func a_name_containing_a_separator_matches_nothing() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        for name in ["Contents/ARTBAT", "/etc/passwd", "../../etc/passwd", "Contents\\ARTBAT"] {
            #expect(try lookup(server, root, name).unwrap_err() == nfs_status.NOENT)
        }
    }
    @Test("looking_up_inside_a_file_is_notdir") func looking_up_inside_a_file_is_notdir() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let file = try lookup_path(server, root, "PIONEER/rekordbox/export.pdb").unwrap()
        #expect(try lookup(server, file, "anything").unwrap_err() == nfs_status.NOTDIR)
    }
    @Test("a_forged_handle_is_stale_not_a_node") func a_forged_handle_is_stale_not_a_node() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        var forged = root.as_bytes()
        forged[7] = 5
        let handle = try #require(Handle.from_slice(forged))
        #expect(
            try ok_reader(
                ask(
                    server, PROGRAM_NFS, VERSION_NFS, nfs_proc.GETATTR,
                    Writer().opaque_fixed(handle.as_bytes()).into_bytes())
            ).u32() == nfs_status.STALE)
        var wrong_root = root.as_bytes()
        wrong_root[11] = 2
        var zero = root.as_bytes()
        zero[3] = 0
        for forged in [wrong_root, zero] {
            #expect(
                try ok_reader(
                    ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.GETATTR, Writer().opaque_fixed(forged).into_bytes())
                ).u32() == nfs_status.STALE)
        }
    }
    @Test("the_xdj700s_first_lookup_resolves_under_the_mount_handle")
    func the_xdj700s_first_lookup_resolves_under_the_mount_handle() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        #expect(root.as_bytes() == from_hex(XDJ700_MOUNT_REPLY))
        for sent in XDJ700_FIRST_LOOKUPS {
            let handle = try #require(Handle.from_slice(from_hex(sent)))
            #expect(try lookup(server, handle, "Contents").is_ok())
            let pioneer = try lookup(server, handle, "PIONEER").unwrap()
            #expect(try pioneer == lookup(server, root, "PIONEER").unwrap())
        }
    }
    @Test("the_xdj700_walks_to_a_track_and_reads_it_with_its_own_trailing_bytes")
    func the_xdj700_walks_to_a_track_and_reads_it_with_its_own_trailing_bytes() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        var at = try mount_root(server)
        for part in ["Contents", "ARTBAT", "The Abyss.mp3"] {
            at = try lookup(server, as_xdj700_sends(at), part).unwrap()
        }
        let sent = try as_xdj700_sends(at)
        #expect(
            try ok_reader(
                ask(
                    server, PROGRAM_NFS, VERSION_NFS, nfs_proc.GETATTR,
                    Writer().opaque_fixed(sent.as_bytes()).into_bytes())
            ).u32() == nfs_status.OK)
        #expect(try read_whole(server, sent) == Array(repeating: 7, count: 40000))
    }
    @Test("a_handle_displays_as_its_words_and_trailing_bytes") func a_handle_displays_as_its_words_and_trailing_bytes()
        throws
    {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        #expect(
            try mount_root(server).description == "00000001.00000001.00000001."
                + String(repeating: "00", count: HANDLE_LEN - 12))
    }
    @Test("attributes_describe_a_read_only_tree") func attributes_describe_a_read_only_tree() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let file = try lookup_path(server, root, "Contents/ARTBAT/The Abyss.mp3").unwrap()
        let reader = try ok_reader(
            ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.GETATTR, Writer().opaque_fixed(file.as_bytes()).into_bytes())
        )
        #expect(try reader.u32() == nfs_status.OK)
        #expect(try reader.u32() == 1)
        #expect(try reader.u32() & 0o170000 == 0o100000)
        #expect(try reader.u32() == 1)
        _ = try reader.u32()
        _ = try reader.u32()
        #expect(try reader.u32() == 40000)
        _ = try reader.u32()
        _ = try reader.u32()
        _ = try reader.u32()
        #expect(try reader.u32() == 2)
        let directory = try lookup(server, root, "Contents").unwrap()
        let dir_reader = try ok_reader(
            ask(
                server, PROGRAM_NFS, VERSION_NFS, nfs_proc.GETATTR,
                Writer().opaque_fixed(directory.as_bytes()).into_bytes()))
        #expect(try dir_reader.u32() == nfs_status.OK)
        #expect(try dir_reader.u32() == 2)
        #expect(try dir_reader.u32() == 0o040755)
    }
    @Test("a_file_reads_back_byte_for_byte") func a_file_reads_back_byte_for_byte() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let file = try lookup_path(server, root, "Contents/ARTBAT/The Abyss.mp3").unwrap()
        let data = try read_whole(server, file)
        #expect(data.count == 40000)
        #expect(data.allSatisfy { $0 == 7 })
        let small = try lookup_path(server, root, "PIONEER/rekordbox/export.pdb").unwrap()
        #expect(try read_whole(server, small) == bytes("hello"))
    }
    @Test("a_registered_file_does_not_hide_an_allowed_folder_beside_it")
    func a_registered_file_does_not_hide_an_allowed_folder_beside_it() throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let music = dir.join("Music")
        let transcend = dir.join("Transcend")
        try mkdir(music + "/PioneerDJ")
        try write(music + "/PioneerDJ/one.mp3", Array(repeating: 3, count: 70000))
        try mkdir(transcend + "/Ron")
        try write(transcend + "/Ron/two.mp3", bytes("two"))
        try write(dir.join("loose.mp3"), bytes("loose"))
        let vfs = Vfs("/")
        vfs.add_file_unsized("Volumes/SD/loose.mp3", dir.join("loose.mp3"))
        vfs.allow_folder("Volumes/SD/Music", music)
        vfs.allow_folder("Volumes/Transcend/Music", transcend)
        let exports = Exports()
        exports.insert(vfs)
        let server = Server(exports, nfsPort, mountPort)
        let root = try mount_root(server)
        let one = try lookup_path(server, root, "Volumes/SD/Music/PioneerDJ/one.mp3").unwrap()
        #expect(try read_whole(server, one) == Array(repeating: 3, count: 70000))
        let two = try lookup_path(server, root, "Volumes/Transcend/Music/Ron/two.mp3").unwrap()
        #expect(try read_whole(server, two) == bytes("two"))
        let loose = try lookup_path(server, root, "Volumes/SD/loose.mp3").unwrap()
        #expect(try read_whole(server, loose) == bytes("loose"))
        #expect(try lookup_path(server, root, "Volumes/SD/Other").unwrap_err() == nfs_status.NOENT)
        #expect(try lookup_path(server, root, "Volumes/Other").unwrap_err() == nfs_status.NOENT)
    }
    @Test("each_new_read_reopens_the_file_and_reports_its_current_attributes")
    func each_new_read_reopens_the_file_and_reports_its_current_attributes() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let handle = try lookup_path(server, root, "Contents/ARTBAT/The Abyss.mp3").unwrap()
        func read() throws -> (UInt32, [UInt8]) {
            let args = Writer().opaque_fixed(handle.as_bytes()).u32(0).u32(32768).u32(0)
            let reader = try ok_reader(ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.READ, args.into_bytes()))
            #expect(try reader.u32() == nfs_status.OK)
            var size: UInt32 = 0
            for field in 0..<17 {
                let value = try reader.u32()
                if field == 5 { size = value }
            }
            return (size, try reader.opaque())
        }
        let first = try read()
        #expect(first.0 == 40000)
        #expect(first.1 == Array(repeating: 7, count: 32768))
        let replacement: [UInt8] = Array(repeating: 9, count: 16384)
        try write(dir.join("replacement.mp3"), replacement)
        try FileManager.default.removeItem(atPath: dir.join("track.mp3"))
        try FileManager.default.moveItem(atPath: dir.join("replacement.mp3"), toPath: dir.join("track.mp3"))
        let second = try read()
        #expect(second.0 == 16384)
        #expect(second.1 == replacement)
        try FileManager.default.removeItem(atPath: dir.join("track.mp3"))
        try assert_read_edge_status(server, handle, 0, 32768, nfs_status.IO)
    }
    @Test("cdj_32_kib_reads_are_complete_before_the_end_of_the_file")
    func cdj_32_kib_reads_are_complete_before_the_end_of_the_file() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let file = try lookup_path(server, root, "Contents/ARTBAT/The Abyss.mp3").unwrap()
        for offset in [UInt32(0), 4096] {
            let args = Writer().opaque_fixed(file.as_bytes()).u32(offset).u32(32768).u32(0)
            let reader = try ok_reader(ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.READ, args.into_bytes()))
            #expect(try reader.u32() == nfs_status.OK)
            for _ in 0..<17 { _ = try reader.u32() }
            #expect(try reader.opaque() == Array(repeating: 7, count: 32768))
            #expect(reader.remaining() == 0)
        }
    }
    @Test("a_read_is_capped_at_the_protocol_limit_however_much_is_asked_for")
    func a_read_is_capped_at_the_protocol_limit_however_much_is_asked_for() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let file = try lookup_path(server, root, "Contents/ARTBAT/The Abyss.mp3").unwrap()
        let args = Writer().opaque_fixed(file.as_bytes()).u32(0).u32(.max).u32(.max)
        let reader = try ok_reader(ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.READ, args.into_bytes()))
        #expect(try reader.u32() == nfs_status.OK)
        for _ in 0..<17 { _ = try reader.u32() }
        #expect(MAX_READ == 0xfc00)
        #expect(try reader.opaque().count == min(40000, MAX_READ))
    }
    @Test("reading_at_or_past_the_end_is_io_as_rekordbox_answers_it")
    func reading_at_or_past_the_end_is_io_as_rekordbox_answers_it() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let file = try lookup_path(server, root, "PIONEER/rekordbox/export.pdb").unwrap()
        for offset in [UInt32(1000000), 40000] {
            let args = Writer().opaque_fixed(file.as_bytes()).u32(offset).u32(4096).u32(0)
            #expect(
                try ok_reader(ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.READ, args.into_bytes())).u32()
                    == nfs_status.IO)
        }
    }
    @Test("read_edge_zero_count_is_io_for_nonempty_and_empty_files")
    func read_edge_zero_count_is_io_for_nonempty_and_empty_files() throws {
        let (dir, server, file, empty) = try read_edge_fixture()
        defer { withExtendedLifetime(dir) {} }
        try assert_read_edge_status(server, file, 0, 0, nfs_status.IO)
        try assert_read_edge_status(server, empty, 0, 0, nfs_status.IO)
        try assert_read_edge_status(server, empty, 0, 4096, nfs_status.IO)
        try assert_read_edge_status(server, file, 2, 0, nfs_status.IO)
        #expect(try Array(Data(contentsOf: URL(fileURLWithPath: dir.join("nonempty.dat")))) == bytes("hello"))
        #expect(try Array(Data(contentsOf: URL(fileURLWithPath: dir.join("empty.dat")))) == bytes(""))
    }
    @Test("read_edge_exact_eof_and_past_eof_have_status_only_io_replies")
    func read_edge_exact_eof_and_past_eof_have_status_only_io_replies() throws {
        let (dir, server, file, _) = try read_edge_fixture()
        defer { withExtendedLifetime(dir) {} }
        for offset in [UInt32(5), 6, .max] {
            for count in [UInt32(0), 1, 4096] {
                try assert_read_edge_status(server, file, offset, count, nfs_status.IO)
            }
        }
    }
    @Test("read_edge_stale_handle_is_stale_even_when_count_is_zero")
    func read_edge_stale_handle_is_stale_even_when_count_is_zero() throws {
        let (dir, server, _, _) = try read_edge_fixture()
        defer { withExtendedLifetime(dir) {} }
        let stale = try #require(Handle.from_slice(Array(repeating: 0xff, count: HANDLE_LEN)))
        for count in [UInt32(0), 4096] { try assert_read_edge_status(server, stale, 0, count, nfs_status.STALE) }
    }
    @Test("read_edge_positive_short_read_keeps_attributes_length_data_and_padding")
    func read_edge_positive_short_read_keeps_attributes_length_data_and_padding() throws {
        let (dir, server, file, _) = try read_edge_fixture()
        defer { withExtendedLifetime(dir) {} }
        try assert_read_edge_status(server, file, 0, 0, nfs_status.IO)
        for count in [UInt32(4096), .max] {
            let request = call(PROGRAM_NFS, VERSION_NFS, nfs_proc.READ, read_edge_arguments(file, 2, count))
            let xid = try Call.decode(request).xid
            let actual = server.handle(request)
            var expected = read_edge_envelope(xid, 0)
            let attributes = try ask(
                server, PROGRAM_NFS, VERSION_NFS, nfs_proc.GETATTR, Writer().opaque_fixed(file.as_bytes()).into_bytes())
            expected += attributes[24..<96]
            expected += word(3)
            expected += bytes("llo\0")
            #expect(actual == expected)
        }
        #expect(try Array(Data(contentsOf: URL(fileURLWithPath: dir.join("nonempty.dat")))) == bytes("hello"))
    }
    @Test("read_edge_truncated_handle_offset_or_count_is_garbage_args")
    func read_edge_truncated_handle_offset_or_count_is_garbage_args() throws {
        let (dir, server, file, _) = try read_edge_fixture()
        defer { withExtendedLifetime(dir) {} }
        let arguments = read_edge_arguments(file, 0, 0)
        for cut in 0..<(HANDLE_LEN + 8) {
            let request = call(PROGRAM_NFS, VERSION_NFS, nfs_proc.READ, Array(arguments.prefix(cut)))
            let xid = try Call.decode(request).xid
            #expect(server.handle(request) == read_edge_envelope(xid, 4))
        }
        try assert_read_edge_status(server, file, 0, 0, nfs_status.IO)
    }
    @Test("reading_a_directory_is_isdir") func reading_a_directory_is_isdir() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let args = Writer().opaque_fixed(root.as_bytes()).u32(0).u32(4096).u32(0)
        #expect(
            try ok_reader(ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.READ, args.into_bytes())).u32()
                == nfs_status.ISDIR)
    }
    @Test("a_directory_lists_its_children") func a_directory_lists_its_children() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        #expect(try list(server, root, 8192) == ["Contents", "PIONEER"])
        let pioneer = try lookup(server, root, "PIONEER").unwrap()
        #expect(try list(server, pioneer, 8192) == ["rekordbox", "USBANLZ"])
        let empty = try lookup(server, pioneer, "USBANLZ").unwrap()
        #expect(try list(server, empty, 8192).isEmpty)
    }
    @Test("a_listing_that_does_not_fit_resumes_from_its_cookie")
    func a_listing_that_does_not_fit_resumes_from_its_cookie() throws {
        let vfs = Vfs("/")
        for i in 0..<200 { vfs.add_file(String(format: "Contents/track %03d.mp3", i), "/dev/null", 0, 0) }
        let exports = Exports()
        exports.insert(vfs)
        let server = Server(exports, nfsPort, mountPort)
        let root = try mount_root(server)
        let contents = try lookup(server, root, "Contents").unwrap()
        let names = try list(server, contents, 512)
        #expect(names.count == 200)
        #expect(names.first == "track 000.mp3")
        #expect(names.last == "track 199.mp3")
        #expect(try names == list(server, contents, 8192))
    }
    @Test("listing_a_file_is_notdir") func listing_a_file_is_notdir() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let file = try lookup_path(server, root, "PIONEER/rekordbox/export.pdb").unwrap()
        let args = Writer().opaque_fixed(file.as_bytes()).u32(0).u32(4096)
        #expect(
            try ok_reader(ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.READDIR, args.into_bytes())).u32()
                == nfs_status.NOTDIR)
    }
    @Test("every_mutating_procedure_is_refused_as_read_only") func every_mutating_procedure_is_refused_as_read_only()
        throws
    {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let args = Writer().opaque_fixed(root.as_bytes()).into_bytes()
        for procedure in [
            nfs_proc.SETATTR, nfs_proc.WRITE, nfs_proc.CREATE, nfs_proc.REMOVE, nfs_proc.RENAME, nfs_proc.MKDIR,
            nfs_proc.RMDIR,
        ] {
            #expect(try ok_reader(ask(server, PROGRAM_NFS, VERSION_NFS, procedure, args)).u32() == nfs_status.STALE)
        }
        for procedure in [nfs_proc.LINK, nfs_proc.SYMLINK, nfs_proc.READLINK] {
            #expect(try ok_reader(ask(server, PROGRAM_NFS, VERSION_NFS, procedure, args)).u32() == nfs_status.ACCES)
        }
    }
    @Test("statfs_reports_the_host_filesystems_figures") func statfs_reports_the_host_filesystems_figures() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let file = try lookup_path(server, root, "PIONEER/rekordbox/export.pdb").unwrap()
        let reader = try ok_reader(
            ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.STATFS, Writer().opaque_fixed(file.as_bytes()).into_bytes()))
        #expect(try reader.u32() == nfs_status.OK)
        let tsize = try reader.u32()
        let bsize = try reader.u32()
        let blocks = try reader.u32()
        #expect(tsize > 0 && bsize > 0 && blocks > 0)
    }
    @Test("a_truncated_request_is_answered_rather_than_dropped")
    func a_truncated_request_is_answered_rather_than_dropped() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        for procedure in [nfs_proc.GETATTR, nfs_proc.LOOKUP, nfs_proc.READ, nfs_proc.READDIR] {
            for len in [0, 4, 16, 31] {
                #expect(
                    try Reply.decode(ask(server, PROGRAM_NFS, VERSION_NFS, procedure, Array(repeating: 0, count: len)))
                        .accept_status == Rpc.accept.GARBAGE_ARGS)
            }
        }
    }
    @Test("handles_survive_a_rebuild_of_the_same_tree") func handles_survive_a_rebuild_of_the_same_tree() {
        func build() -> Vfs {
            let vfs = Vfs("/")
            vfs.add_file("Contents/a.mp3", "/dev/null", 1, 0)
            vfs.add_file("Contents/b.mp3", "/dev/null", 1, 0)
            return vfs
        }
        let first = build()
        let second = build()
        for index in 0..<first.len() { #expect(first.handle(index) == second.handle(index)) }
    }
    @Test("a_handle_from_another_export_is_not_accepted") func a_handle_from_another_export_is_not_accepted() throws {
        let exports = Exports()
        let a = Vfs("/A/")
        let b = Vfs("/B/")
        a.add_file("Contents/x.mp3", "/dev/null", 1, 0)
        b.add_file("Contents/y.mp3", "/dev/null", 1, 0)
        exports.insert(a)
        exports.insert(b)
        let original_server = Server(exports, 2049, 0)
        let first = try #require(original_server.exports().get("/A/"))
        let second = try #require(original_server.exports().get("/B/"))
        #expect(first.handle(1) != second.handle(1))
        #expect(try first.node_of(#require(second.handle(1))) == nil)
        #expect(try second.node_of(#require(first.handle(1))) == nil)
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let args = Writer().opaque_fixed(try #require(second.handle(1)).as_bytes())
        #expect(
            try ok_reader(ask(server, PROGRAM_NFS, VERSION_NFS, nfs_proc.GETATTR, args.into_bytes())).u32()
                == nfs_status.STALE)
    }
    @Test("an_absolute_path_splits_into_the_export_and_the_path_within_it")
    func an_absolute_path_splits_into_the_export_and_the_path_within_it() throws {
        let mac = try #require(split_export("/Users/chris/Music/track.mp3"))
        #expect(mac.0 == "/")
        #expect(mac.1 == "Users/chris/Music/track.mp3")
        let windows = try #require(split_export("C:\\Users\\chris\\Music\\track.mp3"))
        #expect(windows.0 == "/C/")
        #expect(windows.1 == "Users/chris/Music/track.mp3")
        let drive = try #require(split_export("d:/Music/track.mp3"))
        #expect(drive.0 == "/D/")
        #expect(drive.1 == "Music/track.mp3")
        #expect(split_export("relative/path.mp3") == nil)
    }
    @Test("building_the_tree_ignores_traversal_in_a_path") func building_the_tree_ignores_traversal_in_a_path() {
        let vfs = Vfs("/")
        vfs.add_file("../../etc/passwd", "/dev/null", 1, 0)
        #expect(vfs.resolve("etc/passwd") != nil)
        #expect(vfs.resolve("..") == vfs.root())
    }
    @Test("a_call_seen_before_gets_the_reply_it_got_then") func a_call_seen_before_gets_the_reply_it_got_then() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let raw = call(PROGRAM_NFS, VERSION_NFS, nfs_proc.GETATTR, Writer().opaque_fixed(root.as_bytes()).into_bytes())
        let first = try #require(server.handle(raw))
        let again = try #require(server.handle(raw))
        #expect(first == again)
        #expect(try #require(server.handle_from(raw, Address4("192.168.1.152"), 700)) == first)
    }
    @Test("lock_manager_calls_are_dropped_without_a_reply") func lock_manager_calls_are_dropped_without_a_reply() throws
    {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        for program in [PROGRAM_NLM, PROGRAM_NSM] { #expect(server.handle(call(program, 1, 0, [])) == nil) }
        #expect(server.handle(call(100099, 1, 0, [])) != nil)
    }
    @Test("the_export_list_is_empty_and_a_mount_refused_until_the_link_is_up")
    func the_export_list_is_empty_and_a_mount_refused_until_the_link_is_up() throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        try write(dir.join("a.mp3"), bytes("x"))
        let vfs = Vfs("/")
        vfs.add_file("Music/a.mp3", dir.join("a.mp3"), 1, 0)
        let exports = Exports()
        exports.insert(vfs)
        let up = AtomicUInt8(0)
        let server = Server(exports, nfsPort, mountPort).with_gate(up)
        let reader = try ok_reader(ask(server, PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.EXPORT, []))
        #expect(try reader.u32() == 0)
        #expect(
            try ok_reader(ask(server, PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.MNT, Writer().utf16("/").into_bytes()))
                .u32() == nfs_status.ACCES)
        up.store(0x11)
        let listed = try ok_reader(ask(server, PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.EXPORT, []))
        #expect(try listed.u32() == 1)
        #expect(try listed.utf16() == "/")
        let root = try mount_root(server)
        #expect(server.is_mounted(try Address4("127.0.0.1")))
        #expect(server.mounted_hosts() == [try Address4("127.0.0.1")])
        _ = try ask(server, PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.UMNT, Writer().utf16("/").into_bytes())
        #expect(!server.is_mounted(try Address4("127.0.0.1")))
        _ = root
    }
    @Test("a_mount_from_outside_the_export_subnet_is_refused") func a_mount_from_outside_the_export_subnet_is_refused()
        throws
    {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        server.with_export_host("192.168.1.14/255.255.255.0")
        let raw = call(PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.MNT, Writer().utf16("/").into_bytes())
        let inside = try #require(server.handle_from(raw, Address4("192.168.1.152"), 700))
        #expect(try ok_reader(inside).u32() == nfs_status.OK)
        let outside = try #require(server.handle_from(raw, Address4("10.0.0.5"), 700))
        #expect(try ok_reader(outside).u32() == nfs_status.ACCES)
        #expect(server.mounted_hosts() == [try Address4("192.168.1.152")])
    }
    @Test("a_decomposed_name_finds_the_composed_file_and_listings_go_out_decomposed_on_apple")
    func a_decomposed_name_finds_the_composed_file_and_listings_go_out_decomposed_on_apple() throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        try write(dir.join("e.mp3"), bytes("x"))
        let vfs = Vfs("/")
        vfs.add_file("Music/caf\u{e9}.mp3", dir.join("e.mp3"), 1, 0)
        let exports = Exports()
        exports.insert(vfs)
        let server = Server(exports, nfsPort, mountPort)
        let root = try mount_root(server)
        let music = try lookup(server, root, "Music").unwrap()
        #expect(try lookup(server, music, "cafe\u{301}.mp3").is_ok())
        #expect(try lookup(server, music, "caf\u{e9}.mp3").is_ok())
        let listed = try list(server, music, 8192)
        #if canImport(Darwin)
            let expected = "cafe\u{301}.mp3"
        #else
            let expected = "caf\u{e9}.mp3"
        #endif
        // 원본 Rust 문자열 비교는 바이트 비교이므로 Swift의 정규화 동등성에 맡기지 않는다.
        #expect(listed.map { Array($0.utf8) } == [Array(expected.utf8)])
    }
    @Test("readdir_cookies_are_file_ids_and_an_unknown_one_is_io")
    func readdir_cookies_are_file_ids_and_an_unknown_one_is_io() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let reader = try ok_reader(
            ask(
                server, PROGRAM_NFS, VERSION_NFS, nfs_proc.READDIR,
                Writer().opaque_fixed(root.as_bytes()).u32(0).u32(8192).into_bytes()))
        #expect(try reader.u32() == nfs_status.OK)
        #expect(try reader.u32() == 1)
        let fileid = try reader.u32()
        _ = try reader.utf16()
        #expect(try reader.u32() == fileid)
        #expect(
            try ok_reader(
                ask(
                    server, PROGRAM_NFS, VERSION_NFS, nfs_proc.READDIR,
                    Writer().opaque_fixed(root.as_bytes()).u32(0xdead).u32(8192).into_bytes())
            ).u32() == nfs_status.IO)
    }
    @Test("portmap_dumps_its_three_mappings") func portmap_dumps_its_three_mappings() throws {
        let (dir, server) = try fixture()
        defer { withExtendedLifetime(dir) {} }
        let reader = try ok_reader(ask(server, PROGRAM_PORTMAP, VERSION_PORTMAP, 4, []))
        var seen: [(UInt32, UInt32)] = []
        while try reader.u32() == 1 {
            let program = try reader.u32()
            _ = try reader.u32()
            _ = try reader.u32()
            seen.append((program, try reader.u32()))
        }
        #expect(seen.count == 3)
        #expect(seen.contains { $0.0 == PROGRAM_NFS && $0.1 == UInt32(nfsPort) })
        #expect(seen.contains { $0.0 == PROGRAM_MOUNT && $0.1 == UInt32(mountPort) })
    }
    private func folder_fixture() throws -> (TempDir, Server, String) {
        let dir = try TempDir()
        let music = dir.join("Music")
        try mkdir(music + "/Artist/Album")
        try write(music + "/Artist/Album/one.mp3", Array(repeating: 1, count: 3000))
        try write(music + "/Artist/loose.mp3", bytes("loose"))
        try write(music + "/Caf\u{e9}.wav", bytes("composed on disk"))
        try write(dir.join("beside.mp3"), bytes("beside the folder"))
        try symlink(dir.join("beside.mp3"), music + "/link.mp3")
        let (export, folder) = try #require(split_export(music))
        let vfs = Vfs(export)
        vfs.allow_folder(folder, music)
        let exports = Exports()
        exports.insert(vfs)
        return (dir, Server(exports, nfsPort, mountPort), folder)
    }
    @Test("a_track_under_an_allowed_folder_is_found_and_read_without_being_registered")
    func a_track_under_an_allowed_folder_is_found_and_read_without_being_registered() throws {
        let (dir, server, folder) = try folder_fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let one = try lookup_path(server, root, "\(folder)/Artist/Album/one.mp3").unwrap()
        #expect(try read_whole(server, one) == Array(repeating: 1, count: 3000))
        let loose = try lookup_path(server, root, "\(folder)/Artist/loose.mp3").unwrap()
        #expect(try read_whole(server, loose) == bytes("loose"))
        #expect(try lookup_path(server, root, "\(folder)/Artist/Album/one.mp3").unwrap() == one)
    }
    @Test("nothing_beside_or_above_an_allowed_folder_resolves")
    func nothing_beside_or_above_an_allowed_folder_resolves() throws {
        let (dir, server, folder) = try folder_fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let (_, beside) = try #require(split_export(dir.join("beside.mp3")))
        #expect(try lookup_path(server, root, beside) == .err(nfs_status.NOENT))
        let slash = try #require(folder.lastIndex(of: "/"))
        let parent = String(folder[..<slash])
        let last = String(folder[folder.index(after: slash)...])
        let way = try lookup_path(server, root, parent).unwrap()
        #expect(try list(server, way, 8192) == [last])
        #expect(try lookup(server, way, "beside.mp3") == .err(nfs_status.NOENT))
        let allowed = try lookup_path(server, root, folder).unwrap()
        #expect(try lookup(server, allowed, "..") == .ok(way))
        #expect(try lookup(server, way, "..").is_ok())
        #expect(try lookup(server, allowed, "Artist/Album") == .err(nfs_status.NOENT))
    }
    @Test("a_symlink_in_an_allowed_folder_is_not_followed") func a_symlink_in_an_allowed_folder_is_not_followed() throws
    {
        let (dir, server, folder) = try folder_fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        #expect(try lookup_path(server, root, "\(folder)/link.mp3") == .err(nfs_status.NOENT))
        let allowed = try lookup_path(server, root, folder).unwrap()
        let names = try list(server, allowed, 8192)
        #expect(!names.contains("link.mp3"))
    }
    @Test("an_allowed_folder_lists_what_the_host_has_and_a_decomposed_name_finds_a_composed_file")
    func an_allowed_folder_lists_what_the_host_has_and_a_decomposed_name_finds_a_composed_file() throws {
        let (dir, server, folder) = try folder_fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let allowed = try lookup_path(server, root, folder).unwrap()
        let names = try list(server, allowed, 8192)
        #expect(names.contains("Artist"))
        let cafe = try lookup(server, allowed, "Cafe\u{301}.wav").unwrap()
        #expect(try read_whole(server, cafe) == bytes("composed on disk"))
        #expect(try lookup(server, allowed, "Caf\u{e9}.wav") == .ok(cafe))
    }
    @Test("a_mac_library_path_on_a_linux_host_resolves_through_a_volumes_symlink_or_bind_mount")
    func a_mac_library_path_on_a_linux_host_resolves_through_a_volumes_symlink_or_bind_mount() throws {
        let dir = try TempDir()
        defer { withExtendedLifetime(dir) {} }
        let card = dir.join("media/ron/Transcend/Music/Len Faki & Juxta Position")
        try mkdir(card)
        let track = "Len Faki & Juxta Position - Caf\u{e9} (Original Mix).mp3"
        try write(card + "/" + track, bytes("the track"))
        try symlink(dir.join("media/ron"), dir.join("Volumes-link"))
        try mkdir(dir.join("Volumes-bind"))
        try symlink(dir.join("media/ron/Transcend"), dir.join("Volumes-bind/Transcend"))
        for volumes in ["Volumes-link", "Volumes-bind"] {
            let vfs = Vfs("/")
            vfs.allow_folder("Volumes/Transcend/Music", dir.join(volumes) + "/Transcend/Music")
            let exports = Exports()
            exports.insert(vfs)
            let server = Server(exports, nfsPort, mountPort)
            let root = try mount_root(server)
            let stored = "Volumes/Transcend/Music/Len Faki & Juxta Position/\(track)"
            let handle = try lookup_path(server, root, stored).unwrap()
            #expect(try read_whole(server, handle) == bytes("the track"))
            let decomposed =
                "Volumes/Transcend/Music/Len Faki & Juxta Position/"
                + track.replacingOccurrences(of: "\u{e9}", with: "e\u{301}")
            #expect(try lookup_path(server, root, decomposed) == .ok(handle))
            #expect(try lookup_path(server, root, "Volumes/SD") == .err(nfs_status.NOENT))
            #expect(try lookup_path(server, root, "volumes") == .err(nfs_status.NOENT))
        }
    }
    private func symlink_fixture() throws -> (TempDir, Server, String) {
        let dir = try TempDir()
        let music = dir.join("Music")
        let elsewhere = dir.join("elsewhere")
        try mkdir(music + "/Real")
        try mkdir(elsewhere + "/Album")
        try mkdir(elsewhere + "/Private")
        try write(elsewhere + "/Album/one.mp3", bytes("one through a folder link"))
        try write(elsewhere + "/Album/stray.txt", bytes("beside one"))
        try write(elsewhere + "/two.mp3", bytes("two through a file link"))
        try write(elsewhere + "/Private/secret.txt", bytes("no track goes here"))
        try write(elsewhere + "/secret.mp3", bytes("nor here"))
        try symlink(elsewhere + "/Album", music + "/Album")
        try symlink(elsewhere + "/two.mp3", music + "/Real/two.mp3")
        try symlink(elsewhere + "/Private", music + "/Private")
        try symlink(elsewhere + "/secret.mp3", music + "/Real/secret.mp3")
        let (export, folder) = try #require(split_export(music))
        let vfs = Vfs(export)
        vfs.allow_folder(folder, music)
        vfs.allow_track(music + "/Album/one.mp3")
        vfs.allow_track(music + "/Real/two.mp3")
        let exports = Exports()
        exports.insert(vfs)
        return (dir, Server(exports, nfsPort, mountPort), folder)
    }
    @Test("a_symlink_on_a_library_tracks_path_is_followed_and_no_other")
    func a_symlink_on_a_library_tracks_path_is_followed_and_no_other() throws {
        let (dir, server, folder) = try symlink_fixture()
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let one = try lookup_path(server, root, "\(folder)/Album/one.mp3").unwrap()
        #expect(try read_whole(server, one) == bytes("one through a folder link"))
        let two = try lookup_path(server, root, "\(folder)/Real/two.mp3").unwrap()
        #expect(try read_whole(server, two) == bytes("two through a file link"))
        let album = try lookup_path(server, root, "\(folder)/Album").unwrap()
        let names = try list(server, album, 8192).sorted()
        #expect(names == ["one.mp3", "stray.txt"])
        let allowed = try lookup_path(server, root, folder).unwrap()
        #expect(try lookup(server, album, "..") == .ok(allowed))
        #expect(try lookup(server, album, "Private") == .err(nfs_status.NOENT))
        #expect(try lookup_path(server, root, "\(folder)/Private") == .err(nfs_status.NOENT))
        #expect(try lookup_path(server, root, "\(folder)/Private/secret.txt") == .err(nfs_status.NOENT))
        #expect(try lookup_path(server, root, "\(folder)/Real/secret.mp3") == .err(nfs_status.NOENT))
        #expect(try list(server, allowed, 8192).sorted() == ["Album", "Real"])
        let real = try lookup_path(server, root, "\(folder)/Real").unwrap()
        #expect(try list(server, real, 8192) == ["two.mp3"])
    }
    private func link_probe_server(_ setup: (String, Vfs) throws -> Void) throws -> (TempDir, Server, String) {
        let dir = try TempDir()
        let music = dir.join("Music")
        try mkdir(music + "/Real")
        try mkdir(dir.join("secret/inner"))
        try write(dir.join("secret/id_rsa"), bytes("PRIVATE"))
        try write(dir.join("secret/inner/deep"), bytes("DEEP"))
        let (export, folder) = try #require(split_export(music))
        let vfs = Vfs(export)
        vfs.allow_folder(folder, music)
        try setup(dir.path, vfs)
        let exports = Exports()
        exports.insert(vfs)
        return (dir, Server(exports, nfsPort, mountPort), folder)
    }
    @Test("a_track_path_linked_to_a_directory_is_not_followed")
    func a_track_path_linked_to_a_directory_is_not_followed() throws {
        let (dir, server, folder) = try link_probe_server { root, vfs in
            let music = root + "/Music"
            try symlink(root + "/secret", music + "/Real/x.mp3")
            vfs.allow_track(music + "/Real/x.mp3")
        }
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        #expect(try lookup_path(server, root, "\(folder)/Real/x.mp3") == .err(nfs_status.NOENT))
        #expect(try lookup_path(server, root, "\(folder)/Real/x.mp3/id_rsa") == .err(nfs_status.NOENT))
        #expect(try lookup_path(server, root, "\(folder)/Real/x.mp3/inner/deep") == .err(nfs_status.NOENT))
        let real = try lookup_path(server, root, "\(folder)/Real").unwrap()
        #expect(try list(server, real, 8192).isEmpty)
    }
    @Test("a_folder_link_above_a_track_that_points_to_a_file_is_not_followed")
    func a_folder_link_above_a_track_that_points_to_a_file_is_not_followed() throws {
        let (dir, server, folder) = try link_probe_server { root, vfs in
            let music = root + "/Music"
            try symlink(root + "/secret/id_rsa", music + "/Album")
            vfs.allow_track(music + "/Album/one.mp3")
        }
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        #expect(try lookup_path(server, root, "\(folder)/Album") == .err(nfs_status.NOENT))
        #expect(try lookup_path(server, root, "\(folder)/Album/one.mp3") == .err(nfs_status.NOENT))
        let allowed = try lookup_path(server, root, folder).unwrap()
        #expect(try list(server, allowed, 8192) == ["Real"])
    }
    @Test("links_off_a_track_path_lead_nowhere") func links_off_a_track_path_lead_nowhere() throws {
        let (dir, server, folder) = try link_probe_server { root, vfs in
            let music = root + "/Music"
            try mkdir(root + "/ext/Album")
            try write(root + "/ext/Album/one.mp3", bytes("one"))
            try symlink(root + "/secret", root + "/ext/Album/escape")
            try symlink(root + "/ext/Album", music + "/Album")
            try symlink(root + "/secret", music + "/Priv")
            try symlink(root + "/secret", music + "/Al")
            vfs.allow_track(music + "/Album/one.mp3")
            vfs.allow_track(music + "/Real/../Priv/x.mp3")
        }
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        let one = try lookup_path(server, root, "\(folder)/Album/one.mp3").unwrap()
        #expect(try read_whole(server, one) == bytes("one"))
        for path in ["Priv/id_rsa", "Real/../Priv/id_rsa", "Al/id_rsa", "Album/escape", "Album/escape/id_rsa"] {
            #expect(try lookup_path(server, root, "\(folder)/\(path)") == .err(nfs_status.NOENT))
        }
        let album = try lookup_path(server, root, "\(folder)/Album").unwrap()
        let up = try lookup(server, album, "..").unwrap()
        #expect(try lookup_path(server, root, folder) == .ok(up))
        #expect(try lookup(server, up, "secret") == .err(nfs_status.NOENT))
        #expect(try lookup(server, up, "ext") == .err(nfs_status.NOENT))
    }
    @Test("a_link_loop_on_a_track_path_ends") func a_link_loop_on_a_track_path_ends() throws {
        let (dir, server, folder) = try link_probe_server { root, vfs in
            let music = root + "/Music"
            try symlink(music + "/Loop", music + "/Loop")
            try symlink(music, music + "/Self")
            vfs.allow_track(music + "/Loop/x.mp3")
            vfs.allow_track(music + "/Self/Self/Self/x.mp3")
        }
        defer { withExtendedLifetime(dir) {} }
        let root = try mount_root(server)
        #expect(try lookup_path(server, root, "\(folder)/Loop/x.mp3") == .err(nfs_status.NOENT))
        let deepest = try lookup_path(server, root, "\(folder)/Self/Self/Self").unwrap()
        #expect(try lookup(server, deepest, "Self") == .err(nfs_status.NOENT))
    }
}
