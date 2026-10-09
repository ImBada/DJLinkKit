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

/// 확장 헤더(플래그 0x40)가 있는 태그. `extendedHeader`는 크기 칸을 포함한 확장 헤더 전체다.
private func id3TagWithExtendedHeader(_ majorVersion: Int, _ extendedHeader: [UInt8], _ frames: [[UInt8]]) -> [UInt8] {
    var tag = id3Tag(majorVersion, [extendedHeader] + frames)
    tag[5] = 0x40
    return tag
}

/// APIC 프레임(v2.3): 인코딩 바이트, MIME(latin1)+0, 그림 종류, 설명(인코딩대로)+끝 표시, 이미지.
private func apicFrame(encodingByte: UInt8, description: [UInt8], terminator: [UInt8], image: [UInt8]) -> [UInt8] {
    let body = [UInt8].concat([
        [encodingByte],
        [UInt8]("image/jpeg\0", encoding: .latin1),
        [3],
        description,
        terminator,
        image,
    ])
    var header = [UInt8].alloc(10)
    header.set([UInt8]("APIC", encoding: .ascii), 0)
    header.writeUInt32BE(body.count, 4)
    return header + body
}

/// 시험용 JPEG 머리말(첫 세 바이트만 실제 JPEG와 같다).
private let fakeJpeg: [UInt8] = [0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 5, 6, 7, 8]

// FLAC

