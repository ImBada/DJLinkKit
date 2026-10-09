import DJLinkKit
import Foundation
import Testing

// PLAN §9: 원본 버그를 고친 시험(원본 시험 파일이 아니다). 고친 곳마다 원본 위치를 적는다.
// 시험용 파일은 코드로 만든 바이트뿐이다.

// ---------------------------------------------------------------- 도우미

private func atom(_ type: String, _ parts: [UInt8]...) -> [UInt8] {
    let body = [UInt8].concat(parts)
    var header = [UInt8].alloc(8)
    header.writeUInt32BE(body.count + 8, 0)
    // atom 이름은 바이트 그대로(latin1)라서 `©`는 0xa9 한 바이트다.
    header.set([UInt8](type, encoding: .latin1), 4)
    return header + body
}

/// data atom: 4바이트 type + 4바이트 locale + 값.
private func dataAtom(_ typeIndicator: Int, _ value: [UInt8]) -> [UInt8] {
    var head = [UInt8].alloc(8)
    head.writeUInt32BE(typeIndicator, 0)
    return atom("data", head, value)
}

private func textItem(_ type: String, _ value: String) -> [UInt8] {
    atom(type, dataAtom(1, [UInt8](value, encoding: .utf8)))
}

private func numberItem(_ type: String, _ value: Int) -> [UInt8] {
    var bytes = [UInt8].alloc(2)
    bytes.writeUInt16BE(value, 0)
    return atom(type, dataAtom(0, bytes))
}

private func mp4File(_ items: [UInt8]...) -> [UInt8] {
    [UInt8].concat([
        atom("ftyp", [UInt8]("M4A \0\0\0\0", encoding: .latin1)),
        atom("moov", atom("udta", atom("meta", .alloc(4), atom("ilst", [UInt8].concat(items))))),
    ])
}

// ----------------------------------------------------------------- 시험

@Suite("metadata-connect 원본 버그 고침")
struct MetadataConnectUpstreamFixTests {
    @Suite("mp4 문자열 atom(©nam 등)")
    struct Mp4StringAtoms {
        // 원본 metadata-connect/src/parsers/mp4.ts:52 — 'ascii'로 읽어 0xa9가 ')'가 되어 ©nam이 맞지 않았다.
        @Test("reads title, artist, album, genre and year from the © atoms")
        func readsTextAtoms() async throws {
            let file = mp4File(
                textItem("\u{a9}nam", "Some Title"),
                textItem("\u{a9}ART", "Some Artist"),
                textItem("\u{a9}alb", "Some Album"),
                textItem("\u{a9}gen", "Deep House"),
                textItem("\u{a9}day", "2021-05-04")
            )

            let metadata = try #require(try await MetadataConnect.extractFromMp4(MetadataConnect.createBufferReader(file, "m4a")))

            #expect(metadata.title == "Some Title")
            #expect(metadata.artist == "Some Artist")
            #expect(metadata.album == "Some Album")
            #expect(metadata.genre == "Deep House")
            #expect(metadata.year == 2021)
        }

        @Test("decodes the data atom value as UTF-8 after the 8 byte type and locale")
        func decodesUtf8() async throws {
            let file = mp4File(
                textItem("\u{a9}nam", "Café 한국어"),
                textItem("\u{a9}ART", "  padded \0 artist  ")
            )

            let metadata = try #require(try await MetadataConnect.extractFromMp4(MetadataConnect.createBufferReader(file, "m4a")))

            #expect(metadata.title == "Café 한국어")
            #expect(metadata.artist == "padded  artist")
        }

        @Test("keeps the first value when an atom repeats")
        func keepsFirstValue() async throws {
            let file = mp4File(textItem("\u{a9}nam", "First"), textItem("\u{a9}nam", "Second"))

            let metadata = try #require(try await MetadataConnect.extractFromMp4(MetadataConnect.createBufferReader(file, "m4a")))

            #expect(metadata.title == "First")
        }

        @Test("reads the year from the first four digits of the date")
        func readsYearFromDate() async throws {
            let file = mp4File(textItem("\u{a9}day", "Released 1999"))

            let metadata = try #require(try await MetadataConnect.extractFromMp4(MetadataConnect.createBufferReader(file, "m4a")))

            #expect(metadata.year == 1999)
        }

        @Test("reads the 16-bit big-endian tmpo and gnre atoms")
        func readsNumericAtoms() async throws {
            // gnre는 ID3v1 번호 + 1 이다(18 → 17번 Rock)
            let file = mp4File(numberItem("tmpo", 128), numberItem("gnre", 18))

            let metadata = try #require(try await MetadataConnect.extractFromMp4(MetadataConnect.createBufferReader(file, "m4a")))

            #expect(metadata.bpm == 128)
            #expect(metadata.genre == "Rock")
        }

        @Test("prefers the text genre over the numeric gnre atom")
        func prefersTextGenre() async throws {
            let file = mp4File(textItem("\u{a9}gen", "Techno"), numberItem("gnre", 18))

            let metadata = try #require(try await MetadataConnect.extractFromMp4(MetadataConnect.createBufferReader(file, "m4a")))

            #expect(metadata.genre == "Techno")
        }

        @Test("does not match an atom whose name only differs in the high bit")
        func ignoresHighBitAliases() async throws {
            // 0x29는 ')'. 0xa9와 상위 비트만 다르다.
            let file = mp4File(textItem(")nam", "Wrong"))

            let metadata = try await MetadataConnect.extractFromMp4(MetadataConnect.createBufferReader(file, "m4a"))

            #expect(metadata?.title == nil)
        }
    }
}
