import DJLinkKit
import DJLinkTestSupport
import Testing

@DJLinkActor struct DBMetadataSetup {
    static func opts(trackId: Int = 40492, trackBPM: Double? = nil) -> GetMetadata.Options {
        .init(deviceId: 3, trackSlot: .usb, trackType: .rb, trackId: trackId, trackBPM: trackBPM)
    }
    static func adapter(_ id: Int = 40492, _ title: String, tempo: Double = 0) -> DBTestAdapter {
        let result = DBTestAdapter()
        result.tracks[id] = dbTrack(id, title, tempo: tempo)
        return result
    }
    static func remote(hostId: Int = 5, hasTrack: Bool = true) -> DBTestRemote {
        DBTestRemote(
            hasTrack
                ? DBTestQuery { query, _ in
                    switch query {
                    case .getMetadata: return .track(dbTrack(40492, "From RemoteDB"))
                    case .getTrackInfo: return .path("")
                    default: return .beatGrid([])
                    }
                } : nil, hostId: hostId)
    }
    static func database(_ local: DBTestLocal, _ remote: DBTestRemote, _ logger: DBTestLogger = .init()) -> Database {
        Database(local, remote, DBTestDevices(), logger: logger, dependencies: dbDependencies())
    }
}

@Suite("getMetadata.viaLocal outcome") @DJLinkActor
struct DBGetMetadataLocalTests {
    @Test("reports no-database when the slot has no rekordbox database loaded")
    func noDatabase() async throws {
        let result = try await GetMetadata.viaLocal(
            DBTestLocal(nil), DBTestDevices().device!, DBMetadataSetup.opts(), dependencies: dbDependencies())
        #expect(result.track == nil)
        #expect(result.miss == .noDatabase)
        #expect(result.switchedTo == nil)
    }
    @Test("reports track-absent when the database is loaded but lacks the track")
    func absent() async throws {
        let adapter = DBTestAdapter()
        let result = try await GetMetadata.viaLocal(
            DBTestLocal(adapter), DBTestDevices().device!, DBMetadataSetup.opts(), dependencies: dbDependencies())
        #expect(result.track == nil)
        #expect(result.miss == .trackAbsent)
        #expect(result.switchedTo == nil)
        #expect(adapter.trackCalls == [40492])
    }
    @Test("reports no miss when the track is found")
    func found() async throws {
        let result = try await GetMetadata.viaLocal(
            DBTestLocal(DBMetadataSetup.adapter(40492, "Laberynth")), DBTestDevices().device!, DBMetadataSetup.opts(),
            dependencies: dbDependencies())
        #expect(result.miss == nil)
        #expect(result.track?.id == 40492)
        #expect(result.track?.title == "Laberynth")
    }
}

