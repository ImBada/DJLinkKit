import Foundation
import Testing

@testable import djlink

/// 임시 폴더에서만 파일을 만든다(소켓은 열지 않는다).
private func withTemporaryDirectory<T>(_ body: (String) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("djlink-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory.path)
}

private func makeWriter(link: @escaping @Sendable (String, String) -> Int32) -> POSIXFileWriter {
    var writer = POSIXFileWriter()
    writer.link = link
    return writer
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

    @Test("without hard link support the file is created exclusively")
    func fallsBackWithoutLink() throws {
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
