import DJLinkTestSupport
import Testing

@testable import DJLinkKit

@Suite("TCP 및 remotedb 전송 이식 검증") @DJLinkActor
struct RemoteDBTransportTests {
    @Test("크기를 채울 때까지 기다리고 남은 바이트는 다음 읽기에 둔다")
    func partialRead() async throws {
        let socket = FakeTCPConnection()
        var completed = false
        let task = Task { @DJLinkActor in
            let result = try await socket.read(4)
            completed = true
            return result
        }
        await TestClock().settle()
        socket.inject([1, 2])
        await TestClock().settle()
        #expect(!completed)
        socket.inject([3, 4, 5])
        #expect(try await task.value == [1, 2, 3, 4])
        #expect(try await socket.read(nil) == [5])
    }
    @Test("종료에서 짧은 읽기를 돌려준 다음 nil을 돌려준다")
    func endOfStream() async throws {
        let socket = FakeTCPConnection()
        socket.inject([1, 2])
        socket.end()
        #expect(try await socket.read(4) == [1, 2])
        #expect(try await socket.read(1) == nil)
        await #expect(throws: DJLinkError("write after end")) { try await socket.write([3]) }
    }
    @Test("TestClock의 유휴 제한 시간이 읽기를 깨운다")
    func timeout() async {
        let clock = TestClock()
        let timed = FakeTCPConnection(clock: clock)
        timed.setTimeout(100) { timed.destroy(TimeoutError()) }
        let read = Task { try await timed.read(4) }
        await clock.settle()
        clock.advance(ms: 99)
        #expect(timed.isOpen)
        clock.advance(ms: 1)
        await #expect(throws: TimeoutError.self) { try await read.value }
    }
    @Test("빈 binary 인자를 생략하는 원본 메시지 바이트를 유지한다")
    func emptyBinaryQuirk() async throws {
        let message = Message(
            transactionId: 9, type: .artwork,
            args: [RemoteDBUInt32(1), RemoteDBUInt32(2), RemoteDBUInt32(0), RemoteDBBinary([])])
        #expect(message.buffer.count == 47)
        let stream = FakeTCPConnection()
        stream.inject(message.buffer)
        let decoded = try await Message.fromStream(stream, .artwork)
        #expect(decoded.transactionId == 9)
        #expect(try decoded.data == .artwork([]))
    }
    @Test("연결 핸드셰이크가 멈추면 설정한 오류로 종료한다")
    func handshakeTimeout() async {
        @DJLinkActor final class Devices: RemoteDBDeviceSource {
            let devices = [1: mockDevice()]
        }
        let clock = TestClock()
        let factory = FakeSocketFactory()
        var creations = 0
        factory.makeTCPConnection = {
            let socket = FakeTCPConnection(clock: clock)
            creations += 1
            if creations == 1 {
                socket.onWrite = { _ in
                    socket.inject([0x12, 0x34])
                    socket.end()
                }
            }
            return socket
        }
        let database = RemoteDatabase(deviceManager: Devices(), hostDevice: mockDevice(id: 7), socketFactory: factory)
        let connection = Task { try await database.get(1) }
        await clock.waitForTimers(atLeast: 1)
        await clock.settle()
        clock.advance(ms: 10000)
        await #expect(throws: DJLinkError("RemoteDB connection to 10.0.0.1:4660 timed out")) {
            try await connection.value
        }
    }
}

extension RemoteDBTransportTests {
    @Test("원본 고급 큐의 null 펼치기로 생긴 label·color 객체를 버리지 않는다")
    func untypedAdvancedCue() throws {
        var entry = [UInt8].alloc(0x53)
        entry.writeUInt32LE(entry.count)
        entry[6] = 3
        entry.writeUInt16LE(4, 0x48)
        entry.set([0x41, 0, 0, 0], 0x4a)
        entry[0x52] = 9
        let response = try responseTransform(
            .advCueAndLoops, [RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(entry.count), RemoteDBBinary(entry)])
        #expect(response == .advancedCueAndLoops([.untyped(color: CueColor(rawValue: 9), label: "A")]))
    }
    @Test("Track의 정수 year에 담기지 않는 원본 number를 별도 결과로 보존한다")
    func rawMetadataYear() async throws {
        let socket = FakeTCPConnection()
        let conn = Connection(device: mockDevice(), socket: socket)
        let query = QueryInterface(conn: conn, lock: AsyncMutex(), hostDevice: mockDevice(id: 5))
        let messages = [
            Message(type: .success, args: [RemoteDBUInt32(0), RemoteDBUInt32(1)]),
            Message(type: .menuHeader, args: []),
            Message(
                type: .menuItem,
                args: [
                    RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBString("2024.5"),
                    RemoteDBUInt32(0), RemoteDBString(""), RemoteDBUInt32(ItemType.year.rawValue), RemoteDBUInt32(0),
                    RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(0),
                ]),
            Message(type: .menuFooter, args: []),
        ]
        socket.inject(messages.flatMap(\.buffer))
        let result = try await query.query(
            queryDescriptor: QueryDescriptor(menuTarget: .main, trackSlot: .usb, trackType: .rb), query: .getMetadata,
            args: RemoteDBQueryArgs(trackId: 1))
        guard case let .trackWithRawYear(track, year) = result else {
            Issue.record("원본 연도 값이 사라졌다")
            return
        }
        #expect(track.year == nil)
        #expect(year == 2024.5)
    }
}

