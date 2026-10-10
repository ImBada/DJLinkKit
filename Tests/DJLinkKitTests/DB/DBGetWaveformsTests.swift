import DJLinkKit
import Testing

@Suite("getWaveforms.viaRemote") @DJLinkActor
struct DBGetWaveformsTests {
    // 원본과 다름: JS의 축약 가짜 {type: 0, height: 10, color: 'blue'}를 기존 RGB 파형 형으로 나타낸다.
    static let mockWaveformHd: WaveformHD = [.init(height: 10, color: [0, 0, 1])]
    static let mockWaveformPreview: WaveformPreview = [.init(height: 4, whiteness: 0.5)]
    static let mockWaveformDetailed: WaveformDetailed = [.init(height: 8, whiteness: 0.2)]
    static func makeConn() -> DBTestQuery {
        DBTestQuery { query, _ in
            switch query {
            case .getWaveformHD: return .waveformHD(mockWaveformHd)
            case .getWaveformPreview:
                return .waveformPreview(mockWaveformPreview.map { .init(height: $0.height, whiteness: $0.whiteness) })
            case .getWaveformDetailed: return .waveformDetailed(mockWaveformDetailed)
            default: throw DJLinkError("Unexpected query")
            }
        }
    }
    static func opts(_ type: TrackType, trackId: Int = 197) -> GetWaveforms.Options {
        .init(deviceId: 1, trackSlot: .usb, trackType: type, track: dbTrack(trackId))
    }

    @Suite("non-streaming tracks") @DJLinkActor
    struct NonStreaming {
        @Test("returns only waveformHd")
        func onlyHD() async throws {
            let result = try await GetWaveforms.viaRemote(DBTestRemote(makeConn()), opts(.rb))
            #expect(result == Waveforms(waveformHd: mockWaveformHd))
            #expect(result?.waveformPreview == nil)
            #expect(result?.waveformDetailed == nil)
        }
        @Test("queries only GetWaveformHD")
        func onlyQueryHD() async throws {
            let conn = makeConn()
            _ = try await GetWaveforms.viaRemote(DBTestRemote(conn), opts(.rb))
            #expect(conn.calls.map { $0.0.rawValue } == [0x2c04])
        }
        @Test("returns null when device has no remote db")
        func noConnection() async throws {
            #expect(try await GetWaveforms.viaRemote(DBTestRemote(nil), opts(.rb)) == nil)
        }
    }

    @Suite("streaming tracks") @DJLinkActor
    struct Streaming {
        @Test("returns waveformHd, waveformPreview, and waveformDetailed")
        func allWaveforms() async throws {
            let result = try await GetWaveforms.viaRemote(DBTestRemote(makeConn()), opts(.streaming))
            #expect(
                result
                    == Waveforms(
                        waveformHd: mockWaveformHd, waveformPreview: mockWaveformPreview,
                        waveformDetailed: mockWaveformDetailed))
        }
        @Test("queries GetWaveformHD, GetWaveformPreview, and GetWaveformDetailed")
        func allQueries() async throws {
            let conn = makeConn()
            _ = try await GetWaveforms.viaRemote(DBTestRemote(conn), opts(.streaming))
            let queries = conn.calls.map { $0.0.rawValue }
            #expect(queries.contains(0x2c04))
            #expect(queries.contains(0x2004))
            #expect(queries.contains(0x2904))
            #expect(queries.count == 3)
        }
        @Test("fetches preview and detailed in parallel")
        func parallelQueries() async throws {
            let conn = makeConn()
            _ = try await GetWaveforms.viaRemote(DBTestRemote(conn), opts(.streaming))
            let order = conn.calls.map { $0.0.rawValue }
            #expect(order.first == 0x2c04)
            #expect(Array(order.dropFirst()).sorted() == [0x2004, 0x2904].sorted())
        }
        @Test("passes correct trackId to all queries")
        func passesTrackId() async throws {
            let conn = makeConn()
            _ = try await GetWaveforms.viaRemote(DBTestRemote(conn), opts(.streaming, trackId: 23315459))
            for call in conn.calls { #expect(call.1.trackId == 23315459) }
        }
        @Test("returns null when device has no remote db")
        func noConnection() async throws {
            #expect(try await GetWaveforms.viaRemote(DBTestRemote(nil), opts(.streaming)) == nil)
        }
    }
}