@Suite("Database.getMetadata local-miss fallback") @DJLinkActor
struct DBGetMetadataFallbackTests {
    @Test("falls back to the remote database when the loaded database lacks the track")
    func absentFallback() async throws {
        let remote = DBMetadataSetup.remote()
        let track = try await DBMetadataSetup.database(DBTestLocal(DBTestAdapter()), remote).getMetadata(
            DBMetadataSetup.opts())
        #expect(remote.getCalls == [3])
        #expect(track?.title == "From RemoteDB")
    }
    @Test("falls back to the remote database when no database is loaded for the slot")
    func noDatabaseFallback() async throws {
        let track = try await DBMetadataSetup.database(DBTestLocal(nil), DBMetadataSetup.remote()).getMetadata(
            DBMetadataSetup.opts())
        #expect(track?.title == "From RemoteDB")
    }
    @Test("does not touch the remote database when the local lookup succeeds")
    func localSuccess() async throws {
        let remote = DBMetadataSetup.remote()
        let track = try await DBMetadataSetup.database(DBTestLocal(DBMetadataSetup.adapter(40492, "From USB")), remote)
            .getMetadata(DBMetadataSetup.opts())
        #expect(track?.title == "From USB")
        #expect(remote.getCalls.isEmpty)
    }
    @Test("logs which kind of miss happened before falling back")
    func logsMiss() async throws {
        let logger = DBTestLogger()
        _ = try await DBMetadataSetup.database(DBTestLocal(DBTestAdapter()), DBMetadataSetup.remote(), logger)
            .getMetadata(DBMetadataSetup.opts())
        #expect(logger.warnings.contains { $0.contains("the loaded database holds no track with that id") })
    }
    @Suite("when the virtual CDJ is announced outside the 1-6 range")
    struct OutsideRange {
        @Test("still attempts the remote fallback") @DJLinkActor
        func fallback() async throws {
            let remote = DBMetadataSetup.remote(hostId: 7)
            let track = try await DBMetadataSetup.database(DBTestLocal(nil), remote).getMetadata(DBMetadataSetup.opts())
            #expect(!remote.getCalls.isEmpty)
            #expect(track?.title == "From RemoteDB")
        }
    }
    @Test("returns null rather than throwing when the remote fallback fails")
    func failedFallback() async throws {
        let logger = DBTestLogger()
        let remote = DBMetadataSetup.remote()
        remote.error = DJLinkError("RemoteDB connection timed out")
        #expect(
            try await DBMetadataSetup.database(DBTestLocal(nil), remote, logger).getMetadata(DBMetadataSetup.opts())
                == nil)
        #expect(logger.warnings.contains { $0.contains("RemoteDB connection timed out") })
    }
    @Test("returns null when the remote database has no connection to the device")
    func noConnection() async throws {
        #expect(
            try await DBMetadataSetup.database(DBTestLocal(nil), DBMetadataSetup.remote(hasTrack: false)).getMetadata(
                DBMetadataSetup.opts()) == nil)
    }
}

@Suite("getMetadata database-format check (NP3-399)") @DJLinkActor
struct DBGetMetadataFormatTests {
    @Test("hands the player-reported BPM to the local lookup")
    func passesBPM() async throws {
        let local = DBTestLocal(DBMetadataSetup.adapter(32657, "Focused", tempo: 126))
        _ = try await GetMetadata.viaLocal(
            local, DBTestDevices().device!, DBMetadataSetup.opts(trackId: 32657, trackBPM: 126),
            dependencies: dbDependencies())
        #expect(local.lookupCalls.count == 1)
        let call = try #require(local.lookupCalls.first)
        #expect(call.0 == 3)
        #expect(call.1 == .usb)
        #expect(call.2 == 32657)
        #expect(call.3 == .init(trackBPM: 126))
    }
    @Test("logs when the slot switched database format to answer")
    func logsSwitch() async throws {
        let logger = DBTestLogger()
        let local = DBTestLocal(DBMetadataSetup.adapter(32657, "Focused", tempo: 126), switchedTo: .pdb)
        let track = try await DBMetadataSetup.database(
            local, DBMetadataSetup.remote(hostId: 7, hasTrack: false), logger
        ).getMetadata(DBMetadataSetup.opts(trackId: 32657, trackBPM: 126))
        #expect(track?.title == "Focused")
        #expect(logger.infos.contains { $0.contains("now read from the legacy PDB database") })
    }
    @Test("passes a null BPM when the caller has none")
    func nullBPM() async throws {
        let local = DBTestLocal(DBMetadataSetup.adapter(1, "x", tempo: 0))
        _ = try await DBMetadataSetup.database(local, DBMetadataSetup.remote(hostId: 7, hasTrack: false)).getMetadata(
            DBMetadataSetup.opts(trackId: 1))
        #expect(local.lookupCalls.count == 1)
        let call = try #require(local.lookupCalls.first)
        #expect(call.0 == 3)
        #expect(call.1 == .usb)
        #expect(call.2 == 1)
        #expect(call.3 == .init(trackBPM: nil))
    }
}
