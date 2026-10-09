import Foundation

// 원본 alphatheta-connect/src/metadata.ts

public typealias ExtractedMetadata = MetadataConnect.ExtractedMetadata

/// Extract full metadata from an audio file using a FileReader.
///
/// This is the low-level API that works with any FileReader implementation.
/// For extracting from a Pro DJ Link device, use extractMetadataFromDevice.
///
/// - Parameter reader: FileReader interface for reading file data
/// - Returns: Extracted metadata, or nil if extraction fails
public func extractFullMetadata(_ reader: any MetadataConnect.FileReader) async -> ExtractedMetadata? {
    await MetadataConnect.extractMetadata(reader)
}

/// Check if metadata extraction is supported for a file extension.
///
/// - Parameter extension: File extension (with or without leading dot)
/// - Returns: true if the extension is supported
public func isMetadataExtractionSupported(_ extension: String) -> Bool {
    MetadataConnect.isExtensionSupported(`extension`)
}

/// Extract full metadata from an audio file on a Pro DJ Link device.
///
/// This function reads only the necessary bytes from the file header,
/// avoiding the need to transfer entire audio files over the network.
///
/// - Parameters:
///   - device: The Pro DJ Link device
///   - slot: The media slot containing the file (USB, SD, etc.)
///   - filePath: The file path on the device
///   - source: NFS 읽기를 맡는 주입점(원본은 `src/nfs`의 `getFileInfo`·`fetchFileRange`를 직접 부른다)
/// - Returns: Extracted metadata, or nil if extraction fails
public func extractMetadataFromDevice(
    _ device: Device,
    _ slot: MediaSlot,
    _ filePath: String,
    source: any ArtworkNFSFileSource = NFSArtworkFileSource()
) async -> ExtractedMetadata? {
    // Get file extension and check if supported
    let fileExtension = filePath.components(separatedBy: ".").last?.lowercased() ?? ""
    if !MetadataConnect.isExtensionSupported(fileExtension) {
        return nil
    }

    do {
        let fileInfo = try await source.getFileInfo(device: device, slot: slot, path: filePath)
        if fileInfo.size == 0 {
            return nil
        }

        let reader = createNfsFileReader(device, slot, filePath, fileInfo.size, source: source)
        return await MetadataConnect.extractMetadata(reader)
    } catch {
        // Return null on any error (file not found, network issues, etc.)
        return nil
    }
}
