// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbxport/crates/rbl-index/src/file_time.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// 생성 시각만 읽는다. 실제 파일 읽기는 호출자가 이 API를 호출할 때만 일어난다.
import Darwin
import Foundation

public func created_secs(_ path: String) -> Int64? {
    guard !path.isEmpty, !path.utf8.contains(0) else { return nil }
    // std::fs::metadata처럼 마지막 symlink도 따라가 대상의 생성 시각을 읽는다.
    var value = stat()
    guard path.withCString({ stat($0, &value) }) == 0 else { return nil }
    let seconds = Int64(value.st_birthtimespec.tv_sec)
    return seconds < 0 && value.st_birthtimespec.tv_nsec > 0 ? seconds + 1 : seconds
}

extension Library {
    public func file_created(_ row: Row) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return file_created_cache.map { $0.at(Int(row)) ?? nil } ?? created_secs(folder_path.get(Int(row)))
    }
    func file_created_all() -> [Int64?] {
        lock.lock()
        defer { lock.unlock() }
        if let file_created_cache { return file_created_cache }
        // 원본과 다름: 메타데이터 읽기는 Swift에서 직렬로 수행하며 행 순서를 유지한다.
        let all = (0..<count).map { created_secs(folder_path.get($0)) }
        file_created_cache = all
        return all
    }
    func file_created_rank() -> [UInt32] {
        lock.lock()
        defer { lock.unlock() }
        if let file_created_rank_cache { return file_created_rank_cache }
        let rank = column_rank(.fileCreated)
        file_created_rank_cache = rank
        return rank
    }
    func forget_file_created() {
        lock.lock()
        defer { lock.unlock() }
        file_created_cache = nil
        file_created_rank_cache = nil
    }
}
