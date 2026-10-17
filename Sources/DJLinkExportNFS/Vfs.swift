// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
import DJLinkKit
// 원본: crates/rbl-nfs/src/vfs.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public let HANDLE_LEN = 32
public let MAX_READ = 0xfc00
public enum NodeKind: Equatable, Sendable { case directory, file }
public struct Stat: Equatable, Sendable {
    public var size: UInt64 = 0
    public var mode: UInt32 = 0, nlink: UInt32 = 0, uid: UInt32 = 0, gid: UInt32 = 0
    public var blocksize: UInt32 = 0, rdev: UInt32 = 0, blocks: UInt32 = 0
    public var accessed: UInt32 = 0, modified: UInt32 = 0, changed: UInt32 = 0
    public init() {}
    public static func plain(_ size: UInt64, _ modified: UInt32) -> Stat {
        var stat = Stat()
        stat.size = size
        stat.mode = 0o100444
        stat.nlink = 1
        stat.blocksize = 4096
        stat.blocks = UInt32(exactly: size / 512 + (size % 512 == 0 ? 0 : 1)) ?? .max
        stat.accessed = modified
        stat.modified = modified
        stat.changed = modified
        return stat
    }
    public static func directory(_ modified: UInt32) -> Stat {
        var stat = Stat()
        stat.size = 64
        stat.mode = 0o040755
        stat.nlink = 2
        stat.blocksize = 4096
        stat.accessed = modified
        stat.modified = modified
        stat.changed = modified
        return stat
    }
}
public struct Handle: Equatable, Hashable, Sendable, CustomStringConvertible {
    private let bytes: [UInt8]
    fileprivate init(_ bytes: [UInt8]) { self.bytes = bytes }
    public func as_bytes() -> [UInt8] { bytes }
    public static func from_slice(_ bytes: [UInt8]) -> Handle? {
        bytes.count >= HANDLE_LEN ? Handle(Array(bytes.prefix(HANDLE_LEN))) : nil
    }
    public var description: String {
        bytes.enumerated().map { ([4, 8, 12].contains($0.offset) ? "." : "") + String(format: "%02x", $0.element) }
            .joined()
    }
}
public struct Attributes: Equatable, Sendable {
    public var kind: NodeKind
    public var size: UInt64
    public var fileid: UInt32
    public var modified: UInt32
    public var stat: Stat
    public init(kind: NodeKind, size: UInt64, fileid: UInt32, modified: UInt32, stat: Stat) {
        self.kind = kind
        self.size = size
        self.fileid = fileid
        self.modified = modified
        self.stat = stat
    }
}
private struct Node {
    var name: String, kind: NodeKind, parent: Int
    var children: [Int] = [], by_name: [String: Int] = [:]
    var source: String?, listed: Bool, stat: Stat?
    init(_ name: String, _ kind: NodeKind, _ parent: Int, _ source: String?, _ stat: Stat?, _ listed: Bool) {
        self.name = name
        self.kind = kind
        self.parent = parent
        self.source = source
        self.stat = stat
        self.listed = listed
    }
}
private struct Root { var parts: [String], host: String }
private func key(_ name: String) -> String { name.decomposedStringWithCanonicalMapping }
private func parts_of(_ path: String) -> [String] {
    path.components(separatedBy: "/").filter { !$0.isEmpty && $0 != "." && $0 != ".." }
}
private func join_path(_ dir: String, _ name: String) -> String { dir.hasSuffix("/") ? dir + name : dir + "/" + name }
private func path_components(_ path: String) -> [String] {
    // Rust Path는 '.'은 제거하지만 '..'은 보존하며 절대 경로의 루트도 구별한다.
    (path.hasPrefix("/") ? ["/"] : []) + path.components(separatedBy: "/").filter { !$0.isEmpty && $0 != "." }
}
private func is_plain_name(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
}
private func host_metadata(_ path: String, follow: Bool = true) -> stat? {
    guard !path.utf8.contains(0) else { return nil }
    var value = stat()
    let result = path.withCString { pointer in follow ? stat(pointer, &value) : lstat(pointer, &value) }
    return result == 0 ? value : nil
}
private func entry_kind(_ meta: stat) -> NodeKind? {
    switch meta.st_mode & S_IFMT {
    case S_IFDIR: return .directory
    case S_IFREG: return .file
    default: return nil
    }
}
private func stat_file(_ path: String) -> Stat {
    guard let meta = host_metadata(path) else { return Stat.plain(0, 0) }
    func low<T: BinaryInteger>(_ value: T) -> UInt32 { UInt32(exactly: value) ?? .max }
    func seconds<T: BinaryInteger>(_ value: T) -> UInt32 { value < 0 ? 0 : low(value) }
    var value = Stat()
    value.size = UInt64(max(0, meta.st_size))
    value.mode = UInt32(meta.st_mode) & 0xffff
    value.nlink = low(meta.st_nlink)
    value.uid = UInt32(meta.st_uid)
    value.gid = UInt32(meta.st_gid)
    value.blocksize = low(meta.st_blksize)
    value.rdev = low(meta.st_dev)
    value.blocks = low(meta.st_blocks)
    #if canImport(Darwin)
        value.accessed = seconds(meta.st_atimespec.tv_sec)
        value.modified = seconds(meta.st_mtimespec.tv_sec)
        value.changed = UInt32(exactly: meta.st_ctimespec.tv_sec) ?? 0
    #else
        value.accessed = seconds(meta.st_atim.tv_sec)
        value.modified = seconds(meta.st_mtim.tv_sec)
        value.changed = UInt32(exactly: meta.st_ctim.tv_sec) ?? 0
    #endif
    return value
}

