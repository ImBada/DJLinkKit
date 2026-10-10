@testable import DJLinkKit
import Testing

// 원본 tests/artwork/parsers.spec.ts

@Suite("Artwork Extraction")
struct ArtworkParsersTests {
    @Suite("ID3 Parser (MP3)")
    struct ID3Parser {
        @Test("should extract JPEG artwork from ID3v2.4 APIC frame")
        func shouldExtractJPEGArtworkFromID3v24APICFrame() async throws {
            let mp3Data = createMp3WithArtwork(TINY_JPEG)
            let reader = createBufferReader(mp3Data, "mp3")
            let result = try await extractFromMp3(reader)

            let artwork = try #require(result)
            #expect(artwork.mimeType.rawValue == "image/jpeg")
            #expect(artwork.pictureType == PictureType.frontCover)
            #expect(artwork.data.bytesEqual(TINY_JPEG))
        }

        @Test("should extract PNG artwork")
        func shouldExtractPNGArtwork() async throws {
            let mp3Data = createMp3WithArtwork(TINY_PNG)
            let reader = createBufferReader(mp3Data, "mp3")
            let result = try await extractFromMp3(reader)

            let artwork = try #require(result)
            #expect(artwork.mimeType.rawValue == "image/png")
        }

        @Test("should return null for non-ID3 data")
        func shouldReturnNullForNonID3Data() async throws {
            let reader = createBufferReader([UInt8]("not an mp3", encoding: .utf8), "mp3")
            let result = try await extractFromMp3(reader)
            #expect(result == nil)
        }
    }

    @Suite("MP4 Parser")
    struct MP4Parser {
        @Test("should extract artwork from MP4/M4A covr atom")
        func shouldExtractArtworkFromMP4M4ACovrAtom() async throws {
            let mp4Data = createMp4WithArtwork(TINY_JPEG)
            let reader = createBufferReader(mp4Data, "m4a")
            let result = try await extractFromMp4(reader)

            let artwork = try #require(result)
            #expect(artwork.mimeType.rawValue == "image/jpeg")
            #expect(artwork.data.bytesEqual(TINY_JPEG))
        }

        @Test("should return null for non-MP4 data")
        func shouldReturnNullForNonMP4Data() async throws {
            let reader = createBufferReader([UInt8]("not an mp4", encoding: .utf8), "m4a")
            let result = try await extractFromMp4(reader)
            #expect(result == nil)
        }
    }

    @Suite("FLAC Parser")
    struct FLACParser {
        @Test("should extract artwork from FLAC PICTURE metadata block")
        func shouldExtractArtworkFromFLACPICTUREMetadataBlock() async throws {
            let flacData = createFlacWithArtwork(TINY_JPEG)
            let reader = createBufferReader(flacData, "flac")
            let result = try await extractFromFlac(reader)

            let artwork = try #require(result)
            #expect(artwork.mimeType.rawValue == "image/jpeg")
            #expect(artwork.width == 1)
            #expect(artwork.height == 1)
            #expect(artwork.data.bytesEqual(TINY_JPEG))
        }

        @Test("should return null for non-FLAC data")
        func shouldReturnNullForNonFLACData() async throws {
            let reader = createBufferReader([UInt8]("not a flac", encoding: .utf8), "flac")
            let result = try await extractFromFlac(reader)
            #expect(result == nil)
        }
    }

    @Suite("AIFF Parser")
    struct AIFFParser {
        @Test("should extract artwork from AIFF ID3 chunk")
        func shouldExtractArtworkFromAIFFID3Chunk() async throws {
            let aiffData = createAiffWithArtwork(TINY_JPEG)
            let reader = createBufferReader(aiffData, "aiff")
            let result = try await extractFromAiff(reader)

            let artwork = try #require(result)
            #expect(artwork.mimeType.rawValue == "image/jpeg")
        }

        @Test("should return null for non-AIFF data")
        func shouldReturnNullForNonAIFFData() async throws {
            let reader = createBufferReader([UInt8]("not an aiff", encoding: .utf8), "aiff")
            let result = try await extractFromAiff(reader)
            #expect(result == nil)
        }
    }

    @Suite("extractArtwork (auto-detection)")
    struct ExtractArtworkAutoDetection {
        @Test("should detect MP3 from extension")
        func shouldDetectMP3FromExtension() async throws {
            let mp3Data = createMp3WithArtwork(TINY_JPEG)
            let reader = createBufferReader(mp3Data, "mp3")
            let result = try await extractArtwork(reader)
            #expect(result != nil)
        }

        @Test("should detect M4A from extension")
        func shouldDetectM4AFromExtension() async throws {
            let mp4Data = createMp4WithArtwork(TINY_JPEG)
            let reader = createBufferReader(mp4Data, "m4a")
            let result = try await extractArtwork(reader)
            #expect(result != nil)
        }

        @Test("should detect FLAC from extension")
        func shouldDetectFLACFromExtension() async throws {
            let flacData = createFlacWithArtwork(TINY_JPEG)
            let reader = createBufferReader(flacData, "flac")
            let result = try await extractArtwork(reader)
            #expect(result != nil)
        }

        @Test("should detect AIFF from extension")
        func shouldDetectAIFFFromExtension() async throws {
            let aiffData = createAiffWithArtwork(TINY_JPEG)
            let reader = createBufferReader(aiffData, "aiff")
            let result = try await extractArtwork(reader)
            #expect(result != nil)
        }
    }
}
