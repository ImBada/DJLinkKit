import DJLinkKit
import Foundation
import Testing

// 원본 metadata-connect/test/extract.test.ts

@Suite("metadata-connect")
struct MetadataConnectExtractTests {
    @Suite("isExtensionSupported")
    struct IsExtensionSupported {
        @Test("returns true for supported extensions")
        func returnsTrueForSupportedExtensions() {
            #expect(MetadataConnect.isExtensionSupported("mp3") == true)
            #expect(MetadataConnect.isExtensionSupported("m4a") == true)
            #expect(MetadataConnect.isExtensionSupported("mp4") == true)
            #expect(MetadataConnect.isExtensionSupported("aac") == true)
            #expect(MetadataConnect.isExtensionSupported("flac") == true)
            #expect(MetadataConnect.isExtensionSupported("aiff") == true)
            #expect(MetadataConnect.isExtensionSupported("aif") == true)
        }

        @Test("returns false for unsupported extensions")
        func returnsFalseForUnsupportedExtensions() {
            #expect(MetadataConnect.isExtensionSupported("wav") == false)
            #expect(MetadataConnect.isExtensionSupported("ogg") == false)
            #expect(MetadataConnect.isExtensionSupported("txt") == false)
        }

        @Test("handles case insensitivity")
        func handlesCaseInsensitivity() {
            #expect(MetadataConnect.isExtensionSupported("MP3") == true)
            #expect(MetadataConnect.isExtensionSupported("FLAC") == true)
            #expect(MetadataConnect.isExtensionSupported("M4A") == true)
        }
    }

    @Suite("getSupportedExtensions")
    struct GetSupportedExtensions {
        @Test("returns all supported extensions")
        func returnsAllSupportedExtensions() {
            let extensions = MetadataConnect.getSupportedExtensions()
            #expect(extensions.contains("mp3"))
            #expect(extensions.contains("m4a"))
            #expect(extensions.contains("flac"))
            #expect(extensions.contains("aiff"))
            #expect(extensions.count > 0)
        }
    }

    @Suite("getParserForExtension")
    struct GetParserForExtension {
        @Test("returns a parser for supported extensions")
        func returnsAParserForSupportedExtensions() {
            // 원본의 toBeTypeOf('function')은 값이 있는지(nil이 아닌지)로 옮긴다. 원본과 다름: Swift엔 typeof가 없다.
            #expect(MetadataConnect.getParserForExtension("mp3") != nil)
            #expect(MetadataConnect.getParserForExtension("m4a") != nil)
            #expect(MetadataConnect.getParserForExtension("flac") != nil)
        }

        @Test("returns null for unsupported extensions")
        func returnsNullForUnsupportedExtensions() {
            #expect(MetadataConnect.getParserForExtension("wav") == nil)
            #expect(MetadataConnect.getParserForExtension("ogg") == nil)
        }
    }

    @Suite("createBufferReader")
    struct CreateBufferReader {
        @Test("creates a reader with correct properties")
        func createsAReaderWithCorrectProperties() {
            let buffer = [UInt8]("test data", encoding: .utf8)
            let reader = MetadataConnect.createBufferReader(buffer, "mp3")

            #expect(reader.size == buffer.count)
            #expect(reader.extension == "mp3")
        }

        @Test("reads data at correct offset")
        func readsDataAtCorrectOffset() async throws {
            let buffer = [UInt8]("Hello, World!", encoding: .utf8)
            let reader = MetadataConnect.createBufferReader(buffer, "mp3")

            let data = try await reader.read(0, 5)
            #expect(data.toString() == "Hello")

            let data2 = try await reader.read(7, 5)
            #expect(data2.toString() == "World")
        }

        @Test("handles reading past end of buffer")
        func handlesReadingPastEndOfBuffer() async throws {
            let buffer = [UInt8]("Short", encoding: .utf8)
            let reader = MetadataConnect.createBufferReader(buffer, "mp3")

            let data = try await reader.read(0, 100)
            #expect(data.count == 5)
            #expect(data.toString() == "Short")
        }
    }

    @Suite("extractMetadata")
    struct ExtractMetadata {
        @Test("returns null for empty buffer")
        func returnsNullForEmptyBuffer() async {
            let reader = MetadataConnect.createBufferReader([], "mp3")
            let metadata = await MetadataConnect.extractMetadata(reader)
            #expect(metadata == nil)
        }

        @Test("returns null for unsupported format")
        func returnsNullForUnsupportedFormat() async {
            let reader = MetadataConnect.createBufferReader([UInt8]("test", encoding: .utf8), "wav")
            let metadata = await MetadataConnect.extractMetadata(reader)
            #expect(metadata == nil)
        }

        @Test("returns null for invalid MP3 data")
        func returnsNullForInvalidMP3Data() async {
            let reader = MetadataConnect.createBufferReader([UInt8]("not an mp3 file", encoding: .utf8), "mp3")
            let metadata = await MetadataConnect.extractMetadata(reader)
            #expect(metadata == nil)
        }

        @Test("returns null for invalid FLAC data")
        func returnsNullForInvalidFLACData() async {
            let reader = MetadataConnect.createBufferReader([UInt8]("not a flac file", encoding: .utf8), "flac")
            let metadata = await MetadataConnect.extractMetadata(reader)
            #expect(metadata == nil)
        }

        @Test("returns null for invalid M4A data")
        func returnsNullForInvalidM4AData() async {
            let reader = MetadataConnect.createBufferReader([UInt8]("not an m4a file", encoding: .utf8), "m4a")
            let metadata = await MetadataConnect.extractMetadata(reader)
            #expect(metadata == nil)
        }
    }
}

@Suite("ID3v2 parsing")
struct MetadataConnectID3v2ParsingTests {
    @Test("parses valid ID3v2.3 header")
    func parsesValidID3v23Header() async {
        // Create a minimal valid ID3v2.3 tag
        let id3Header: [UInt8] = [
            0x49, 0x44, 0x33, // "ID3"
            0x03, 0x00, // Version 2.3
            0x00, // Flags
            0x00, 0x00, 0x00, 0x00, // Size (syncsafe, 0 bytes)
        ]

        let reader = MetadataConnect.createBufferReader(id3Header, "mp3")
        let metadata = await MetadataConnect.extractMetadata(reader)
        // Empty tag should return null (no metadata found)
        #expect(metadata == nil)
    }
}