@DJLinkActor
public final class Vfs {
    private var export: String, nodes: [Node], roots: [Root] = [], tracks: Set<[UInt8]> = []
    fileprivate var id_base: UInt32 = 0
    /// 원본 경로 → 대신 내어 줄 호스트 경로(`redirect`)
    private var redirects: [String: String] = [:]
    public init(_ export: String) {
        self.export = export
        nodes = [Node("", .directory, 0, nil, .directory(0), false)]
    }
    public static func new(_ export: String) -> Vfs { Vfs(export) }
    public func clone() -> Vfs {
        let copy = Vfs(export)
        copy.nodes = nodes
        copy.roots = roots
        copy.tracks = tracks
        copy.redirects = redirects
        copy.id_base = id_base
        return copy
    }
    public func export_name() -> String { export }
    public func root() -> Int { 0 }
    public func len() -> Int { nodes.count }
    public func is_empty() -> Bool { nodes.count <= 1 && roots.isEmpty }
    public func allow_folder(_ path: String, _ host: String) {
        let parts = parts_of(path)
        guard !parts.isEmpty,
            !roots.contains(where: { $0.parts.map { Array($0.utf8) } == parts.map { Array($0.utf8) } })
        else { return }
        roots.append(Root(parts: parts, host: host))
    }
    /// 그 원본 파일을 찾으면 다른 호스트 파일을 내어 준다(크기·내용이 그 파일 것이다). 원본에 없는 입구다.
    /// 플레이어가 곡 정보를 곡 번호별로 기억해 바꾼 경로 대신 원본 이름으로 다시 찾을 때 쓴다(CDJ-2000nexus 실기).
    /// 이미 찾은 노드도 그 자리에서 바꾼다. 새 노드로 이름 자리만 바꾸면 nexus가 싣는 도중 옛 핸들과 섞어 써서 싣기가 멈췄다(2026-10-17 실기).
    /// 그래서 그 원본을 읽던 다른 플레이어도 다음 읽기부터 바꾼 파일을 받는다
    public func redirect(_ host: String, to replacement: String) {
        redirects[host] = replacement
        for index in nodes.indices where nodes[index].kind == .file && nodes[index].source == host {
            nodes[index].source = replacement
            nodes[index].stat = nil
        }
    }
    private func served(_ host: String) -> String { redirects[host] ?? host }
    public func allow_track(_ host: String) { tracks.insert(Array(path_components(host).joined(separator: "\0").utf8)) }
    private func track_path_role(_ path: String) -> (Bool, Bool) {
        let parts = path_components(path).map { Array($0.utf8) }
        let normalized = Array(path_components(path).joined(separator: "\0").utf8)
        // BTreeSet<Path>에서 해당 경로 바로 다음 값만 보는 원본 절차를 보존한다.
        let next = tracks.sorted(by: { $0.lexicographicallyPrecedes($1) }).first {
            normalized.lexicographicallyPrecedes($0)
        }
        let above =
            next.map { $0.split(separator: 0, omittingEmptySubsequences: false).map(Array.init).starts(with: parts) }
            ?? false
        return (tracks.contains(normalized), above)
    }
    private func host_entry(_ dir: String, _ name: String) -> NodeKind? {
        let path = join_path(dir, name)
        guard let meta = host_metadata(path, follow: false) else { return nil }
        if meta.st_mode & S_IFMT == S_IFLNK {
            let (is_track, above) = track_path_role(path)
            guard let target = host_metadata(path), let kind = entry_kind(target) else { return nil }
            return (kind == .file && is_track) || (kind == .directory && above) ? kind : nil
        }
        return entry_kind(meta)
    }
    @discardableResult public func add_file(_ path: String, _ source: String, _ size: UInt64, _ modified: UInt32) -> Int
    { add(path, (source, .plain(size, modified)), .directory(modified)) }
    @discardableResult public func add_file_unsized(_ path: String, _ source: String) -> Int {
        add(path, (source, nil), .directory(0))
    }
    @discardableResult public func add_dir(_ path: String) -> Int { add(path, nil, .directory(0)) }
    private func add(_ path: String, _ file: (String, Stat?)?, _ dir_stat: Stat) -> Int {
        let parts = parts_of(path)
        var at = 0
        if file != nil && parts.isEmpty { return at }
        let directories = file == nil ? parts : Array(parts.dropLast())
        for part in directories { at = insert(at, part, .directory, nil, dir_stat, false) }
        if let file, let last = parts.last { return insert(at, last, .file, file.0, file.1, true) }
        return at
    }
    private func insert(
        _ parent: Int, _ name: String, _ kind: NodeKind, _ source: String?, _ stat: Stat?, _ listed: Bool
    ) -> Int {
        let k = key(name)
        if nodes.indices.contains(parent), let existing = nodes[parent].by_name[k] { return existing }
        let index = nodes.count
        nodes.append(Node(name, kind, parent, source, stat, listed))
        if nodes.indices.contains(parent) {
            nodes[parent].children.append(index)
            nodes[parent].by_name[k] = index
        }
        return index
    }
    public func child(_ parent: Int, _ name: String) -> Int? {
        guard nodes.indices.contains(parent), nodes[parent].kind == .directory else { return nil }
        if name == "." { return parent }
        if name == ".." { return nodes[parent].parent }
        if let existing = nodes[parent].by_name[key(name)] { return existing }
        guard !nodes[parent].listed, is_plain_name(name) else { return nil }
        if let dir = nodes[parent].source {
            let composed = name.precomposedStringWithCanonicalMapping
            let found: NodeKind
            let as_named: String
            if let kind = host_entry(dir, name) {
                found = kind
                as_named = name
            } else if !composed.utf8.elementsEqual(name.utf8), let kind = host_entry(dir, composed) {
                found = kind
                as_named = composed
            } else {
                return nil
            }
            let host = join_path(dir, as_named)
            return insert(parent, as_named, found, found == .file ? served(host) : host, nil, found == .file)
        }
        let path = path_of(parent) + [key(name)]
        let depth = path.count
        guard
            let root = roots.first(where: {
                $0.parts.count >= depth && zip($0.parts.map(key), path).allSatisfy { pair in pair.0 == pair.1 }
            })
        else { return nil }
        let host = root.parts.count == depth ? root.host : nil
        return insert(parent, root.parts[depth - 1], .directory, host, host == nil ? .directory(0) : nil, false)
    }
    private func path_of(_ index: Int) -> [String] {
        var at = index
        var parts: [String] = []
        while at != 0 {
            guard nodes.indices.contains(at) else { break }
            parts.append(key(nodes[at].name))
            at = nodes[at].parent
        }
        return parts.reversed()
    }
    public func children(_ index: Int) -> [Int] {
        guard nodes.indices.contains(index) else { return [] }
        if nodes[index].listed || nodes[index].kind != .directory { return nodes[index].children }
        if let dir = nodes[index].source {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            let entries = names.filter(is_plain_name).compactMap { name -> (String, NodeKind)? in
                host_entry(dir, name).map { (name, $0) }
            }.sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
            for (name, kind) in entries {
                let host = join_path(dir, name)
                _ = insert(index, name, kind, kind == .file ? served(host) : host, nil, kind == .file)
            }
        } else {
            let path = path_of(index)
            let depth = path.count
            var next: [(String, String?)] = []
            var seen: Set<String> = []
            for root in roots {
                guard root.parts.count > depth, zip(root.parts.map(key), path).allSatisfy({ pair in pair.0 == pair.1 })
                else { continue }
                let name = root.parts[depth]
                if seen.insert(key(name)).inserted {
                    next.append((name, root.parts.count == depth + 1 ? root.host : nil))
                }
            }
            // 원본 children의 host 노드에도 synthetic stat을 저장하지만 attributes는 host stat을 우선한다.
            for (name, host) in next { _ = insert(index, name, .directory, host, .directory(0), false) }
        }
        nodes[index].listed = true
        return nodes[index].children
    }
    public func wire_name(_ index: Int) -> String? {
        guard let name = name(index) else { return nil }
        #if canImport(Darwin)
            return key(name)
        #else
            return name
        #endif
    }
    public func resolve(_ path: String) -> Int? {
        var at = root()
        for part in path.components(separatedBy: "/") where !part.isEmpty {
            guard let next = child(at, part) else { return nil }
            at = next
        }
        return at
    }
    public func kind(_ index: Int) -> NodeKind? { nodes.indices.contains(index) ? nodes[index].kind : nil }
    public func name(_ index: Int) -> String? { nodes.indices.contains(index) ? nodes[index].name : nil }
    public func source(_ index: Int) -> String? { nodes.indices.contains(index) ? nodes[index].source : nil }
    public func attributes(_ index: Int) -> Attributes? {
        guard nodes.indices.contains(index) else { return nil }
        let node = nodes[index]
        let value = node.source.map(stat_file) ?? node.stat ?? .directory(0)
        return Attributes(
            kind: node.kind, size: value.size, fileid: fileid(index), modified: value.modified, stat: value)
    }
    private func fileid(_ index: Int) -> UInt32 {
        guard let own = UInt32(exactly: index + 1) else { return .max }
        let (value, overflow) = own.addingReportingOverflow(id_base)
        return overflow ? .max : value
    }
    public func handle(_ index: Int) -> Handle? {
        guard nodes.indices.contains(index) else { return nil }
        return Handle(
            Xdr.Writer().u32(fileid(index)).u32(fileid(nodes[index].parent)).u32(fileid(root())).into_bytes()
                + Array(repeating: 0, count: 20))
    }
    public func node_of(_ handle: Handle) -> Int? {
        let reader = Xdr.Reader(handle.as_bytes())
        guard let own = try? reader.u32(), let parent = try? reader.u32(), let root = try? reader.u32(), own > id_base
        else { return nil }
        let index = Int(own - id_base - 1)
        guard nodes.indices.contains(index), parent == fileid(nodes[index].parent), root == fileid(self.root()) else {
            return nil
        }
        return index
    }
}

