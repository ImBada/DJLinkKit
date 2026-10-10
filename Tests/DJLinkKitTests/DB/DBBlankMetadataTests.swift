import DJLinkKit
import DJLinkTestSupport
import Testing

@DJLinkActor private func dbMenuItem(_ type: Int, label1: String = "", label2: String = "", mainId: Int = 0) -> Message
{
    Message(
        type: Response.menuItem,
        args: [
            RemoteDBUInt32(0), RemoteDBUInt32(mainId), RemoteDBUInt32((label1.utf16.count + 1) * 2),
            RemoteDBString(label1),
            RemoteDBUInt32((label2.utf16.count + 1) * 2), RemoteDBString(label2), RemoteDBUInt32(type),
            RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(0), RemoteDBUInt32(0),
        ])
}
@DJLinkActor private func dbMenu(_ request: Request, _ items: [Message]) -> [Message] {
    let success = Message(
        type: Response.success, args: [RemoteDBUInt32(request.rawValue), RemoteDBUInt32(items.count)])
    if items.isEmpty { return [success] }
    return [success, Message(type: Response.menuHeader, args: [])] + items + [
        Message(type: Response.menuFooter, args: [])
    ]
}
@DJLinkActor private func dbReplayingRemote(_ responses: [Message]) -> DBTestRemote {
    let socket = FakeTCPConnection()
    for response in responses { socket.inject(response.buffer) }
    // 원본 wire.stop()은 읽기만 끝내지만 FakeTCPConnection.end()는 쓰기도 닫는다.
    // 응답은 전부 미리 넣어 두고 쓰기 창구를 열어 같은 바이트 흐름을 읽는다.
    let conn = Connection(device: mockDevice(id: 1, name: "XDJ-AZ"), socket: socket)
    return DBTestRemote(QueryInterface(conn: conn, lock: AsyncMutex(), hostDevice: mockDevice(id: 2)))
}
@DJLinkActor private func dbStreamingOpts(slot: MediaSlot = .init(rawValue: 0x0f), trackId: Int = 119)
    -> GetMetadata.Options
{
    .init(deviceId: 1, trackSlot: slot, trackType: .streaming, trackId: trackId, trackBPM: nil)
}

@Suite("viaRemote on a lookup that comes back without a title or artist") @DJLinkActor
struct DBBlankMetadataTests {
    @Test("reports that the player sent no items at all")
    func noItems() async throws {
        let remote = dbReplayingRemote(dbMenu(.getMetadata, []) + dbMenu(.getTrackInfo, []))
        let logger = DBTestLogger()
        let track = try await GetMetadata.viaRemote(remote, dbStreamingOpts(), logger: logger)
        #expect(track?.title == "")
        #expect(track?.artist == nil)
        #expect(logger.warnings.count == 1)
        #expect(
            logger.warnings.first
                == "Device 1 answered the metadata query for track 119 (slot 15 unknown, type 6 streaming) with no title or artist: 0 of 0 item(s) received; track info: failed (Player sent no file path (0 item(s) available))"
        )
    }
    @Test("uses native streaming title and artist metadata")
    func nativeMetadata() async throws {
        let remote = dbReplayingRemote(
            dbMenu(
                .getMetadata,
                [
                    dbMenuItem(0x0099, label1: "Dancing", label2: "Bittermind"), dbMenuItem(0x000b, mainId: 300),
                ]) + dbMenu(.getTrackInfo, []))
        let logger = DBTestLogger()
        let track = try await GetMetadata.viaRemote(remote, dbStreamingOpts(), logger: logger)
        #expect(track?.title == "Dancing")
        #expect(track?.artist?.name == "Bittermind")
        #expect(track?.duration == 300)
        #expect(logger.warnings.isEmpty)
    }
    @Test("shortens an oversized item so the report stays readable")
    func oversizedItem() async throws {
        let remote = dbReplayingRemote(
            dbMenu(.getMetadata, [dbMenuItem(0x009a, label1: String(repeating: "x", count: 500))])
                + dbMenu(.getTrackInfo, []))
        let logger = DBTestLogger()
        _ = try await GetMetadata.viaRemote(remote, dbStreamingOpts(), logger: logger)
        let report = try #require(logger.warnings.first)
        let item = report.components(separatedBy: "; ")[1]
        #expect(item.utf16.count == 201)
        #expect(item.hasSuffix("…"))
    }
}

@Suite("viaRemote on a streaming track the player describes in full") @DJLinkActor
struct DBFullStreamingMetadataTests {
    @Test("reads the title, artist and Beatport path without reporting anything")
    func fullMetadata() async throws {
        let remote = dbReplayingRemote(
            dbMenu(
                .getMetadata,
                [
                    dbMenuItem(0x0004, label1: "Automatic Love", mainId: 2),
                    dbMenuItem(0x0007, label1: "Fury Weekend", mainId: 7),
                ]) + dbMenu(.getTrackInfo, [dbMenuItem(0x0000, label1: "/26883657.m4a")]))
        let logger = DBTestLogger()
        let track = try await GetMetadata.viaRemote(
            remote, dbStreamingOpts(slot: .beatport, trackId: 2), logger: logger)
        #expect(track?.title == "Automatic Love")
        #expect(track?.artist?.name == "Fury Weekend")
        #expect(track?.filePath == "/26883657.m4a")
        #expect(logger.warnings.isEmpty)
    }
}
