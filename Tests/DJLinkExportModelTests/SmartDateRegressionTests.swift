// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-index/src/smart.rs (자체 회귀)
import Foundation
import Testing

@testable import DJLinkExportModel

@Suite struct SmartDateRegressionTests {
    @Test("오늘 날짜가 비그레고리력 설정에서도 현지 그레고리력 연월일을 반환한다")
    func today_uses_gregorian_components() throws {
        // 2026-10-14 15:30 UTC는 UTC+9에서 다음 날이다.
        let date = Date(timeIntervalSince1970: 1_791_991_800)
        for identifier in [Calendar.Identifier.japanese, .buddhist] {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 9 * 60 * 60))
            #expect(calendar.component(.year, from: date) != 2026)
            #expect(SmartDate.today(date: date, calendar: calendar) == SmartDate(year: 2026, month: 10, day: 15))
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            #expect(SmartDate.today(date: date, calendar: calendar) == SmartDate(year: 2026, month: 10, day: 14))
        }
    }
}
