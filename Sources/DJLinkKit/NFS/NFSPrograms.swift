public let STANDARD_PORTMAP_PORT = 111
public let REKORDBOX_PORTMAP_PORT = 50111
private let READ_SIZE = 8192
public struct NFSProgram: Sendable {
    public var id: Int
    public var version: Int
    public init(id: Int, version: Int) {
        self.id = id
        self.version = version
    }
}
public struct NFSExport: Equatable, Sendable {
    public var filesystem: String
    public var groups: [String]
    public init(filesystem: String, groups: [String]) {
        self.filesystem = filesystem
        self.groups = groups
    }
}
public enum NFSFileType: String, Sendable { case null, regular, directory, block, char, link }
public struct FileInfo: Equatable, Sendable {
    public var handle: [UInt8]
    public var name: String
    public var size: Int
    public var type: NFSFileType
    public init(handle: [UInt8], name: String, size: Int, type: NFSFileType) {
        self.handle = handle
        self.name = name
        self.size = size
        self.type = type
    }
}
@DJLinkActor public func makeProgramClient(
    _ conn: RpcConnection, _ program: NFSProgram, _ portmapPort: Int = STANDARD_PORTMAP_PORT
) async throws -> RpcProgram {
    let data = try await conn.call(
        port: portmapPort, program: portmap.Program, version: portmap.Version,
        procedure: portmap.Procedure.getPort.rawValue,
        data: portmap.GetPort(program: program.id, version: program.version, protocol: 17, port: 0).toXDR())
    let port = try data.readInt32BE()
    return RpcProgram(conn, program.id, program.version, port)
}
@DJLinkActor public func getExports(_ conn: RpcProgram, _ span: TelemetrySpan? = nil) async throws -> [NFSExport] {
    let tx = span?.startChild(SpanContext(op: "getExports"))
    let data = try await conn.call(procedure: mount.Procedure.export.rawValue, data: [])
    guard let entry = try mount.ExportListResponse.fromXDR(data).next else { return [] }
    let exports = try flattenLinkedList(entry, next: { $0.next }).map { entry in
        // 원본도 groups가 없는 export를 처리하지 못한다. 이식에서는 trap 대신 오류를 던진다.
        guard let groups = entry.groups else {
            throw DJLinkError("Cannot read properties of undefined (reading 'next')")
        }
        return NFSExport(filesystem: entry.filesystem, groups: flattenLinkedList(groups, next: { $0.next }).map(\.name))
    }
    tx?.finish()
    return exports
}
@DJLinkActor public func mountFilesystem(_ conn: RpcProgram, _ export: NFSExport, _ span: TelemetrySpan? = nil)
    async throws -> [UInt8]
{
    let tx = span?.startChild(SpanContext(op: "mountFilesystem"))
    let resp = try await conn.call(
        procedure: mount.Procedure.mount.rawValue, data: mount.MountRequest(filesystem: export.filesystem).toXDR())
    guard case let .success(handle) = try mount.FHStatus.fromXDR(resp) else {
        throw DJLinkError("Failed to mount filesystem")
    }
    tx?.finish()
    return handle
}
@DJLinkActor public func lookupFile(
    _ conn: RpcProgram, _ handle: [UInt8], _ filename: String, _ span: TelemetrySpan? = nil
) async throws -> FileInfo {
    let tx = span?.startChild(SpanContext(op: "lookupFile", description: filename))
    let resp = try await conn.call(
        procedure: nfs.Procedure.lookup.rawValue, data: nfs.DirectoryOpArgs(handle: handle, filename: filename).toXDR())
    guard case let .success(body) = try nfs.DirectoryOpResponse.fromXDR(resp) else {
        throw DJLinkError("Failed file lookup of \(filename)")
    }
    let info = FileInfo(
        handle: body.handle, name: filename, size: body.attributes.size,
        type: NFSFileType(rawValue: body.attributes.type.name)!)
    tx?.finish()
    return info
}
@DJLinkActor public func lookupPath(
    _ conn: RpcProgram, _ rootHandle: [UInt8], _ filepath: String, _ span: TelemetrySpan? = nil
) async throws -> FileInfo {
    let tx = span?.startChild(SpanContext(op: "lookupPath", description: filepath))
    let path = filepath.hasPrefix("/") ? String(filepath.dropFirst()) : filepath
    var handle = rootHandle
    var info: FileInfo?
    for filename in path.split(separator: "/", omittingEmptySubsequences: false) {
        let fileInfo = try await lookupFile(conn, handle, String(filename), tx)
        info = fileInfo
        handle = fileInfo.handle
    }
    tx?.finish()
    return info!
}
@DJLinkActor public func fetchFile(
    _ conn: RpcProgram, _ file: FileInfo, _ onProgress: (@DJLinkActor (FetchProgress) -> Void)? = nil,
    _ span: TelemetrySpan? = nil, _ readSize: Int? = nil
) async throws -> [UInt8] {
    let readSize = readSize == nil || readSize == 0 ? READ_SIZE : readSize!
    guard readSize <= 8192 else { throw DJLinkError("Maximum read size for NFS is 8192. You specified: \(readSize)") }
    var data = [UInt8].alloc(file.size)
    var bytesRead = 0
    let tx = span?.startChild(SpanContext(op: "download", description: file.name))
    while bytesRead < file.size {
        let resp = try await conn.call(
            procedure: nfs.Procedure.read.rawValue,
            data: nfs.ReadArgs(handle: file.handle, offset: bytesRead, count: readSize, totalCount: 0).toXDR())
        guard case let .success(body) = try nfs.ReadResponse.fromXDR(resp) else {
            throw DJLinkError("Failed to read file at offset \(bytesRead) / \(file.size)")
        }
        guard body.data.count <= data.count - bytesRead else {
            throw BufferRangeError("offset is out of bounds")
        }
        data.set(body.data, bytesRead)
        bytesRead += body.data.count
        onProgress?(FetchProgress(read: bytesRead, total: file.size))
    }
    tx?.finish()
    return data
}
@DJLinkActor public func fetchFileRange(
    _ conn: RpcProgram, _ file: FileInfo, _ offset: Int, _ length: Int, _ span: TelemetrySpan? = nil
) async throws -> [UInt8] {
    var data = [UInt8].alloc(length)
    var bytesRead = 0
    let tx = span?.startChild(SpanContext(op: "downloadRange", description: file.name))
    while bytesRead < length {
        let resp = try await conn.call(
            procedure: nfs.Procedure.read.rawValue,
            data: nfs.ReadArgs(
                handle: file.handle, offset: offset + bytesRead, count: min(READ_SIZE, length - bytesRead),
                totalCount: 0
            ).toXDR())
        guard case let .success(body) = try nfs.ReadResponse.fromXDR(resp) else {
            throw DJLinkError("Failed to read file at offset \(offset + bytesRead)")
        }
        if body.data.isEmpty { break }
        guard body.data.count <= data.count - bytesRead else {
            throw BufferRangeError("offset is out of bounds")
        }
        data.set(body.data, bytesRead)
        bytesRead += body.data.count
    }
    tx?.finish()
    return bytesRead < length ? data.subarray(0, bytesRead) : data
}
