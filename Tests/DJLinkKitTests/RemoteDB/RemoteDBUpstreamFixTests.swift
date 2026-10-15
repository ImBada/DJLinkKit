import DJLinkKit
import DJLinkTestSupport
import Synchronization
import Testing

// PLAN §9: 원본 버그를 고친 시험(원본 시험 파일이 아니다).
// - #46: 응답 스트림이 CDJ가 먼저 보낸 메시지 때문에 한 칸씩 밀린다(`src/remotedb/message/index.ts`의 `fromStream`은
//   트랜잭션 번호를 보지 않는다).
// - #47: 연결이 끝나면 시간 제한을 꺼서(`src/remotedb/index.ts`의 `setTimeout(0)`) 응답이 없는 질의가 영영 멈춘다.
// 시험용 바이트는 코드로 만든 것과, 2026-10-16 실기(CDJ-2000nexus)에서 CDJ가 먼저 보낸 54바이트(이슈 #46)뿐이다.

/// 이슈 #46에 적힌, CDJ가 요청하지 않고 보낸 메시지(트랜잭션 0x03800122, 종류 0x4b02, 54바이트).
private let UNSOLICITED_MESSAGE: [UInt8] = hexBytes(
    """
    11 87 23 49 ae 11 03 80 01 22 10 4b 02 0f 04 14 00 00 00 0c 06 06 06 02 00 00 00 00 00 00 00 00
    11 00 00 3e 03 11 00 00 00 00 11 00 00 00 02 26 00 00 00 01 00 00
    """)
private let UNSOLICITED_TRANSACTION = 0x0380_0122
private let UNSOLICITED_TYPE = MessageType(rawValue: 0x4b02)

private func hexBytes(_ text: String) -> [UInt8] {
    text.split(whereSeparator: \.isWhitespace).map { UInt8($0, radix: 16)! }
}

/// 보낸 요청 바이트에서 트랜잭션 번호를 읽는다(0x11 매직 4바이트 0x11 트랜잭션 4바이트).
private func transactionId(ofRequest data: [UInt8]) -> Int {
    try! data.readUInt32BE(6)
}

@DJLinkActor private func artworkResponse(_ transactionId: Int, _ bytes: [UInt8]) -> [UInt8] {
    Message(
        transactionId: transactionId, type: .artwork,
        args: [RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(bytes.count), RemoteDBBinary(bytes)]
    ).buffer
}

@DJLinkActor private func menuItem(_ transactionId: Int, title: String) -> [UInt8] {
    Message(
        transactionId: transactionId, type: .menuItem,
        args: [
            RemoteDBUInt32(0), RemoteDBUInt32(7), RemoteDBUInt32((title.utf16.count + 1) * 2), RemoteDBString(title),
            RemoteDBUInt32(2), RemoteDBString(""), RemoteDBUInt32(ItemType.trackTitle.rawValue), RemoteDBUInt32(0),
            RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(0),
        ]
    ).buffer
}

private final class DebugRecorder: Logger {
    private let lines = Mutex<[String]>([])
    var debugLines: [String] { lines.withLock { $0 } }
    func trace(_ msg: String, _ args: [any Sendable]) {}
    func debug(_ msg: String, _ args: [any Sendable]) { lines.withLock { $0.append(msg) } }
    func info(_ msg: String, _ args: [any Sendable]) {}
    func warn(_ msg: String, _ args: [any Sendable]) {}
    func error(_ msg: String, _ args: [any Sendable]) {}
}

