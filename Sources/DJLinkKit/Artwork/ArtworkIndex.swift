import Foundation

private let SUPPORTED_EXTENSIONS: Set<String> = ["mp3", "m4a", "mp4", "aac", "flac", "aiff", "aif"]

public func isArtworkExtractionSupported(_ extension: String) -> Bool {
    SUPPORTED_EXTENSIONS.contains(`extension`.lowercased())
}

public func extractArtwork(_ reader: any ArtworkFileReader) async throws -> ExtractedArtwork? {
    let ext = reader.extension.lowercased()

    switch ext {
    case "mp3":
        return try await extractFromMp3(reader)
    case "m4a", "mp4", "aac":
        return try await extractFromMp4(reader)
    case "flac":
        return try await extractFromFlac(reader)
    case "aiff", "aif":
        return try await extractFromAiff(reader)
    default:
        let mp3Result = try await extractFromMp3(reader)
        if let mp3Result {
            return mp3Result
        }
        return try await extractFromMp4(reader)
    }
}

public func extractArtworkFromDevice(
    _ device: Device,
    _ slot: MediaSlot,
    _ filePath: String,
    _ logger: any Logger = noopLogger,
    source: any ArtworkNFSFileSource = NFSArtworkFileSource()
) async throws -> ExtractedArtwork? {
    logger.debug(
        "[artwork-nfs] getFileInfo: device=\(device.ip.address), slot=\(slot.rawValue), path=\(filePath)"
    )
    let fileInfo = try await source.getFileInfo(device: device, slot: slot, path: filePath)
    logger.debug("[artwork-nfs] File found: \(fileInfo.size) bytes")
    let reader = createNfsFileReader(device, slot, filePath, fileInfo.size, source: source)
    let result = try await extractArtwork(reader)
    logger.debug(
        "[artwork-nfs] extractArtwork result: \(result.map { "\($0.mimeType.rawValue) (\($0.data.count)b)" } ?? "null")"
    )
    return result
}
