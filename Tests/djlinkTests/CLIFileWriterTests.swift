import Foundation
import Synchronization
import Testing

@testable import djlink

/// 임시 폴더에서만 파일을 만든다(소켓은 열지 않는다).
private func withTemporaryDirectory<T>(_ body: (String) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("djlink-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory.path)
}

private func makeWriter(
    link: @escaping @Sendable (String, String) -> Int32,
    renameExclusively: (@Sendable (String, String) -> Int32)? = nil
) -> POSIXFileWriter {
    var writer = POSIXFileWriter()
    writer.link = link
    if let renameExclusively { writer.renameExclusively = renameExclusively }
    return writer
}

/// `link`와 덮어쓰지 않는 이름 바꾸기가 모두 지원되지 않는 파일 시스템(FAT 계열 가정).
private func makeLinklessWriter() -> POSIXFileWriter {
    makeWriter(
        link: { _, _ in
            errno = ENOTSUP
            return -1
        },
        renameExclusively: { _, _ in
            errno = ENOTSUP
            return -1
        })
}

/// 호출 횟수를 세다가 `limit`번째 호출부터 던지는 취소 검사.
private final class CancelAfter: Sendable {
    let calls = Mutex(0)
    let limit: Int

    init(_ limit: Int) { self.limit = limit }

    func check() throws {
        let count = calls.withLock { count in
            count += 1
            return count
        }
        if count >= limit { throw CLIAborted() }
    }
}

private func names(in directory: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory).sorted()
}

