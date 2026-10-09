public struct MetadataResponse: Equatable, Sendable {
    public var itemsAvailable: Int
    public var items: [Items]
    public init(itemsAvailable: Int, items: [Items]) {
        self.itemsAvailable = itemsAvailable
        self.items = items
    }
}
public struct RemoteDBQueryArgs: Sendable {
    public var trackId: Int?
    public var artworkId: Int?
    public var id: Int?
    public var isFolderRequest: Bool?
    public var onResponse: (@DJLinkActor @Sendable (MetadataResponse) -> Void)?
    public init(
        trackId: Int? = nil, artworkId: Int? = nil, id: Int? = nil, isFolderRequest: Bool? = nil,
        onResponse: (@DJLinkActor @Sendable (MetadataResponse) -> Void)? = nil
    ) {
        self.trackId = trackId
        self.artworkId = artworkId
        self.id = id
        self.isFolderRequest = isFolderRequest
        self.onResponse = onResponse
    }
}
public struct RemoteDBPlaylist: Equatable, Sendable {
    public var folders: [Playlist]
    public var playlists: [Playlist]
    public var trackEntries: [Items]
    public init(folders: [Playlist], playlists: [Playlist], trackEntries: [Items]) {
        self.folders = folders
        self.playlists = playlists
        self.trackEntries = trackEntries
    }
}
public enum RemoteDBQueryResult: Equatable, Sendable {
    // 기반 Track.year(Int?)에 들어가지 않는 원본 number도 잃지 않는다.
    case trackWithRawYear(track: Track, year: Double)
    case advancedCueAndLoops([RemoteDBAdvancedCueEntry])
    case track(Track), artwork([UInt8]), waveformPreview(RemoteDBWaveformPreview), path(String), cueAndLoops(
        [CueAndLoop])
    case beatGrid(BeatGrid), waveformDetailed(WaveformDetailed), waveformHD(WaveformHD), playlist(RemoteDBPlaylist)
}
@DJLinkActor func queryHandler(
    conn: Connection, lookupDescriptor: LookupDescriptor, query: Query, args: RemoteDBQueryArgs, span: TelemetrySpan
) async throws -> RemoteDBQueryResult {
    var fields: [Field] = [try fieldFromDescriptor(lookupDescriptor)]
    let responseType: Response
    switch query {
    case .menuPlaylist:
        fields += [
            RemoteDBUInt32(0), RemoteDBUInt32(args.id ?? 0), RemoteDBUInt32(args.isFolderRequest == true ? 1 : 0),
        ]
        responseType = .success
    case .getArtwork:
        guard let artworkId = args.artworkId else { throw DJLinkError("Missing artworkId") }
        fields.append(RemoteDBUInt32(artworkId))
        responseType = .artwork
    case .getMetadata, .getGenericMetadata, .getTrackInfo, .getWaveformPreview, .getWaveformDetailed, .getWaveformHD,
        .getCueAndLoops, .getAdvCueAndLoops, .getBeatGrid:
        guard let trackId = args.trackId else { throw DJLinkError("Missing trackId") }
        if query == .getWaveformPreview { fields.append(RemoteDBUInt32(0)) }
        fields.append(RemoteDBUInt32(trackId))
        switch query {
        case .getWaveformPreview:
            fields += [RemoteDBUInt32(0), RemoteDBBinary([])]
            responseType = .waveformPreview
        case .getWaveformDetailed:
            fields.append(RemoteDBUInt32(0))
            responseType = .waveformDetailed
        case .getAdvCueAndLoops:
            fields.append(RemoteDBUInt32(0))
            responseType = .advCueAndLoops
        case .getWaveformHD:
            fields += [
                RemoteDBUInt32(try [UInt8]("PWV5", encoding: .utf8).readUInt32LE()),
                RemoteDBUInt32(try [UInt8]("EXT\0", encoding: .utf8).readUInt32LE()),
            ]
            responseType = .waveformHD
        case .getCueAndLoops: responseType = .cueAndLoop
        case .getBeatGrid: responseType = .beatGrid
        default: responseType = .success
        }
    default: throw DJLinkError("No query handler registered for \(query.rawValue)")
    }
    try await conn.writeMessage(Message(type: query, args: fields), span)
    let resp = try await conn.readMessage(responseType, span)
    switch try resp.data {
    case let .artwork(data): return .artwork(data)
    case let .beatGrid(grid): return .beatGrid(grid)
    case let .waveformPreview(data): return .waveformPreview(data)
    case let .waveformDetailed(data): return .waveformDetailed(data)
    case let .waveformHD(data): return .waveformHD(data)
    case let .cueAndLoops(data): return .cueAndLoops(data)
    case let .advancedCueAndLoops(data): return .advancedCueAndLoops(data)
    case let .success(success):
        var received: [Items] = []
        for try await item in renderItems(conn, lookupDescriptor, success.itemsAvailable, span) {
            received.append(item)
        }
        switch query {
        case .getMetadata:
            args.onResponse?(MetadataResponse(itemsAvailable: success.itemsAvailable, items: received))
            return try makeRemoteDBTrack(received, generic: false)
        case .getGenericMetadata: return try makeRemoteDBTrack(received, generic: true)
        case .getTrackInfo:
            guard let path = received.last(where: { $0.type == .path })?.path else {
                throw DJLinkError("Player sent no file path (\(success.itemsAvailable) item(s) available)")
            }
            return .path(path)
        case .menuPlaylist:
            let parentId = args.id == 0 ? nil : args.id
            let folders = received.filter { $0.type == .folder }.map {
                Playlist(id: $0.id!, name: $0.name!, isFolder: true, parentId: parentId)
            }
            let playlists = received.filter { $0.type == .playlist }.map {
                Playlist(id: $0.id!, name: $0.name!, isFolder: false, parentId: parentId)
            }
            return .playlist(
                RemoteDBPlaylist(
                    folders: folders, playlists: playlists, trackEntries: received.filter { $0.type == .trackTitle }))
        default: throw DJLinkError("Unexpected setup success")
        }
    default: throw DJLinkError("Unexpected query response")
    }
}
private func makeRemoteDBTrack(_ received: [Items], generic: Bool) throws -> RemoteDBQueryResult {
    var items: [ItemType: Items] = [:]
    for item in received { items[item.type] = item }
    if generic {
        // 원본 generic metadata는 필수 항목에 optional chaining이 없다.
        for type in [ItemType.trackTitle, .duration, .tempo, .comment, .rating, .bitRate] where items[type] == nil {
            throw DJLinkError("Cannot read properties of undefined")
        }
    }
    func entity<E: NamedEntity>(_ type: ItemType, _ entityType: E.Type) -> E? {
        guard let item = items[type], let id = item.id, let name = item.name else { return nil }
        return E(id: id, name: name)
    }
    let title = items[.trackTitle]
    let streaming = generic ? nil : items[.streamingTrackMetadata]
    let artist =
        entity(.artist, Artist.self) ?? streaming?.artist.flatMap { $0.isEmpty ? nil : Artist(id: 0, name: $0) }
    let colorItem = findColor(items.values.sorted { $0.type.rawValue < $1.type.rawValue })
    let year = generic ? nil : items[.year]?.year
    let track = Track(
        id: title?.id ?? 0, title: title?.title ?? streaming?.title ?? "", duration: items[.duration]?.duration ?? 0,
        bitrate: items[.bitRate]?.bitrate, tempo: items[.tempo]?.bpm ?? 0, rating: items[.rating]?.rating ?? 0,
        comment: items[.comment]?.comment ?? "", filePath: "", fileName: "",
        year: year.flatMap { $0.isFinite ? Int(exactly: $0) : nil }, artwork: Artwork(id: title?.artworkId ?? 0),
        artist: artist, originalArtist: generic ? nil : entity(.originalArtist, Artist.self),
        remixer: generic ? nil : entity(.remixer, Artist.self), album: entity(.albumTitle, Album.self),
        label: generic ? nil : entity(.label, Label.self), genre: entity(.genre, Genre.self),
        color: colorItem.flatMap { item in
            guard let id = item.id, let name = item.name else { return nil }
            return Color(id: id, name: name)
        },
        key: generic ? nil : entity(.key, Key.self))
    if let year, track.year == nil { return .trackWithRawYear(track: track, year: year) }
    return .track(track)
}

public typealias HandlerArgs = RemoteDBQueryArgs
public typealias HandlerReturn = RemoteDBQueryResult
public typealias Handler =
    @DJLinkActor @Sendable (Connection, LookupDescriptor, HandlerArgs, TelemetrySpan) async throws -> HandlerReturn

/// 원본 queryHandlers의 같은 11개 키를 공개한다. 지원되지 않은 메뉴 요청은 더하지 않는다.
@DJLinkActor public let queryHandlers: [Query: Handler] = {
    let queries: [Query] = [
        .getMetadata, .getArtwork, .getWaveformPreview, .getTrackInfo, .getGenericMetadata,
        .getCueAndLoops, .getBeatGrid, .getWaveformDetailed, .getAdvCueAndLoops, .getWaveformHD, .menuPlaylist,
    ]
    return Dictionary(
        uniqueKeysWithValues: queries.map { query in
            let handler: Handler = { conn, descriptor, args, span in
                try await queryHandler(conn: conn, lookupDescriptor: descriptor, query: query, args: args, span: span)
            }
            return (query, handler)
        })
}()
