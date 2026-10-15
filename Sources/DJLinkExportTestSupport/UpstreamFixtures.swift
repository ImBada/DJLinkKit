// SPDX-License-Identifier: GPL-2.0-or-later
// 원본의 민감할 수 있는 캡처는 공개 저장소에 복사하지 않고 고정 원본에서 그대로 읽는다.
import Foundation

public enum UpstreamFixtures {
    public static let commit = "90bfb53da59c5b2c3f0b76101601f30a6b74ab2b"

    public static func root() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let path = env["DJLINK_EXPORT_UPSTREAM_DIR"] { return URL(fileURLWithPath: path) }
        if let path = env["UPSTREAM_DIR"] { return URL(fileURLWithPath: path).appendingPathComponent("rbxport") }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("src/upstream/rbxport")
    }

    public static func bytes(crate: String, path: String) throws -> [UInt8] {
        guard !crate.contains("/"), !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            throw FixtureError.invalidPath
        }
        let url = root().appendingPathComponent("crates").appendingPathComponent(crate).appendingPathComponent(path)
        return Array(try Data(contentsOf: url))
    }

    public static func text(crate: String, path: String) throws -> String {
        String(decoding: try bytes(crate: crate, path: path), as: UTF8.self)
    }

    public enum FixtureError: Error { case invalidPath }
}
