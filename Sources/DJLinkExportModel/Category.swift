// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-index/src/category.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
// Link Export 메뉴의 원본 숫자 범위와 버킷이다.
public func bpm_bucket(_ bpm_x100: UInt32) -> UInt32 { sat_add(bpm_x100, 50) / 100 * 100 }
private func descending(_ values: [UInt32]) -> [UInt32] { Array(Set(values)).sorted(by: >) }
extension Library {
    public func bpm_buckets() -> [UInt32] {
        Array(Set(bpm_x100.filter { $0 != 0 && $0 <= 49_949 }.map(bpm_bucket))).sorted()
    }
    public func bpm_matches(_ row: Row, _ selected_x100: UInt32, _ tolerance_pct: UInt32) -> Bool {
        guard let bpm = bpm_x100.at(Int(row)), bpm != 0, bpm <= 49_949 else { return false }
        if tolerance_pct == 0 { return bpm_bucket(bpm) == selected_x100 }
        let spread = UInt32(exactly: UInt64(selected_x100) * UInt64(tolerance_pct) / 100) ?? .max
        return (selected_x100 >= spread ? selected_x100 - spread : 0) <= bpm && bpm <= sat_add(selected_x100, spread)
    }
    public func bitrates() -> [UInt32] { descending(Array(bitrate.prefix(count))) }
    public func bitrate_matches(_ row: Row, _ bitrate: UInt32) -> Bool { self.bitrate.at(Int(row)) == bitrate }
    public func ratings() -> [UInt32] { descending(rating.prefix(count).map(UInt32.init)) }
    public func rating_matches(_ row: Row, _ rating: UInt32) -> Bool {
        self.rating.at(Int(row)).map(UInt32.init) == rating
    }
    public func color_ids() -> [UInt32] { Array(1...8) }
    public func color_matches(_ row: Row, _ color: UInt32) -> Bool {
        (1...8).contains(color) && self.color.at(Int(row)).map(UInt32.init) == color
    }
    public func duration_minute_buckets() -> [UInt32] {
        descending(length_sec.prefix(count).filter { $0 <= 10_799 }.map { $0 / 60 })
    }
    public func duration_minute_matches(_ row: Row, _ minute: UInt32) -> Bool {
        length_sec.at(Int(row)).map { $0 <= 10_799 && $0 / 60 == minute } ?? false
    }
    public func release_decades() -> [UInt32] {
        descending(year.prefix(count).filter { $0 != 0 && $0 <= 2999 }.map { UInt32($0 / 10 * 10) })
    }
    public func release_years(_ decade: UInt32) -> [UInt32] {
        descending(
            year.prefix(count).filter { $0 != 0 && $0 <= 2999 }.map(UInt32.init).filter { $0 / 10 * 10 == decade })
    }
    public func release_year_matches(_ row: Row, _ year: UInt32) -> Bool {
        year != 0 && year <= 2999 && self.year.at(Int(row)).map(UInt32.init) == year
    }
    public func filename_rows() -> [Row] {
        var rows = (0..<count).compactMap(Row.init(exactly:))
        // View의 문자열 열처럼 UTF-8 키를 행마다 한 번만 만들고 동률은 행 순서로 정한다.
        var keys = [[UInt8]](repeating: [], count: count)
        for row in rows { keys[Int(row)] = Array(fold(file_name.get(Int(row))).utf8) }
        rows.sort { a, b in
            let x = keys[Int(a)]
            let y = keys[Int(b)]
            return x == y ? a < b : x.lexicographicallyPrecedes(y)
        }
        return rows
    }
}
