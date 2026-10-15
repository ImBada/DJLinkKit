// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbl-index/src/strings.rs inline 시험.
import Testing

@testable import DJLinkExportModel

@Suite struct StringsTests {
    @Test("packs_and_returns_strings") func packs() {
        var c = StrColumn()
        c.push("Airplane Mode")
        c.push("")
        c.push("Ébano")
        #expect(c.get(0) == "Airplane Mode")
        #expect(c.get(1) == "")
        #expect(c.get(2) == "Ébano")
        #expect(c.get(99) == "")
    }
    @Test("folds_case_and_accents") func accents() {
        #expect(fold("Björk") == "bjork")
        #expect(fold("DÉJÀ VU") == "deja vu")
        #expect(fold("Straße") == "strasse")
        #expect(fold("Tiësto") == "tiesto")
    }
    @Test("folding_drops_punctuation_so_search_ignores_it") func punctuation() {
        #expect(fold("Wh0 - House (Remix)") == "wh0  house remix")
    }
    @Test("smart_folding_preserves_punctuation_and_normalizes_width") func smart() {
        #expect(fold_smart("Ａlphá-Beta") == "alpha-beta")
        #expect(fold_smart("カタカナ") == fold_smart("かたかな"))
        #expect(fold_smart("Straße") == "strasse")
        #expect(fold_smart("before\0after") == "before")
    }
    @Test("interner_returns_empty_for_the_null_id") func interner() {
        var i = Interner()
        let a = i.push("ARTBAT")
        #expect(i.name(a) == "ARTBAT")
        #expect(i.name(UInt32.max) == "")
        #expect(i.folded(a) == "artbat")
    }
}