/// 핸드셰이크까지 해 주고, 그 뒤 요청마다 `respond`가 돌려준 바이트를 보내는 CDJ.
@DJLinkActor
private final class ScriptedPlayer: RemoteDBDeviceSource {
    let device = mockDevice()
    var devices: [DeviceID: Device] { [device.id: device] }
    let clock = TestClock()
    let factory = FakeSocketFactory()
    private(set) var connections: [FakeTCPConnection] = []
    /// (연결 번호, 그 연결에서 몇 번째 요청인지, 요청 바이트) -> 보낼 응답 바이트. 비우면 아무 말도 하지 않는다.
    var respond: (Int, Int, [UInt8]) -> [UInt8] = { _, _, _ in [] }
    private(set) var requests: [[[UInt8]]] = []
    /// 소개 응답 앞에 CDJ가 먼저 보내는 바이트.
    var beforeIntroduceReply: [UInt8] = []
    init() {
        factory.makeTCPConnection = { [unowned self] in
            let socket = FakeTCPConnection(clock: clock)
            socket.onConnect = { port, _ in
                if port == 0 {
                    socket.onWrite = { _ in
                        socket.inject([0x12, 0x34])
                        socket.end()
                    }
                } else {
                    let index = self.connections.count
                    self.connections.append(socket)
                    self.requests.append([])
                    var step = 0
                    socket.onWrite = { data in
                        defer { step += 1 }
                        switch step {
                        case 0: socket.inject(RemoteDBUInt32(0x01).buffer)
                        case 1:
                            socket.inject(
                                self.beforeIntroduceReply
                                    + Message(
                                        transactionId: 0xfffffffe, type: .success,
                                        args: [RemoteDBUInt32(0), RemoteDBUInt32(0)]
                                    ).buffer)
                        default:
                            let requestIndex = self.requests[index].count
                            self.requests[index].append(data)
                            let reply = self.respond(index, requestIndex, data)
                            if !reply.isEmpty { socket.inject(reply) }
                        }
                    }
                }
            }
            return socket
        }
    }
    func database() -> RemoteDatabase {
        RemoteDatabase(deviceManager: self, hostDevice: mockDevice(id: 5), socketFactory: factory, serverQueryPort: 0)
    }
    func hangUp() { connections.filter(\.isOpen).forEach { $0.end() } }
}

private let usbRekordbox = QueryDescriptor(menuTarget: .main, trackSlot: .usb, trackType: .rb)

@DJLinkActor
private func artwork(_ remotedb: RemoteDatabase, _ deviceId: DeviceID = 1) async throws -> RemoteDBQueryResult {
    let query = try #require(try await remotedb.get(deviceId))
    return try await query.query(
        queryDescriptor: usbRekordbox, query: .getArtwork, args: RemoteDBQueryArgs(artworkId: 9))
}

