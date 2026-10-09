import Darwin
import Foundation

// 파일을 쓰는 곳. 이미 있는 파일은 어떤 경우에도 덮어쓰지 않는다. 시험은 가짜나 임시 폴더를 쓴다.

/// 쓰려는 파일이 이미 있다.
struct CLIFileExistsError: Error, Equatable, Sendable {
    var path: String
}

/// 파일 시스템 호출 실패. 메시지는 사용자에게 그대로 보인다.
struct CLIFileError: Error, Equatable, Sendable, CustomStringConvertible {
    var message: String

    var description: String { message }
}

protocol CLIFileWriter: Sendable {
    func fileExists(atPath path: String) -> Bool
    /// 폴더가 없으면 만든다(중간 폴더 포함).
    func createDirectory(atPath path: String) throws
    /// `path`에 `data`를 쓴다. 이미 있으면 `CLIFileExistsError`를 던지고 아무것도 바꾸지 않는다.
    /// 중간에 실패하면 반쯤 쓴 파일을 남기지 않는다.
    func publishWithoutOverwriting(_ data: [UInt8], toPath path: String, checkCancellation: @Sendable () throws -> Void)
        throws
}

extension CLIFileWriter {
    func publishWithoutOverwriting(_ data: [UInt8], toPath path: String) throws {
        try publishWithoutOverwriting(data, toPath: path, checkCancellation: {})
    }
}

/// POSIX 호출로 쓴다. `.atomic`과 `.withoutOverwriting`은 같이 쓸 수 없어서(NSData.h),
/// 같은 폴더의 임시 파일에 먼저 쓰고 `link(2)`로 게시한다. `link`는 대상이 있으면 `EEXIST`로 실패한다.
/// `link`를 지원하지 않는 파일 시스템(FAT 등)에서는 `O_EXCL`로 만든 파일에 직접 쓴다(덮어쓰지는 않지만 원자적이지는 않다).
struct POSIXFileWriter: CLIFileWriter {
    /// 시험이 `link` 실패를 만들어 보려고 바꿔 넣는다.
    var link: @Sendable (_ existing: String, _ new: String) -> Int32 = { Darwin.link($0, $1) }

    init() {}

    func fileExists(atPath path: String) -> Bool {
        var info = stat()
        // 끊어진 심볼릭 링크도 있는 것으로 본다.
        return lstat(path, &info) == 0
    }

    func createDirectory(atPath path: String) throws {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw CLIFileError(message: "폴더를 만들지 못했다: \(path) (\(error.localizedDescription))")
        }
    }

    func publishWithoutOverwriting(_ data: [UInt8], toPath path: String, checkCancellation: @Sendable () throws -> Void)
        throws
    {
        try checkCancellation()
        // 이미 있으면 임시 파일도 만들지 않는다. 그 사이에 생기는 경우는 아래 `link`/`O_EXCL`이 막는다.
        if fileExists(atPath: path) { throw CLIFileExistsError(path: path) }
        let directory = (path as NSString).deletingLastPathComponent
        let temporary =
            (directory.isEmpty ? "." : directory) + "/.djlink-\(getpid())-\(UUID().uuidString).tmp"
        let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        guard fd >= 0 else { throw Self.error("임시 파일을 만들지 못했다", temporary) }
        // 게시에 성공해도 임시 이름은 지운다(하드 링크라 게시한 파일은 남는다).
        defer { unlink(temporary) }
        do {
            try Self.writeAll(fd, data, path: temporary, checkCancellation: checkCancellation)
            guard fsync(fd) == 0 else { throw Self.error("임시 파일을 디스크에 쓰지 못했다", temporary) }
        } catch {
            close(fd)
            throw error
        }
        guard close(fd) == 0 else { throw Self.error("임시 파일을 닫지 못했다", temporary) }

        try checkCancellation()
        if link(temporary, path) == 0 { return }
        switch errno {
        case EEXIST:
            throw CLIFileExistsError(path: path)
        case ENOTSUP, EPERM, ENOSYS, EXDEV:
            // 하드 링크를 지원하지 않는 파일 시스템.
            try Self.createExclusively(data, path: path, checkCancellation: checkCancellation)
        default:
            throw Self.error("파일을 게시하지 못했다", path)
        }
    }

    private static func createExclusively(_ data: [UInt8], path: String, checkCancellation: @Sendable () throws -> Void)
        throws
    {
        try checkCancellation()
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        guard fd >= 0 else {
            if errno == EEXIST || errno == ELOOP { throw CLIFileExistsError(path: path) }
            throw error("파일을 만들지 못했다", path)
        }
        do {
            try writeAll(fd, data, path: path, checkCancellation: checkCancellation)
            try checkCancellation()
        } catch {
            // 이 호출이 만든 파일이므로 지워도 된다.
            close(fd)
            unlink(path)
            throw error
        }
        guard close(fd) == 0 else {
            unlink(path)
            throw error("파일을 닫지 못했다", path)
        }
    }

    private static func writeAll(
        _ fd: Int32, _ data: [UInt8], path: String, checkCancellation: @Sendable () throws -> Void
    ) throws {
        var offset = 0
        while offset < data.count {
            try checkCancellation()
            let written = data.withUnsafeBytes { raw in
                write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw error("파일에 쓰지 못했다", path)
            }
            if written == 0 { throw CLIFileError(message: "파일 쓰기가 진행되지 않았다: \(path)") }
            offset += written
        }
    }

    private static func error(_ what: String, _ path: String) -> CLIFileError {
        CLIFileError(message: "\(what): \(path) (\(String(cString: strerror(errno))))")
    }
}
