@testable import DJLinkKit
import Foundation
import Testing

// 원본 tests/artwork/extraction.integration.test.ts
//
// Integration tests that verify artwork extraction works with real audio files.
// These tests read actual files from disk to ensure the parsers handle
// real-world file formats correctly.
//
// To run these tests, you need audio files in the test samples directory.
// The tests will skip gracefully if sample files are not present.
//
// 원본과 다름: 원본은 파일이 없으면 시험 본문에서 return해 통과로 센다. 여기서는 같은 조건을 `.enabled(if:)`로 걸어
// 건너뛴 것으로 센다(우리 쪽 AGENTS.md: 조건부 시험은 같은 조건을 건다). 본문의 검사도 원본대로 둔다.
// 원본 `beforeAll`은 샘플 폴더가 없으면 만들고 안내를 찍는다. 리소스 폴더는 빌드 산출물이라 만들지 않는다.

/// 원본의 SAMPLES_DIR(`__dirname/_samples`). 번들된 Fixtures/artwork/_samples를 본다.
private let SAMPLES_DIR: URL? = Bundle.module.resourceURL?.appendingPathComponent("Fixtures/artwork/_samples")

// Helper to check if a file exists
private func fileExists(_ filePath: String) -> Bool {
    FileManager.default.isReadableFile(atPath: filePath)
}

private func samplePath(_ name: String) -> String {
    SAMPLES_DIR?.appendingPathComponent(name).path ?? "_samples/\(name)"
}

// Helper to read file and create reader
private func createReaderFromFile(_ filePath: String) throws -> any ArtworkFileReader {
    let buffer = [UInt8](try Data(contentsOf: URL(fileURLWithPath: filePath)))
    let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
    return createBufferReader(buffer, ext)
}

private let supportedMimeTypes = ["image/jpeg", "image/png", "image/gif"]

@Suite("Artwork Extraction Integration")
struct ArtworkExtractionIntegrationTests {
    @Suite("MP3 with ID3v2")
    struct MP3WithID3v2 {
        static let path = samplePath("sample.mp3")

        @Test("should extract artwork from real MP3 file", .enabled(if: fileExists(MP3WithID3v2.path)))
        func shouldExtractArtworkFromRealMP3File() async throws {
            let samplePath = Self.path
            if !fileExists(samplePath) {
                print("Skipping: \(samplePath) not found")
                return
            }

            let reader = try createReaderFromFile(samplePath)
            let result = try await extractArtwork(reader)

            if let result {
                #expect(result.data.count > 0)
                #expect(supportedMimeTypes.contains(result.mimeType.rawValue))
                print("Extracted \(result.mimeType.rawValue) artwork: \(result.data.count) bytes")
            } else {
                print("No artwork found in sample.mp3")
            }
        }
    }

    @Suite("M4A/AAC")
    struct M4AAAC {
        static let path = samplePath("sample.m4a")

        @Test("should extract artwork from real M4A file", .enabled(if: fileExists(M4AAAC.path)))
        func shouldExtractArtworkFromRealM4AFile() async throws {
            let samplePath = Self.path
            if !fileExists(samplePath) {
                print("Skipping: \(samplePath) not found")
                return
            }

            let reader = try createReaderFromFile(samplePath)
            let result = try await extractArtwork(reader)

            if let result {
                #expect(result.data.count > 0)
                #expect(supportedMimeTypes.contains(result.mimeType.rawValue))
                print("Extracted \(result.mimeType.rawValue) artwork: \(result.data.count) bytes")
            } else {
                print("No artwork found in sample.m4a")
            }
        }
    }

    @Suite("FLAC")
    struct FLAC {
        static let path = samplePath("sample.flac")

