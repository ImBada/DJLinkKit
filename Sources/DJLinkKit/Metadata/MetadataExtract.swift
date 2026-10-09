import Foundation

extension MetadataConnect {
    /// Map of file extensions to their metadata parsers
    /// (원본은 객체 키 순서가 곧 `getSupportedExtensions()`의 순서라 배열로 순서를 지킨다.)
    private static let PARSER_MAP: [(extension: String, parser: MetadataParser)] = [
        // MP3
        ("mp3", { try await extractFromMp3($0) }),

        // MP4/M4A/AAC
        ("m4a", { try await extractFromMp4($0) }),
        ("mp4", { try await extractFromMp4($0) }),
        ("m4p", { try await extractFromMp4($0) }),
        ("m4b", { try await extractFromMp4($0) }),
        ("aac", { try await extractFromMp4($0) }),

        // FLAC
        ("flac", { try await extractFromFlac($0) }),

        // AIFF
        ("aiff", { try await extractFromAiff($0) }),
        ("aif", { try await extractFromAiff($0) }),
        ("aifc", { try await extractFromAiff($0) }),
    ]

    /// Get the appropriate parser for a file extension
    public static func getParserForExtension(_ extension: String) -> MetadataParser? {
        var normalizedExt = `extension`.lowercased()
        // .replace(/^\./, '')
        if normalizedExt.hasPrefix(".") { normalizedExt.removeFirst() }
        return PARSER_MAP.first { $0.extension == normalizedExt }?.parser
    }

    /// Get list of supported file extensions
    public static func getSupportedExtensions() -> [String] {
        PARSER_MAP.map(\.extension)
    }

    /// Check if a file extension is supported
    public static func isExtensionSupported(_ extension: String) -> Bool {
        getParserForExtension(`extension`) != nil
    }

    /// Options for extractMetadata
    public struct ExtractMetadataOptions: Sendable {
        /// Optional logger instance. If omitted, logging is silently disabled.
        public var logger: (any Logger)?

        public init(logger: (any Logger)? = nil) {
            self.logger = logger
        }
    }

    /// Extract metadata from an audio file using the appropriate parser
    ///
    /// - Parameters:
    ///   - reader: FileReader interface for reading file data
    ///   - options: Optional configuration including logger
    /// - Returns: Extracted metadata, or nil if extraction fails or format is unsupported
    public static func extractMetadata(
        _ reader: any FileReader,
        _ options: ExtractMetadataOptions? = nil
    ) async -> ExtractedMetadata? {
        let logger = options?.logger ?? noopLogger
        guard let parser = getParserForExtension(reader.extension) else {
            logger.debug("No parser found for extension: %s", reader.extension)
            return nil
        }

        do {
            logger.debug("Extracting metadata from %s file (%d bytes)", reader.extension, reader.size)
            let result = try await parser(reader)
            if let result {
                logger.debug(
                    "Extracted metadata: title=%s, artist=%s", result.title ?? "(none)", result.artist ?? "(none)"
                )
            } else {
                logger.debug("Parser returned null for %s file", reader.extension)
            }
            return result
        } catch {
            logger.warn("Failed to extract metadata from %s file: %s", reader.extension, error)
            return nil
        }
    }
}
