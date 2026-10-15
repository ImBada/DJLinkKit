// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbl-fakecdj/src/lib.rs (실제 소켓으로 서버를 시험하는 클라이언트 쪽)
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import DJLinkExportDBServer
import DJLinkExportNFS
import DJLinkKit
import Foundation

/// 가짜 CDJ의 클라이언트 절반. 서버를 실제 127.0.0.1 소켓으로 끝까지 시험한다.
///
/// ExportIntegrationSupport.swift의 `FakePlayer*`는 가짜 소켓 버스가 응답을 송신 중에 돌려주는 것을 전제로 하고
/// 시간 제한도 없다. 실제 소켓은 응답이 나중에 오고 서버가 멈추면 영원히 기다리므로, 원본처럼 2초 제한이 있는
/// 클라이언트를 따로 둔다. 아무것도 쓰지 않는 읽기 전용 클라이언트라는 점은 원본과 같다.
///
/// 원본과 다름:
/// - `Io`·`Rpc`·`Xdr` 오류 갈래는 만들지 않고, 밑에서 올라온 오류를 그대로 던진다(시험은 갈래를 가리지 않는다).
/// - RPC 클라이언트는 `0.0.0.0` 대신 서버 주소(127.0.0.1)에 묶는다. 시험은 127.0.0.1만 쓴다는 규칙 때문이고,
///   그 밖의 주소로는 보내지도 연결하지도 않고 던진다.
/// - TCP `set_nodelay(true)`는 `TCPConnection`에 같은 옵션이 없어 옮기지 않았다.
enum FakeCdj {
    /// 요청 하나가 재시도나 포기 전까지 기다리는 시간.
    static let TIMEOUT: Duration = .seconds(2)

    enum CdjError: Error, Equatable {
        case nfs(UInt32)
        case rejected(reply: UInt32, accept: UInt32)
        case notRegistered
        case noExport(String)
        case noDatabasePort
        case notAFile(String)
    }

    /// LAN에 아무것도 보내지 않도록 127.0.0.1 밖의 주소는 거절한다.
    static func requireLoopback(_ address: AddressInfo) throws {
        guard address.address == "127.0.0.1" else {
            throw DJLinkError("the fake CDJ only talks to 127.0.0.1, not \(address.address)")
        }
    }

    /// 2초 안에 오지 않으면 던지는 TCP 읽기(원본의 `set_read_timeout`).
    @DJLinkActor
    static func timed_read(_ stream: any TCPConnection, _ size: Int?) async throws -> [UInt8]? {
        try await withTimeout(clock: SystemClock.shared, TIMEOUT) { try await stream.read(size) }
    }

    /// 2초 안에 연결하지 못하면 던지는 TCP 연결(원본의 `connect_timeout`).
    @DJLinkActor
    private static func open_stream(_ address: AddressInfo, _ factory: any SocketFactory) async throws
        -> any TCPConnection
    {
        try requireLoopback(address)
        let stream = try factory.createTCPConnection()
        do {
            try await withTimeout(clock: SystemClock.shared, TIMEOUT) {
                try await stream.connect(port: address.port, host: address.address)
            }
        } catch {
            stream.destroy(nil)
            throw error
        }
        return stream
    }

    /// UDP 소켓 하나 위의 RPC 클라이언트.
    @DJLinkActor
    final class RpcClient {
        private let socket: any UDPSocket
        private(set) var server: AddressInfo
        private var xid: UInt32 = 1
        // 응답은 송신이 끝나기 전에도 올 수 있으므로 소켓 이벤트로 먼저 모아 둔다.
        private var inbox: [[UInt8]] = []

        private init(_ socket: any UDPSocket, _ server: AddressInfo) {
            self.socket = socket
            self.server = server
            socket.onMessage { [weak self] bytes, _ in self?.inbox.append(bytes) }
        }

        static func connect(_ server: AddressInfo, _ factory: any SocketFactory) async throws -> RpcClient {
            try FakeCdj.requireLoopback(server)
            let socket = try factory.createUDPSocket(reuseAddr: false)
            do {
                _ = try await socket.bind(port: 0, address: server.address)
            } catch {
                try? socket.close()
                throw error
            }
            return RpcClient(socket, server)
        }

        /// portmap이 방금 알려 준 다른 포트로 옮긴다.
        func retarget(_ port: Int) { server.port = port }

        func close() { try? socket.close() }

