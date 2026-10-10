import Foundation

// 다른 트랙의 DeviceManager·StatusEmitter·NFS를 이 트랙의 주입점으로 잇는다.
@DJLinkActor public protocol LocalDBDeviceSource: AnyObject {
    var devices: [DeviceID: Device] { get }
    func on(_ event: String, _ handler: @escaping @DJLinkActor (Device) -> Void)
}
@DJLinkActor public protocol LocalDBMediaSlotSource: AnyObject {
    func queryMediaSlot(hostDevice: Device, device: Device, slot: MediaSlot) async throws
        -> MediaSlotInfo
}
public struct LocalDBFetchProgress: Equatable, Sendable {
    public var read: Int
    public var total: Int
    public init(read: Int, total: Int) {
        self.read = read
        self.total = total
    }
}
@DJLinkActor public struct LocalDBFetchFileOptions {
    public var device: Device
    public var slot: MediaSlot
    public var path: String
    public var span: TelemetrySpan?
    public var onProgress: (@DJLinkActor (LocalDBFetchProgress) -> Void)?
    public init(
        device: Device, slot: MediaSlot, path: String, span: TelemetrySpan? = nil,
        onProgress: (@DJLinkActor (LocalDBFetchProgress) -> Void)? = nil
    ) {
        self.device = device
        self.slot = slot
        self.path = path
        self.span = span
        self.onProgress = onProgress
    }
}
public typealias LocalDBFetchFile = @DJLinkActor (LocalDBFetchFileOptions) async throws -> [UInt8]
@DJLinkActor public protocol LocalDBFileSystem {
    var tmpdir: String { get }
    func writeFileSync(_ path: String, _ data: [UInt8]) throws
    func unlinkSync(_ path: String) throws
}
@DJLinkActor public struct LocalDBNativeFileSystem: LocalDBFileSystem {
    public init() {}
    public var tmpdir: String { FileManager.default.temporaryDirectory.path }
    public func writeFileSync(_ path: String, _ data: [UInt8]) throws {
        try Data(data).write(to: URL(filePath: path))
    }
    public func unlinkSync(_ path: String) throws { try FileManager.default.removeItem(atPath: path) }
}
@DJLinkActor public struct LocalDBHydrationOptions {
    public var orm: any DatabaseAdapter
    public var pdbData: [UInt8]
    public var span: TelemetrySpan?
    public var onProgress: (@DJLinkActor (HydrationProgress) -> Void)?
}
public typealias LocalDBHydrateDatabase =
    @DJLinkActor (LocalDBHydrationOptions) async throws -> Void
@DJLinkActor public struct LocalDBDependencies {
    public var fetchFile: LocalDBFetchFile
    public var fileSystem: any LocalDBFileSystem
    public var makeOneLibraryAdapter: @DJLinkActor (String) throws -> any DatabaseAdapter
    public var makeMetadataORM: @DJLinkActor () throws -> any DatabaseAdapter
    public var hydrateDatabase: LocalDBHydrateDatabase
    public var startTransaction: @DJLinkActor (SpanContext) -> TelemetrySpan
    public var platform: String
    public init(
        fetchFile: @escaping LocalDBFetchFile = { options in
            // 원본 `fetchFile({device, slot, path, onProgress, span})`(src/nfs)
            var onProgress: (@DJLinkActor (FetchProgress) -> Void)?
            if let callback = options.onProgress {
                onProgress = { progress in callback(LocalDBFetchProgress(read: progress.read, total: progress.total)) }
            }
            return try await DJLinkKit.fetchFile(
                device: options.device, slot: options.slot, path: options.path, onProgress: onProgress,
                span: options.span)
        },
        fileSystem: any LocalDBFileSystem = LocalDBNativeFileSystem(),
        makeOneLibraryAdapter: @escaping @DJLinkActor (String) throws -> any DatabaseAdapter = {
            try OneLibraryAdapter(dbPath: $0)
        },
        makeMetadataORM: @escaping @DJLinkActor () throws -> any DatabaseAdapter = {
            try MetadataORM()
        },
        hydrateDatabase: @escaping LocalDBHydrateDatabase = { options in
            guard let orm = options.orm as? MetadataORM else { throw DJLinkError("Expected MetadataORM") }
            try await DJLinkKit.hydrateDatabase(
                .init(
                    orm: orm, pdbData: options.pdbData, span: options.span, onProgress: options.onProgress))
        },
        startTransaction: @escaping @DJLinkActor (SpanContext) -> TelemetrySpan = Telemetry
            .startTransaction,
        platform: String = "darwin"
    ) {
        self.fetchFile = fetchFile
        self.fileSystem = fileSystem
        self.makeOneLibraryAdapter = makeOneLibraryAdapter
        self.makeMetadataORM = makeMetadataORM
        self.hydrateDatabase = hydrateDatabase
        self.startTransaction = startTransaction
        self.platform = platform
    }
}
