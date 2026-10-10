// DJCrate CipherDatabase.swift(MIT)에서 필요한 연결·초기화·질의 부분을 옮겼다.
import Foundation
import SQLCipher

/// SQLCipher 키. 둘 다 `PRAGMA key = '<키>'`로 넣으므로 글자를 좁혀 SQL 문자열에 넣어도 안전하게 한다.
public enum CipherKey: Sendable {
    /// 로컬 `master.db`: 16진수 글자만
    case hex(String)
    /// USB OneLibrary(`exportLibrary.db`): `[A-Za-z0-9]`만, 빈 문자열 금지
    case passphrase(String)

    /// `PRAGMA key` 문장. 허용하지 않는 글자가 있으면 오류를 던진다.
    func pragma() throws -> String {
        switch self {
        case .hex(let key):
            guard key.allSatisfy(\.isHexDigit) else {
                throw DJLinkError("Invalid encryption key derived")
            }
            return "PRAGMA key = '\(key)'"
        case .passphrase(let key):
            guard !key.isEmpty,
                key.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) })
            else { throw DJLinkError("Invalid encryption key derived") }
            return "PRAGMA key = '\(key)'"
        }
    }
}

/// DB를 여는 방식
public enum OpenMode: Sendable {
    /// 읽기 전용(`query_only`)
    case readOnly
    case readWrite
    /// 새 파일만 만든다. 이미 있는 파일이면 실패
    case create
}

/// SQLCipher C API를 감싼 연결. OneLibrary는 읽기 전용으로, 합성 시험 DB는 만들기 모드로 연다.
public final class CipherDatabase {
    private var handle: OpaquePointer?

    /// SQLCipher는 `sqlite3_initialize` 안에서 자기 전역 초기화(정적 뮤텍스·암호 제공자)를 마치는데, 그 초기화가 끝나기 전에
    /// 다른 스레드의 `sqlite3_initialize`가 "이미 됨"으로 돌아온다. 프로세스에서 처음 여는 순간 스레드가 겹치면 뒤늦게 들어온 스레드가
    /// `PRAGMA key`에서 "sqlcipher not initialized"로 실패했다(#154). `static let`은 처음 부른 스레드가 끝낼 때까지 다른 스레드를
    /// 기다리게 하므로, 여는 곳마다 먼저 거치면 초기화가 끝난 뒤에만 열린다.
    private static let sqlcipherReady: Void = { _ = sqlite3_initialize() }()

    /// 기존 호출(16진수 키)은 이 모양 그대로 쓴다.
    public convenience init(path: String, key: String?, writable: Bool = false) throws {
        try self.init(path: path, key: key.map { .hex($0) }, mode: writable ? .readWrite : .readOnly)
    }

    public init(
        path: String, key: CipherKey?, mode: OpenMode, validate: Bool = true,
        cipherCompatibility: Int? = nil
    ) throws {
        // 키 글자는 파일을 열기 전에 본다(거부할 키로 새 파일을 만들지 않게).
        let pragma = try key?.pragma()
        let flags: Int32
        switch mode {
        case .readOnly: flags = SQLITE_OPEN_READONLY
        case .readWrite: flags = SQLITE_OPEN_READWRITE
        case .create:
            if path != ":memory:", FileManager.default.fileExists(atPath: path) {
                throw DJLinkError("Database already exists: \(path)")
            }
            flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        }
        Self.sqlcipherReady
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close_v2(handle)
            handle = nil  // deinit이 한 번 더 닫지 않도록
            throw DJLinkError("Database open failed: \(path): \(message)")
        }
        if let pragma { try execute(pragma) }
        if let cipherCompatibility {
            try execute("PRAGMA cipher_compatibility = \(cipherCompatibility)")
        }
        if mode == .readOnly {
            try execute("PRAGMA query_only = ON")
        } else {
            sqlite3_busy_timeout(handle, 2000)
        }
        try? execute("PRAGMA cache_size = -65536")
        try? execute("PRAGMA temp_store = MEMORY")
        if validate {
            do {
                _ = try scalarInt("SELECT count(*) FROM sqlite_master")
            } catch {
                throw DJLinkError("Database open failed: \(path): invalid key or corrupt database")
            }
        }
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// 연결을 바로 닫는다(쓰기 뒤 파일을 다시 열어 검사하기 전에 쓴다).
    public func close() {
        sqlite3_close_v2(handle)
        handle = nil
    }

