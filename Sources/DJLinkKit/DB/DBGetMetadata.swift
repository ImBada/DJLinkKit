import Foundation

public enum GetMetadata {
    public struct Options: Sendable {
        public var deviceId: DeviceID
        public var trackSlot: MediaSlot
        public var trackType: TrackType
        public var trackId: Int
        public var trackBPM: Double?
        public var span: TelemetrySpan?
        public init(
            deviceId: DeviceID, trackSlot: MediaSlot, trackType: TrackType, trackId: Int, trackBPM: Double? = nil,
            span: TelemetrySpan? = nil
        ) {
            self.deviceId = deviceId
            self.trackSlot = trackSlot
            self.trackType = trackType
            self.trackId = trackId
            self.trackBPM = trackBPM
            self.span = span
        }
    }
    public enum LocalMiss: String, Sendable { case noDatabase = "no-database", trackAbsent = "track-absent" }
    public struct LocalResult: Equatable, Sendable {
        public var track: Track?
        public var miss: LocalMiss?
        public var switchedTo: DatabaseType?
    }

    public static func describeBlankMetadata(_ opts: Options, _ response: MetadataResponse?, _ trackInfo: String)
        -> String
    {
        let reports = (response?.items ?? []).map { item in
            let hex = String(format: "0x%04x", item.type.rawValue)
            // 원본 객체의 삽입 순서. 사전에는 순서가 없으므로 알려진 칸을 원본 순서로 직렬화한다.
            let order: [String]
            switch item.type {
            case .path: order = ["path"]
            case .trackTitle: order = ["id", "title", "artworkId"]
            case .streamingTrackMetadata: order = ["title", "artist"]
            case .albumTitle, .artist, .genre, .label, .key, .originalArtist, .remixer, .folder, .playlist,
                .colorNone, .colorPink, .colorRed, .colorOrange, .colorYellow, .colorGreen, .colorAqua,
                .colorBlue, .colorPurple:
                order = ["id", "name"]
            case .bitRate: order = ["bitrate"]
            case .comment: order = ["comment"]
            case .year: order = ["year"]
            case .rating: order = ["rating"]
            case .tempo: order = ["bpm"]
            case .duration: order = ["duration"]
            default: order = ["parentId", "mainId", "label1", "label2", "artworkId"]
            }
            let keys =
                order.filter { item.rawValues[$0] != nil }
                + item.rawValues.keys.filter { $0 != "type" && !order.contains($0) }.sorted()
            let fields = keys.map { key in
                let value: String
                switch item.rawValues[key]! {
                case let .number(number): value = String(number)
                case let .decimal(number): value = number.jsNumberString
                case let .string(string): value = dbJSONString(string)
                case let .binary(bytes):
                    value = "{\"type\":\"Buffer\",\"data\":[\(bytes.map(String.init).joined(separator: ","))]}"
                }
                return "\(dbJSONString(key)):\(value)"
            }.joined(separator: ",")
            let report = "\(hex) {\(fields)}"
            // JS slice와 length는 UTF-16 코드 단위다.
            return report.utf16.count > 200 ? String(decoding: report.utf16.prefix(200), as: UTF16.self) + "…" : report
        }
        let items =
            response.map {
                (["\($0.items.count) of \($0.itemsAvailable) item(s) received"] + reports).joined(separator: "; ")
            } ?? "no response recorded"
        return
            "Device \(opts.deviceId) answered the metadata query for track \(opts.trackId) (slot \(opts.trackSlot.rawValue) \(getSlotName(opts.trackSlot) ?? "unknown"), type \(opts.trackType.rawValue) \(getTrackTypeName(opts.trackType) ?? "unknown")) with no title or artist: \(items); track info: \(trackInfo)"
    }

    @DJLinkActor public static func viaRemote(
        _ remote: any DBRemoteDatabase, _ opts: Options, logger: any Logger = noopLogger
    ) async throws -> Track? {
        guard let conn = try await remote.getDBQuery(opts.deviceId) else { return nil }
        let descriptor = QueryDescriptor(menuTarget: .main, trackSlot: opts.trackSlot, trackType: opts.trackType)
        let isUnanalyzed = opts.trackType == .unanalyzed || opts.trackType == .audioCD
        let skipLocalFileLookups = isUnanalyzed || opts.trackType == .streaming
        let response = DBMetadataResponseBox()
        var args = RemoteDBQueryArgs(trackId: opts.trackId)
        if !isUnanalyzed {
            args.onResponse = { response.value = $0 }
        }
        let metadata = try await conn.query(
            queryDescriptor: descriptor, query: isUnanalyzed ? .getGenericMetadata : .getMetadata,
            args: args, span: opts.span)
        var track = try dbTrackResult(metadata)
        var trackInfoError: String?
        do {
            let result = try await conn.query(
                queryDescriptor: descriptor, query: .getTrackInfo, args: .init(trackId: opts.trackId), span: opts.span)
            guard case let .path(path) = result else { throw DJLinkError("Expected track info query result") }
            track.filePath = path
        } catch {
            if !skipLocalFileLookups { throw error }
            trackInfoError = dbErrorMessage(error)
        }
        if track.title.jsTrim().isEmpty
            && (track.artist?.name.jsTrim().isEmpty ?? true)
        {
            logger.warn(
                describeBlankMetadata(
                    opts, response.value, trackInfoError.map { "failed (\($0))" } ?? dbJSONString(track.filePath)))
        }
        if !skipLocalFileLookups {
            let result = try await conn.query(
                queryDescriptor: descriptor, query: .getBeatGrid, args: .init(trackId: opts.trackId), span: opts.span)
            guard case let .beatGrid(grid) = result else { throw DJLinkError("Expected beat grid query result") }
            track.beatGrid = grid
        }
        return track
    }

    @DJLinkActor public static func viaLocal(
        _ local: any DBLocalDatabase, _ device: Device, _ opts: Options, dependencies: DBDependencies = .init()
    ) async throws -> LocalResult {
        guard opts.trackSlot == .usb || opts.trackSlot == .sd else {
            throw DJLinkError("Expected USB or SD slot for local database query")
        }
        let lookup = try await local.findTrack(
            opts.deviceId, opts.trackSlot, opts.trackId, .init(trackBPM: opts.trackBPM))
        guard lookup.adapter != nil else { return .init(track: nil, miss: .noDatabase, switchedTo: nil) }
        guard var track = lookup.track else { return .init(track: nil, miss: .trackAbsent, switchedTo: nil) }
        let anlz = try await dependencies.loadAnlz(
            track, "DAT", anlzLoader(device: device, slot: opts.trackSlot, dependencies: dependencies))
        track.beatGrid = anlz.beatGrid
        track.waveformHd = nil
        return .init(track: track, miss: nil, switchedTo: lookup.switchedTo)
    }
}

@DJLinkActor private final class DBMetadataResponseBox { var value: MetadataResponse? }
