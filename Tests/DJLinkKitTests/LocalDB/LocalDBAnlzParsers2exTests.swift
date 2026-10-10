import Foundation
import Testing

@testable import DJLinkKit

@Suite(".2EX Parser Functions")
struct LocalDBAnlzParsers2exTests {
    @Suite("makeWaveform3BandPreview")
    struct Group0 {
        @Test("extracts numEntries from Kaitai object")
        func test0() throws {
            let result = makeWaveform3BandPreview(
                .init(lenEntries: 1200, entries: [UInt8](repeating: 0, count: 1200 * 3)))
            #expect(result.numEntries == 1200)
        }
        @Test("extracts data as Uint8Array")
        func test1() throws {
            let result = makeWaveform3BandPreview(
                .init(lenEntries: 2, entries: [10, 20, 30, 40, 50, 60]))
            // 원본과 다름: Uint8Array는 [UInt8]이며 Any 경계에서 대응 형을 확인한다.
            #expect((result.data as Any) is [UInt8])
            #expect(result.data.count == 6)
        }
        @Test("preserves exact byte values in data")
        func test2() throws {
            let entries: [UInt8] = [255, 0, 128, 0, 255, 64, 100, 100, 100]
            let result = makeWaveform3BandPreview(.init(lenEntries: 3, entries: entries))
            #expect(result.data == [255, 0, 128, 0, 255, 64, 100, 100, 100])
        }
        @Test("handles typical 1200-entry preview")
        func test3() throws {
            let numEntries = 1200
            let entries = (0..<(numEntries * 3)).map { UInt8($0 % 256) }
            let result = makeWaveform3BandPreview(.init(lenEntries: numEntries, entries: entries))
            #expect(result.numEntries == 1200)
            #expect(result.data.count == 3600)
        }
        @Test("handles zero entries")
        func test4() throws {
            let result = makeWaveform3BandPreview(.init(lenEntries: 0, entries: []))
            #expect(result.numEntries == 0)
            #expect(result.data.count == 0)
        }
        @Test("handles single entry")
        func test5() throws {
            let result = makeWaveform3BandPreview(.init(lenEntries: 1, entries: [42, 84, 168]))
            #expect(result.numEntries == 1)
            #expect(result.data == [42, 84, 168])
        }
        @Test("creates an independent copy of the data")
        func test6() throws {
            var entries: [UInt8] = [10, 20, 30]
            let result = makeWaveform3BandPreview(.init(lenEntries: 1, entries: entries))
            entries[0] = 99
            #expect(result.data[0] == 10)
        }
    }
    @Suite("makeWaveform3BandDetail")
    struct Group1 {
        @Test("extracts numEntries from Kaitai object")
        func test7() throws {
            let result = makeWaveform3BandDetail(
                .init(lenEntries: 45000, entries: [UInt8](repeating: 0, count: 45000 * 3)))
            #expect(result.numEntries == 45000)
        }
        @Test("extracts data as Uint8Array")
        func test8() throws {
            let result = makeWaveform3BandDetail(.init(lenEntries: 2, entries: [10, 20, 30, 40, 50, 60]))
            // 원본과 다름: Uint8Array는 [UInt8]이며 Any 경계에서 대응 형을 확인한다.
            #expect((result.data as Any) is [UInt8])
            #expect(result.data.count == 6)
        }
        @Test("preserves exact byte values in data")
        func test9() throws {
            let result = makeWaveform3BandDetail(
                .init(lenEntries: 2, entries: [0, 128, 255, 64, 192, 32]))
            #expect(result.data == [0, 128, 255, 64, 192, 32])
        }
        @Test("handles large detail waveform (5-min track)")
        func test10() throws {
            let numEntries = 45000
            let entries = (0..<(numEntries * 3)).map { UInt8($0 % 256) }
            let result = makeWaveform3BandDetail(.init(lenEntries: numEntries, entries: entries))
            #expect(result.numEntries == 45000)
            #expect(result.data.count == 135000)
        }
        @Test("handles zero entries")
        func test11() throws {
            let result = makeWaveform3BandDetail(.init(lenEntries: 0, entries: []))
            #expect(result.numEntries == 0)
            #expect(result.data.count == 0)
        }
        @Test("creates an independent copy of the data")
        func test12() throws {
            var entries: [UInt8] = [10, 20, 30]
            let result = makeWaveform3BandDetail(.init(lenEntries: 1, entries: entries))
            entries[0] = 99
            #expect(result.data[0] == 10)
        }
    }
    @Suite("makeVocalConfig")
    struct Group2 {
        @Test("extracts all three threshold values")
        func test13() throws {
            let result = makeVocalConfig(.init(thresholdLow: 10, thresholdMid: 50, thresholdHigh: 90))
            #expect(result == VocalConfig(thresholdLow: 10, thresholdMid: 50, thresholdHigh: 90))
        }
        @Test("handles zero thresholds")
        func test14() throws {
            let result = makeVocalConfig(.init(thresholdLow: 0, thresholdMid: 0, thresholdHigh: 0))
            #expect(result == VocalConfig(thresholdLow: 0, thresholdMid: 0, thresholdHigh: 0))
        }
        @Test("handles maximum observed threshold values")
        func test15() throws {
            let result = makeVocalConfig(.init(thresholdLow: 114, thresholdMid: 146, thresholdHigh: 159))
            #expect(result == VocalConfig(thresholdLow: 114, thresholdMid: 146, thresholdHigh: 159))
        }
        @Test("handles typical real-world threshold values")
        func test16() throws {
            let result = makeVocalConfig(.init(thresholdLow: 97, thresholdMid: 114, thresholdHigh: 130))
            #expect(result == VocalConfig(thresholdLow: 97, thresholdMid: 114, thresholdHigh: 130))
        }
        @Test("returns a plain object with exactly 3 properties")
        func test17() throws {
            let result = makeVocalConfig(.init(thresholdLow: 10, thresholdMid: 50, thresholdHigh: 90))
            // 원본과 다름: Object.keys 대신 Mirror로 저장 속성 이름을 검사한다.
            let keys = Mirror(reflecting: result).children.compactMap(\.label).sorted()
            #expect(keys.count == 3)
            #expect(keys == ["thresholdHigh", "thresholdLow", "thresholdMid"])
        }
    }
}
