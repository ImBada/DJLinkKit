import Foundation
import Testing

@testable import DJLinkKit

@Suite("makeSongStructure")
struct LocalDBAnlzParsersSongStructureTests {
    @Test("reads mood, bank and end beat from the body")
    func test0() throws {
        let result = makeSongStructure(.init(fourcc: "PSSI", mood: 2, bank: 7, endBeat: 512))
        #expect(result == SongStructure(mood: .mid, bank: .club_1, endBeat: 512, phrases: []))
    }
    @Test("reads phrase index, beat and kind from the generated field names")
    func test1() throws {
        let result = makeSongStructure(
            .init(
                fourcc: "PSSI", mood: 1, bank: 0, endBeat: 256,
                phrases: [
                    .init(phraseNumber: 1, beatNumber: 1, kind: .init(id: 1)),
                    .init(phraseNumber: 2, beatNumber: 65, kind: .init(id: 2)),
                    .init(phraseNumber: 3, beatNumber: 129, kind: .init(id: 5)),
                ]))
        #expect(
            result.phrases == [
                .init(index: 1, beat: 1, kind: 1, phraseType: "Intro"),
                .init(index: 2, beat: 65, kind: 2, phraseType: "Up"),
                .init(index: 3, beat: 129, kind: 5, phraseType: "Chorus"),
            ])
    }
    @Test("labels kinds by mood")
    func test2() throws {
        let mid = makeSongStructure(
            .init(fourcc: "PSSI", mood: 2, phrases: [.init(phraseNumber: 1, beatNumber: 1, kind: .init(id: 9))]))
        let low = makeSongStructure(
            .init(fourcc: "PSSI", mood: 3, phrases: [.init(phraseNumber: 1, beatNumber: 1, kind: .init(id: 4))]))
        #expect(mid.phrases[0].phraseType == "Chorus")
        #expect(low.phrases[0].phraseType == "Verse 1")
    }
    @Test("includes fill-in details only when present")
    func test3() throws {
        let result = makeSongStructure(
            .init(
                fourcc: "PSSI", mood: 2,
                phrases: [
                    .init(phraseNumber: 1, beatNumber: 1, kind: .init(id: 1)),
                    .init(phraseNumber: 2, beatNumber: 33, kind: .init(id: 9), fillIn: 1, fillInBeatNumber: 60),
                ]))
        #expect(result.phrases[0].fill == nil)
        #expect(result.phrases[0].fillBeat == nil)
        #expect(result.phrases[1].fill == 1)
        #expect(result.phrases[1].fillBeat == 60)
    }
    @Test("falls back for unknown moods, banks and kinds")
    func test4() throws {
        let result = makeSongStructure(
            .init(
                fourcc: "PSSI", mood: 9, bank: 42, phrases: [.init(phraseNumber: 1, beatNumber: 1, kind: .init(id: 99))]
            ))
        #expect(result.mood == .high)
        #expect(result.bank == .default)
        #expect(result.phrases[0].phraseType == "Unknown")
    }
}
