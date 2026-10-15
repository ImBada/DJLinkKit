// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: crates/rbl-core/src/xml.rs의 tests
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportModel

@Suite("xml::tests") struct XmlTests {
    @Test("elements_come_back_in_order_with_their_attributes") func elements_come_back_in_order_with_their_attributes()
        throws
    {
        let doc = #"""
            <?xml version="1.0" encoding="UTF-8"?>
                        <!-- a comment with <angles> -->
                        <DJ_PLAYLISTS Version="1.0.0"><COLLECTION Entries="1">
                          <TRACK TrackID="7" Name="Tom&apos;s &quot;Song&quot;" Location='file://localhost/Music/a%20b.mp3'/>
                        </COLLECTION></DJ_PLAYLISTS>
            """#
        let seen = tags(doc)
        #expect(seen.map { $0.name() } == ["DJ_PLAYLISTS", "COLLECTION", "TRACK", "COLLECTION", "DJ_PLAYLISTS"])
        guard case let .open(_, attributes, closed) = seen[2] else { throw XmlTestError.expectedOpen }
        #expect(closed)
        #expect(attribute(attributes, "name") == "Tom's \"Song\"")
        #expect(attribute(attributes, "Location") == "file://localhost/Music/a%20b.mp3")
        #expect(attribute(attributes, "Missing") == "")
    }
    @Test("escaping_round_trips") func escaping_round_trips() {
        let text = "a < b & c > \"d\" 'e'"
        #expect(unescape(escape(text)) == text)
        #expect(unescape("&#65;&#x42;&unknown;&") == "AB&unknown;&")
    }
}
private enum XmlTestError: Error { case expectedOpen }
