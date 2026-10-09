import DJLinkKit
import DJLinkTestSupport
import Testing

@Suite("NFS 전송 이식 검증", .serialized) @DJLinkActor
struct NFSTransportTests {
    @Test("UTF-16LE 문자열과 다음 XDR 정수의 정렬을 유지한다")
    func xdrPadding() throws {
        var encoder = XDREncoder()
        try encoder.string("abc", encoding: .utf16le)
        encoder.uint(0x12345678)
        #expect(encoder.bytes == [0, 0, 0, 6, 0x61, 0, 0x62, 0, 0x63, 0, 0, 0, 0x12, 0x34, 0x56, 0x78])
        var decoder = XDRDecoder(encoder.bytes)
        #expect(try decoder.string(encoding: .utf16le) == "abc")
        #expect(try decoder.uint() == 0x12345678)
        #expect(throws: (any Error).self) { try nfs.ReadArgs.fromXDR([1]) }
    }
    @Test("RPC 첫 요청의 XID와 AUTH_UNIX 바이트를 유지한다")
    func rpcWireBytes() async throws {
        let factory = FakeSocketFactory()
        let clock = TestClock()
        let conn = try RpcConnection(
            address: "192.168.1.2", retryConfig: RetryConfig(retries: 0), socketFactory: factory, clock: clock)
        let task = Task { try await conn.call(port: 111, program: 100000, version: 2, procedure: 3, data: [0xab]) }
        await clock.waitForTimers(atLeast: 1)
        await clock.settle()
        let socket = try #require(factory.udpSockets.first)
        let sent = try #require(socket.sent.first)
        #expect(sent.port == 111)
        #expect(sent.address == "192.168.1.2")
        var expected: [UInt8] = []
        for value in [2, 0, 2, 100000, 2, 3, 1, 20, 0x967b8703, 0, 0, 0, 0, 0, 0] {
            var bytes = [UInt8].alloc(4)
            bytes.writeUInt32BE(value)
            expected += bytes
        }
        expected += [0xab, 0, 0, 0]
        #expect(sent.message == expected)
        // 원본도 응답 XID를 검증하지 않는다.
        socket.emitMessage([0, 0, 0, 99, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xcd])
        #expect(try await task.value == [0xcd])
        try await conn.disconnect()
        #expect(socket.isClosed)
        #expect(conn.connected)
    }
    @Test("RPC 시간 초과만 재시도하고 같은 요청 바이트를 다시 보낸다")
    func rpcRetry() async throws {
        let factory = FakeSocketFactory()
        let clock = TestClock()
        let conn = try RpcConnection(
            address: "192.168.1.2", retryConfig: RetryConfig(retries: 1, minTimeout: 20, transactionTimeout: 10),
            socketFactory: factory, clock: clock)
        let task = Task { try await conn.call(port: 111, program: 100000, version: 2, procedure: 3, data: []) }
        await clock.waitForTimers(atLeast: 1)
        await clock.settle()
        clock.advance(ms: 10)
        await clock.settle()
        #expect(factory.udpSockets[0].sent.count == 1)
        clock.advance(ms: 20)
        await clock.settle()
        #expect(factory.udpSockets[0].sent.count == 2)
        #expect(factory.udpSockets[0].sent[0].message == factory.udpSockets[0].sent[1].message)
        clock.advance(ms: 10)
        await #expect(throws: TimeoutError.self) { try await task.value }
        factory.udpSockets[0].emitMessage([0])
    }
    @Test("retry 기본 지수 지연과 최대 지연을 적용한다")
    func retryBackoff() async throws {
        let clock = TestClock()
        var attempts: [Int] = []
        let task = Task { @DJLinkActor in
            try await withRetry(
                clock: clock, options: RetryOptions(retries: 3, factor: 2, minTimeout: 10, maxTimeout: 25)
            ) { attempt in
                attempts.append(attempt)
                if attempt < 4 { throw TimeoutError() }
                return 42
            }
        }
        await clock.waitForTimers(atLeast: 1)
        clock.advance(ms: 10)
        await clock.settle()
        #expect(attempts == [1, 2])
        clock.advance(ms: 20)
        await clock.settle()
        #expect(attempts == [1, 2, 3])
        clock.advance(ms: 25)
        #expect(try await task.value == 42)
        #expect(attempts == [1, 2, 3, 4])
    }
    @Test("NFS 읽기 응답의 68바이트 속성과 가변 데이터 정렬을 읽는다")
    func nfsReadResponse() throws {
        var bytes = [UInt8].alloc(4 + 68 + 4 + 4)
        bytes.writeUInt32BE(1, 4)
        bytes.writeUInt32BE(3, 24)
        bytes.writeUInt32BE(3, 72)
        bytes.set([0x10, 0x20, 0x30], 76)
        guard case let .success(body) = try nfs.ReadResponse.fromXDR(bytes) else {
            Issue.record("읽기 응답이 실패했다")
            return
        }
        #expect(body.attributes.type == .regular)
        #expect(body.attributes.size == 3)
        #expect(body.data == [0x10, 0x20, 0x30])
        #expect(try nfs.ReadResponse.success(body).toXDR() == bytes)
    }
}

