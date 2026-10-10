import Foundation

public typealias NfsMediaSlot = MediaSlot
public struct FetchProgress: Equatable, Sendable {
    public var read: Int
    public var total: Int
    public init(read: Int, total: Int) {
        self.read = read
        self.total = total
    }
}
public struct NFSPath: Equatable, Sendable {
    // RB 슬롯의 상대 경로는 원본에서도 undefined mountPath를 만든다.
    public var mountPath: String?
    public var nfsPath: String
    public init(mountPath: String?, nfsPath: String) {
        self.mountPath = mountPath
        self.nfsPath = nfsPath
    }
}
public func parseWindowsPath(_ filePath: String) -> NFSPath? {
    let expression = try! NSRegularExpression(pattern: #"^([A-Za-z]):[/\\](.*)$"#)
    let range = NSRange(filePath.startIndex..., in: filePath)
    guard let match = expression.firstMatch(in: filePath, range: range),
        let driveRange = Range(match.range(at: 1), in: filePath),
        let pathRange = Range(match.range(at: 2), in: filePath)
    else { return nil }
    return NFSPath(
        mountPath: "/\(filePath[driveRange].uppercased())/",
        nfsPath: String(filePath[pathRange]).replacingOccurrences(of: "\\", with: "/"))
}
public func resolveNfsPath(_ slot: NfsMediaSlot, _ filePath: String) -> NFSPath {
    if slot == .rb {
        if let parsed = parseWindowsPath(filePath) { return parsed }
        if filePath.hasPrefix("/") { return NFSPath(mountPath: "/", nfsPath: String(filePath.dropFirst())) }
    }
    return NFSPath(mountPath: slot == .usb ? "/C/" : slot == .sd ? "/B/" : nil, nfsPath: filePath)
}
public func getPortmapPort(_ device: Device) -> Int {
    device.type == .rekordbox ? REKORDBOX_PORTMAP_PORT : STANDARD_PORTMAP_PORT
}
@DJLinkActor private struct ClientSet {
    let conn: RpcConnection
    let mountClient: RpcProgram
    let nfsClient: RpcProgram
}
@DJLinkActor private var retryConfig = RetryConfig()
@DJLinkActor private var clientsCache: [String: ClientSet] = [:]
@DJLinkActor private var rootHandleCache: [String: [String: [UInt8]]] = [:]
@DJLinkActor private var nfsSocketFactory: any SocketFactory = LiveSocketFactory.shared
@DJLinkActor private var nfsClock: any DJLinkClock = SystemClock.shared
/// 원본 전역 모듈 상태를 유지하면서 시험이 소켓·시간을 바꿔 넣는 창구.
@DJLinkActor public func configureNFSDependencies(socketFactory: any SocketFactory, clock: any DJLinkClock) {
    nfsSocketFactory = socketFactory
    nfsClock = clock
}
/// CLI 안전을 위한 추가(기본값 nil은 원본 동작). NFS 요청을 만들기 전에 경로를 검사한다.
/// 던지면 소켓을 만들거나 요청을 보내기 전에 멈춘다. `fetchFile`·`fetchFileRange`·`getFileInfo`가 모두 거친다.
@DJLinkActor private var nfsPathGuard:
    (@DJLinkActor (_ device: Device, _ slot: NfsMediaSlot, _ path: String) throws -> Void)?
@DJLinkActor public func configureNFSPathGuard(
    _ guardPath: (@DJLinkActor (_ device: Device, _ slot: NfsMediaSlot, _ path: String) throws -> Void)?
) {
    nfsPathGuard = guardPath
}
/// CLI 안전을 위한 추가(기본값은 원본 동작: 부르지 않으면 연결을 그대로 둔다).
/// 캐시에 있는 모든 NFS 클라이언트(장치마다 따로 연 RPC 소켓)를 닫고 캐시를 비운다. 닫기 오류는 무시한다.
@DJLinkActor public func closeAllNFSClients() async {
    let clients = Array(clientsCache.values)
    clientsCache.removeAll()
    rootHandleCache.removeAll()
    for client in clients {
        client.conn.connected = false
        try? await client.conn.disconnect()
    }
}
@DJLinkActor private func getClients(_ device: Device) async throws -> ClientSet {
    let address = device.ip.address
    if let cached = clientsCache[address], cached.conn.connected { return cached }
    clientsCache.removeValue(forKey: address)
    let conn = try RpcConnection(
        address: address, retryConfig: retryConfig, socketFactory: nfsSocketFactory, clock: nfsClock)
    let mountClient = try await makeProgramClient(
        conn, NFSProgram(id: mount.Program, version: mount.Version), getPortmapPort(device))
    let nfsClient = try await makeProgramClient(
        conn, NFSProgram(id: nfs.Program, version: nfs.Version), getPortmapPort(device))
    let set = ClientSet(conn: conn, mountClient: mountClient, nfsClient: nfsClient)
    clientsCache[address] = set
    return set
}
@DJLinkActor private func getRootHandle(
    device: Device, mountPath: String?, mountClient: RpcProgram, span: TelemetrySpan?
) async throws -> [UInt8]? {
    let tx = span?.startChild(SpanContext(op: "getRootHandle"))
    let address = device.ip.address
    if let mountPath, let cached = rootHandleCache[address]?[mountPath] { return cached }
    let exports = try await getExports(mountClient, tx)
    guard let target = exports.first(where: { $0.filesystem == mountPath }) else { return nil }
    let handle = try await mountFilesystem(mountClient, target, tx)
    rootHandleCache[address, default: [:]][target.filesystem] = handle
    tx?.finish()
    return handle
}
private func badRoothandleError(_ slot: MediaSlot, _ deviceId: DeviceID) -> DJLinkError {
    DJLinkError("The slot (\(slot.rawValue)) is not exported on Device \(deviceId)")
}
@DJLinkActor private func locateFile(device: Device, slot: NfsMediaSlot, path: String, span: TelemetrySpan) async throws
    -> (FileInfo, RpcProgram)
{
    try nfsPathGuard?(device, slot, path)
    let resolved = resolveNfsPath(slot, path)
    let clients = try await getClients(device)
    guard
        let rootHandle = try await getRootHandle(
            device: device, mountPath: resolved.mountPath, mountClient: clients.mountClient, span: span)
    else { throw badRoothandleError(slot, device.id) }
    let info: FileInfo
    do { info = try await lookupPath(clients.nfsClient, rootHandle, resolved.nfsPath, span) } catch {
        rootHandleCache.removeValue(forKey: device.ip.address)
        guard
            let newRoot = try await getRootHandle(
                device: device, mountPath: resolved.mountPath, mountClient: clients.mountClient, span: span)
        else { throw badRoothandleError(slot, device.id) }
        info = try await lookupPath(clients.nfsClient, newRoot, resolved.nfsPath, span)
    }
    return (info, clients.nfsClient)
}
@DJLinkActor public func fetchFile(
    device: Device, slot: NfsMediaSlot, path: String, onProgress: (@DJLinkActor (FetchProgress) -> Void)? = nil,
    chunkSize: Int? = nil, span: TelemetrySpan? = nil
) async throws -> [UInt8] {
    let tx =
        span?.startChild(SpanContext(op: "fetchFile")) ?? Telemetry.startTransaction(SpanContext(name: "fetchFile"))
    let (info, client) = try await locateFile(device: device, slot: slot, path: path, span: tx)
    let file = try await fetchFile(client, info, onProgress, tx, chunkSize)
    tx.setData("path", path)
    tx.setData("slot", nfsSlotName(slot))
    tx.setData("size", info.size)
    tx.finish()
    return file
}
@DJLinkActor public func fetchFileRange(
    device: Device, slot: NfsMediaSlot, path: String, offset: Int, length: Int, span: TelemetrySpan? = nil
) async throws -> [UInt8] {
    let tx =
        span?.startChild(SpanContext(op: "fetchFileRange"))
        ?? Telemetry.startTransaction(SpanContext(name: "fetchFileRange"))
    let (info, client) = try await locateFile(device: device, slot: slot, path: path, span: tx)
    let actualOffset = min(offset, info.size)
    let actualLength = min(length, info.size - min(offset, info.size))
    if actualLength <= 0 {
        tx.finish()
        return []
    }
    let data = try await fetchFileRange(client, info, actualOffset, actualLength, tx)
    tx.setData("path", path)
    tx.setData("slot", nfsSlotName(slot))
    tx.setData("offset", actualOffset)
    tx.setData("length", actualLength)
    tx.setData("fileSize", info.size)
    tx.finish()
    return data
}
@DJLinkActor public func getFileInfo(device: Device, slot: NfsMediaSlot, path: String, span: TelemetrySpan? = nil)
    async throws -> FileInfo
{
    let tx =
        span?.startChild(SpanContext(op: "getFileInfo")) ?? Telemetry.startTransaction(SpanContext(name: "getFileInfo"))
    let (info, _) = try await locateFile(device: device, slot: slot, path: path, span: tx)
    tx.setData("path", path)
    tx.setData("slot", nfsSlotName(slot))
    tx.setData("size", info.size)
    tx.finish()
    return info
}
@DJLinkActor public func resetDeviceCache(_ device: Device) {
    clientsCache.removeValue(forKey: device.ip.address)
    rootHandleCache.removeValue(forKey: device.ip.address)
}
@DJLinkActor public func configureRetryStrategy(_ config: RetryConfig) {
    retryConfig = config
    for client in clientsCache.values { client.conn.retryConfig = config }
}
private func nfsSlotName(_ slot: MediaSlot) -> String? { slot.jsName?.lowercased() }
