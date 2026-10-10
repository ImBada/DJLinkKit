import Foundation
import Testing

@testable import DJLinkKit

@Suite("makeExtendedCues")
struct LocalDBAnlzParsersExtendedCuesTests {
    @Test("maps a plain memory cue")
    func test0() throws {
        let cue = try #require(
            makeExtendedCues(
                .init(
                    fourcc: "PCO2",
                    cues: [.init(hotCue: 0, type: 1, time: 1000, loopTime: 0, colorId: 0, lenComment: 0)])
            ).first)
        #expect(cue == ExtendedCue(hotCue: 0, type: 1, time: 1000))
    }
    @Test("carries the quantized loop size read from the tag")
    func test1() throws {
        let cue = try #require(
            makeExtendedCues(
                .init(
                    fourcc: "PCO2",
                    cues: [
                        .init(
                            hotCue: 0, type: 2, time: 2000, loopTime: 6000, colorId: 5, loopNumerator: 4,
                            loopDenominator: 1, lenComment: 0)
                    ])
            ).first)
        #expect(
            cue
                == ExtendedCue(
                    hotCue: 0, type: 2, time: 2000, loopTime: 6000, colorId: 5, loopNumerator: 4,
                    loopDenominator: 1))
    }
    @Test("leaves loop size out when the loop is not quantized")
    func test2() throws {
        let cue = try #require(
            makeExtendedCues(
                .init(
                    fourcc: "PCO2",
                    cues: [
                        .init(
                            hotCue: 0, type: 2, time: 0, loopTime: 500, colorId: 0, loopNumerator: 0,
                            loopDenominator: 0, lenComment: 0)
                    ])
            ).first)
        #expect(cue.loopNumerator == nil)
        #expect(cue.loopDenominator == nil)
    }
    @Test("maps hot cue colours and comments")
    func test3() throws {
        let cue = try #require(
            makeExtendedCues(
                .init(
                    fourcc: "PCO2",
                    cues: [
                        .init(
                            hotCue: 3, type: 1, time: 3000, loopTime: 0, colorId: 0, lenComment: 10,
                            comment: "Drop\0", colorCode: 0x2a, colorRed: 255, colorGreen: 0, colorBlue: 0)
                    ])
            ).first)
        #expect(
            cue
                == ExtendedCue(
                    hotCue: 3, type: 1, time: 3000, colorCode: 0x2a, colorRgb: .init(r: 255, g: 0, b: 0),
                    comment: "Drop"))
    }
    @Test("drops a comment that is only the trailing NUL")
    func test4() throws {
        let cue = try #require(
            makeExtendedCues(
                .init(
                    fourcc: "PCO2",
                    cues: [
                        .init(hotCue: 0, type: 1, time: 0, loopTime: 0, colorId: 0, lenComment: 2, comment: "\0")
                    ])
            ).first)
        #expect(cue.comment == nil)
    }
}
