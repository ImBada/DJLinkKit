import DJLinkKit
import Testing

@Suite("getPlaylist.viaLocal") @DJLinkActor
struct DBGetPlaylistTests {
    func makeAdapter() -> DBTestAdapter {
        let adapter = DBTestAdapter()
        adapter.tracks = [10: dbTrack(10, "Ten"), 20: dbTrack(20, "Twenty")]
        adapter.playlistResult = .init(trackEntries: [
            .init(id: 1, sortIndex: 0, playlistId: 5, trackId: 20),
            .init(id: 2, sortIndex: 1, playlistId: 5, trackId: 10),
        ])
        return adapter
    }

    @Test("resolves playlist entries through their trackId")
    func resolvesEntries() async throws {
        let adapter = makeAdapter()
        let contents = try #require(
            try await GetPlaylist.viaLocal(
                DBTestLocal(adapter),
                .init(deviceId: 2, mediaSlot: .usb, playlist: .init(id: 5, name: "Set", isFolder: false, parentId: nil))
            ))
        #expect(contents.totalTracks == 2)
        var titles: [String] = []
        for try await track in contents.tracks { titles.append(track.title) }
        #expect(titles == ["Twenty", "Ten"])
        #expect(adapter.trackCalls == [20, 10])
    }

    @Test("returns null when the slot has no database")
    func noDatabase() async throws {
        #expect(try await GetPlaylist.viaLocal(DBTestLocal(nil), .init(deviceId: 2, mediaSlot: .sd)) == nil)
    }

    @Test("rejects slots that cannot hold a rekordbox database")
    func rejectsSlot() async throws {
        await #expect(throws: DJLinkError("Expected USB or SD slot for local database query")) {
            try await GetPlaylist.viaLocal(DBTestLocal(makeAdapter()), .init(deviceId: 2, mediaSlot: .rb))
        }
    }
}