    public func execute(_ sql: String) throws {
        guard handle != nil else { throw DJLinkError("The database connection is not open") }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw DJLinkError(message)
        }
    }

    /// 자리표시자(`?`)에 넣을 값
    public enum Value: Sendable, Equatable, ExpressibleByIntegerLiteral, ExpressibleByStringLiteral,
        ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral
    {
        public init(integerLiteral value: Int) { self = .int(value) }
        public init(stringLiteral value: String) { self = .text(value) }
        public init(floatLiteral value: Double) { self = .real(value) }
        public init(booleanLiteral value: Bool) { self = .int(value ? 1 : 0) }
        public init(nilLiteral: ()) { self = .null }
        case blob([UInt8])
        case text(String)
        case int(Int)
        case real(Double)
        case null
    }

    public func query(_ sql: String, _ values: [Value] = [], _ each: (Row) throws -> Void) throws {
        guard handle != nil else { throw DJLinkError("The database connection is not open") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DJLinkError(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let result =
                switch value {
                case .text(let text):
                    sqlite3_bind_text(statement, position, text, Int32(text.utf8.count), transient)
                case .int(let number): sqlite3_bind_int64(statement, position, Int64(number))
                case .real(let number): sqlite3_bind_double(statement, position, number)
                case .blob(let bytes):
                    bytes.isEmpty
                        ? sqlite3_bind_zeroblob(statement, position, 0)
                        : bytes.withUnsafeBytes {
                            sqlite3_bind_blob(statement, position, $0.baseAddress, Int32($0.count), transient)
                        }
                case .null: sqlite3_bind_null(statement, position)
                }
            guard result == SQLITE_OK else {
                throw DJLinkError(String(cString: sqlite3_errmsg(handle)))
            }
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                try each(Row(statement: statement))
            case SQLITE_DONE:
                return
            default:
                throw DJLinkError(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    /// 값을 넣어 한 문장을 실행하고 바뀐 행 수를 돌려준다.
    @discardableResult
    public func run(_ sql: String, _ values: [Value]) throws -> Int {
        try query(sql, values) { _ in }
        return Int(sqlite3_changes(handle))
    }

    public func scalarInt(_ sql: String) throws -> Int {
        var value = 0
        try query(sql) { value = $0.int(0) ?? 0 }
        return value
    }

    public func rows(_ sql: String, _ values: [Value] = []) throws -> [LocalDBRow] {
        var rows: [LocalDBRow] = []
        try query(sql, values) { row in
            var item: LocalDBRow = [:]
            for i in 0..<row.count {
                let c = Int32(i)
                switch sqlite3_column_type(row.statement, c) {
                case SQLITE_INTEGER: item[row.name(c)] = .int(row.int(c)!)
                case SQLITE_FLOAT: item[row.name(c)] = .real(row.double(c)!)
                case SQLITE_TEXT: item[row.name(c)] = .text(row.string(c)!)
                case SQLITE_BLOB: item[row.name(c)] = .blob(row.blob(c)!)
                default: item[row.name(c)] = .null
                }
            }
            rows.append(item)
        }
        return rows
    }

    public struct Row {
        let statement: OpaquePointer?

        public func string(_ column: Int32) -> String? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL,
                let text = sqlite3_column_text(statement, column)
            else { return nil }
            return String(
                decoding: UnsafeBufferPointer(
                    start: text, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
        }

        public var count: Int { Int(sqlite3_column_count(statement)) }

        /// 칸 이름
        public func name(_ column: Int32) -> String {
            sqlite3_column_name(statement, column).map { String(cString: $0) } ?? ""
        }

        public func blob(_ column: Int32) -> [UInt8]? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
                return nil
            }
            let length = Int(sqlite3_column_bytes(statement, column))
            guard let bytes = sqlite3_column_blob(statement, column) else {
                return []
            }
            return Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: length))
        }

        public func int(_ column: Int32) -> Int? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
            return Int(sqlite3_column_int64(statement, column))
        }

        public func double(_ column: Int32) -> Double? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
            return sqlite3_column_double(statement, column)
        }
    }
}