extension RemoteDBTransportTests {
    @Test("인자 수보다 짧은 형 목록은 trap 대신 원본 오류로 거절한다")
    func shortArgumentList() async {
        let stream = FakeTCPConnection()
        let fields: [Field] = [
            RemoteDBUInt32(REMOTEDB_MAGIC), RemoteDBUInt32(1), RemoteDBUInt16(Response.success.rawValue),
            RemoteDBUInt8(1), RemoteDBBinary([]), RemoteDBUInt32(0),
        ]
        stream.inject(fields.flatMap(\.buffer))
        await #expect(throws: DJLinkError("Cannot read properties of undefined (reading 'name')")) {
            try await Message.fromStream(stream, .success)
        }
    }

    @Test("잘린 미리보기 파형의 undefined 높이와 NaN 흰색을 보존한다")
    func truncatedWaveformPreview() throws {
        let response = try responseTransform(
            .waveformPreview, [RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(3), RemoteDBBinary([9, 7, 5])])
        guard case let .waveformPreview(data) = response else {
            Issue.record("미리보기 파형이어야 한다")
            return
        }
        #expect(data.count == 400)
        #expect(data[0].height == 9)
        #expect(data[0].whiteness == 1)
        #expect(data[1].height == 5)
        #expect(data[1].whiteness.isNaN)
        #expect(data[2].height == nil)
        #expect(data[2].whiteness.isNaN)
    }

    @Test("고급 큐의 색 바이트가 없으면 undefined를 보존한다")
    func truncatedAdvancedCueColor() throws {
        var entry = [UInt8].alloc(0x4e)
        entry.writeUInt32LE(entry.count)
        entry.writeUInt16LE(4, 0x48)
        entry.set([0x41, 0, 0, 0], 0x4a)
        let args: [Field] = [RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(entry.count), RemoteDBBinary(entry)]
        entry[6] = 3
        #expect(
            try responseTransform(.advCueAndLoops, Array(args.dropLast()) + [RemoteDBBinary(entry)])
                == .advancedCueAndLoops([.untyped(color: nil, label: "A")]))
        entry[6] = 1
        #expect(
            try responseTransform(.advCueAndLoops, Array(args.dropLast()) + [RemoteDBBinary(entry)])
                == .cueAndLoops([.cuePoint(CuePoint(offset: 0, label: "A", color: nil))]))
    }

    @Test("저장한 읽기 오류는 한 번만 전달하고 destroy(nil)은 지운다")
    func errorLifetime() async throws {
        // Live 객체도 connect 전에는 실제 소켓을 만들지 않는다.
        for socket in [FakeTCPConnection(), LiveTCPConnection()] as [any TCPConnection] {
            (socket as? FakeTCPConnection)?.inject([9])
            socket.destroy(DJLinkError("once"))
            await #expect(throws: DJLinkError("once")) { try await socket.read(1) }
            #expect(try await socket.read(1) == nil)
            socket.destroy(DJLinkError("cleared"))
            socket.destroy(nil)
            #expect(try await socket.read(1) == nil)
        }
    }

    @Test("메뉴 칸의 형이 달라도 원본 value를 그대로 보존한다")
    func mismatchedItemFields() throws {
        let args: [Field] = [
            RemoteDBBinary([1, 2]), RemoteDBString("track-id"), RemoteDBUInt32(0), RemoteDBUInt32(42),
            RemoteDBUInt32(0), RemoteDBBinary([3, 4]), RemoteDBUInt32(ItemType.trackTitle.rawValue),
            RemoteDBUInt32(0), RemoteDBString("artwork-id"),
        ]
        let item = try fieldsToItem(args)
        #expect(item.type == .trackTitle)
        #expect(
            item.rawValues == [
                "type": .number(ItemType.trackTitle.rawValue), "id": .string("track-id"),
                "title": .number(42), "artworkId": .string("artwork-id"),
            ])
        var numeric = args
        numeric[6] = RemoteDBUInt32(ItemType.tempo.rawValue)
        numeric[1] = RemoteDBString("12500")
        #expect(try fieldsToItem(numeric).bpm == 125)
        numeric[6] = RemoteDBString("unrecognized")
        let unknown = try fieldsToItem(numeric)
        #expect(unknown.rawValues["type"] == .string("unrecognized"))
        #expect(unknown.rawValues["parentId"] == .binary([1, 2]))
        #expect(unknown.rawValues["label2"] == .binary([3, 4]))
    }
}
