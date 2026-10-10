import Foundation
import Testing

@testable import DJLinkKit

@Suite("makeCueAndLoop")
struct LocalDBAnlzParsersCuesTests {
    @Test("maps memory cue points and loops")
    func test0() throws {
        let result = makeCueAndLoop(
            .init(
                fourcc: "PCOB",
                cues: [
                    .init(hotCue: 0, type: 1, time: 1000, loopTime: 0),
                    .init(hotCue: 0, type: 2, time: 2000, loopTime: 3000),
                ]))
        #expect(result == [.cuePoint(.init(offset: 1000)), .loop(.init(offset: 2000, length: 1000))])
    }
    @Test("takes the hot cue button from hotCue, not from the entry type")
    func test1() throws {
        let result = makeCueAndLoop(
            .init(
                fourcc: "PCOB",
                cues: [
                    .init(hotCue: 3, type: 1, time: 4000, loopTime: 0),
                    .init(hotCue: 8, type: 2, time: 5000, loopTime: 6000),
                    .init(hotCue: 1, type: 1, time: 7000, loopTime: 0),
                ]))
        #expect(
            result == [
                .hotCue(.init(offset: 4000, button: .C)),
                .hotLoop(.init(offset: 5000, button: .H, length: 1000)),
                .hotCue(.init(offset: 7000, button: .A)),
            ])
    }
    @Test("drops entries that are neither a cue nor a loop")
    func test2() throws {
        #expect(
            makeCueAndLoop(
                .init(
                    fourcc: "PCOB",
                    cues: [
                        .init(hotCue: 0, type: 0, time: 100, loopTime: 0),
                        .init(hotCue: 0, type: 1, time: 200, loopTime: 0),
                    ]))
                == [.cuePoint(.init(offset: 200))])
    }
}
