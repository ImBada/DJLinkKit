public enum DatabasePreference: String, Sendable { case auto, oneLibrary, pdb }
public enum DatabaseType: String, Sendable { case oneLibrary, pdb }
public struct PlaylistQueryResult: Equatable, Sendable {
    public var folders: [Playlist]
    public var playlists: [Playlist]
    public var trackEntries: [PlaylistEntryWithFKs]
    public init(
        folders: [Playlist] = [], playlists: [Playlist] = [], trackEntries: [PlaylistEntryWithFKs] = []
    ) {
        self.folders = folders
        self.playlists = playlists
        self.trackEntries = trackEntries
    }
}
@DJLinkActor public protocol DatabaseAdapter: AnyObject {
    var type: DatabaseType { get }
    func findTrack(_ id: Int) throws -> Track?
    func findPlaylist(_ playlistId: Int?) throws -> PlaylistQueryResult
    func close()
}
extension DatabaseAdapter {
    public func findPlaylist() throws -> PlaylistQueryResult { try findPlaylist(nil) }
}
public typealias LocalDBRow = [String: CipherDatabase.Value]
extension Dictionary where Key == String, Value == CipherDatabase.Value {
    public func int(_ key: String) -> Int? {
        switch self[key] {
        case .int(let n): n
        case .real(let n):
            // 원본 number를 Int로 표현할 수 없는 값은 nil로 남겨 trap을 피한다.
            n.isFinite ? Int(exactly: n.rounded(.towardZero)) : nil
        default: nil
        }
    }
    public func double(_ key: String) -> Double? {
        switch self[key] {
        case .int(let n): Double(n)
        case .real(let n): n
        default: nil
        }
    }
    public func string(_ key: String) -> String? {
        if case .text(let s) = self[key] { s } else { nil }
    }
}
