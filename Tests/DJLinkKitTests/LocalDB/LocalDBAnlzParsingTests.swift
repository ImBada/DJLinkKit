import Foundation
import Testing

@testable import DJLinkKit

@Suite("ANLZ Binary Fixtures")
struct LocalDBAnlzParsingTests {
    @Suite("file header")
    struct Group0 {
        @Test("creates valid ANLZ file header")
        func test0() throws {
            let buffer = createAnlzFile([])
            #expect(buffer.count == 12)
            #expect(buffer.toString(.ascii, 0, 4) == "PMAI")
            #expect(try buffer.readUInt32BE(4) == 12)
            #expect(try buffer.readUInt32BE(8) == 12)
        }
        @Test("calculates file length correctly with sections")
        func test1() throws {
            let pwv6 = createPWV6Section(numEntries: 10)
            let buffer = createAnlzFile([pwv6])
            let expectedLength = 12 + pwv6.count
            #expect(try Int(buffer.readUInt32BE(8)) == expectedLength)
            #expect(buffer.count == expectedLength)
        }
    }
    @Suite("PWV6 section")
    struct Group1 {
        @Test("creates valid section header")
        func test2() throws {
            let section = createPWV6Section(numEntries: 100)
            #expect(try section.readUInt32BE(0) == 0x5057_5636)
            #expect(try section.readUInt32BE(4) == 12)
            #expect(try section.readUInt32BE(8) == 12 + 4 + 4 + 100 * 3)
        }
        @Test("stores entry bytes correctly")
        func test3() throws {
            let section = createPWV6Section(numEntries: 100)
            #expect(try section.readUInt32BE(12) == 3)
        }
        @Test("stores num_entries correctly")
        func test4() throws {
            let section = createPWV6Section(numEntries: 500)
            #expect(try section.readUInt32BE(16) == 500)
        }
        @Test("stores waveform data correctly")
        func test5() throws {
            let data: [UInt8] = [255, 0, 128, 0, 255, 64, 100, 100, 100]
            let section = createPWV6Section(numEntries: 3, data: data)
            #expect(section.subarray(20, 20 + 9) == data)
        }
        @Test("generates default data when not provided")
        func test6() throws {
            let section = createPWV6Section(numEntries: 10)
            #expect(section.count == 12 + 8 + 10 * 3)
        }
    }
    @Suite("PWV7 section")
    struct Group2 {
        @Test("creates valid section header")
        func test7() throws {
            let section = createPWV7Section(numEntries: 1000)
            #expect(try section.readUInt32BE(0) == 0x5057_5637)
            #expect(try section.readUInt32BE(4) == 12)
        }
        @Test("stores entry bytes correctly")
        func test8() throws {
            let section = createPWV7Section()
            #expect(try section.readUInt32BE(12) == 3)
        }
        @Test("stores num_entries correctly")
        func test9() throws {
            let section = createPWV7Section(numEntries: 30000)
            #expect(try section.readUInt32BE(16) == 30000)
        }
        @Test("stores waveform data correctly")
        func test10() throws {
            let data: [UInt8] = [10, 20, 30, 40, 50, 60]
            let section = createPWV7Section(numEntries: 2, data: data)
            #expect(section.subarray(24, 24 + 6) == data)
        }
    }
    @Suite("PWVC section")
    struct Group3 {
        @Test("creates valid section header")
        func test11() throws {
            let section = createPWVCSection()
            #expect(try section.readUInt32BE(0) == 0x5057_5643)
            #expect(try section.readUInt32BE(4) == 12)
            #expect(try section.readUInt32BE(8) == 20)
        }
        @Test("stores threshold_low correctly")
        func test12() throws {
            let section = createPWVCSection(thresholdLow: 15)
            #expect(try section.readUInt16BE(14) == 15)
        }
        @Test("stores threshold_mid correctly")
        func test13() throws {
            let section = createPWVCSection(thresholdMid: 55)
            #expect(try section.readUInt16BE(16) == 55)
        }
        @Test("stores threshold_high correctly")
        func test14() throws {
            let section = createPWVCSection(thresholdHigh: 95)
            #expect(try section.readUInt16BE(18) == 95)
        }
        @Test("handles zero thresholds")
        func test15() throws {
            let section = createPWVCSection(thresholdLow: 0, thresholdMid: 0, thresholdHigh: 0)
            #expect(try section.readUInt16BE(14) == 0)
            #expect(try section.readUInt16BE(16) == 0)
            #expect(try section.readUInt16BE(18) == 0)
        }
        @Test("handles max observed thresholds")
        func test16() throws {
            let section = createPWVCSection(thresholdLow: 114, thresholdMid: 146, thresholdHigh: 159)
            #expect(try section.readUInt16BE(14) == 114)
            #expect(try section.readUInt16BE(16) == 146)
            #expect(try section.readUInt16BE(18) == 159)
        }
    }
    @Suite("PWV5 section")
    struct Group4 {
        @Test("creates valid section header")
        func test17() throws {
            let section = createPWV5Section(numEntries: 1000)
            #expect(try section.readUInt32BE(0) == 0x5057_5635)
            #expect(try section.readUInt32BE(4) == 12)
        }
        @Test("stores entry bytes correctly")
        func test18() throws {
            let section = createPWV5Section()
            #expect(try section.readUInt32BE(12) == 2)
        }
        @Test("stores num_entries correctly")
        func test19() throws {
            let section = createPWV5Section(numEntries: 2000)
            #expect(try section.readUInt32BE(16) == 2000)
        }
        @Test("stores waveform data correctly")
        func test20() throws {
            let data: [UInt8] = [0x12, 0x34, 0x56, 0x78]
            let section = createPWV5Section(numEntries: 2, data: data)
            #expect(section.subarray(24, 28) == data)
        }
    }
    @Suite("combined files")
    struct Group5 {
        @Test("creates valid 2EX file with all sections")
        func test21() throws {
            let buffer = create2EXFile(
                pwv6: .init(numEntries: 100), pwv7: .init(numEntries: 500),
                pwvc: .init(thresholdLow: 10, thresholdMid: 50, thresholdHigh: 90))
            #expect(buffer.toString(.ascii, 0, 4) == "PMAI")
            let found = try (12..<(buffer.count - 4)).map { try buffer.readUInt32BE($0) }
            #expect(found.contains(0x5057_5636) == true)
            #expect(found.contains(0x5057_5637) == true)
            #expect(found.contains(0x5057_5643) == true)
        }
        @Test("creates valid 2EX file with single section")
        func test22() throws {
            let buffer = create2EXFile(pwv6: .init(numEntries: 50))
            #expect(buffer.toString(.ascii, 0, 4) == "PMAI")
            let found = try (12..<(buffer.count - 4)).map { try buffer.readUInt32BE($0) }
            #expect(found.contains(0x5057_5636) == true)
            #expect(found.contains(0x5057_5637) == false)
            #expect(found.contains(0x5057_5643) == false)
        }
        @Test("creates valid EXT file with PWV5 section")
        func test23() throws {
            let buffer = createEXTFile(pwv5: .init(numEntries: 1000))
            #expect(buffer.toString(.ascii, 0, 4) == "PMAI")
            let found = try (12..<(buffer.count - 4)).map { try buffer.readUInt32BE($0) }
            #expect(found.contains(0x5057_5635) == true)
        }
    }
    @Suite("data integrity")
    struct Group6 {
        @Test("preserves exact waveform data in PWV6")
        func test24() throws {
            let data: [UInt8] = [255, 0, 128, 0, 255, 64, 100, 100, 100]
            let section = createPWV6Section(numEntries: 3, data: data)
            #expect(section.subarray(20, 29) == data)
        }
        @Test("preserves exact waveform data in PWV7")
        func test25() throws {
            let data: [UInt8] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120]
            let section = createPWV7Section(numEntries: 4, data: data)
            #expect(section.subarray(24, 36) == data)
        }
        @Test("handles large waveform data")
        func test26() throws {
            let numEntries = 30000
            let dataLength = numEntries * 3
            let data = (0..<dataLength).map { UInt8($0 % 256) }
            let section = createPWV7Section(numEntries: numEntries, data: data)
            #expect(try section.readUInt32BE(16) == numEntries)
            #expect(section[24] == 0)
            #expect(Int(section[24 + dataLength - 1]) == (dataLength - 1) % 256)
        }
    }
    @Suite("section tags")
    struct Group7 {
        @Test("has correct PWV5 tag (WAVE_COLOR_SCROLL)")
        func test27() throws {
            #expect(localDBSectionTags["WAVE_COLOR_SCROLL"] == 0x5057_5635)
        }
        @Test("has correct PWV6 tag (WAVE_COLOR_3CHANNEL)")
        func test28() throws {
            #expect(localDBSectionTags["WAVE_COLOR_3CHANNEL"] == 0x5057_5636)
        }
        @Test("has correct PWV7 tag (WAVE_HD)")
        func test29() throws {
            #expect(localDBSectionTags["WAVE_HD"] == 0x5057_5637)
        }
        @Test("has correct PWVC tag (VOCAL_CONFIG)")
        func test30() throws {
            #expect(localDBSectionTags["VOCAL_CONFIG"] == 0x5057_5643)
        }
    }
}
