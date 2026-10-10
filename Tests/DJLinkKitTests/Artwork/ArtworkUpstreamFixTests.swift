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

/// APIC 프레임(v2.3): 인코딩 바이트, MIME(latin1)+0, 그림 종류, 설명(인코딩대로)+끝 표시, 이미지.
private func apicFrame(
    encodingByte: UInt8,
    description: [UInt8],
    terminator: [UInt8],
    image: [UInt8],
    syncsafeSize: Bool = false
) -> [UInt8] {
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
    if syncsafeSize {
        header[4] = UInt8((body.count >> 21) & 0x7f)
        header[5] = UInt8((body.count >> 14) & 0x7f)
        header[6] = UInt8((body.count >> 7) & 0x7f)
        header[7] = UInt8(body.count & 0x7f)
    } else {
        header.writeUInt32BE(body.count, 4)
    }
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

    @Suite("APIC 설명 문자열의 BOM")
    struct ApicBom {
        // 원본 alphatheta-connect/src/artwork/parsers/id3.ts:80 — BOM을 인코딩 바이트 바로 뒤(MIME 문자열 자리)에서 찾았다.
        // BOM은 설명 문자열 앞에 있다. 설명은 읽은 뒤 버려지고 끝 표시 찾기는 바이트 순서와 상관없어서,
        // 결과가 달라지는 입력은 없다. 아래 시험은 고치기 전후 모두 통과하는 확인용이다.
        @Test("reads the picture after a UTF-16 description with a little-endian BOM")
        func littleEndianBom() async throws {
            let description: [UInt8] = [0xff, 0xfe, 0x43, 0x00, 0x6f, 0x00, 0x76, 0x00]
            let file = id3Tag(3, [apicFrame(encodingByte: 1, description: description, terminator: [0, 0], image: TINY_JPEG)])

            let result = try await extractFromMp3(createBufferReader(file, "mp3"))

            #expect(try #require(result).data.bytesEqual(TINY_JPEG))
        }

        @Test("reads the picture after a UTF-16 description with a big-endian BOM")
        func bigEndianBom() async throws {
            let description: [UInt8] = [0xfe, 0xff, 0x00, 0x43, 0x00, 0x6f, 0x00, 0x76]
            let file = id3Tag(3, [apicFrame(encodingByte: 1, description: description, terminator: [0, 0], image: TINY_JPEG)])

            let result = try await extractFromMp3(createBufferReader(file, "mp3"))

            #expect(try #require(result).data.bytesEqual(TINY_JPEG))
        }
    }

    @Suite("ID3 확장 헤더")
    struct ExtendedHeader {
        // 원본 alphatheta-connect/src/artwork/parsers/id3.ts:128 — v2.3의 확장 헤더 크기는 크기 칸 4바이트를 뺀 값인데
        // 4바이트를 더하지 않아 프레임이 4바이트 앞에서 읽히기 시작했다.
        @Test("skips a v2.3 extended header (size excludes the size field itself)")
        func v23ExtendedHeader() async throws {
            let extended: [UInt8] = [0, 0, 0, 6, 0, 0, 0, 0, 0, 0]
            let frame = apicFrame(encodingByte: 0, description: [], terminator: [0], image: TINY_JPEG)
            let file = id3TagWithExtendedHeader(3, extended, [frame])

            let result = try await extractFromMp3(createBufferReader(file, "mp3"))

            #expect(try #require(result).data.bytesEqual(TINY_JPEG))
        }

        @Test("skips a v2.3 extended header that carries a CRC")
        func v23ExtendedHeaderWithCrc() async throws {
            let extended: [UInt8] = [0, 0, 0, 10, 0x80, 0, 0, 0, 0, 0, 0x12, 0x34, 0x56, 0x78]
            let frame = apicFrame(encodingByte: 0, description: [], terminator: [0], image: TINY_JPEG)
            let file = id3TagWithExtendedHeader(3, extended, [frame])

            let result = try await extractFromMp3(createBufferReader(file, "mp3"))

            #expect(try #require(result).data.bytesEqual(TINY_JPEG))
        }

        @Test("skips a v2.4 extended header (size includes the size field itself)")
        func v24ExtendedHeader() async throws {
            let extended: [UInt8] = [0, 0, 0, 6, 1, 0]
            let frame = apicFrame(encodingByte: 0, description: [], terminator: [0], image: TINY_JPEG, syncsafeSize: true)
            let file = id3TagWithExtendedHeader(4, extended, [frame])

            let result = try await extractFromMp3(createBufferReader(file, "mp3"))

            #expect(try #require(result).data.bytesEqual(TINY_JPEG))
        }
    }
}
