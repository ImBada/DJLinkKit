@testable import DJLinkKit
import Testing

// PLAN §9: 원본 버그를 고친 시험(원본 시험 파일이 아니다). 고친 곳마다 원본 위치를 적는다.
// 시험용 파일은 코드로 만든 바이트뿐이다(ArtworkFixtures.swift의 TINY_JPEG 등).

// ---------------------------------------------------------------- 도우미

private func mp4Atom(_ type: [UInt8], _ data: [UInt8]) -> [UInt8] {
    var header = [UInt8].alloc(8)
    header.writeUInt32BE(8 + data.count, 0)
    header.set(type, 4)
    return header + data
}

private func mp4Atom(_ type: String, _ data: [UInt8]) -> [UInt8] {
    mp4Atom([UInt8](type, encoding: .latin1), data)
}

/// `covr` atom 이름을 바이트로 받는 mp4 파일(ArtworkFixtures의 `createMp4WithArtwork`와 같은 구조).
private func mp4WithCover(_ imageData: [UInt8], covrName: [UInt8]) -> [UInt8] {
    var dataContent = [UInt8].alloc(8 + imageData.count)
    dataContent.writeUInt32BE(13, 0)
    dataContent.set(imageData, 8)

    let covr = mp4Atom(covrName, mp4Atom("data", dataContent))
    let ilst = mp4Atom("ilst", covr)
    let meta = mp4Atom("meta", [UInt8].alloc(4) + ilst)
    let moov = mp4Atom("moov", mp4Atom("udta", meta))
    let ftyp = mp4Atom("ftyp", [UInt8]("M4A \u{0}\u{0}\u{0}\u{0}M4A mp42isom", encoding: .latin1))
    return ftyp + moov
}

// ----------------------------------------------------------------- 시험

@Suite("artwork 원본 버그 고침")
struct ArtworkUpstreamFixTests {
    @Suite("mp4 atom 이름")
    struct Mp4AtomNames {
        // 원본 alphatheta-connect/src/artwork/parsers/mp4.ts:19 — 'ascii'로 읽어 상위 비트가 지워졌다.
        @Test("does not mistake an atom whose name differs from covr only in the high bit")
        func ignoresHighBitAliasOfCovr() async throws {
            // 0xe3 'o' 'v' 'r' — 상위 비트를 지우면 'covr'가 된다.
            let file = mp4WithCover(TINY_JPEG, covrName: [0xe3, 0x6f, 0x76, 0x72])

            let result = try await extractFromMp4(createBufferReader(file, "m4a"))

            #expect(result == nil)
        }

        @Test("still reads the real covr atom")
        func readsRealCovr() async throws {
            let file = mp4WithCover(TINY_JPEG, covrName: [UInt8]("covr", encoding: .latin1))

            let result = try await extractFromMp4(createBufferReader(file, "m4a"))

            #expect(try #require(result).data.bytesEqual(TINY_JPEG))
        }
    }
}
