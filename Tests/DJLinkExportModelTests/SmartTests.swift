// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-index/src/smart.rs의 tests
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportModel

private enum SmartTestError: Error { case expectedCondition }
private func smartCondition(_ item: Item) throws -> Condition {
    guard case let .condition(c) = item else { throw SmartTestError.expectedCondition }
    return c
}
private func one(_ property: Property, _ op: Operator, _ left: String, _ right: String, _ unit: String) -> SmartRule {
    SmartRule(root: Group(logic: .all, items: [.condition(Condition.from_editor(property, op, left, right, unit))]))
}
@Suite("smart::tests") struct SmartTests {
    @Test("a_rule_parses_into_its_conditions") func a_rule_parses_into_its_conditions() throws {
        let xml = #"""
            <NODE Id="1" LogicalOperator="2" AutomaticUpdate="1">
                             <CONDITION PropertyName="genre" Operator="8" ValueUnit="" ValueLeft="Tech &amp; House" ValueRight=""/>
                             <CONDITION PropertyName="bpm" Operator="5" ValueUnit="" ValueLeft="120" ValueRight="130"/>
                           </NODE>
            """#
        let rule = try #require(SmartRule.parse(xml))
        #expect(rule.root.logic == .any)
        #expect(rule.root.items.count == 2)
        let first = try smartCondition(rule.root.items[0])
        #expect(first.property == .genre)
        #expect(first.operator == .contains)
        #expect(first.left == "Tech & House")
        #expect(rule.unsupported() == 0)
    }
    @Test("only_direct_conditions_of_the_first_node_are_kept") func only_direct_conditions_of_the_first_node_are_kept()
        throws
    {
        let xml = #"""
            <?xml version="1.0"?><NODE LogicalOperator="1"><NODE LogicalOperator="2">
                           <CONDITION PropertyName="myTag" Operator="1" ValueLeft="7" ValueRight=""/>
                           </NODE><CONDITION PropertyName="rating" Operator="3" ValueLeft="3" ValueRight=""/></NODE>
            """#
        let rule = try #require(SmartRule.parse(xml))
        #expect(rule.root.items.count == 1)
        #expect(try smartCondition(rule.root.items[0]).property == .rating)
        #expect(rule.unsupported() == 0)
        let wrapped = try #require(
            SmartRule.parse(
                #"<NODE LogicalOperator="1"><WRAP><CONDITION PropertyName="rating" Operator="3" ValueLeft="3"/></WRAP></NODE>"#
            ))
        #expect(wrapped.root.items.count == 0)
    }
    @Test("a_smart_document_requires_a_complete_first_node") func a_smart_document_requires_a_complete_first_node() {
        #expect(SmartRule.parse("") == nil)
        #expect(SmartRule.parse("<NODE/>") != nil)
        #expect(SmartRule.parse("\u{feff}<NODE/>") == nil)
        #expect(SmartRule.parse("leading<NODE/>") == nil)
        #expect(SmartRule.parse("\0<NODE/>") == nil)
        #expect(SmartRule.parse("<ROOT><NODE/></ROOT>") == nil)
        #expect(SmartRule.parse("<CONDITION/><NODE/>") == nil)
        #expect(SmartRule.parse("<NODE><CONDITION/>") == nil)
        #expect(SmartRule.parse("<NODE><CONDITION></NODE>") == nil)
        #expect(SmartRule.parse("<!--before--><?probe?><NODE></NODES>") != nil)
    }
    @Test("attributes_follow_rekordbox_case_and_integer_rules")
    func attributes_follow_rekordbox_case_and_integer_rules() throws {
        let rule = try #require(
            SmartRule.parse(
                #"<NODE LogicalOperator="+2"><CONDITION PropertyName="GENRE" Operator="0001" ValueLeft="House"/></NODE>"#
            ))
        #expect(rule.root.logic == .any)
        let first = try smartCondition(rule.root.items[0])
        #expect(first.property == .genre)
        #expect(first.operator == .equal)
        let other = try #require(
            SmartRule.parse(
                #"<NODE logicaloperator="2"><CONDITION PropertyName=" genre " Operator="+1" ValueLeft="House"/></NODE>"#
            ))
        #expect(other.root.logic == .all)
        let second = try smartCondition(other.root.items[0])
        #expect(second.property == .unsupported)
        #expect(second.operator == .equal)
    }
    @Test("a_rule_written_out_reads_back_the_same") func a_rule_written_out_reads_back_the_same() throws {
        let rule = SmartRule(
            root: Group(
                logic: .any,
                items: [
                    .condition(Condition(property: .genre, operator: .contains, left: "Tech & \"House\"")),
                    .condition(Condition(property: .dateAdded, operator: .inLast, left: "30", unit: "day")),
                ]))
        let xml = rule.to_xml(4290236987)
        #expect(
            xml.hasPrefix(
                #"<NODE Id="-4730309" LogicalOperator="2" AutomaticUpdate="0"><CONDITION PropertyName="genre" Operator="8""#
            ))
        #expect(try #require(SmartRule.parse(xml)) == rule)
    }
    @Test("rules_are_written_byte_for_byte_as_rekordbox_writes_them")
    func rules_are_written_byte_for_byte_as_rekordbox_writes_them() throws {
        let cases: [(UInt64, SmartRule, String)] = [
            (
                2_759_501_183, one(.genre, .contains, "House", "", ""),
                #"<NODE Id="-1535466113" LogicalOperator="1" AutomaticUpdate="0"><CONDITION PropertyName="genre" Operator="8" ValueUnit="" ValueLeft="House" ValueRight=""/></NODE>"#
            ),
            (
                3_213_900_474, one(.bpm, .inRange, "120", "126.5", ""),
                #"<NODE Id="-1081066822" LogicalOperator="1" AutomaticUpdate="0"><CONDITION PropertyName="bpm" Operator="5" ValueUnit="0" ValueLeft="12000" ValueRight="12650"/></NODE>"#
            ),
            (
                2_465_685_253, one(.dateAdded, .inLast, "30", "", "day"),
                #"<NODE Id="-1829282043" LogicalOperator="1" AutomaticUpdate="0"><CONDITION PropertyName="stockDate" Operator="6" ValueUnit="day" ValueLeft="30" ValueRight=""/></NODE>"#
            ),
            (
                3_744_254_916, one(.dateAdded, .inLast, "2", "", "month"),
                #"<NODE Id="-550712380" LogicalOperator="1" AutomaticUpdate="0"><CONDITION PropertyName="stockDate" Operator="6" ValueUnit="month" ValueLeft="2" ValueRight=""/></NODE>"#
            ),
            (
                3_632_566_146, one(.rating, .greater, "2", "", ""),
                #"<NODE Id="-662401150" LogicalOperator="1" AutomaticUpdate="0"><CONDITION PropertyName="rating" Operator="3" ValueUnit="" ValueLeft="2" ValueRight="0"/></NODE>"#
            ),
            (
                93_964_985, one(.color, .equal, "1", "", ""),
                #"<NODE Id="93964985" LogicalOperator="1" AutomaticUpdate="0"><CONDITION PropertyName="grouping" Operator="1" ValueUnit="" ValueLeft="1" ValueRight=""/></NODE>"#
            ),
            (
                4_045_890_599, one(.color, .equal, "0", "", ""),
                #"<NODE Id="-249076697" LogicalOperator="1" AutomaticUpdate="0"><CONDITION PropertyName="grouping" Operator="1" ValueUnit="" ValueLeft="0" ValueRight=""/></NODE>"#
            ),
            (
                1_755_093_896, one(.duration, .greater, "300", "", ""),
                #"<NODE Id="1755093896" LogicalOperator="1" AutomaticUpdate="0"><CONDITION PropertyName="duration" Operator="3" ValueUnit="" ValueLeft="300" ValueRight=""/></NODE>"#
            ),
            (
                1_473_708_092,
                SmartRule(
                    root: Group(
                        logic: .any,
                        items: [
                            .condition(Condition.from_editor(.artist, .startsWith, "a", "", "")),
                            .condition(Condition.from_editor(.fileName, .contains, "<&\">", "", "")),
                        ])),
                #"<NODE Id="1473708092" LogicalOperator="2" AutomaticUpdate="0"><CONDITION PropertyName="artist" Operator="10" ValueUnit="" ValueLeft="a" ValueRight=""/><CONDITION PropertyName="fileName" Operator="8" ValueUnit="" ValueLeft="&lt;&amp;&quot;&gt;" ValueRight=""/></NODE>"#
            ),
            (
                745_864_668, one(.dateAdded, .greater, "2020-01-31", "", ""),
                #"<NODE Id="745864668" LogicalOperator="1" AutomaticUpdate="0"><CONDITION PropertyName="stockDate" Operator="3" ValueUnit="" ValueLeft="2020-01-31" ValueRight=""/></NODE>"#
            ),
            (
                3_975_680_467, one(.key, .equal, "Am", "", ""),
                #"<NODE Id="-319286829" LogicalOperator="1" AutomaticUpdate="0"><CONDITION PropertyName="key" Operator="1" ValueUnit="" ValueLeft="Am" ValueRight=""/></NODE>"#
            ),
        ]
        for (id, rule, rekordbox) in cases {
            #expect(rule.to_xml(id) == rekordbox)
            #expect(try #require(SmartRule.parse(rekordbox)) == rule)
        }
    }
    @Test("attribute_values_are_escaped_as_juce_escapes_them") func attribute_values_are_escaped_as_juce_escapes_them()
        throws
    {
        #expect(escape_attribute("<&\">") == "&lt;&amp;&quot;&gt;")
        #expect(escape_attribute("Tom's") == "Tom's")
        #expect(escape_attribute("Caf\u{e9} \u{65e5}\u{1f600}") == "Caf&#233; &#26085;&#128512;")
        #expect(escape_attribute("a\tb\nc\r") == "a&#9;b&#10;c&#13;")
        #expect(escape_attribute("~ !#$%()*+,-./:;=?@[]_{|}") == "~ !#$%()*+,-./:;=?@[]_{|}")
        #expect(escape_attribute("a^b`c") == "a&#94;b&#96;c")
        #expect(escape_attribute("\u{7f}") == "&#127;")
        let rule = one(.title, .contains, "Caf\u{e9} 'x' <&\">\t", "", "")
        #expect(try #require(SmartRule.parse(rule.to_xml(1))) == rule)
    }
    @Test("an_empty_group_closes_itself") func an_empty_group_closes_itself() {
        let rule = SmartRule(root: Group(logic: .all, items: []))
        #expect(rule.to_xml(7) == #"<NODE Id="7" LogicalOperator="1" AutomaticUpdate="0"/>"#)
    }
    @Test("a_bpm_is_stored_in_hundredths_as_rekordbox_stores_it")
    func a_bpm_is_stored_in_hundredths_as_rekordbox_stores_it() throws {
        for (input, expected) in [
            ("120", "12000"), ("126.5", "12650"), ("126.55", "12655"), ("126.559", "12655"), ("126.05", "12605"),
            (".5", "50"), ("128.", "12800"), ("", "0"), (" 98", "9800"),
        ] { #expect(bpm_to_stored(input) == expected) }
        for (input, expected) in [
            ("12000", "120"), ("12650", "126.5"), ("12605", "126.05"), ("120", "1.2"), ("126", "1.26"), ("0", "0"),
        ] { #expect(bpm_for_editor(input) == expected) }
        let c = try smartCondition(one(.bpm, .equal, "128", "", "").root.items[0])
        #expect([c.left, c.right, c.unit] == ["12800", "0", "0"])
        let v = c.editor_values()
        #expect([v.0, v.1, v.2] == ["128", "", ""])
    }
    @Test("a_rating_outside_a_range_stores_zero_on_the_right") func a_rating_outside_a_range_stores_zero_on_the_right()
        throws
    {
        let c = try smartCondition(one(.rating, .equal, "3", "", "").root.items[0])
        #expect(c.right == "0")
        let v = c.editor_values()
        #expect([v.0, v.1, v.2] == ["3", "", ""])
        let ranged = try smartCondition(one(.rating, .inRange, "1", "4", "").root.items[0])
        #expect([ranged.left, ranged.right] == ["1", "4"])
        let r = ranged.editor_values()
        #expect([r.0, r.1, r.2] == ["1", "4", ""])
    }
    @Test("months_window_starts_on_the_last_day_of_the_month_n_months_back")
    func months_window_starts_on_the_last_day_of_the_month_n_months_back() {
        func day(_ y: Int64, _ m: Int64, _ d: Int64) -> SmartDate { SmartDate(year: y, month: m, day: d) }
        let today = day(2026, 10, 9)
        #expect(today.minus(4, "month") == day(2026, 6, 30))
        #expect(today.minus(6, "month") == day(2026, 4, 30))
        #expect(today.minus(9, "month") == day(2026, 1, 31))
        #expect(today.minus(12, "month") == day(2025, 10, 31))
        #expect(today.minus(36, "month") == day(2023, 10, 31))
        #expect(day(2026, 10, 1).minus(4, "month") == day(2026, 6, 30))
        #expect(day(2026, 10, 31).minus(4, "month") == day(2026, 6, 30))
        #expect(day(2026, 1, 31).minus(1, "month") == day(2025, 12, 31))
        #expect(day(2026, 3, 31).minus(1, "month") == day(2026, 2, 28))
        #expect(day(2024, 3, 31).minus(1, "month") == day(2024, 2, 29))
        #expect(day(2024, 5, 15).minus(3, "month") == day(2024, 2, 29))
        #expect(day(2024, 3, 1).minus(12, "month") == day(2023, 3, 31))
        #expect(day(2026, 2, 14).minus(2, "month") == day(2025, 12, 31))
        #expect(day(2026, 1, 5).minus(13, "month") == day(2024, 12, 31))
        #expect(today.minus(0, "month") == day(2026, 9, 30))
        #expect(today.minus(-3, "month") == day(2026, 9, 30))
    }
    @Test("relative_dates_only_treat_singular_month_as_a_calendar_unit")
    func relative_dates_only_treat_singular_month_as_a_calendar_unit() throws {
        let d = try #require(SmartDate.parse("2026-03-31 10:00:00"))
        #expect(d.minus(1, "month") == SmartDate(year: 2026, month: 2, day: 28))
        #expect(d.minus(2, "weeks") == SmartDate(year: 2026, month: 3, day: 30))
        #expect(d.minus(1, "MONTH") == SmartDate(year: 2026, month: 2, day: 28))
        #expect(d.minus(1, "year") == d)
        #expect(d.minus(31, "day") == SmartDate(year: 2026, month: 3, day: 1))
        #expect(try #require(SmartDate.parse("2024-02-29")).days() == 19782)
        #expect(SmartDate.parse("not a date") == nil)
    }
    @Test("relative_date_counts_require_nonnegative_integers") func relative_date_counts_require_nonnegative_integers()
    {
        #expect(relative_count("2") == 2)
        #expect(relative_count("0") == 0)
        #expect(relative_count("-1") == 0)
        #expect(relative_count("1.5") == 0)
        #expect(relative_count("not-a-number") == 0)
    }
    @Test("smart_dates_use_fixed_positions_and_normalize_the_calendar")
    func smart_dates_use_fixed_positions_and_normalize_the_calendar() throws {
        let january = try #require(smart_date("2025-01-31"))
        #expect(smart_date("2025/01/31") == january)
        #expect(smart_date("2025Ω01Ω31") == january)
        #expect(smart_date("2025-02-29") == smart_date("2025-03-01"))
        #expect(smart_date("2025-13-01") == smart_date("2026-01-01"))
        #expect(smart_date("2025-01-00") == smart_date("2024-12-31"))
        #expect(smart_date("202A-01-31") == smart_date("2037-01-31"))
    }
    @Test("smart_dates_reject_values_outside_rekordbox_conversion")
    func smart_dates_reject_values_outside_rekordbox_conversion() {
        for input in [
            "1970-01-01", "1969-12-31", "9999-12-31", "2025-1-31", "2025-01-31T00:00", " 2025-01-31", "２０２５-０１-３１",
            "2025-0\0-31",
        ] { #expect(smart_date(input) == nil) }
    }
    @Test("smart_date_comparisons_require_a_valid_track_date") func smart_date_comparisons_require_a_valid_track_date()
    {
        func condition(_ op: Operator, _ left: String) -> CompiledCondition {
            CompiledCondition(
                Condition(property: .dateAdded, operator: op, left: left), Library(),
                SmartDate(year: 2025, month: 1, day: 31))
        }
        #expect(!condition(.notEqual, "2025-01-31").date_matches("not-a-date"))
        #expect(condition(.notEqual, "not-a-date").date_matches("2025-01-31"))
        #expect(!condition(.equal, "not-a-date").date_matches("2025-01-31"))
    }
    @Test("my_tag_ids_are_read_as_juce_reads_an_int_attribute")
    func my_tag_ids_are_read_as_juce_reads_an_int_attribute() {
        #expect(my_tag_key("700002") == 700002)
        #expect(my_tag_key("  +42abc") == 42)
        #expect(my_tag_key("-7") == -7)
        #expect(my_tag_key("") == 0)
        #expect(my_tag_key("tag") == 0)
        #expect(my_tag_key("3000000000") == my_tag_key("-1294967296"))
    }
    @Test("a_my_tag_condition_answers_only_contains_and_does_not_contain")
    func a_my_tag_condition_answers_only_contains_and_does_not_contain() throws {
        let rule = try #require(
            SmartRule.parse(
                #"<NODE LogicalOperator="1"><CONDITION PropertyName="myTag" Operator="8" ValueLeft="12" ValueRight=""/></NODE>"#
            ))
        #expect(try smartCondition(rule.root.items[0]).property == .myTag)
        #expect(rule.unsupported() == 0)
        func compiled(_ op: Operator) -> CompiledCondition {
            CompiledCondition(
                Condition(property: .myTag, operator: op, left: "12"), Library(),
                SmartDate(year: 2025, month: 1, day: 31))
        }
        #expect(compiled(.contains).tag_matches([3, 12]))
        #expect(!compiled(.contains).tag_matches([3]))
        #expect(!compiled(.contains).tag_matches([]))
        #expect(compiled(.notContains).tag_matches([]))
        #expect(compiled(.notContains).tag_matches([3]))
        #expect(!compiled(.notContains).tag_matches([12]))
        for op in [Operator.equal, .notEqual, .greater, .startsWith] {
            #expect(!compiled(op).tag_matches([12]))
            #expect(!compiled(op).tag_matches([]))
        }
    }
    @Test("values_are_read_the_way_rekordbox_writes_them") func values_are_read_the_way_rekordbox_writes_them() {
        #expect(whole("128") == 128)
        #expect(whole("128.5") == 128)
        #expect(whole("12800") == 12800)
        #expect(whole("0.5") == 0)
        #expect(whole("2147483648") == Int64(Int32.max))
        #expect(seconds("5:30") == 330)
        #expect(seconds("330") == 330)
        #expect(color_id("Aqua") == 0)
        #expect(color_id("Pink") == 0)
        #expect(color_id("3") == 3)
        #expect(color_id(" 3x") == 3)
        #expect(unescape("a &lt;b&gt; &#39;c&#x27; &unknown; &") == "a <b> 'c' &unknown; &")
    }
}