@Suite("remotedb 응답이 CDJ가 먼저 보낸 메시지에 밀리지 않는 것(#46)") @DJLinkActor
struct RemoteDBUnsolicitedMessageTests {
    @Test("이슈 #46의 54바이트는 한 메시지로 읽히고 원래 바이트로 다시 만들어진다")
    func capturedBytesDecode() async throws {
        let stream = FakeTCPConnection()
        stream.inject(UNSOLICITED_MESSAGE)
        let message = try await Message.fromStream(stream, UNSOLICITED_TYPE)
        #expect(message.transactionId == UNSOLICITED_TRANSACTION)
        #expect(message.args.count == 4)
        #expect(message.buffer == UNSOLICITED_MESSAGE)
        #expect(UNSOLICITED_MESSAGE.count == 54)
    }
    @Test("트랜잭션 번호를 주지 않으면 원본처럼 순서대로 읽고 종류만 본다")
    func upstreamDefault() async {
        let stream = FakeTCPConnection()
        stream.inject(UNSOLICITED_MESSAGE + artworkResponse(1, [1, 2, 3]))
        await #expect(throws: DJLinkError("Expected message type 0x4002, got 0x4b02")) {
            try await Message.fromStream(stream, .artwork)
        }
    }
    @Test("트랜잭션 번호를 주면 다른 번호의 메시지를 끝까지 읽어 버리고 맞는 번호의 응답을 돌려준다")
    func fromStreamSkipsOtherTransactions() async throws {
        let stream = FakeTCPConnection()
        stream.inject(
            UNSOLICITED_MESSAGE + artworkResponse(1, [1, 2, 3]) + UNSOLICITED_MESSAGE + artworkResponse(2, [4])
                + artworkResponse(3, [5]))
        let first = try await Message.fromStream(stream, .artwork, expectedTransactionId: 2)
        #expect(first.transactionId == 2)
        #expect(try first.data == .artwork([4]))
        // 번호가 맞는 메시지에서 멈추므로 뒤에 온 바이트는 그대로 남는다.
        let second = try await Message.fromStream(stream, .artwork, expectedTransactionId: 3)
        #expect(try second.data == .artwork([5]))
    }
    @Test("번호가 맞는 메시지의 종류가 다르면 그때는 원본처럼 종류 오류로 끝낸다")
    func fromStreamChecksTypeOfMatchingMessage() async {
        let stream = FakeTCPConnection()
        stream.inject(UNSOLICITED_MESSAGE + Message(transactionId: 7, type: .error, args: []).buffer)
        await #expect(throws: DJLinkError("Expected message type 0x4002, got 0x4003")) {
            try await Message.fromStream(stream, .artwork, expectedTransactionId: 7)
        }
    }
    @Test("다른 번호의 메시지는 정해진 수까지만 건너뛰고 그보다 많으면 오류로 끝낸다")
    func fromStreamBoundsSkippedMessages() async throws {
        let limit = Message.maxSkippedMessages
        let allowed = FakeTCPConnection()
        allowed.inject(Array(repeating: UNSOLICITED_MESSAGE, count: limit).flatMap { $0 } + artworkResponse(2, [1]))
        #expect(try await Message.fromStream(allowed, .artwork, expectedTransactionId: 2).data == .artwork([1]))
        let flooded = FakeTCPConnection()
        flooded.inject(Array(repeating: UNSOLICITED_MESSAGE, count: limit + 1).flatMap { $0 } + artworkResponse(2, [1]))
        await #expect(throws: DJLinkError("Skipped more than \(limit) messages while waiting for transaction 0x2")) {
            try await Message.fromStream(flooded, .artwork, expectedTransactionId: 2)
        }
    }
    @Test("건너뛴 메시지는 종류와 트랜잭션 번호를 debug 로그로 남긴다")
    func logsSkippedMessage() async throws {
        let stream = FakeTCPConnection()
        let logger = DebugRecorder()
        stream.inject(UNSOLICITED_MESSAGE + artworkResponse(2, [1]))
        _ = try await Message.fromStream(stream, .artwork, expectedTransactionId: 2, logger: logger)
        #expect(
            logger.debugLines == [
                "[remotedb] Skipped message type 0x4b02 with transaction 0x3800122 while waiting for transaction 0x2"
            ])
    }
    @Test("응답 앞에 CDJ가 먼저 보낸 메시지가 끼어도 건너뛰고 자기 응답을 돌려준다")
    func skipsBeforeResponse() async throws {
        let player = ScriptedPlayer()
        player.respond = { _, _, request in
            UNSOLICITED_MESSAGE + artworkResponse(transactionId(ofRequest: request), [1, 2, 3])
        }
        let result = try await artwork(player.database())
        #expect(result == .artwork([1, 2, 3]))
    }
    @Test("종류가 같아도 번호가 다른 응답은 자기 것이 아니다(앞선 질의에서 남은 응답)")
    func skipsStaleResponseOfSameType() async throws {
        let player = ScriptedPlayer()
        player.respond = { _, _, request in
            artworkResponse(0x77, [9, 9]) + artworkResponse(transactionId(ofRequest: request), [1])
        }
        #expect(try await artwork(player.database()) == .artwork([1]))
    }
    @Test("소개 응답 앞에 CDJ가 먼저 보낸 메시지가 있어도 연결이 이어진다")
    func skipsBeforeIntroduceReply() async throws {
        let player = ScriptedPlayer()
        player.beforeIntroduceReply = UNSOLICITED_MESSAGE
        player.respond = { _, _, request in artworkResponse(transactionId(ofRequest: request), [3]) }
        #expect(try await artwork(player.database()) == .artwork([3]))
    }
    @Test("질의가 끝난 뒤 CDJ가 먼저 보낸 메시지가 다음 질의의 응답으로 읽히지 않는다")
    func skipsBetweenQueries() async throws {
        let player = ScriptedPlayer()
        player.respond = { _, requestIndex, request in
            artworkResponse(transactionId(ofRequest: request), [UInt8(requestIndex)])
        }
        let remotedb = player.database()
        #expect(try await artwork(remotedb) == .artwork([0]))
        player.connections[0].inject(UNSOLICITED_MESSAGE)
        #expect(try await artwork(remotedb) == .artwork([1]))
        #expect(try await artwork(remotedb) == .artwork([2]))
        #expect(player.connections.count == 1)
    }
    @Test("메뉴 질의의 머리·항목·꼬리 사이에 끼어도 렌더 요청의 트랜잭션으로 이어 읽는다")
    func skipsInsideMenuQuery() async throws {
        let player = ScriptedPlayer()
        player.respond = { _, requestIndex, request in
            let tx = transactionId(ofRequest: request)
            if requestIndex == 0 {
                return Message(
                    transactionId: tx, type: .success, args: [RemoteDBUInt32(0x2002), RemoteDBUInt32(1)]
                ).buffer + UNSOLICITED_MESSAGE
            }
            return Message(transactionId: tx, type: .menuHeader, args: []).buffer + UNSOLICITED_MESSAGE
                + menuItem(tx, title: "Dancing") + UNSOLICITED_MESSAGE
                + Message(transactionId: tx, type: .menuFooter, args: []).buffer + UNSOLICITED_MESSAGE
        }
        let remotedb = player.database()
        let query = try #require(try await remotedb.get(1))
        let result = try await query.query(
            queryDescriptor: usbRekordbox, query: .getMetadata, args: RemoteDBQueryArgs(trackId: 3))
        guard case let .track(track) = result else {
            Issue.record("곡 결과가 아니다: \(result)")
            return
        }
        #expect(track.title == "Dancing")
        #expect(player.requests[0].count == 2)
    }
}

