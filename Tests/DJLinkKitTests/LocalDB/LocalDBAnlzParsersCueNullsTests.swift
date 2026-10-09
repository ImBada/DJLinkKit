import Foundation
import Testing

@testable import DJLinkKit

@Suite("makeCueAndLoop")
struct LocalDBAnlzParsersCueNullsTests {
    @Test("drops entries that are neither a cue point nor a loop")
    func test0() throws {
        let result = makeCueAndLoop(
            .init(cues: [
                .init(hotCue: 0, type: 0, time: 100, loopTime: 0), .init(hotCue: 0, type: 1, time: 200, loopTime: 0),
                .init(hotCue: 0, type: 9, time: 300, loopTime: 0),
            ]))
        #expect(result == [.cuePoint(.init(offset: 200))])
    }
    @Test("returns an empty list when nothing survives")
    func test1() throws {
        #expect(makeCueAndLoop(.init(cues: [.init(hotCue: 0, type: 0, time: 100, loopTime: 0)])) == [])
    }
}
