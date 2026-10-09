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

// ID3 (mp3)

/// v2.3/2.4 프레임: 4바이트 ID, 4바이트 크기(v2.3은 big-endian), 플래그 2바이트.
private func id3v23Frame(_ id: String, _ value: String) -> [UInt8] {
    let body = [UInt8.zero] + [UInt8](value, encoding: .latin1)
    var header = [UInt8].alloc(10)
    header.set([UInt8](id, encoding: .ascii), 0)
    header.writeUInt32BE(body.count, 4)
    return header + body
}

/// v2.2 프레임: 3바이트 ID, 3바이트 크기, 플래그 없음.
private func id3v22Frame(_ id: String, _ value: String) -> [UInt8] {
    let body = [UInt8.zero] + [UInt8](value, encoding: .latin1)
    var header = [UInt8].alloc(6)
    header.set([UInt8](id, encoding: .ascii), 0)
    header[3] = UInt8((body.count >> 16) & 0xff)
    header[4] = UInt8((body.count >> 8) & 0xff)
    header[5] = UInt8(body.count & 0xff)
    return header + body
}

private func id3Tag(_ majorVersion: Int, _ frames: [[UInt8]]) -> [UInt8] {
    let body = [UInt8].concat(frames)
    var header = [UInt8].alloc(10)
    header.set([UInt8]("ID3", encoding: .ascii), 0)
    header[3] = UInt8(majorVersion)
    header[6] = UInt8((body.count >> 21) & 0x7f)
    header[7] = UInt8((body.count >> 14) & 0x7f)
    header[8] = UInt8((body.count >> 7) & 0x7f)
    header[9] = UInt8(body.count & 0x7f)
    return header + body
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

    @Suite("ID3 프레임 ID 비교")
    struct Id3FrameIds {
        // 원본 metadata-connect/src/parsers/id3.ts:139 — `frameId.startsWith(target)`이라 TCOM·TCOP이 장르(TCO)로 읽혔다.
        @Test("does not read the composer frame TCOM as the genre")
        func tcomIsNotGenre() async throws {
            let file = id3Tag(3, [id3v23Frame("TIT2", "Title"), id3v23Frame("TCOM", "Some Composer")])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata.title == "Title")
            #expect(metadata.genre == nil)
        }

        @Test("does not read the copyright frame TCOP as the genre")
        func tcopIsNotGenre() async throws {
            let file = id3Tag(4, [id3v23Frame("TIT2", "Title"), id3v23Frame("TCOP", "2021 Some Label")])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata.genre == nil)
        }

        @Test("still reads the genre from TCON when TCOM comes first")
        func tconAfterTcom() async throws {
            let file = id3Tag(3, [id3v23Frame("TCOM", "Some Composer"), id3v23Frame("TCON", "(17)")])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata.genre == "Rock")
        }

        @Test("reads the v2.2 three-letter frames, but not the other v2.2 TC frames")
        func v22Frames() async throws {
            let file = id3Tag(
                2,
                [
                    id3v22Frame("TCM", "Some Composer"),
                    id3v22Frame("TCR", "2021 Some Label"),
                    id3v22Frame("TT2", "Title"),
                    id3v22Frame("TCO", "House"),
                ])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata.title == "Title")
            #expect(metadata.genre == "House")
        }

        @Test("matches every frame ID exactly")
        func allFramesExact() async throws {
            let file = id3Tag(
                3,
                [
                    id3v23Frame("TIT2", "Title"),
                    id3v23Frame("TPE1", "Artist"),
                    id3v23Frame("TALB", "Album"),
                    id3v23Frame("TCON", "Deep House"),
                    id3v23Frame("TPUB", "Label"),
                    id3v23Frame("TYER", "2020"),
                    id3v23Frame("TBPM", "126"),
                    id3v23Frame("TKEY", "Am"),
                ])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata.title == "Title")
            #expect(metadata.artist == "Artist")
            #expect(metadata.album == "Album")
            #expect(metadata.genre == "Deep House")
            #expect(metadata.label == "Label")
            #expect(metadata.year == 2020)
            #expect(metadata.bpm == 126)
            #expect(metadata.key == "Am")
        }
    }
}