@DJLinkActor private final class ScriptedNFSSocket: UDPSocket {
    let fake = FakeUDPSocket()
    var pending: [UInt8]?
    let respond: @DJLinkActor ([UInt8]) throws -> [UInt8]
    init(respond: @escaping @DJLinkActor ([UInt8]) throws -> [UInt8]) { self.respond = respond }
    func onMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        fake.onMessage(handler)
    }
    func onceMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        let listener = fake.onceMessage(handler)
        if let pending {
            self.pending = nil
            fake.emitMessage(pending)
        }
        return listener
    }
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) -> SocketListener { fake.onError(handler) }
    func onClose(_ handler: @escaping @DJLinkActor () -> Void) -> SocketListener { fake.onClose(handler) }
    func off(_ listener: SocketListener) { fake.off(listener) }
    func removeAllListeners() { fake.removeAllListeners() }
    func bind(port: Int?, address: String?) async throws -> AddressInfo {
        try await fake.bind(port: port, address: address)
    }
    func send(_ msg: [UInt8], port: Int, address: String, callback: (@DJLinkActor ((any Error)?, Int) -> Void)?) {
        do {
            pending = try respond(msg)
            fake.send(msg, port: port, address: address, callback: callback)
        } catch { callback?(error, 0) }
    }
    func setBroadcast(_ flag: Bool) { fake.setBroadcast(flag) }
    func address() -> AddressInfo? { fake.address() }
    func close(_ callback: (@DJLinkActor () -> Void)?) { fake.close(callback) }
    var isClosed: Bool { fake.isClosed }
}
@DJLinkActor private final class ScriptedNFSFactory: SocketFactory {
    var requests: [rpc.Request] = []
    var udpSockets: [ScriptedNFSSocket] = []
    let contents: [UInt8] = [1, 2, 3, 4, 5]
    let handle = [UInt8](repeating: 0x12, count: 32)
    var failNextLookup = false
    var staleLookups = 0
    var oversizedRead = false
    var exportPaths = ["/C/"]
    func createUDPSocket(reuseAddr: Bool) throws -> any UDPSocket {
        let socket = ScriptedNFSSocket { [self] bytes in
            let packet = try rpc.Packet.fromXDR(bytes)
            guard case let .request(request) = packet.message else { throw DJLinkError("요청이어야 한다") }
            requests.append(request)
            let response: [UInt8]
            switch (request.program, request.procedure) {
            case (portmap.Program, 3):
                var data = [UInt8].alloc(4)
                data.writeUInt32BE(1234)
                response = data
            case (mount.Program, 5):
                let exports = exportPaths.reversed().reduce(nil as mount.ExportList?) { next, path in
                    mount.ExportList(filesystem: path, groups: mount.Groups(name: "*"), next: next)
                }
                response = try mount.ExportListResponse(next: exports).toXDR()
            case (mount.Program, 1): response = try mount.FHStatus.success(handle).toXDR()
            case (nfs.Program, 4):
                if failNextLookup {
                    failNextLookup = false
                    staleLookups += 1
                    response = try nfs.DirectoryOpResponse.failure(70).toXDR()
                } else {
                    let lookup = try nfs.DirectoryOpArgs.fromXDR(request.data)
                    response = try nfs.DirectoryOpResponse.success(
                        nfs.DirectoryOpResponseBody(
                            handle: handle,
                            attributes: nfs.FileAttributes(
                                type: lookup.filename == "folder" ? .directory : .regular, size: contents.count))
                    ).toXDR()
                }
            case (nfs.Program, 6):
                let read = try nfs.ReadArgs.fromXDR(request.data)
                response = try nfs.ReadResponse.success(
                    nfs.ReadBody(
                        attributes: nfs.FileAttributes(type: .regular, size: contents.count),
                        data: oversizedRead
                            ? contents : contents.subarray(read.offset, min(contents.count, read.offset + read.count)))
                ).toXDR()
            default: throw DJLinkError("알 수 없는 시험 요청")
            }
            return try rpc.Packet(
                xid: packet.xid,
                message: .response(
                    .accepted(
                        rpc.AcceptedResponse(verifier: rpc.Auth(flavor: 0, body: []), response: .success(response))))
            ).toXDR()
        }
        udpSockets.append(socket)
        return socket
    }
    func createTCPConnection() throws -> any TCPConnection { throw DJLinkError("이 시험은 UDP만 쓴다") }
}