@Suite("CLI file writer")
struct CLIFileWriterTests {
    @Test("a new file is published with its content and no temporary file is left")
    func publishes() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let writer = POSIXFileWriter()
            let path = directory + "/export.pdb"
            #expect(!writer.fileExists(atPath: path))
            try writer.publishWithoutOverwriting([1, 2, 3, 4], toPath: path)
            #expect(writer.fileExists(atPath: path))
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data([1, 2, 3, 4]))
            #expect(try names(in: directory) == ["export.pdb"])
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            #expect((attributes[.posixPermissions] as? Int ?? 0) & 0o022 == 0, "다른 사용자가 쓸 수 없다")
        }
    }

    @Test("an empty file can be published")
    func publishesEmpty() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            try POSIXFileWriter().publishWithoutOverwriting([], toPath: directory + "/empty")
            #expect(try names(in: directory) == ["empty"])
        }
    }

    @Test("an existing file is never overwritten and nothing else is left behind")
    func refusesExisting() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let writer = POSIXFileWriter()
            let path = directory + "/a.bin"
            try Data([9, 9]).write(to: URL(fileURLWithPath: path))
            #expect(throws: CLIFileExistsError(path: path)) {
                try writer.publishWithoutOverwriting([1, 2, 3], toPath: path)
            }
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data([9, 9]))
            #expect(try names(in: directory) == ["a.bin"])
        }
    }

    @Test("a dangling symlink counts as existing and is not followed")
    func refusesSymlink() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let writer = POSIXFileWriter()
            let path = directory + "/link"
            let target = directory + "/target"
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
            #expect(writer.fileExists(atPath: path))
            #expect(throws: CLIFileExistsError(path: path)) { try writer.publishWithoutOverwriting([1], toPath: path) }
            #expect(!FileManager.default.fileExists(atPath: target))
        }
    }

    @Test("a file that appears between the check and the publish is not overwritten")
    func losesTheRace() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let path = directory + "/raced.bin"
            let writer = makeWriter(link: { existing, new in
                FileManager.default.createFile(atPath: new, contents: Data([7]))
                return Darwin.link(existing, new)
            })
            #expect(throws: CLIFileExistsError.self) { try writer.publishWithoutOverwriting([1, 2, 3], toPath: path) }
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data([7]))
            #expect(try names(in: directory) == ["raced.bin"])
        }
    }

    @Test("a link that reports EEXIST leaves the existing file alone")
    func linkExists() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let path = directory + "/exists.bin"
            let writer = makeWriter(link: { _, new in
                FileManager.default.createFile(atPath: new, contents: Data([5]))
                errno = EEXIST
                return -1
            })
            #expect(throws: CLIFileExistsError(path: path)) { try writer.publishWithoutOverwriting([1], toPath: path) }
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data([5]))
            #expect(try names(in: directory) == ["exists.bin"])
        }
    }

    @Test("without hard link support the file is published by an exclusive rename")
    func renamesWithoutLink() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let writer = makeWriter(link: { _, _ in
                errno = ENOTSUP
                return -1
            })
            let path = directory + "/fat.bin"
            try writer.publishWithoutOverwriting([4, 5, 6], toPath: path)
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data([4, 5, 6]))
            #expect(try names(in: directory) == ["fat.bin"])
        }
    }

    @Test("an exclusive rename never replaces a file that appeared in the meantime")
    func renameKeepsExisting() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let path = directory + "/fat.bin"
            let writer = makeWriter(
                link: { _, _ in
                    errno = ENOTSUP
                    return -1
                },
                renameExclusively: { existing, new in
                    FileManager.default.createFile(atPath: new, contents: Data([3]))
                    return renamex_np(existing, new, UInt32(RENAME_EXCL))
                })
            #expect(throws: CLIFileExistsError(path: path)) { try writer.publishWithoutOverwriting([1], toPath: path) }
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data([3]))
            #expect(try names(in: directory) == ["fat.bin"])
        }
    }

    @Test("only when neither link nor an exclusive rename works is the file created exclusively")
    func fallsBackToDirectWrite() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let path = directory + "/fat.bin"
            try makeLinklessWriter().publishWithoutOverwriting([4, 5, 6], toPath: path)
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data([4, 5, 6]))
            #expect(try names(in: directory) == ["fat.bin"])
        }
    }

    @Test("the direct write refuses a file that appeared in the meantime")
    func directWriteKeepsExisting() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let path = directory + "/fat.bin"
            let writer = makeWriter(
                link: { _, _ in
                    errno = ENOTSUP
                    return -1
                },
                renameExclusively: { _, new in
                    FileManager.default.createFile(atPath: new, contents: Data([8]))
                    errno = ENOTSUP
                    return -1
                })
            #expect(throws: CLIFileExistsError(path: path)) { try writer.publishWithoutOverwriting([1], toPath: path) }
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data([8]))
            #expect(try names(in: directory) == ["fat.bin"])
        }
    }

    @Test("the fallback also refuses a file that appeared in the meantime")
    func fallbackKeepsExisting() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let path = directory + "/fat.bin"
            let writer = makeWriter(link: { _, new in
                FileManager.default.createFile(atPath: new, contents: Data([8]))
                errno = EPERM
                return -1
            })
            #expect(throws: CLIFileExistsError(path: path)) { try writer.publishWithoutOverwriting([1], toPath: path) }
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data([8]))
            #expect(try names(in: directory) == ["fat.bin"])
        }
    }

    @Test("a large write is cut into 1 MiB pieces with a cancellation check between them")
    func writesInChunks() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let size = 3 * POSIXFileWriter.writeChunkSize + 5
            let check = CancelAfter(Int.max)
            try POSIXFileWriter().publishWithoutOverwriting(
                [UInt8](repeating: 7, count: size), toPath: directory + "/big.bin",
                checkCancellation: { try check.check() })
            // 시작·쓰기 4조각·게시 직전.
            #expect(check.calls.withLock { $0 } >= 6)
            let attributes = try FileManager.default.attributesOfItem(atPath: directory + "/big.bin")
            #expect(attributes[.size] as? Int == size)
        }
    }

    @Test("a cancellation in the middle of the temporary write leaves neither temporary nor final file")
    func cancelledDuringTemporaryWrite() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let check = CancelAfter(4)
            let data = [UInt8](repeating: 1, count: 3 * POSIXFileWriter.writeChunkSize)
            #expect(throws: CLIAborted.self) {
                try POSIXFileWriter().publishWithoutOverwriting(
                    data, toPath: directory + "/big.bin", checkCancellation: { try check.check() })
            }
            #expect(check.calls.withLock { $0 } == 4)
            #expect(try names(in: directory).isEmpty)
        }
    }

    @Test("a cancellation in the middle of the direct write removes the half-written final file")
    func cancelledDuringDirectWrite() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            // 호출 순서: 시작(1)·임시 쓰기 2조각(2~3)·링크 직전(4)·이름 바꾸기 직전(5)·직접 쓰기 시작(6)·첫 조각(7)·둘째 조각 전(8).
            let check = CancelAfter(8)
            let finalFileSeenBeforeCancel = Mutex(false)
            let path = directory + "/big.bin"
            let data = [UInt8](repeating: 1, count: 2 * POSIXFileWriter.writeChunkSize)
            #expect(throws: CLIAborted.self) {
                try makeLinklessWriter().publishWithoutOverwriting(
                    data, toPath: path,
                    checkCancellation: {
                        if check.calls.withLock({ $0 }) == 7 {
                            finalFileSeenBeforeCancel.withLock { $0 = FileManager.default.fileExists(atPath: path) }
                        }
                        try check.check()
                    })
            }
            #expect(finalFileSeenBeforeCancel.withLock { $0 }, "최종 이름에 반쯤 쓴 파일이 있었다")
            #expect(try names(in: directory).isEmpty)
        }
    }

    @Test("a failed publish leaves no temporary file")
    func failedPublishCleansUp() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let writer = makeWriter(link: { _, _ in
                errno = EIO
                return -1
            })
            #expect(throws: CLIFileError.self) { try writer.publishWithoutOverwriting([1], toPath: directory + "/x") }
            #expect(try names(in: directory).isEmpty)
        }
    }

    @Test("a missing parent folder is an error, not a silent create")
    func missingParent() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            #expect(throws: CLIFileError.self) {
                try POSIXFileWriter().publishWithoutOverwriting([1], toPath: directory + "/nope/x")
            }
        }
    }

    @Test("directories are created with their parents and an existing one is fine")
    func createsDirectories() throws {
        try withTemporaryDirectory { (directory: String) throws -> Void in
            let writer = POSIXFileWriter()
            try writer.createDirectory(atPath: directory + "/a/b")
            try writer.createDirectory(atPath: directory + "/a/b")
            #expect(writer.fileExists(atPath: directory + "/a/b"))
        }
    }
}