private func vorbisComment(_ fields: [String]) -> [UInt8] {
    let vendor = [UInt8]("reference libFLAC", encoding: .utf8)
    var parts: [[UInt8]] = [.alloc(4), vendor, .alloc(4)]
    parts[0].writeUInt32LE(vendor.count, 0)
    parts[2].writeUInt32LE(fields.count, 0)

    for field in fields {
        let encoded = [UInt8](field, encoding: .utf8)
        var length = [UInt8].alloc(4)
        length.writeUInt32LE(encoded.count, 0)
        parts.append(length)
        parts.append(encoded)
    }

    let body = [UInt8].concat(parts)
    var blockHeader = [UInt8].alloc(4)
    blockHeader[0] = 0x80 | 4 // last block, VORBIS_COMMENT
    blockHeader[1] = UInt8((body.count >> 16) & 0xff)
    blockHeader[2] = UInt8((body.count >> 8) & 0xff)
    blockHeader[3] = UInt8(body.count & 0xff)

    return [UInt8]("fLaC", encoding: .ascii) + blockHeader + body
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

    @Suite("값이 모두 비어 있으면 null")
    struct EmptyResult {
        // 원본 metadata-connect/src/parsers/mp4.ts:315, id3.ts:245, flac.ts — `Object.keys(metadata).length === 0`은
        // `metadata.title = undefined`로 생긴 키도 세어서 값이 하나도 없어도 null이 아니었다.
        @Test("returns null when every mp4 atom is empty")
        func mp4Empty() async throws {
            let file = mp4File(textItem("\u{a9}nam", ""), textItem("\u{a9}ART", " \0 "), numberItem("gnre", 0), numberItem("tmpo", 0))

            let metadata = try await MetadataConnect.extractFromMp4(MetadataConnect.createBufferReader(file, "m4a"))

            #expect(metadata == nil)
        }

        @Test("returns null when an mp4 date has no year")
        func mp4NoYear() async throws {
            let file = mp4File(textItem("\u{a9}day", "unknown"))

            let metadata = try await MetadataConnect.extractFromMp4(MetadataConnect.createBufferReader(file, "m4a"))

            #expect(metadata == nil)
        }

        @Test("keeps only the real values of an mp4 that also has empty atoms")
        func mp4Mixed() async throws {
            let file = mp4File(textItem("\u{a9}nam", ""), textItem("\u{a9}ART", "Artist"))

            let metadata = try #require(try await MetadataConnect.extractFromMp4(MetadataConnect.createBufferReader(file, "m4a")))

            #expect(metadata == MetadataConnect.ExtractedMetadata(artist: "Artist"))
        }

        @Test("returns null when every ID3 text frame is empty or unparsable")
        func id3Empty() async throws {
            let file = id3Tag(
                3,
                [
                    id3v23Frame("TIT2", ""),
                    id3v23Frame("TYER", "unknown"),
                    id3v23Frame("TBPM", "fast"),
                    id3v23Frame("TCON", ""),
                ])

            let metadata = try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3"))

            #expect(metadata == nil)
        }

        @Test("keeps only the real values of an ID3 tag that also has empty frames")
        func id3Mixed() async throws {
            let file = id3Tag(3, [id3v23Frame("TIT2", ""), id3v23Frame("TPE1", "Artist")])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata == MetadataConnect.ExtractedMetadata(artist: "Artist"))
        }

        @Test("returns null when the Vorbis comments hold no known field")
        func flacEmpty() async throws {
            let file = vorbisComment(["ENCODER=reference libFLAC", "TITLE=", "DATE=unknown"])

            let metadata = try await MetadataConnect.extractFromFlac(MetadataConnect.createBufferReader(file, "flac"))

            #expect(metadata == nil)
        }

        @Test("keeps only the real values of Vorbis comments that also have empty fields")
        func flacMixed() async throws {
            let file = vorbisComment(["TITLE=", "ARTIST=Artist"])

            let metadata = try #require(try await MetadataConnect.extractFromFlac(MetadataConnect.createBufferReader(file, "flac")))

            #expect(metadata == MetadataConnect.ExtractedMetadata(artist: "Artist"))
        }
    }

    @Suite("APIC 설명 문자열의 BOM")
    struct ApicBom {
        // 원본 metadata-connect/src/parsers/id3.ts:52 — BOM을 인코딩 바이트 바로 뒤(MIME 문자열 자리)에서 찾았다.
        // BOM은 설명 문자열 앞에 있다. 설명은 읽은 뒤 버려지고 끝 표시 찾기는 바이트 순서와 상관없어서,
        // 결과가 달라지는 입력은 없다. 아래 시험은 고치기 전후 모두 통과하는 확인용이다.
        @Test("reads the picture after a UTF-16 description with a little-endian BOM")
        func littleEndianBom() async throws {
            let description: [UInt8] = [0xff, 0xfe, 0x43, 0x00, 0x6f, 0x00, 0x76, 0x00]
            let file = id3Tag(3, [apicFrame(encodingByte: 1, description: description, terminator: [0, 0], image: fakeJpeg)])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata.artwork == fakeJpeg)
            #expect(metadata.artworkMimeType == .jpeg)
        }

        @Test("reads the picture after a UTF-16 description with a big-endian BOM")
        func bigEndianBom() async throws {
            let description: [UInt8] = [0xfe, 0xff, 0x00, 0x43, 0x00, 0x6f, 0x00, 0x76]
            let file = id3Tag(3, [apicFrame(encodingByte: 1, description: description, terminator: [0, 0], image: fakeJpeg)])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata.artwork == fakeJpeg)
        }

        @Test("reads the picture after an empty UTF-16 description that only has a BOM")
        func bomOnlyDescription() async throws {
            let file = id3Tag(3, [apicFrame(encodingByte: 1, description: [0xff, 0xfe], terminator: [0, 0], image: fakeJpeg)])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata.artwork == fakeJpeg)
        }
    }

    @Suite("ID3 확장 헤더")
    struct ExtendedHeader {
        // 원본 metadata-connect/src/parsers/id3.ts:158 — v2.3의 확장 헤더 크기는 크기 칸 4바이트를 뺀 값인데
        // 4바이트를 더하지 않아 프레임이 4바이트 앞에서 읽히기 시작했다.
        @Test("skips a v2.3 extended header (size excludes the size field itself)")
        func v23ExtendedHeader() async throws {
            // 크기 6 = 플래그 2 + 패딩 4. 헤더 전체는 10바이트.
            let extended: [UInt8] = [0, 0, 0, 6, 0, 0, 0, 0, 0, 0]
            let file = id3TagWithExtendedHeader(3, extended, [id3v23Frame("TIT2", "Title"), id3v23Frame("TPE1", "Artist")])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata.title == "Title")
            #expect(metadata.artist == "Artist")
        }

        @Test("skips a v2.3 extended header that carries a CRC")
        func v23ExtendedHeaderWithCrc() async throws {
            // 크기 10 = 플래그 2 + 패딩 4 + CRC 4. 헤더 전체는 14바이트.
            let extended: [UInt8] = [0, 0, 0, 10, 0x80, 0, 0, 0, 0, 0, 0x12, 0x34, 0x56, 0x78]
            let file = id3TagWithExtendedHeader(3, extended, [id3v23Frame("TIT2", "Title")])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata.title == "Title")
        }

        @Test("skips a v2.4 extended header (size includes the size field itself)")
        func v24ExtendedHeader() async throws {
            // 동기 안전 크기 6 = 크기 칸 4 + 플래그 바이트 수 1 + 플래그 1. 헤더 전체가 6바이트.
            let extended: [UInt8] = [0, 0, 0, 6, 1, 0]
            let file = id3TagWithExtendedHeader(4, extended, [id3v23Frame("TIT2", "Title")])

            let metadata = try #require(try await MetadataConnect.extractFromMp3(MetadataConnect.createBufferReader(file, "mp3")))

            #expect(metadata.title == "Title")
        }
    }
}
