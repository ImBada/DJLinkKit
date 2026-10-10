import Foundation
import Testing

@testable import DJLinkKit

@Suite("Requesting Vocal Detection Configuration")
@DJLinkActor struct LocalDBLoadAnlzVocalConfigTests {
    @Suite("loadAnlz with VOCAL_CONFIG section")
    @DJLinkActor struct Group0 {
        @Test("extracts vocal config from .2EX file with PWVC section")
        func test0() async throws {
            let mockTrack = Track(
                id: 1, title: "Test Track", duration: 300, tempo: 128, rating: 0, comment: "",
                filePath: "/music/test.mp3", fileName: "test.mp3",
                analyzePath: "/music/PIONEER/USBANLZ/P000/0000/ANLZ0000")
            let mockResolver: AnlzResolver = { _ in [] }
            let result = try await loadAnlz(
                mockTrack, type: "2EX", anlzResolver: mockResolver,
                reader: { _ in
                    [.init(fourcc: "PWVC", thresholdLow: 97, thresholdMid: 114, thresholdHigh: 130)]
                })
            #expect(result.vocalConfig == .init(thresholdLow: 97, thresholdMid: 114, thresholdHigh: 130))
        }
        @Test("resolves the correct .2EX file path from track analyzePath")
        func test1() async throws {
            let mockTrack = Track(
                id: 1, title: "Test Track", duration: 300, tempo: 128, rating: 0, comment: "",
                filePath: "/music/test.mp3", fileName: "test.mp3",
                analyzePath: "/music/PIONEER/USBANLZ/P000/0000/ANLZ0000")
            var paths: [String] = []
            let resolver: AnlzResolver = { path in
                paths.append(path)
                return []
            }
            _ = try await loadAnlz(mockTrack, type: "2EX", anlzResolver: resolver, reader: { _ in [] })
            #expect(paths == ["/music/PIONEER/USBANLZ/P000/0000/ANLZ0000.2EX"])
        }
        @Test("returns undefined vocalConfig when .2EX has no PWVC section")
        func test2() async throws {
            let mockTrack = Track(
                id: 1, title: "Test Track", duration: 300, tempo: 128, rating: 0, comment: "",
                filePath: "/music/test.mp3", fileName: "test.mp3",
                analyzePath: "/music/PIONEER/USBANLZ/P000/0000/ANLZ0000")
            let mockResolver: AnlzResolver = { _ in [] }
            let result = try await loadAnlz(
                mockTrack, type: "2EX", anlzResolver: mockResolver,
                reader: { _ in
                    [.init(fourcc: "PWV6", lenEntries: 100, entries: [UInt8](repeating: 0, count: 300))]
                })
            #expect(result.vocalConfig == nil)
        }
        @Test("extracts vocal config alongside waveform sections")
        func test3() async throws {
            let mockTrack = Track(
                id: 1, title: "Test Track", duration: 300, tempo: 128, rating: 0, comment: "",
                filePath: "/music/test.mp3", fileName: "test.mp3",
                analyzePath: "/music/PIONEER/USBANLZ/P000/0000/ANLZ0000")
            let mockResolver: AnlzResolver = { _ in [] }
            let result = try await loadAnlz(
                mockTrack, type: "2EX", anlzResolver: mockResolver,
                reader: { _ in
                    [
                        .init(fourcc: "PWV6", lenEntries: 50, entries: [UInt8](repeating: 0, count: 150)),
                        .init(fourcc: "PWV7", lenEntries: 1000, entries: [UInt8](repeating: 0, count: 3000)),
                        .init(fourcc: "PWVC", thresholdLow: 10, thresholdMid: 50, thresholdHigh: 90),
                    ]
                })
            #expect(result.vocalConfig == .init(thresholdLow: 10, thresholdMid: 50, thresholdHigh: 90))
            #expect(result.waveform3BandPreview?.numEntries == 50)
            #expect(result.waveform3BandDetail?.numEntries == 1000)
        }
        @Test("handles zero threshold values")
        func test4() async throws {
            let mockTrack = Track(
                id: 1, title: "Test Track", duration: 300, tempo: 128, rating: 0, comment: "",
                filePath: "/music/test.mp3", fileName: "test.mp3",
                analyzePath: "/music/PIONEER/USBANLZ/P000/0000/ANLZ0000")
            let mockResolver: AnlzResolver = { _ in [] }
            let result = try await loadAnlz(
                mockTrack, type: "2EX", anlzResolver: mockResolver,
                reader: { _ in [.init(fourcc: "PWVC", thresholdLow: 0, thresholdMid: 0, thresholdHigh: 0)] }
            )
            #expect(result.vocalConfig == .init(thresholdLow: 0, thresholdMid: 0, thresholdHigh: 0))
        }
        @Test("handles maximum observed threshold values")
        func test5() async throws {
            let mockTrack = Track(
                id: 1, title: "Test Track", duration: 300, tempo: 128, rating: 0, comment: "",
                filePath: "/music/test.mp3", fileName: "test.mp3",
                analyzePath: "/music/PIONEER/USBANLZ/P000/0000/ANLZ0000")
            let mockResolver: AnlzResolver = { _ in [] }
            let result = try await loadAnlz(
                mockTrack, type: "2EX", anlzResolver: mockResolver,
                reader: { _ in
                    [.init(fourcc: "PWVC", thresholdLow: 114, thresholdMid: 146, thresholdHigh: 159)]
                })
            #expect(result.vocalConfig == .init(thresholdLow: 114, thresholdMid: 146, thresholdHigh: 159))
        }
        @Test("returns all three threshold fields as numbers")
        func test6() async throws {
            let mockTrack = Track(
                id: 1, title: "Test Track", duration: 300, tempo: 128, rating: 0, comment: "",
                filePath: "/music/test.mp3", fileName: "test.mp3",
                analyzePath: "/music/PIONEER/USBANLZ/P000/0000/ANLZ0000")
            let mockResolver: AnlzResolver = { _ in [] }
            let result = try await loadAnlz(
                mockTrack, type: "2EX", anlzResolver: mockResolver,
                reader: { _ in
                    [.init(fourcc: "PWVC", thresholdLow: 100, thresholdMid: 200, thresholdHigh: 300)]
                })
            let vc = try #require(result.vocalConfig)
            // 원본과 다름: typeof number 대신 정적 형을 검사한다.
            let _: Int = vc.thresholdLow
            let _: Int = vc.thresholdMid
            let _: Int = vc.thresholdHigh
        }
    }
    @Suite("getTrackAnalysis vocal config flow")
    @DJLinkActor struct Group1 {
        @Test("vocal config is null when .2EX load fails")
        func test7() async throws {
            let mockTrack = Track(
                id: 1, title: "Test Track", duration: 300, tempo: 128, rating: 0, comment: "",
                filePath: "/music/test.mp3", fileName: "test.mp3",
                analyzePath: "/music/PIONEER/USBANLZ/P000/0000/ANLZ0000")
            let failingResolver: AnlzResolver = { _ in throw DJLinkError("File not found") }
            let twoxResult = try? await loadAnlz(
                mockTrack, type: "2EX", anlzResolver: failingResolver, reader: { _ in [] })
            #expect(twoxResult?.vocalConfig == nil)
        }
        @Test("vocal config is null when .2EX has no PWVC section")
        func test8() async throws {
            let mockTrack = Track(
                id: 1, title: "Test Track", duration: 300, tempo: 128, rating: 0, comment: "",
                filePath: "/music/test.mp3", fileName: "test.mp3",
                analyzePath: "/music/PIONEER/USBANLZ/P000/0000/ANLZ0000")
            let mockResolver: AnlzResolver = { _ in [] }
            let result = try await loadAnlz(
                mockTrack, type: "2EX", anlzResolver: mockResolver, reader: { _ in [] })
            #expect(result.vocalConfig == nil)
        }
        @Test("vocal config is populated from successful .2EX parse")
        func test9() async throws {
            let mockTrack = Track(
                id: 1, title: "Test Track", duration: 300, tempo: 128, rating: 0, comment: "",
                filePath: "/music/test.mp3", fileName: "test.mp3",
                analyzePath: "/music/PIONEER/USBANLZ/P000/0000/ANLZ0000")
            let mockResolver: AnlzResolver = { _ in [] }
            let result = try await loadAnlz(
                mockTrack, type: "2EX", anlzResolver: mockResolver,
                reader: { _ in
                    [.init(fourcc: "PWVC", thresholdLow: 80, thresholdMid: 100, thresholdHigh: 110)]
                })
            #expect(result.vocalConfig == .init(thresholdLow: 80, thresholdMid: 100, thresholdHigh: 110))
        }
    }
}