extension NFSTransportTests {
    @Test("NFS 파일·범위 읽기·정보 조회에서 연결과 루트 핸들을 재사용한다")
    func fileOperations() async throws {
        let factory = ScriptedNFSFactory()
        let clock = TestClock()
        let device = mockDevice(ip: try Address4("192.0.2.10"))
        configureNFSDependencies(socketFactory: factory, clock: clock)
        configureRetryStrategy(RetryConfig(retries: 0))
        defer {
            resetDeviceCache(device)
            configureNFSDependencies(socketFactory: LiveSocketFactory.shared, clock: SystemClock.shared)
            configureRetryStrategy(RetryConfig())
        }
        var progress: [FetchProgress] = []
        let data = try await fetchFile(
            device: device, slot: .usb, path: "/folder/fixture.bin", onProgress: { progress.append($0) }, chunkSize: 2)
        #expect(data == [1, 2, 3, 4, 5])
        #expect(
            progress == [
                FetchProgress(read: 2, total: 5), FetchProgress(read: 4, total: 5), FetchProgress(read: 5, total: 5),
            ])
        let reads = try factory.requests.filter { $0.program == nfs.Program && $0.procedure == 6 }.map {
            try nfs.ReadArgs.fromXDR($0.data)
        }
        #expect(reads.map(\.offset) == [0, 2, 4])
        #expect(reads.map(\.count) == [2, 2, 2])
        #expect(
            try await fetchFileRange(device: device, slot: .usb, path: "folder/fixture.bin", offset: 4, length: 100)
                == [5])
        #expect(
            try await fetchFileRange(device: device, slot: .usb, path: "folder/fixture.bin", offset: 100, length: 100)
                == [])
        let info = try await getFileInfo(device: device, slot: .usb, path: "folder/fixture.bin")
        #expect(info.size == 5)
        #expect(info.name == "fixture.bin")
        #expect(info.handle == factory.handle)
        #expect(factory.requests.filter { $0.program == portmap.Program }.count == 2)
        #expect(factory.requests.filter { $0.program == mount.Program }.count == 2)
        #expect(clock.pendingTimerCount == 0)
        resetDeviceCache(device)
        _ = try await getFileInfo(device: device, slot: .usb, path: "folder/fixture.bin")
        #expect(factory.requests.filter { $0.program == portmap.Program }.count == 4)
    }
    @Test("오래된 루트 핸들로 조회가 실패하면 캐시를 지우고 한 번 재마운트한다")
    func staleRootHandle() async throws {
        let factory = ScriptedNFSFactory()
        let clock = TestClock()
        let device = mockDevice(ip: try Address4("192.0.2.11"))
        configureNFSDependencies(socketFactory: factory, clock: clock)
        defer {
            resetDeviceCache(device)
            configureNFSDependencies(socketFactory: LiveSocketFactory.shared, clock: SystemClock.shared)
        }
        _ = try await getFileInfo(device: device, slot: .usb, path: "folder/fixture.bin")
        factory.failNextLookup = true
        #expect(try await fetchFile(device: device, slot: .usb, path: "folder/fixture.bin") == factory.contents)
        #expect(factory.staleLookups == 1)
        #expect(factory.requests.filter { $0.program == mount.Program && $0.procedure == 1 }.count == 2)
    }
}