@Suite("remotedb 질의가 응답을 기다리는 시간 제한(#47)") @DJLinkActor
struct RemoteDBQueryTimeoutTests {
    /// 질의를 시작해 두고 결과를 `outcome`에 모은다. 끝나지 않아도 시험이 멈추지 않게 한다.
    @DJLinkActor final class Pending {
        var outcome: Result<RemoteDBQueryResult, any Error>?
        var task: Task<Void, Never>?
    }
    private func start(_ remotedb: RemoteDatabase, _ player: ScriptedPlayer) async -> Pending {
        let pending = Pending()
        pending.task = Task {
            do { pending.outcome = .success(try await artwork(remotedb)) } catch { pending.outcome = .failure(error) }
        }
        // 연결이 끝나고 요청을 보낸 뒤 응답을 기다릴 때까지 양보한다.
        await player.clock.waitForTimers(atLeast: 1, timeout: .milliseconds(300))
        await player.clock.settle()
        return pending
    }
    @Test("응답이 없으면 10초 뒤 연결을 닫고 오류로 끝나며, 다음 get()은 새로 연결한다")
    func timesOutAndReconnects() async throws {
        let player = ScriptedPlayer()
        player.respond = { connectionIndex, _, request in
            connectionIndex == 0 ? [] : artworkResponse(transactionId(ofRequest: request), [4, 5])
        }
        let remotedb = player.database()
        let pending = await start(remotedb, player)
        player.clock.advance(ms: 9999)
        await player.clock.settle()
        #expect(pending.outcome == nil)
        #expect(player.connections[0].isOpen)
        player.clock.advance(ms: 1)
        await player.clock.settle()
        guard let outcome = pending.outcome else {
            Issue.record("10초가 지나도 질의가 끝나지 않았다")
            player.hangUp()
            await pending.task?.value
            return
        }
        guard case let .failure(error) = outcome else {
            Issue.record("응답이 없는데 질의가 성공했다")
            return
        }
        #expect((error as? DJLinkError) == DJLinkError("RemoteDB query to 10.0.0.1 timed out"))
        #expect(!player.connections[0].isOpen)
        // 같은 장치의 잠금도 풀려서 다음 get()이 새로 연결하고 질의가 된다.
        #expect(try await artwork(remotedb) == .artwork([4, 5]))
        #expect(player.connections.count == 2)
    }
    @Test("응답이 오는 동안에는 제한 시간이 늘어난다(10초 동안 바이트가 없을 때만 끝낸다)")
    func idleOnly() async throws {
        let player = ScriptedPlayer()
        let response = artworkResponse(1, [1, 2, 3])
        player.respond = { _, _, _ in [] }
        let remotedb = player.database()
        let pending = await start(remotedb, player)
        player.clock.advance(ms: 9000)
        player.connections[0].inject(Array(response.prefix(10)))
        await player.clock.settle()
        player.clock.advance(ms: 9000)
        await player.clock.settle()
        #expect(pending.outcome == nil)
        player.connections[0].inject(Array(response.dropFirst(10)))
        await player.clock.settle()
        guard let outcome = pending.outcome else {
            Issue.record("응답을 다 받았는데 질의가 끝나지 않았다")
            player.hangUp()
            await pending.task?.value
            return
        }
        #expect((try? outcome.get()) == .artwork([1, 2, 3]))
    }
    @Test("질의가 끝나면 시간 제한을 풀어서 놀고 있는 연결은 원본처럼 열려 있다")
    func idleConnectionStaysOpen() async throws {
        let player = ScriptedPlayer()
        player.respond = { _, _, request in artworkResponse(transactionId(ofRequest: request), [1]) }
        let remotedb = player.database()
        #expect(try await artwork(remotedb) == .artwork([1]))
        #expect(player.clock.pendingTimerCount == 0)
        player.clock.advance(ms: 600_000)
        #expect(player.connections[0].isOpen)
        #expect(try await artwork(remotedb) == .artwork([1]))
        #expect(player.connections.count == 1)
    }
    @Test("질의가 오류로 끝나도 시간 제한을 푼다")
    func clearsAfterFailure() async throws {
        let player = ScriptedPlayer()
        player.respond = { _, _, request in
            Message(transactionId: transactionId(ofRequest: request), type: .error, args: []).buffer
        }
        let remotedb = player.database()
        await #expect(throws: DJLinkError("Expected message type 0x4002, got 0x4003")) {
            try await artwork(remotedb)
        }
        #expect(player.clock.pendingTimerCount == 0)
    }
}

