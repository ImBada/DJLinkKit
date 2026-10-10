/// A Database is the central service used to query devices on the prolink network for information from their databases.
@DJLinkActor public final class Database {
    private enum LookupStrategy { case remote, local, noneAvailable }
    private let localDatabase: any DBLocalDatabase
    private let remoteDatabase: any DBRemoteDatabase
    private let deviceManager: any DBDeviceSource
    private let logger: any Logger
    private let dependencies: DBDependencies
    private let hostDeviceRef: DeviceReference
    public var hostDevice: Device { hostDeviceRef.device }

    public init(
        local: any DBLocalDatabase, remote: any DBRemoteDatabase, deviceManager: any DBDeviceSource,
        logger: any Logger = noopLogger, hostDevice: DeviceReference? = nil, dependencies: DBDependencies = .init()
    ) {
        self.localDatabase = local
        self.remoteDatabase = remote
        self.deviceManager = deviceManager
        self.logger = logger
        self.dependencies = dependencies
        self.hostDeviceRef = hostDevice ?? DeviceReference(remote.hostDevice)
    }
    public convenience init(
        _ local: any DBLocalDatabase, _ remote: any DBRemoteDatabase, _ deviceManager: any DBDeviceSource,
        logger: any Logger = noopLogger, hostDevice: DeviceReference? = nil, dependencies: DBDependencies = .init()
    ) {
        self.init(
            local: local, remote: remote, deviceManager: deviceManager, logger: logger, hostDevice: hostDevice,
            dependencies: dependencies)
    }
    /// 시험처럼 장치 값을 넘길 때의 편의 생성자.
    public convenience init(
        local: any DBLocalDatabase, remote: any DBRemoteDatabase, deviceManager: any DBDeviceSource,
        logger: any Logger = noopLogger, hostDevice: Device, dependencies: DBDependencies = .init()
    ) {
        self.init(
            local: local, remote: remote, deviceManager: deviceManager, logger: logger,
            hostDevice: DeviceReference(hostDevice), dependencies: dependencies)
    }
    private func getTrackLookupStrategy(_ device: Device, _ type: TrackType) -> LookupStrategy {
        let isUnanalyzed = type == .audioCD || type == .unanalyzed
        if device.type == .cdj && (isUnanalyzed || type == .streaming) { return .remote }
        return device.type == .rekordbox ? .remote : device.type == .cdj && type == .rb ? .local : .noneAvailable
    }
    private func getMediaLookupStrategy(_ device: Device, _ slot: MediaSlot) -> LookupStrategy {
        device.type == .rekordbox && slot == .rb ? .remote : device.type == .rekordbox ? .noneAvailable : .local
    }
    private func transaction(
        _ operation: String, deviceId: DeviceID, trackSlot: MediaSlot, trackType: TrackType, span: TelemetrySpan?
    ) -> TelemetrySpan {
        let tx = span?.startChild(.init(op: operation)) ?? Telemetry.startTransaction(.init(name: operation))
        tx.setTag("deviceId", String(deviceId))
        tx.setTag("trackType", dbTrackTypeName(trackType))
        tx.setTag("trackSlot", dbSlotName(trackSlot))
        return tx
    }
    public func getDatabaseType(_ deviceId: DeviceID, _ slot: MediaSlot) -> DatabaseType? {
        localDatabase.getDatabaseType(deviceId, slot)
    }
    public func getDatabaseType(deviceId: DeviceID, slot: MediaSlot) -> DatabaseType? {
        getDatabaseType(deviceId, slot)
    }