        /// 호출 하나를 보내고 절차의 결과를 돌려준다.
        func call(_ program: UInt32, _ version: UInt32, _ procedure: UInt32, _ arguments: [UInt8]) async throws
            -> [UInt8]
        {
            xid &+= 1
            let request = Rpc.Call(
                xid: xid, program: program, version: version, procedure: procedure,
                // 실제 플레이어가 보내는 스탬프. 우리 서버는 무시하지만 rekordbox는 아닐 수 있다.
                credential: Rpc.Auth(flavor: Rpc.AUTH_UNIX, body: FakeCdj.unix_credential()),
                verifier: .null(), arguments: arguments
            ).encode()
            try await udpSend(socket, request, server.port, server.address)

            // 먼저 시간이 초과된 호출의 응답이 뒤늦게 올 수 있으므로, 기다리는 xid가 아닌 것은 건너뛴다.
            var deadline = ContinuousClock.now + FakeCdj.TIMEOUT
            while true {
                guard !inbox.isEmpty else {
                    guard ContinuousClock.now < deadline else { throw TimeoutError("the RPC reply timed out") }
                    try await Task.sleep(for: .milliseconds(1))
                    continue
                }
                let bytes = inbox.removeFirst()
                deadline = ContinuousClock.now + FakeCdj.TIMEOUT
                guard let reply = try? Rpc.Reply.decode(bytes) else { continue }
                if reply.xid != xid { continue }
                if !reply.is_success() {
                    throw CdjError.rejected(reply: reply.reply_status, accept: reply.accept_status)
                }
                return reply.results
            }
        }
    }

    /// CDJ가 보내는 `AUTH_UNIX` 본문. 스탬프, 빈 기계 이름, id 없음.
    static func unix_credential() -> [UInt8] {
        Xdr.Writer.with_capacity(24)
            .u32(Rpc.CDJ_AUTH_STAMP)
            .string("")
            .u32(0)  // uid
            .u32(0)  // gid
            .u32(0)  // 보조 그룹 없음
            .into_bytes()
    }

    /// 마운트한 export. 걸어 다니며 읽을 준비가 된 상태.
    @DJLinkActor
    final class Mounted {
        private let nfs: RpcClient
        private let rootHandle: [UInt8]

        fileprivate init(_ nfs: RpcClient, _ rootHandle: [UInt8]) {
            self.nfs = nfs
            self.rootHandle = rootHandle
        }

        func root() -> [UInt8] { rootHandle }

        func close() { nfs.close() }

        /// 디렉터리 하나에서 이름 하나를, 플레이어처럼 찾는다.
        func lookup(_ parent: [UInt8], _ name: String) async throws -> [UInt8] {
            let arguments = Xdr.Writer().opaque_fixed(parent).utf16(name).into_bytes()
            let results = try await nfs.call(PROGRAM_NFS, VERSION_NFS, nfs_proc.LOOKUP, arguments)
            let reader = Xdr.Reader(results)
            let status = try reader.u32()
            if status != nfs_status.OK { throw CdjError.nfs(status) }
            return try reader.opaque_fixed(HANDLE_LEN)
        }

        /// 루트부터 경로 전체를 걷는다.
        func resolve(_ path: String) async throws -> [UInt8] {
            var at = rootHandle
            for part in path.split(separator: "/") { at = try await lookup(at, String(part)) }
            return at
        }

        /// 쿠키를 끝까지 따라가며 디렉터리를 나열한다.
        func list(_ handle: [UInt8]) async throws -> [String] {
            var names: [String] = []
            var cookie: UInt32 = 0
            while true {
                let arguments = Xdr.Writer().opaque_fixed(handle).u32(cookie).u32(8192).into_bytes()
                let results = try await nfs.call(PROGRAM_NFS, VERSION_NFS, nfs_proc.READDIR, arguments)
                let reader = Xdr.Reader(results)
                let status = try reader.u32()
                if status != nfs_status.OK { throw CdjError.nfs(status) }
                while try reader.u32() == 1 {
                    _ = try reader.u32()  // fileid
                    names.append(try reader.utf16())
                    cookie = try reader.u32()
                }
                if try reader.u32() == 1 { return names }
            }
        }

        /// 곡을 불러오는 플레이어처럼 파일 전체를 조각 단위로 가져온다.
        func read_file(_ path: String) async throws -> [UInt8] {
            let handle = try await resolve(path)
            var out: [UInt8] = []
            while true {
                let offset = UInt32(exactly: out.count) ?? UInt32.max
                let arguments = Xdr.Writer()
                    .opaque_fixed(handle)
                    .u32(offset)
                    .u32(UInt32(exactly: MAX_READ) ?? 8192)
                    .u32(0)
                    .into_bytes()
                let results = try await nfs.call(PROGRAM_NFS, VERSION_NFS, nfs_proc.READ, arguments)
                let reader = Xdr.Reader(results)
                let status = try reader.u32()
                if status == nfs_status.ISDIR { throw CdjError.notAFile(path) }
                if status != nfs_status.OK { throw CdjError.nfs(status) }
                // 속성은 32비트 필드 17개이고 여섯째가 크기다. 플레이어는 알려 준 크기까지만 읽는다.
                // rekordbox는 끝에서 읽으면 빈 성공이 아니라 IO로 답한다.
                var size: UInt32 = 0
                for field in 0..<17 {
                    let value = try reader.u32()
                    if field == 5 { size = value }
                }
                let chunk = try reader.opaque()
                out += chunk
                if chunk.isEmpty || (UInt32(exactly: out.count) ?? UInt32.max) >= size { return out }
            }
        }
    }