extension NFSTransportTests {
    @Test("retry의 forever·0 지연·최대 재시도 시간 오류 선택을 유지한다")
    func retryOptionEdges() async throws {
        let clock = TestClock()
        var attempts: [Int] = []
        let forever = Task { @DJLinkActor in
            try await withRetry(
                clock: clock, options: RetryOptions(retries: 0, minTimeout: 0, forever: true, maxRetryTime: 0)
            ) { attempt in
                attempts.append(attempt)
                if attempt < 3 { throw TimeoutError() }
                return 1
            }
        }
        await clock.waitForTimers(atLeast: 1)
        clock.advance(ms: 1)
        await clock.settle()
        #expect(attempts == [1, 2])
        clock.advance(ms: 1)
        #expect(try await forever.value == 1)
        let limited = Task { @DJLinkActor in
            try await withRetry(clock: clock, options: RetryOptions(retries: 3, minTimeout: 10, maxRetryTime: 10)) {
                attempt -> Int in
                throw DJLinkError(attempt == 1 ? "first" : "second")
            }
        }
        await clock.waitForTimers(atLeast: 1)
        clock.advance(ms: 10)
        // promise-retry는 retry(err)가 false이면 마지막으로 넘긴 오류로 거절한다.
        await #expect(throws: DJLinkError("second")) { try await limited.value }
    }
    @Test("일반 XDR opaque 패딩은 검사하고 Pioneer 문자열 패딩은 건너뛴다")
    func paddingCompatibility() throws {
        var opaque = XDRDecoder([0, 0, 0, 1, 1, 0xff, 0, 0])
        #expect(throws: DJLinkError("invalid padding")) { try opaque.variableOpaque() }
        var filename = XDRDecoder([0, 0, 0, 2, 0x41, 0, 0xff, 0xff])
        #expect(try filename.string(encoding: .utf16le) == "A")
        #expect(throws: DJLinkError("invalid XDR contract typecast - source buffer not entirely consumed")) {
            try mount.MountRequest.fromXDR([0, 0, 0, 0, 0, 0, 0, 0])
        }
    }
}

extension NFSTransportTests {
    @Test("NFS 데이터가 남은 목적지 크기를 넘으면 Node RangeError로 거절한다")
    func oversizedReadResponse() async throws {
        let factory = ScriptedNFSFactory()
        let conn = try RpcConnection(address: "192.0.2.15", socketFactory: factory, clock: TestClock())
        let program = RpcProgram(conn, nfs.Program, nfs.Version, 1234)
        let file = FileInfo(handle: factory.handle, name: "fixture.bin", size: 1, type: .regular)
        await #expect(throws: BufferRangeError("offset is out of bounds")) {
            try await fetchFile(program, file)
        }
        factory.oversizedRead = true
        await #expect(throws: BufferRangeError("offset is out of bounds")) {
            try await fetchFileRange(program, file, 0, 1)
        }
        try await conn.disconnect()
    }

    @Test("재시도 횟수를 다 쓰면 가장 흔한 오류가 아닌 마지막 오류로 거절한다")
    func retryLastError() async {
        let clock = TestClock()
        let task = Task { @DJLinkActor in
            try await withRetry(clock: clock, options: RetryOptions(retries: 2, factor: 1, minTimeout: 1)) {
                attempt -> Int in
                throw DJLinkError(attempt < 3 ? "first" : "second")
            }
        }
        await clock.waitForTimers(atLeast: 1)
        clock.advance(ms: 1)
        await clock.settle()
        clock.advance(ms: 1)
        await #expect(throws: DJLinkError("second")) { try await task.value }
    }

    @Test("같은 장치의 두 경로를 동시에 마운트해도 캐시 항목을 잃지 않는다")
    func concurrentMountCache() async throws {
        let factory = ScriptedNFSFactory()
        factory.exportPaths = ["/C/", "/E/", "/F/"]
        let clock = TestClock()
        let device = mockDevice(type: .rekordbox, ip: try Address4("192.0.2.16"))
        configureNFSDependencies(socketFactory: factory, clock: clock)
        defer {
            resetDeviceCache(device)
            configureNFSDependencies(socketFactory: LiveSocketFactory.shared, clock: SystemClock.shared)
        }
        _ = try await getFileInfo(device: device, slot: .rb, path: "C:/fixture.bin")
        let first = Task { try await getFileInfo(device: device, slot: .rb, path: "E:/fixture.bin") }
        let second = Task { try await getFileInfo(device: device, slot: .rb, path: "F:/fixture.bin") }
        _ = try await first.value
        _ = try await second.value
        #expect(factory.requests.filter { $0.program == mount.Program && $0.procedure == 1 }.count == 3)
        _ = try await getFileInfo(device: device, slot: .rb, path: "E:/fixture.bin")
        _ = try await getFileInfo(device: device, slot: .rb, path: "F:/fixture.bin")
        #expect(factory.requests.filter { $0.program == mount.Program && $0.procedure == 1 }.count == 3)
    }
}