/// 2026-10-16 실기(CDJ-2000nexus)에서 받은 `0x2202` 응답(성공, 요청 종류 0x2202, 항목 0개) 42바이트. 트랜잭션 번호만 바꿔 쓴다.
@DJLinkActor private func emptyGenericMetadataReply(_ transactionId: Int) -> [UInt8] {
    var bytes = hexBytes(
        """
        11 87 23 49 ae 11 00 00 00 01 10 40 00 0f 02 14 00 00 00 0c 06 06 00 00 00 00 00 00 00 00 00 00
        11 00 00 22 02 11 00 00 00 00
        """)
    bytes.replaceSubrange(6..<10, with: RemoteDBUInt32(transactionId).data)
    return bytes
}

// PLAN §9(#48): CDJ-2000nexus는 빌린 질의 번호의 플레이어가 망에 없으면 분석하지 않은 곡의 메타데이터 질의에 항목 0개로 답한다.
// 원본은 필수 항목을 찾다 `Cannot read properties of undefined`로 실패했다.
@Suite("remotedb 분석하지 않은 곡의 메타데이터 항목 0개(#48)") @DJLinkActor
struct RemoteDBEmptyMetadataTests {
    private func player() -> ScriptedPlayer {
        let player = ScriptedPlayer()
        player.respond = { _, _, data in emptyGenericMetadataReply(transactionId(ofRequest: data)) }
        return player
    }

    @Test("항목 0개 응답은 렌더 요청 없이 까닭을 적은 오류로 끝나고 연결은 그대로다")
    func emptyMenuThrowsNoItems() async throws {
        let player = player()
        let conn = try #require(try await player.database().get(1))
        await #expect(throws: RemoteDBNoMetadataItemsError(deviceId: 1, trackId: 132)) {
            try await conn.query(
                queryDescriptor: QueryDescriptor(menuTarget: .main, trackSlot: .usb, trackType: .unanalyzed),
                query: .getGenericMetadata, args: RemoteDBQueryArgs(trackId: 132))
        }
        // 렌더 요청(0x3000)을 보내지 않는다.
        #expect(player.requests[0].count == 1)
        #expect(player.connections[0].isOpen)
    }

    @Test("원격 메타데이터 조회도 같은 오류를 내고, 그 설명에 CDJ-2000nexus의 까닭을 적는다")
    func viaRemoteReportsReason() async throws {
        let player = player()
        await #expect(throws: RemoteDBNoMetadataItemsError(deviceId: 1, trackId: 132)) {
            try await GetMetadata.viaRemote(
                player.database(), .init(deviceId: 1, trackSlot: .usb, trackType: .unanalyzed, trackId: 132))
        }
        #expect(
            String(describing: RemoteDBNoMetadataItemsError(deviceId: 1, trackId: 132))
                == "Device 1 answered the metadata query for track 132 with no items (CDJ-2000nexus does this when the player whose number the query borrows is not on the network)"
        )
    }
}
