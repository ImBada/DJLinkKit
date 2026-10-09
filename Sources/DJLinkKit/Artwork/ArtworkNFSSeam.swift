// 원본 artwork/reader.ts·artwork/index.ts·metadata.ts가 `src/nfs`(3단계)에서 가져다 쓰는 것의 주입점(seam).
// 원본 시그니처:
//   fetchFileRange({device, slot, path, offset, length, span?}): Promise<Buffer>
//   getFileInfo({device, slot, path, span?}): Promise<FileInfo>   // 여기서는 size만 쓴다
//   type NfsMediaSlot = MediaSlot.USB | MediaSlot.SD | MediaSlot.RB
// NFS를 옮기는 쪽이 이 프로토콜을 따르게 하거나, 이 파일을 그쪽 형으로 바꾼다.

/// `getFileInfo`가 돌려주는 `FileInfo` 중 artwork·metadata가 읽는 칸.
public struct ArtworkNFSFileInfo: Equatable, Sendable {
    public var size: Int

    public init(size: Int) {
        self.size = size
    }
}

/// `src/nfs`의 `fetchFileRange`·`getFileInfo`. 슬롯은 `NfsMediaSlot`(USB·SD·RB)이다.
public protocol ArtworkNFSFileSource: Sendable {
    /// Fetch a range of bytes from a file on a device's NFS server.
    func fetchFileRange(device: Device, slot: MediaSlot, path: String, offset: Int, length: Int) async throws -> [UInt8]

    /// Get file info (size, handle) without fetching the file content.
    func getFileInfo(device: Device, slot: MediaSlot, path: String) async throws -> ArtworkNFSFileInfo
}

/// 실제 NFS(`NFS/NFSIndex.swift`의 `fetchFileRange`·`getFileInfo`)로 읽는 기본 소스.
public struct NFSArtworkFileSource: ArtworkNFSFileSource {
    public init() {}

    public func fetchFileRange(device: Device, slot: MediaSlot, path: String, offset: Int, length: Int) async throws -> [UInt8] {
        try await DJLinkKit.fetchFileRange(device: device, slot: slot, path: path, offset: offset, length: length)
    }

    public func getFileInfo(device: Device, slot: MediaSlot, path: String) async throws -> ArtworkNFSFileInfo {
        ArtworkNFSFileInfo(size: try await DJLinkKit.getFileInfo(device: device, slot: slot, path: path).size)
    }
}