        @Test("should extract artwork from real FLAC file", .enabled(if: fileExists(FLAC.path)))
        func shouldExtractArtworkFromRealFLACFile() async throws {
            let samplePath = Self.path
            if !fileExists(samplePath) {
                print("Skipping: \(samplePath) not found")
                return
            }

            let reader = try createReaderFromFile(samplePath)
            let result = try await extractArtwork(reader)

            if let result {
                #expect(result.data.count > 0)
                #expect(supportedMimeTypes.contains(result.mimeType.rawValue))
                if let width = result.width, let height = result.height, width != 0, height != 0 {
                    print("Extracted \(result.mimeType.rawValue) artwork: \(width)x\(height), \(result.data.count) bytes")
                } else {
                    print("Extracted \(result.mimeType.rawValue) artwork: \(result.data.count) bytes")
                }
            } else {
                print("No artwork found in sample.flac")
            }
        }
    }

    @Suite("System music library samples")
    struct SystemMusicLibrarySamples {
        // Test against actual files from the user's music library
        // 원본은 원작자의 개인 음악 폴더 경로·곡 이름을 적어 둔다. 공개 저장소라 견본 경로로 바꿨다(시험 동작은 같다).
        static let musicDir = "/Users/example/Music"
        static let testFiles = [
            "\(musicDir)/Artist A/sample-with-artwork.mp3",
            "\(musicDir)/Music/Media.localized/Music/Artist B/Unknown Album/sample-vocals.mp3",
        ]

        @Test(
            "should handle various real-world MP3 files",
            .enabled(if: SystemMusicLibrarySamples.testFiles.contains(where: fileExists))
        )
        func shouldHandleVariousRealWorldMP3Files() async throws {
            // Find a few MP3 files to test (including one known to have artwork)
            for filePath in Self.testFiles {
                if !fileExists(filePath) {
                    continue
                }

                let reader = try createReaderFromFile(filePath)
                let result = try await extractArtwork(reader)

                let fileName = URL(fileURLWithPath: filePath).lastPathComponent
                if let result {
                    print("✓ \(fileName): \(result.mimeType.rawValue), \(result.data.count) bytes")
                    #expect(result.data.count > 0)
                } else {
                    print("○ \(fileName): no artwork")
                }
            }
        }
    }

    @Suite("Now Playing Test playlist (rekordbox)")
    struct NowPlayingTestPlaylist {
        // Test against the "Now Playing Test" playlist files from rekordbox
        // 원본은 원작자 USB·임시 폴더의 실제 곡 경로를 적어 둔다. 공개 저장소라 견본 경로로 바꿨다(시험 동작은 같다).
        static let testTracks: [(name: String, path: String)] = [
            (name: "Track 1 (Artist 1)", path: "/Volumes/SD/Contents/Artist 1/Album 1/track-1.mp3"),
            (name: "Track 2 (Artist 2)", path: "/Volumes/SD/Contents/Artist 2/Album 2/track-2.mp3"),
            (name: "Track 3 (Artist 3)", path: "/Volumes/SD/Contents/Artist 3/Album 3/track-3.mp3"),
            (name: "Track 4 (Artist 4)", path: "/Users/example/temp/contents/Artist 4/Album 4/track-4.mp3"),
        ]

        @Test(
            "should extract artwork from all Now Playing Test tracks",
            .enabled(if: NowPlayingTestPlaylist.testTracks.contains { fileExists($0.path) })
        )
        func shouldExtractArtworkFromAllNowPlayingTestTracks() async throws {
            var testedCount = 0
            var successCount = 0

            for track in Self.testTracks {
                if !fileExists(track.path) {
                    print("⊘ \(track.name): file not found")
                    continue
                }

                testedCount += 1
                let reader = try createReaderFromFile(track.path)
                let result = try await extractArtwork(reader)

                if let result {
                    successCount += 1
                    print("✓ \(track.name): \(result.mimeType.rawValue), \(result.data.count) bytes")
                    #expect(result.data.count > 0)
                    #expect(supportedMimeTypes.contains(result.mimeType.rawValue))
                } else {
                    print("✗ \(track.name): NO ARTWORK EXTRACTED")
                }
            }

            print("\nResults: \(successCount)/\(testedCount) tracks had artwork extracted")

            // Expect at least some files to be testable (SD card mounted)
            if testedCount > 0 {
                #expect(successCount > 0)
            }
        }
    }
}