extension NFSTransportTests {
    @Test("경로 검사 훅이 던지면 소켓을 만들거나 요청을 보내기 전에 멈춘다(CLI 안전을 위한 추가)")
    func pathGuardStopsBeforeAnyRequest() async throws {
        let factory = ScriptedNFSFactory()
        let clock = TestClock()
        let device = mockDevice(ip: try Address4("192.0.2.20"))
        let seen = CallRecorder<String>()
        configureNFSDependencies(socketFactory: factory, clock: clock)
        configureNFSPathGuard { _, slot, path in
            seen.record("\(slot.rawValue):\(path)")
            if path.contains("extracted") { throw DJLinkError("blocked") }
        }
        defer {
            configureNFSPathGuard(nil)
            resetDeviceCache(device)
            configureNFSDependencies(socketFactory: LiveSocketFactory.shared, clock: SystemClock.shared)
        }
        await #expect(throws: DJLinkError("blocked")) {
            try await fetchFile(device: device, slot: .usb, path: "PIONEER/extracted/x")
        }
        await #expect(throws: DJLinkError("blocked")) {
            try await fetchFileRange(device: device, slot: .usb, path: "PIONEER/extracted/x", offset: 0, length: 4)
        }
        await #expect(throws: DJLinkError("blocked")) {
            try await getFileInfo(device: device, slot: .usb, path: "PIONEER/extracted/x")
        }
        #expect(factory.requests.isEmpty)
        #expect(seen.calls.count == 3)
        // 허용한 경로는 그대로 읽힌다.
        #expect(try await fetchFile(device: device, slot: .usb, path: "folder/fixture.bin") == factory.contents)
        #expect(!factory.requests.isEmpty)
    }

    @Test("모든 NFS 클라이언트를 닫으면 RPC 소켓이 닫히고 다음 요청은 새로 연결한다(CLI 안전을 위한 추가)")
    func closeAllClients() async throws {
        let factory = ScriptedNFSFactory()
        let clock = TestClock()
        let device = mockDevice(ip: try Address4("192.0.2.21"))
        configureNFSDependencies(socketFactory: factory, clock: clock)
        defer {
            resetDeviceCache(device)
            configureNFSDependencies(socketFactory: LiveSocketFactory.shared, clock: SystemClock.shared)
        }
        _ = try await getFileInfo(device: device, slot: .usb, path: "folder/fixture.bin")
        #expect(factory.udpSockets.count == 1)
        #expect(factory.udpSockets.allSatisfy { !$0.isClosed })
        await closeAllNFSClients()
        #expect(factory.udpSockets.allSatisfy { $0.isClosed })
        _ = try await getFileInfo(device: device, slot: .usb, path: "folder/fixture.bin")
        #expect(factory.udpSockets.count == 2)
        #expect(!factory.udpSockets[1].isClosed)
        // 아무것도 없을 때 부르는 것도 안전하다.
        await closeAllNFSClients()
        await closeAllNFSClients()
    }
}