@DJLinkActor
public final class Exports {
    private var by_name: [[UInt8]: Vfs] = [:]
    public init() {}
    public static func new() -> Exports { Exports() }
    public func clone() -> Exports {
        let copy = Exports()
        for (name, vfs) in by_name { copy.by_name[name] = vfs.clone() }
        return copy
    }
    public func insert(_ vfs: Vfs) {
        let count = UInt32(exactly: by_name.count) ?? .max
        let (base, overflow) = count.multipliedReportingOverflow(by: 1 << 24)
        // Rust는 Vfs 값을 이동한다. Swift에서도 삽입 시 사본을 두어 소유권을 보존한다.
        let owned = vfs.clone()
        owned.id_base = overflow ? .max : base
        by_name[Array(owned.export_name().utf8)] = owned
    }
    public func get(_ name: String) -> Vfs? { by_name[Array(name.utf8)] }
    public func names() -> [String] {
        by_name.keys.sorted { $0.lexicographicallyPrecedes($1) }.map { String(decoding: $0, as: UTF8.self) }
    }
    public func is_empty() -> Bool { by_name.isEmpty }
    /// 모든 내보내기에서 그 원본 파일 대신 다른 파일을 내어 준다(`Vfs.redirect`)
    public func redirect(_ host: String, to replacement: String) {
        for vfs in by_name.values { vfs.redirect(host, to: replacement) }
    }
}
