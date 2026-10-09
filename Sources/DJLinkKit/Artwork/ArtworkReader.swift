import Foundation

private struct ArtworkNfsFileReader: ArtworkFileReader {
    let device: Device
    let slot: MediaSlot
    let path: String
    let size: Int
    let `extension`: String
    let source: any ArtworkNFSFileSource

    func read(_ offset: Int, _ length: Int) async throws -> [UInt8] {
        try await source.fetchFileRange(device: device, slot: slot, path: path, offset: offset, length: length)
    }
}

private struct ArtworkBufferReader: ArtworkFileReader {
    let buffer: [UInt8]
    let `extension`: String
    var size: Int { buffer.count }

    func read(_ offset: Int, _ length: Int) async throws -> [UInt8] {
        let end = min(offset + length, buffer.count)
        return buffer.subarray(offset, end)
    }
}

/// Create a FileReader backed by NFS that reads from a device's media slot.
func createNfsFileReader(
    _ device: Device,
    _ slot: MediaSlot,
    _ path: String,
    _ fileSize: Int,
    source: any ArtworkNFSFileSource = NFSArtworkFileSource()
) -> any ArtworkFileReader {
    let fileExtension = path.components(separatedBy: ".").last?.lowercased() ?? ""

    return ArtworkNfsFileReader(
        device: device,
        slot: slot,
        path: path,
        size: fileSize,
        extension: fileExtension,
        source: source
    )
}

/// Create a FileReader backed by NFS, automatically fetching file size.
func createNfsFileReaderWithInfo(
    _ device: Device,
    _ slot: MediaSlot,
    _ path: String,
    source: any ArtworkNFSFileSource = NFSArtworkFileSource()
) async throws -> any ArtworkFileReader {
    let fileInfo = try await source.getFileInfo(device: device, slot: slot, path: path)
    return createNfsFileReader(device, slot, path, fileInfo.size, source: source)
}

/// Create a FileReader from a Buffer (for testing).
func createBufferReader(_ buffer: [UInt8], _ extension: String) -> any ArtworkFileReader {
    ArtworkBufferReader(buffer: buffer, extension: `extension`)
}