    public func getMetadata(_ opts: GetMetadata.Options) async throws -> Track? {
        let tx = transaction(
            "dbGetMetadata", deviceId: opts.deviceId, trackSlot: opts.trackSlot, trackType: opts.trackType,
            span: opts.span)
        var callOpts = opts
        callOpts.span = tx
        guard let device = await deviceManager.getDeviceEnsured(opts.deviceId, timeout: 2000) else { return nil }
        var track: Track?
        switch getTrackLookupStrategy(device, opts.trackType) {
        case .remote:
            track = try await GetMetadata.viaRemote(remoteDatabase, callOpts, logger: logger)
        case .local:
            let local = try await GetMetadata.viaLocal(localDatabase, device, callOpts, dependencies: dependencies)
            track = local.track
            if let switchedTo = local.switchedTo {
                logger.info(
                    "Device \(opts.deviceId) \(dbSlotName(opts.trackSlot)) is now read from the \(switchedTo == .pdb ? "legacy PDB" : "OneLibrary") database: it is the one that holds track \(opts.trackId) as the player reports it (NP3-399)"
                )
            }
            if let miss = local.miss {
                logger.warn(
                    "Local metadata lookup missed track \(opts.trackId) on device \(opts.deviceId) \(dbSlotName(opts.trackSlot)): \(miss == .noDatabase ? "no rekordbox database is loaded for that slot" : "the loaded database holds no track with that id")"
                )
                track = await metadataViaRemoteFallback(callOpts)
            }
        case .noneAvailable: tx.setStatus(.unavailable)
        }
        tx.finish()
        return track
    }
    private func metadataViaRemoteFallback(_ opts: GetMetadata.Options) async -> Track? {
        do {
            guard let track = try await GetMetadata.viaRemote(remoteDatabase, opts, logger: logger) else {
                logger.warn("Remote fallback found no track \(opts.trackId) on device \(opts.deviceId)")
                return nil
            }
            logger.info("Remote fallback recovered track \(opts.trackId) from device \(opts.deviceId)")
            return track
        } catch {
            logger.warn(
                "Remote fallback failed for track \(opts.trackId) on device \(opts.deviceId): \(dbErrorMessage(error))")
            return nil
        }
    }
    public func getFile(_ opts: GetFile.Options) async throws -> [UInt8]? {
        let tx = transaction(
            "dbGetFile", deviceId: opts.deviceId, trackSlot: opts.trackSlot, trackType: opts.trackType, span: opts.span)
        var callOpts = opts
        callOpts.span = tx
        guard let device = await deviceManager.getDeviceEnsured(opts.deviceId, timeout: 2000) else { return nil }
        var file: [UInt8]?
        switch getTrackLookupStrategy(device, opts.trackType) {
        case .remote: file = GetFile.viaRemote(remoteDatabase, device, callOpts)
        case .local: file = try await GetFile.viaLocal(localDatabase, device, callOpts, dependencies: dependencies)
        case .noneAvailable: tx.setStatus(.unavailable)
        }
        tx.finish()
        return file
    }
    public func getArtworkThumbnail(_ opts: GetArtworkThumbnail.Options) async throws -> [UInt8]? {
        let tx = transaction(
            "dbGetArtwork", deviceId: opts.deviceId, trackSlot: opts.trackSlot, trackType: opts.trackType,
            span: opts.span)
        var callOpts = opts
        callOpts.span = tx
        guard let device = await deviceManager.getDeviceEnsured(opts.deviceId, timeout: 2000) else { return nil }
        var artwork: [UInt8]?
        switch getTrackLookupStrategy(device, opts.trackType) {
        case .remote: artwork = try await GetArtworkThumbnail.viaRemote(remoteDatabase, callOpts)
        case .local:
            artwork = try await GetArtworkThumbnail.viaLocal(
                localDatabase, device, callOpts, dependencies: dependencies)
        case .noneAvailable: tx.setStatus(.unavailable)
        }
        tx.finish()
        return artwork
    }
    public func getArtwork(_ opts: GetArtworkFromFile.Options) async -> [UInt8]? {
        let tx =
            opts.span?.startChild(.init(op: "dbGetArtwork")) ?? Telemetry.startTransaction(.init(name: "dbGetArtwork"))
        tx.setTag("deviceId", String(opts.deviceId))
        tx.setTag("trackSlot", dbSlotName(opts.trackSlot))
        var callOpts = opts
        callOpts.span = tx
        guard let device = await deviceManager.getDeviceEnsured(opts.deviceId, timeout: 2000) else {
            tx.setStatus(.notFound)
            tx.finish()
            return nil
        }
        let artwork = await GetArtworkFromFile.viaFileExtraction(device, callOpts, dependencies: dependencies)
        tx.finish()
        return artwork
    }
    public func getWaveforms(_ opts: GetWaveforms.Options) async throws -> Waveforms? {
        let tx = transaction(
            "dbGetWaveforms", deviceId: opts.deviceId, trackSlot: opts.trackSlot, trackType: opts.trackType,
            span: opts.span)
        var callOpts = opts
        callOpts.span = tx
        guard let device = await deviceManager.getDeviceEnsured(opts.deviceId, timeout: 2000) else { return nil }
        var waveforms: Waveforms?
        switch getTrackLookupStrategy(device, opts.trackType) {
        case .remote: waveforms = try await GetWaveforms.viaRemote(remoteDatabase, callOpts)
        case .local:
            waveforms = try await GetWaveforms.viaLocal(localDatabase, device, callOpts, dependencies: dependencies)
        case .noneAvailable: tx.setStatus(.unavailable)
        }
        tx.finish()
        return waveforms
    }
    public func getTrackAnalysis(_ opts: GetTrackAnalysis.Options) async throws -> TrackAnalysis? {
        let tx = transaction(
            "dbGetTrackAnalysis", deviceId: opts.deviceId, trackSlot: opts.trackSlot, trackType: opts.trackType,
            span: opts.span)
        var callOpts = opts
        callOpts.span = tx
        guard let device = await deviceManager.getDeviceEnsured(opts.deviceId, timeout: 2000) else {
            tx.finish()
            return nil
        }
        var analysis: TrackAnalysis?
        switch getTrackLookupStrategy(device, opts.trackType) {
        case .local:
            analysis = try await GetTrackAnalysis.viaLocal(localDatabase, device, callOpts, dependencies: dependencies)
        case .remote, .noneAvailable: tx.setStatus(.unavailable)
        }
        tx.finish()
        return analysis
    }
    public func getPlaylist(_ opts: GetPlaylist.Options) async throws -> PlaylistContents? {
        let tx =
            opts.span?.startChild(.init(op: "dbGetPlaylist"))
            ?? Telemetry.startTransaction(.init(name: "dbGetPlaylist"))
        tx.setTag("deviceId", String(opts.deviceId))
        tx.setTag("mediaSlot", dbSlotName(opts.mediaSlot))
        var callOpts = opts
        callOpts.span = tx
        guard let device = await deviceManager.getDeviceEnsured(opts.deviceId, timeout: 2000) else { return nil }
        var contents: PlaylistContents?
        switch getMediaLookupStrategy(device, opts.mediaSlot) {
        case .remote: contents = try await GetPlaylist.viaRemote(remoteDatabase, callOpts)
        case .local: contents = try await GetPlaylist.viaLocal(localDatabase, callOpts)
        case .noneAvailable: tx.setStatus(.unavailable)
        }
        tx.finish()
        return contents
    }
}
