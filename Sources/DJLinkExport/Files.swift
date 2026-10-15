import DJLinkExportModel
import DJLinkExportNFS
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-link/src/files.rs (90bfb53).
import DJLinkKit

public enum Files {
    @DJLinkActor public static func exports(_ library: Library) -> Exports {
        let exports = Exports.new()
        var trees: [Vfs] = []
        for row in 0..<library.len() {
            let path = library.folder_path.get(row)
            guard let (export, relative) = split(path) else { continue }
            let tree: Vfs
            if let existing = trees.first(where: { $0.export_name() == export }) {
                tree = existing
            } else {
                tree = Vfs.new(export)
                trees.append(tree)
            }
            if let (folder, host) = root_of(path, relative) {
                tree.allow_folder(folder, host)
                tree.allow_track(path)
            } else {
                tree.add_file_unsized(relative, path)
            }
        }
        for tree in trees { exports.insert(tree) }
        return exports
    }
    static func root_of(_ path: String, _ relative: String) -> (String, String)? {
        let bytes = Array(relative.utf8)
        var end = 0
        var components = 0
        var start = 0
        while start < bytes.count {
            var finish = start
            while finish < bytes.count && bytes[finish] != 47 { finish += 1 }
            if finish > start {
                components += 1
                end = finish
                if components == 3 { break }
            }
            start = finish + 1
        }
        guard components >= 3, bytes.dropFirst(end).contains(where: { $0 != 47 }) else { return nil }
        let folder = String(decoding: bytes.prefix(end), as: UTF8.self)
        let prefix = Array(path.utf8).dropLast(bytes.count)
        return (folder, String(decoding: prefix, as: UTF8.self) + folder)
    }
    public static func split(_ path: String) -> (String, String)? { split_export(path) }
}
