// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-dbserver/src/filter.rs inline tests @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportDBServer

@Suite struct FilterTests {
    @Test("property_setters_roundtrip_to_captured_fcnd_records")
    func property_setters_roundtrip_to_captured_fcnd_records() {
        var filter = TrackFilter()
        func set(_ flags: UInt8, _ op: UInt8, _ values: [UInt32]) -> [UInt8] {
            [flags, op, UInt8(values.count), 0] + values.flatMap { dbLE($0) }
        }
        let filterResult0 = filter.update(6, set(1, 6, [12690, 14310]))
        #expect(filterResult0)
        let filterResult1 = filter.update(12, set(1, 17, [19, 20, 17, 21]))
        #expect(filterResult1)
        let filterResult2 = filter.update(7, set(0, 0, [3, 0]))
        #expect(filterResult2)
        let filterResult3 = filter.update(15, set(0, 17, [0]))
        #expect(filterResult3)
        let encoded = filter.encode()
        #expect(
            Array(encoded[..<36]) == [
                36, 0, 0, 0, 1, 0, 0, 0, 70, 67, 78, 68, 0, 0, 0, 20, 0, 0, 0, 28, 0, 0, 0, 6, 1, 6, 0, 2, 0, 0, 49,
                146, 0, 0, 55, 230,
            ])
        filter.enabled = true
        #expect(filter.matches(13000, 19, 0, 0))
        #expect(!filter.matches(12000, 19, 0, 0))
        #expect(!filter.matches(13000, 1, 0, 0))
        let before = filter.encode()
        let filterResult4 = !filter.update(6, [1, 6, 2, 0, 1])
        #expect(filterResult4)
        let filterResult5 = !filter.update(99, set(1, 17, [1]))
        #expect(filterResult5)
        #expect(filter.encode() == before)
    }
    @Test("rating_operators_and_colour_ids_match_the_server_comparisons")
    func rating_operators_and_colour_ids_match_the_server_comparisons() {
        var filter = TrackFilter()
        filter.enabled = true
        let filterResult6 = filter.update(7, [1, 0, 2, 0, 3, 0, 0, 0, 0, 0, 0, 0])
        #expect(filterResult6)
        #expect(filter.matches(12000, 1, 3, 0))
        #expect(!filter.matches(12000, 1, 4, 0))
        let filterResult7 = filter.update(7, [1, 3, 2, 0, 3, 0, 0, 0, 0, 0, 0, 0])
        #expect(filterResult7)
        #expect(filter.matches(12000, 1, 4, 0))
        let filterResult8 = filter.update(15, [1, 17, 2, 0, 2, 0, 0, 0, 5, 0, 0, 0])
        #expect(filterResult8)
        #expect(filter.matches(12000, 1, 4, 5))
        #expect(!filter.matches(12000, 1, 4, 3))
    }
    @Test("my_tag_ticks_stop_at_the_bound_and_stay_out_of_the_property_records")
    func my_tag_ticks_stop_at_the_bound_and_stay_out_of_the_property_records() {
        var filter = TrackFilter()
        let before = filter.encode()
        for tag: UInt32 in 0..<4096 {
            let filterResult9 = filter.tick_my_tag(2, tag, true)
            #expect(filterResult9)
        }
        let filterResult10 = !filter.tick_my_tag(2, UInt32.max - 1, true)
        #expect(filterResult10)
        let filterResult11 = filter.tick_my_tag(2, 0, true)
        #expect(filterResult11)
        #expect(filter.my_tag_condition(2).tags.count == MY_TAG_TICK_LIMIT)
        filter.set_my_tag_condition(2, 1, MY_TAG_OR)
        #expect(filter.encode() == before)
        filter.clear_my_tags(2)
        #expect(filter.my_tag_condition(2).tags == [])
        #expect(filter.my_tag_condition(2).mode == MY_TAG_OR)
        #expect(filter.my_tag_condition(9) == MyTagCondition())
    }
}