    /// portmap에서 프로그램의 포트를 묻고 export를 마운트해, 루트에 선 클라이언트를 돌려준다.
    @DJLinkActor
    static func mount(_ portmap: AddressInfo, _ export: String, _ factory: any SocketFactory) async throws -> Mounted {
        let client = try await RpcClient.connect(portmap, factory)
        defer { client.close() }

        let mount_port = try await get_port(client, PROGRAM_MOUNT, VERSION_MOUNT)
        let nfs_port = try await get_port(client, PROGRAM_NFS, VERSION_NFS)

        let mount_client = try await RpcClient.connect(
            AddressInfo(address: portmap.address, port: Int(mount_port)), factory)
        defer { mount_client.close() }
        let exports = try await list_exports(mount_client)
        if !exports.contains(export) { throw CdjError.noExport(export) }

        let arguments = Xdr.Writer().utf16(export).into_bytes()
        let results = try await mount_client.call(PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.MNT, arguments)
        let reader = Xdr.Reader(results)
        let status = try reader.u32()
        if status != nfs_status.OK { throw CdjError.nfs(status) }
        let root = try reader.opaque_fixed(HANDLE_LEN)

        let nfs = try await RpcClient.connect(AddressInfo(address: portmap.address, port: Int(nfs_port)), factory)
        return Mounted(nfs, root)
    }

    @DJLinkActor
    private static func get_port(_ client: RpcClient, _ program: UInt32, _ version: UInt32) async throws -> UInt16 {
        let arguments = Xdr.Writer().u32(program).u32(version).u32(DJLinkExportNFS.IPPROTO_UDP).u32(0).into_bytes()
        let results = try await client.call(PROGRAM_PORTMAP, VERSION_PORTMAP, portmap_proc.GETPORT, arguments)
        let port = try Xdr.Reader(results).u32()
        guard let value = UInt16(exactly: port), value != 0 else { throw CdjError.notRegistered }
        return value
    }

    @DJLinkActor
    private static func list_exports(_ client: RpcClient) async throws -> [String] {
        let results = try await client.call(PROGRAM_MOUNT, VERSION_MOUNT, mount_proc.EXPORT, [])
        let reader = Xdr.Reader(results)
        var names: [String] = []
        while try reader.u32() == 1 {
            names.append(try reader.utf16())
            // 쓰지 않는 그룹 목록.
            while try reader.u32() == 1 { try reader.skip_opaque() }
        }
        return names
    }

    /// 데이터베이스 서버와의 세션.
    @DJLinkActor
    final class Database {
        private let stream: any TCPConnection
        private var transaction: UInt32 = 0
        private var pending: [UInt8] = []

        private init(_ stream: any TCPConnection) { self.stream = stream }

        /// 연결하고 setup 교환까지 마친다.
        static func connect(_ address: AddressInfo, _ our_device: UInt8, _ factory: any SocketFactory) async throws
            -> Database
        {
            let stream = try await FakeCdj.open_stream(address, factory)
            let session = Database(stream)
            do {
                // 플레이어처럼 인사를 양쪽으로 먼저 나눈다(실측).
                try await stream.write(GREETING)
                guard let greeting = try await FakeCdj.timed_read(stream, GREETING.count), greeting == GREETING else {
                    throw CdjError.noDatabasePort
                }
                try await session.send(setup_request(our_device))
                _ = try await session.receive()
            } catch {
                stream.destroy(nil)
                throw error
            }
            return session
        }

        func close() { stream.destroy(nil) }

        func send(_ message: DJLinkExportDBServer.Message) async throws {
            try await stream.write(message.encode())
        }

        /// 다음 트랜잭션 번호로 요청을 보내고 응답을 읽는다.
        func request(_ request_kind: UInt16, _ arguments: [DJLinkExportDBServer.Argument]) async throws
            -> [DJLinkExportDBServer.Message]
        {
            transaction &+= 1
            try await send(.new(transaction, request_kind, arguments))
            return try await receive()
        }

        /// 온전한 메시지가 하나 이상 모일 때까지 읽는다.
        func receive() async throws -> [DJLinkExportDBServer.Message] {
            while true {
                let (messages, used) = DJLinkExportDBServer.Message.decode_all(pending)
                if !messages.isEmpty {
                    pending.removeFirst(used)
                    return messages
                }
                guard let chunk = try await FakeCdj.timed_read(stream, nil), !chunk.isEmpty else { return [] }
                pending += chunk
            }
        }
    }

    /// 포트 질의 서비스에 데이터베이스 서버가 어디서 듣는지 묻는다.
    @DJLinkActor
    static func database_port(_ query: AddressInfo, _ factory: any SocketFactory) async throws -> UInt16 {
        let stream = try await open_stream(query, factory)
        defer { stream.destroy(nil) }
        try await stream.write(PORT_QUERY_REQUEST)
        let received: [UInt8]?
        do {
            received = try await timed_read(stream, 2)
        } catch {
            throw CdjError.noDatabasePort
        }
        guard let answer = received, answer.count == 2 else { throw CdjError.noDatabasePort }
        return UInt16(answer[0]) << 8 | UInt16(answer[1])
    }
}
