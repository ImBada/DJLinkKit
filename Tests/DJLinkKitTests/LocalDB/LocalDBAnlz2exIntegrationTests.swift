import Foundation
import Testing

@testable import DJLinkKit

@Suite(".2EX Integration Tests")
struct LocalDBAnlz2exIntegrationTests {
    @Suite("binary fixture → parser pipeline")
    struct Group0 {
        @Test("parses PWV6 from binary fixture end-to-end")
        func test0() throws {
            let inputData: [UInt8] = [255, 0, 128, 0, 255, 64, 100, 100, 100]
            let sections = try parseAnlzSections(
                create2EXFile(pwv6: .init(numEntries: 3, data: inputData)))
            let section = try #require(sections.first { $0.fourcc == "PWV6" })
            let result = makeWaveform3BandPreview(section)
            #expect(result.numEntries == 3)
            #expect(result.data == inputData)
        }
        @Test("parses PWV7 from binary fixture end-to-end")
        func test1() throws {
            let inputData: [UInt8] = [10, 20, 30, 40, 50, 60]
            let sections = try parseAnlzSections(
                create2EXFile(pwv7: .init(numEntries: 2, data: inputData)))
            let section = try #require(sections.first { $0.fourcc == "PWV7" })
            let result = makeWaveform3BandDetail(section)
            #expect(result.numEntries == 2)
            #expect(result.data == inputData)
        }
        @Test("parses PWVC from binary fixture end-to-end")
        func test2() throws {
            let sections = try parseAnlzSections(
                create2EXFile(pwvc: .init(thresholdLow: 256, thresholdMid: 1024, thresholdHigh: 4096)))
            let section = try #require(sections.first { $0.fourcc == "PWVC" })
            #expect(
                makeVocalConfig(section)
                    == VocalConfig(thresholdLow: 256, thresholdMid: 1024, thresholdHigh: 4096))
        }
        @Test("parses all 3 sections from a complete .2EX file")
        func test3() throws {
            let pwv6Data: [UInt8] = [100, 150, 200, 50, 75, 100]
            let pwv7Data: [UInt8] = [10, 20, 30, 40, 50, 60, 70, 80, 90]
            let sections = try parseAnlzSections(
                create2EXFile(
                    pwv6: .init(numEntries: 2, data: pwv6Data), pwv7: .init(numEntries: 3, data: pwv7Data),
                    pwvc: .init(thresholdLow: 10, thresholdMid: 50, thresholdHigh: 90)))
            #expect(sections.count == 3)
            #expect(makeWaveform3BandPreview(sections[0]) == .init(numEntries: 2, data: pwv6Data))
            #expect(makeWaveform3BandDetail(sections[1]) == .init(numEntries: 3, data: pwv7Data))
            #expect(
                makeVocalConfig(sections[2]) == .init(thresholdLow: 10, thresholdMid: 50, thresholdHigh: 90)
            )
        }
    }
    @Suite("partial .2EX files")
    struct Group1 {
        @Test("parses file with only PWV6")
        func test4() throws {
            let sections = try parseAnlzSections(create2EXFile(pwv6: .init(numEntries: 100)))
            #expect(sections.count == 1)
            #expect(sections[0].fourcc == "PWV6")
            #expect(makeWaveform3BandPreview(sections[0]).numEntries == 100)
        }
        @Test("parses file with only PWVC")
        func test5() throws {
            let sections = try parseAnlzSections(
                create2EXFile(pwvc: .init(thresholdLow: 5, thresholdMid: 25, thresholdHigh: 75)))
            #expect(sections.count == 1)
            #expect(sections[0].fourcc == "PWVC")
            #expect(makeVocalConfig(sections[0]).thresholdLow == 5)
        }
        @Test("parses file with PWV6 and PWVC but no PWV7")
        func test6() throws {
            let sections = try parseAnlzSections(
                create2EXFile(
                    pwv6: .init(numEntries: 50),
                    pwvc: .init(thresholdLow: 10, thresholdMid: 50, thresholdHigh: 90)))
            #expect(sections.count == 2)
            #expect(sections.contains { $0.fourcc == "PWV6" })
            #expect(!sections.contains { $0.fourcc == "PWV7" })
            #expect(sections.contains { $0.fourcc == "PWVC" })
        }
    }
    @Suite("data integrity")
    struct Group2 {
        @Test("preserves all 255 possible byte values through PWV6 pipeline")
        func test7() throws {
            let numEntries = 85
            let data = (0..<(numEntries * 3)).map { UInt8($0 % 256) }
            let sections = try parseAnlzSections(
                create2EXFile(pwv6: .init(numEntries: numEntries, data: data)))
            let result = makeWaveform3BandPreview(sections[0])
            for i in data.indices { #expect(result.data[i] == data[i]) }
        }
        @Test("handles realistic 1200-entry PWV6 data")
        func test8() throws {
            let numEntries = 1200
            var data = [UInt8](repeating: 0, count: numEntries * 3)
            for i in 0..<numEntries {
                let amplitude = sin(Double(i) / Double(numEntries) * .pi)
                data[i * 3] = UInt8(floor(amplitude * 200))
                data[i * 3 + 1] = UInt8(floor(amplitude * 150))
                data[i * 3 + 2] = UInt8(floor(amplitude * 100))
            }
            let sections = try parseAnlzSections(
                create2EXFile(pwv6: .init(numEntries: numEntries, data: data)))
            let result = makeWaveform3BandPreview(sections[0])
            #expect(result.numEntries == 1200)
            #expect(result.data.count == 3600)
            #expect(result.data[600 * 3] > 150)
        }
        @Test("handles realistic 30000-entry PWV7 detail data")
        func test9() throws {
            let numEntries = 30000
            let data = (0..<(numEntries * 3)).map { UInt8($0 % 256) }
            let sections = try parseAnlzSections(
                create2EXFile(pwv7: .init(numEntries: numEntries, data: data)))
            let result = makeWaveform3BandDetail(sections[0])
            #expect(result.numEntries == 30000)
            #expect(result.data.count == 90000)
            #expect(result.data[0] == 0)
            #expect(result.data[1] == 1)
            #expect(result.data[2] == 2)
        }
    }
    @Suite("convertPWV6ToBands")
    struct Group3 {
        @Test("normalizes byte values to 0-1 range")
        func test10() throws {
            let bands = convertPWV6ToBands([255, 0, 128, 0, 255, 64], 2)
            #expect(abs(bands.low[0] - 1) < 0.005)
            #expect(abs(bands.mid[0]) < 0.005)
            #expect(abs(bands.high[0] - 128.0 / 255) < 0.005)
            #expect(abs(bands.low[1]) < 0.005)
            #expect(abs(bands.mid[1] - 1) < 0.005)
            #expect(abs(bands.high[1] - 64.0 / 255) < 0.005)
        }
        @Test("returns arrays of correct length")
        func test11() throws {
            let bands = convertPWV6ToBands([UInt8](repeating: 0, count: 100 * 3), 100)
            #expect(bands.low.count == 100)
            #expect(bands.mid.count == 100)
            #expect(bands.high.count == 100)
        }
        @Test("all values are in 0-1 range")
        func test12() throws {
            let numEntries = 50
            let data = (0..<(numEntries * 3)).map { _ in UInt8.random(in: 0...255) }
            let bands = convertPWV6ToBands(data, numEntries)
            for value in bands.low + bands.mid + bands.high {
                #expect(value >= 0)
                #expect(value <= 1)
            }
        }
        @Test("handles all-zero data (silence)")
        func test13() throws {
            let bands = convertPWV6ToBands([UInt8](repeating: 0, count: 30), 10)
            for i in 0..<10 {
                #expect(bands.low[i] == 0)
                #expect(bands.mid[i] == 0)
                #expect(bands.high[i] == 0)
            }
        }
        @Test("handles all-max data (clipping)")
        func test14() throws {
            let bands = convertPWV6ToBands([UInt8](repeating: 255, count: 30), 10)
            for i in 0..<10 {
                #expect(bands.low[i] == 1)
                #expect(bands.mid[i] == 1)
                #expect(bands.high[i] == 1)
            }
        }
        @Test("handles empty data")
        func test15() throws {
            let bands = convertPWV6ToBands([], 0)
            #expect(bands.low.count == 0)
            #expect(bands.mid.count == 0)
            #expect(bands.high.count == 0)
        }
        @Test("full pipeline: binary fixture → parse → convert to bands")
        func test16() throws {
            let inputData: [UInt8] = [255, 128, 0, 0, 0, 255, 128, 128, 128]
            let sections = try parseAnlzSections(
                create2EXFile(pwv6: .init(numEntries: 3, data: inputData)))
            let preview = makeWaveform3BandPreview(sections[0])
            let bands = convertPWV6ToBands(preview.data, preview.numEntries)
            #expect(bands.low == [1, 0, 128.0 / 255])
            #expect(bands.mid == [128.0 / 255, 0, 128.0 / 255])
            #expect(bands.high == [0, 1, 128.0 / 255])
        }
    }
    @Suite("AnalysisDataPayload shape")
    struct Group4 {
        @Test("waveform3BandPreview converts to expected payload shape")
        func test17() throws {
            let inputData: [UInt8] = [200, 100, 50, 100, 200, 150]
            let sections = try parseAnlzSections(
                create2EXFile(pwv6: .init(numEntries: 2, data: inputData)))
            let preview = makeWaveform3BandPreview(sections[0])
            let payload = convertPWV6ToBands(preview.data, preview.numEntries)
            #expect(payload.low.count == 2)
            #expect(payload.mid.count == 2)
            #expect(payload.high.count == 2)
        }
        @Test("vocalConfig converts to expected payload shape")
        func test18() throws {
            let sections = try parseAnlzSections(
                create2EXFile(pwvc: .init(thresholdLow: 10, thresholdMid: 50, thresholdHigh: 90)))
            let payload = makeVocalConfig(sections[0])
            // 원본과 다름: typeof number와 속성 유무는 저장 속성과 정적 Int 형으로 검사한다.
            #expect(Mirror(reflecting: payload).children.count == 3)
            let _: Int = payload.thresholdLow
            let _: Int = payload.thresholdMid
            let _: Int = payload.thresholdHigh
        }
        @Test("null is a valid value when .2EX file is missing")
        func test19() throws {
            let twoxResult: AnlzResponse2EX? = nil
            #expect(twoxResult?.waveform3BandPreview == nil)
            #expect(twoxResult?.vocalConfig == nil)
        }
    }
}
