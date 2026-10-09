public enum GetArtworkFromFile {
    public struct Options: Sendable {
        public var deviceId: DeviceID
        public var trackSlot: MediaSlot
        public var track: Track
        public var span: TelemetrySpan?
        public var logger: (any Logger)?
        public init(
            deviceId: DeviceID, trackSlot: MediaSlot, track: Track, span: TelemetrySpan? = nil,
            logger: (any Logger)? = nil
        ) {
            self.deviceId = deviceId
            self.trackSlot = trackSlot
            self.track = track
            self.span = span
            self.logger = logger
        }
    }
    @DJLinkActor public static func viaFileExtraction(
        _ device: Device, _ opts: Options, dependencies: DBDependencies = .init()
    ) async -> [UInt8]? {
        let logger = opts.logger ?? noopLogger
        guard opts.trackSlot == .usb || opts.trackSlot == .sd || opts.trackSlot == .rb else {
            logger.debug(
                "[artwork-nfs] Skipping: unsupported slot \(dbSlotName(opts.trackSlot)) (device \(device.name))")
            return nil
        }
        let path = opts.track.filePath
        guard !path.isEmpty else {
            logger.debug("[artwork-nfs] Skipping: no filePath on track")
            return nil
        }
        let ext = path.split(separator: ".", omittingEmptySubsequences: false).last.map { $0.lowercased() } ?? ""
        guard isArtworkExtractionSupported(ext) else {
            logger.debug("[artwork-nfs] Skipping: unsupported extension \".\(ext)\" (\(path))")
            return nil
        }
        logger.debug(
            "[artwork-nfs] Extracting from \(path) (slot=\(dbSlotName(opts.trackSlot)), device=\(device.name) @ \(device.ip.address))"
        )
        let tx =
            opts.span?.startChild(.init(op: "getArtworkFromFile"))
            ?? Telemetry.startTransaction(.init(name: "getArtworkFromFile"))
        do {
            guard let artwork = try await dependencies.extractArtworkFromDevice(device, opts.trackSlot, path, logger)
            else {
                logger.debug("[artwork-nfs] No embedded artwork found in file")
                tx.setData("result", "no_artwork")
                tx.finish()
                return nil
            }
            logger.debug("[artwork-nfs] Success: \(artwork.mimeType.rawValue) (\(artwork.data.count) bytes)")
            tx.setData("result", "success")
            tx.setData("mimeType", artwork.mimeType.rawValue)
            tx.setData("size", artwork.data.count)
            tx.finish()
            return artwork.data
        } catch {
            logger.warn("[artwork-nfs] NFS extraction failed: \(dbErrorMessage(error))")
            tx.setData("result", "error")
            tx.finish()
            Telemetry.captureException(error)
            return nil
        }
    }
}
