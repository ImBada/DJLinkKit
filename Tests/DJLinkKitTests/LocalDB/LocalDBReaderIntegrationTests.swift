import DJLinkTestSupport
import Foundation
import Testing

@testable import DJLinkKit

// 원본 대응 시험과 분리한다. Kaitai를 대체한 리더의 실제 바이트 경계를 검사한다.
@Suite("LocalDB 바이트 리더 연결")
@DJLinkActor struct LocalDBReaderIntegrationTests {
    private var track: Track {
        .init(
            id: 1, title: "합성 곡", duration: 0, tempo: 0, rating: 0, comment: "", filePath: "",
            fileName: "", analyzePath: "/ANLZ0000")
    }
    @Test("실제 2EX 리더가 PWV6·PWV7·PWVC 바이트를 내보낸다")
    func ex2() async throws {
        let bytes = create2EXFile(
            pwv6: .init(numEntries: 2, data: [1, 2, 3, 4, 5, 6]),
            pwv7: .init(numEntries: 1, data: [7, 8, 9]),
            pwvc: .init(thresholdLow: 256, thresholdMid: 1024, thresholdHigh: 4096))
        let result = try await loadAnlz(track, type: .ex2, anlzResolver: { _ in bytes })
        #expect(result.waveform3BandPreview == .init(numEntries: 2, data: [1, 2, 3, 4, 5, 6]))
        #expect(result.waveform3BandDetail == .init(numEntries: 1, data: [7, 8, 9]))
        #expect(result.vocalConfig == .init(thresholdLow: 256, thresholdMid: 1024, thresholdHigh: 4096))
    }
    @Test("실제 EXT 파형의 머리와 색·높이를 구분한다")
    func extWaveforms() async throws {
        let hd = createWaveSection(
            "PWV5", numEntries: 1, entryBytes: 2, unknown: true, data: [0xff, 0xfc])
        let color = createWaveSection(
            "PWV4", numEntries: 1, entryBytes: 6, unknown: true, data: [10, 20, 30, 40, 50, 60])
        let detail = createWaveSection(
            "PWV3", numEntries: 2, entryBytes: 1, unknown: true, data: [0x00, 0xff])
        let bytes = createAnlzFile([hd, color, detail])
        let result = try await loadAnlz(track, type: .ext, anlzResolver: { _ in bytes })
        #expect(result.waveformHd == [.init(height: 31, color: [1, 1, 1])])
        #expect(result.waveformColorPreview == [10, 20, 30, 40, 50, 60])
        #expect(result.waveformDetail == [0, 255])
    }
    @Test("DAT 비트 그리드와 미리 보기의 단위·빈 태그를 구분한다")
    func dat() async throws {
        let grid = anlzSection(
            "PQTZ",
            anlzBE32(0) + anlzBE32(0x80000) + anlzBE32(2) + anlzBE16(1) + anlzBE16(12850) + anlzBE32(1000)
                + anlzBE16(2) + anlzBE16(12850) + anlzBE32(1467), headerLength: 24)
        let preview = anlzSection("PWAV", anlzBE32(2) + anlzBE32(0x10000) + [0, 255], headerLength: 20)
        let tiny = anlzSection("PWV2", anlzBE32(0) + anlzBE32(0x10000), headerLength: 20)
        let bytes = createAnlzFile([grid, preview, tiny])
        let result = try await loadAnlz(track, type: .dat, anlzResolver: { _ in bytes })
        #expect(
            result.beatGrid == [
                .init(offset: 1000, count: 1, bpm: 128.5), .init(offset: 1467, count: 2, bpm: 128.5),
            ])
        #expect(result.waveformPreview?.data == [0, 255])
        #expect(result.waveformTiny?.data == [])
        #expect(result.cueAndLoops == nil)
    }
    @Test("PCOB는 지워진 상태 값에도 원본처럼 큐 형만 걸러낸다")
    func pcob() async throws {
        func cue(_ hot: Int, _ type: UInt8, _ input: Int, _ output: Int) -> [UInt8] {
            let body =
                anlzBE32(hot) + anlzBE32(0) + anlzBE32(0x10000) + anlzBE16(0xffff) + anlzBE16(0xffff) + [
                    type, 0,
                ] + anlzBE16(1000) + anlzBE32(input) + anlzBE32(output) + [UInt8](repeating: 0, count: 16)
            return anlzSection("PCPT", body, headerLength: 28)
        }
        let bytes = createAnlzFile([
            anlzSection(
                "PCOB",
                anlzBE32(1) + anlzBE16(0) + anlzBE16(3) + anlzBE32(0xffff_ffff)
                    + cue(3, 1, 1000, 0xffff_ffff) + cue(8, 2, 2000, 3000) + cue(0, 9, 0, 0), headerLength: 24
            )
        ])
        let result = try await loadAnlz(track, type: .dat, anlzResolver: { _ in bytes })
        #expect(
            result.cueAndLoops == [
                .hotCue(.init(offset: 1000, button: .C)),
                .hotLoop(.init(offset: 2000, button: .H, length: 1000)),
            ])
    }
    @Test("PCO2에서 UTF-16 주석·색·양자화 루프를 읽는다")
    func pco2() async throws {
        let comment = Array("Drop\0".utf16).flatMap { anlzBE16(Int($0)) }
        let body =
            anlzBE32(3) + [UInt8(2), 0] + anlzBE16(1000) + anlzBE32(2000) + anlzBE32(6000) + [
                UInt8(5), 0,
            ] + anlzBE16(0) + anlzBE32(0) + anlzBE16(4) + anlzBE16(1) + anlzBE32(comment.count) + comment
            + [UInt8(0x2a), 255, 0, 0] + [UInt8](repeating: 0, count: 40)
        let entry = anlzSection("PCP2", body, headerLength: 16)
        let bytes = createAnlzFile([
            anlzSection("PCO2", anlzBE32(1) + anlzBE16(1) + anlzBE16(0) + entry, headerLength: 20)
        ])
        let result = try await loadAnlz(track, type: .ext, anlzResolver: { _ in bytes })
        #expect(
            result.extendedCues == [
                .init(
                    hotCue: 3, type: 2, time: 2000, loopTime: 6000, colorId: 5, colorCode: 0x2a,
                    colorRgb: .init(r: 255, g: 0, b: 0), comment: "Drop", loopNumerator: 4, loopDenominator: 1
                )
            ])
    }
    @Test("PSSI는 원본처럼 평문 여부와 무관하게 마스크를 적용한다")
    func pssi() async throws {
        var section = [UInt8](repeating: 0, count: 56)
        section.replaceSubrange(0..<4, with: "PSSI".utf8)
        section.replaceSubrange(4..<8, with: anlzBE32(32))
        section.replaceSubrange(8..<12, with: anlzBE32(56))
        section.replaceSubrange(12..<16, with: anlzBE32(24))
        section.replaceSubrange(16..<18, with: anlzBE16(1))
        section.replaceSubrange(18..<20, with: anlzBE16(2))
        section.replaceSubrange(26..<28, with: anlzBE16(256))
        section[30] = 7
        section.replaceSubrange(32..<34, with: anlzBE16(1))
        section.replaceSubrange(34..<36, with: anlzBE16(1))
        section.replaceSubrange(36..<38, with: anlzBE16(9))
        section[53] = 1
        section.replaceSubrange(54..<56, with: anlzBE16(60))
        let plain = createAnlzFile([section])
        let mask: [UInt8] = [
            0xCB, 0xE1, 0xEE, 0xFA, 0xE5, 0xEE, 0xAD, 0xEE, 0xE9, 0xD2, 0xE9, 0xEB, 0xE1, 0xE9, 0xF3,
            0xE8, 0xE9, 0xF4, 0xE1,
        ]
        for i in 18..<section.count { section[i] ^= mask[(i - 18) % 19] &+ 1 }
        let masked = createAnlzFile([section])
        // 평문에도 마스크를 적용해 mood가 0x0002 ^ 0xCCE2 = 0xCCE0이 된다.
        // 원본 Kaitai처럼 알 수 없는 mood에서도 실패하지 않고 kind를 unknown_tag로 읽는다.
        let fromPlain = try #require(try readLocalDBAnlz(plain).first)
        #expect(fromPlain.mood == 0xCCE0)
        #expect(fromPlain.phrases.map(\.kind) == [.unknownTag])
        let a = try await loadAnlz(track, type: .ext, anlzResolver: { _ in masked })
        #expect(
            a.songStructure
                == .init(
                    mood: .mid, bank: .club_1, endBeat: 256,
                    phrases: [.init(index: 1, beat: 1, kind: 9, phraseType: "Chorus", fill: 1, fillBeat: 60)])
        )
    }
    @Test("짧거나 범위를 넘는 분석 태그를 읽지 않는다")
    func malformed() throws {
        #expect(throws: (any Error).self) { try readLocalDBAnlz([]) }
        #expect(throws: (any Error).self) {
            try readLocalDBAnlz([0xd0, 0x4d, 0x41, 0x49] + anlzBE32(12) + anlzBE32(12))
        }
        #expect(throws: (any Error).self) {
            try readLocalDBAnlz(
                createAnlzFile([anlzSection("PWV6", anlzBE32(3) + anlzBE32(0xffff_ffff))]))
        }
    }
    @Test("PDB 산 행을 읽어 메타데이터·관계·목록을 ORM에 채운다")
    func pdb() async throws {
        var builder = LocalDBPdbBuilder(kind: .export)
        var spec = LocalDBPdbTrackSpec(id: 1)
        spec.artistID = 11
        spec.albumID = 21
        spec.keyID = 31
        spec.artworkID = 41
        spec.colorID = 1
        spec.bpmx100 = 12850
        builder.add(.tracks, LocalDBPdbBuilder.trackRow(spec))
        builder.add(
            .tracks, .init(LocalDBPdbBuilder.trackRow(LocalDBPdbTrackSpec(id: 2)).bytes, live: false))
        builder.add(.artists, LocalDBPdbBuilder.artistRow(11, "합성 아티스트"))
        builder.add(.albums, LocalDBPdbBuilder.albumRow(21, "합성 앨범"))
        builder.add(.keys, LocalDBPdbBuilder.keyRow(31, "Am"))
        builder.add(.colors, LocalDBPdbBuilder.colorRow(1, "Pink"))
        builder.add(.artwork, LocalDBPdbBuilder.idNameRow(41, "/artwork.jpg"))
        builder.add(.playlistTree, LocalDBPdbBuilder.playlistTreeRow(id: 51, name: "합성 목록"))
        builder.add(
            .playlistEntries, LocalDBPdbBuilder.playlistEntryRow(index: 1, trackID: 1, playlistID: 51))
        let orm = try MetadataORM()
        defer { orm.close() }
        let clock = TestClock()
        var progress: [HydrationProgress] = []
        let gate = LocalDBHydrationTestGate(expected: 8)
        let task = Task { @DJLinkActor in
            defer { gate.finish() }
            try await hydrateDatabase(
                .init(
                    orm: orm, pdbData: Array(builder.build().data),
                    onProgress: {
                        progress.append($0)
                        gate.report()
                    }),
                clock: clock)
        }
        await gate.wait()
        clock.runAllTimers()
        try await task.value
        let result = try #require(try orm.findTrack(1))
        #expect(result.title == "시험 곡 1")
        #expect(result.tempo == 128.5)
        #expect(result.analyzePath == "/PIONEER/USBANLZ/P000/00000001/ANLZ0000")
        #expect(result.artist == .init(id: 11, name: "합성 아티스트"))
        #expect(result.album == .init(id: 21, name: "합성 앨범"))
        #expect(result.key == .init(id: 31, name: "Am"))
        #expect(result.artwork == .init(id: 41, path: "/artwork.jpg"))
        #expect(result.color == .init(id: 1, name: "Pink"))
        #expect(try orm.findTrack(2) == nil)
        #expect(try orm.findPlaylist(51).trackEntries == [.init(id: 1, sortIndex: 1, playlistId: 51, trackId: 1)])
        #expect(progress.contains { $0.table == "track" && $0.complete == 1 && $0.total == 1 })
    }
    @Test("Swift 합성 DB 도우미가 원본과 같은 질의 결과를 만든다")
    func syntheticDatabase() throws {
        let path = FileManager.default.temporaryDirectory.appending(
            path: "djlk-synthetic-\(UUID().uuidString).db"
        ).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try createTestOneLibraryDatabase(at: path)
        let adapter = try OneLibraryAdapter(dbPath: path)
        defer { adapter.close() }
        #expect(try adapter.findAllTracks().map(\.id) == [1, 2, 3, 4, 5])
        #expect(try adapter.findCues(1).count == 4)
        #expect(try adapter.findPlaylistContents(1) == [1, 2, 4])
        #expect(
            try adapter.findMyTagsForTrack(1).map(\.name) == ["Favorites", "High Energy", "Classics"])
    }
    @Test("분석 경로에서 UTF-16 기준으로 DAT 확장자를 자른다")
    func unicodePath() { #expect(localDBTrimAnalyzePath("/🎵/ANLZ0000.DAT") == "/🎵/ANLZ0000") }
    @Test("PDB 머리가 지정한 쪽 크기·표 수와 마지막 쪽을 따른다")
    func pdbHeader() throws {
        var bytes = [UInt8](repeating: 0, count: 2048)
        func put(_ value: Int, at offset: Int) {
            for i in 0..<4 { bytes[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
        }
        put(1024, at: 4)
        put(1, at: 8)
        put(999, at: 0x20)
        put(1, at: 0x24)
        put(1, at: 0x28)
        put(1, at: 1024 + 4)
        put(2, at: 1024 + 12)
        bytes[1024 + 0x1B] = 0x64
        let tables = try readLocalDBPdb(bytes)
        #expect(tables.count == 1)
        #expect(tables[0].type == 0)
        #expect(tables[0].rows == [])
    }

    @Test("원본의 알 수 없는 핫 큐 형과 NaN BPM 처리도 유지한다")
    func originalQuirks() throws {
        #expect(
            makeCueAndLoop(.init(cues: [.init(hotCue: 3, type: 9, time: 100)])) == [
                .hotCue(.init(offset: 100, button: .C))
            ])
        var row = track
        row.tempo = .nan
        #expect(trackAgreesWithPlayer(row, .init(trackBPM: 128)))
        #expect(throws: DJLinkError("Invalid array length")) {
            try makeWaveformHd(.init(entries: [0xff]))
        }
    }

    @Test("SQLite 문자열의 중간 NUL도 원본 바인딩처럼 보존한다")
    func sqliteText() throws {
        let db = try CipherDatabase(path: ":memory:", key: nil as CipherKey?, mode: .create)
        defer { db.close() }
        try db.execute("CREATE TABLE sample (value TEXT)")
        try db.run("INSERT INTO sample VALUES (?)", [.text("앞\0뒤")])
        #expect(try db.rows("SELECT value FROM sample").first?.string("value") == "앞\0뒤")
    }

    @Test("이름 크리에이터와 표별 크리에이터가 원본의 빈 이름 처리를 따른다")
    func creators() {
        let mapper: @Sendable (LocalDBRow) -> Artist = makeIdNameHydrator()
        #expect(mapper(["id": 11]) == Artist(id: 11, name: ""))
        #expect(pdbEntityCreators[2]?(["id": 11, "name": "합성"]) == .artist(.init(id: 11, name: "합성")))
        #expect(pdbEntityCreators[11] == nil)
    }

    @Test("SQL 날짜 시간과 ORM 날짜의 밀리초를 보존한다")
    func dates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let expectedLocal = calendar.date(
            from: DateComponents(
                timeZone: .current, year: 2024, month: 1, day: 1, hour: 12, minute: 34, second: 56))
        #expect(localDBParseDate("2024-01-01 12:34:56") == expectedLocal)
        #expect(localDBParseDate("2024-01-01T12:34:56") == expectedLocal)
        #expect(localDBParseDate("not-a-date") == nil)
        var spec = LocalDBPdbTrackSpec(id: 1)
        spec[.analyzeDate] = "2024-01-01T12:34:56.789Z"
        spec[.dateAdded] = "2024-01-02T12:34:56.789Z"
        var row = PdbRowReader(Array(LocalDBPdbBuilder.trackRow(spec).bytes))
        let orm = try MetadataORM()
        defer { orm.close() }
        try orm.insertEntity(.track, createTrack(try PdbRows.track(&row)))
        let value = try #require(try orm.findTrack(1))
        #expect(value.analyzeDate == Date(timeIntervalSince1970: 1704112496.789))
        #expect(value.dateAdded == Date(timeIntervalSince1970: 1704198896.789))
    }

    @Test("트랙의 쓰지 않는 문자열 오프셋은 읽지 않는다")
    func unusedTrackStrings() throws {
        var bytes = Array(LocalDBPdbBuilder.trackRow(.init(id: 1)).bytes)
        let unused = [0, 1, 2, 3, 4, 5, 8, 9, 13, 18]
        for index in unused {
            bytes[0x5E + 2 * index] = 0xFF
            bytes[0x5F + 2 * index] = 0xFF
        }
        var row = PdbRowReader(bytes)
        let value = try PdbRows.track(&row)
        #expect(value.string("title") == "시험 곡 1")
        #expect(row.strings.count == 11)
        let orm = try MetadataORM()
        defer { orm.close() }
        try orm.insertEntity(.track, createTrack(value), pdbRow: value)
        #expect(try orm.findTrack(1)?.title == "시험 곡 1")
    }

    @Test("문자열은 ASCII 전체 바이트와 느슨한 UTF-16을 원본처럼 읽는다")
    func looseStrings() throws {
        #expect(try PdbStringDecoder.decode([7, 0x80, 0xFF], at: 0).value == "\u{80}ÿ")
        #expect(try PdbStringDecoder.decode([0x90, 7, 0, 0, 0, 0xD8, 0xFF], at: 0).value == "�")
        #expect(try PdbStringDecoder.decode([1], at: 0).value == nil)
        #expect(try PdbStringDecoder.decode([2], at: 0).value == nil)
        #expect(try PdbStringDecoder.decode([0x40, 3, 0, 65, 0x80, 0xFF], at: 0).value == "A\u{80}ÿ")
        #expect(
            try PdbStringDecoder.decode([0x90, 11, 0, 0, 0xFF, 0xFE, 0x00, 0xD8, 65, 0, 0x42], at: 0).value == "�A�")
        #expect(try PdbStringDecoder.decode([0x90, 6, 0, 0, 0x03, 0], at: 0, isrcAllowed: true).value == "\u{3}")
        #expect(throws: LocalDBPdbError.self) {
            try PdbStringDecoder.decode([0x40, 4, 0, 65], at: 0)
        }
    }

    @Test("id와 name 표는 생략된 문자열을 빈 이름으로 채운다")
    func skippedNames() throws {
        var name = PdbRowReader([1, 0, 0, 0, 1])
        #expect(try PdbRows.idName(&name).name == "")
        var artist = PdbRowReader([0x60, 0, 0, 0, 1, 0, 0, 0, 3, 10, 2])
        #expect(try PdbRows.artist(&artist).name == "")
        var albumBytes = [UInt8](repeating: 0, count: 27)
        albumBytes[0] = 0x84
        albumBytes[12] = 1
        albumBytes[21] = 24
        albumBytes[22] = 0xFF
        albumBytes[23] = 0xFF
        albumBytes[24] = 5
        albumBytes[25] = 65
        var album = PdbRowReader(albumBytes)
        #expect(try PdbRows.album(&album) == .init(id: 1, name: "A"))
        albumBytes[24] = 2
        album = PdbRowReader(albumBytes)
        #expect(try PdbRows.album(&album).name == "")
        var key = PdbRowReader([1, 0, 0, 0, 0, 0, 0, 0, 1])
        #expect(try PdbRows.key(&key).name == "")
        var color = PdbRowReader([0, 0, 0, 0, 0, 1, 0, 0, 2])
        #expect(try PdbRows.color(&color).name == "")
    }

    @Test("트랙의 생략된 필수 text는 원본의 SQL NOT NULL 오류를 낸다")
    func skippedRequiredText() throws {
        var bytes = Array(LocalDBPdbBuilder.trackRow(.init(id: 1)).bytes)
        let offset = Int(bytes[0x5E + 2 * 17]) | Int(bytes[0x5F + 2 * 17]) << 8
        bytes[offset] = 1
        var row = PdbRowReader(bytes)
        let value = try PdbRows.track(&row)
        #expect(value["title"] == .null)
        let orm = try MetadataORM()
        defer { orm.close() }
        #expect(throws: DJLinkError("NOT NULL constraint failed: track.title")) {
            try orm.insertEntity(.track, createTrack(value), pdbRow: value)
        }
    }

    @Test("무효한 PDB 날짜는 NULL 바인딩 뒤 원본처럼 epoch로 조회한다")
    func invalidPdbDates() throws {
        var spec = LocalDBPdbTrackSpec(id: 1)
        spec[.analyzeDate] = "not-a-date"
        spec[.dateAdded] = ""
        var row = PdbRowReader(Array(LocalDBPdbBuilder.trackRow(spec).bytes))
        let value = createTrack(try PdbRows.track(&row))
        #expect(value.analyzeDate == nil)
        #expect(value.dateAdded == nil)
        let orm = try MetadataORM()
        defer { orm.close() }
        try orm.insertEntity(.track, value)
        #expect(try orm.findTrack(1)?.analyzeDate == Date(timeIntervalSince1970: 0))
        #expect(try orm.findTrack(1)?.dateAdded == Date(timeIntervalSince1970: 0))
    }

    @Test("재생 목록 id는 산 행 순번 대신 SQLite가 부여한다")
    func playlistAutoId() throws {
        let orm = try MetadataORM()
        defer { orm.close() }
        try orm.insertEntity(.playlistEntry, ["id": 40, "sortIndex": 1, "playlistId": 51, "trackId": 1])
        let row = PdbRowReader(Array(LocalDBPdbBuilder.playlistEntryRow(index: 2, trackID: 2, playlistID: 51).bytes))
        let value = try PdbRows.playlistEntry(row)
        #expect(value["id"] == .null)
        try orm.insertEntity(.playlistEntry, value)
        #expect(try orm.findPlaylist(51).trackEntries.map(\.id) == [40, 41])
    }

    @Test("지원하지 않는 PDB 표의 잘못된 쪽 포인터는 따라가지 않는다")
    func ignoredPdbTable() throws {
        var builder = LocalDBPdbBuilder(kind: .export)
        builder.add(.genres, LocalDBPdbBuilder.idNameRow(1, "합성 장르"))
        var bytes = Array(builder.build().data)
        let pointer = 0x1C + 16 * 9
        for i in 8..<16 {
            bytes[pointer + i] = 0xFF
        }
        let tables = try readLocalDBPdb(bytes)
        #expect(tables.map(\.type) == [0, 1, 2, 3, 4, 5, 6, 7, 8, 13])
        #expect(tables.first { $0.type == 1 }?.rows.count == 1)
    }

    @Test("PDB 행 수는 small과 large의 원본 선택 조건을 따른다")
    func pageRowCounts() throws {
        func page(small: UInt8, large: UInt16, packedExtra: UInt8 = 0) throws -> PdbPage {
            var bytes = [UInt8](repeating: 0, count: 4096)
            bytes[0x18] = small
            bytes[0x19] = packedExtra
            bytes[0x22] = UInt8(truncatingIfNeeded: large)
            bytes[0x23] = UInt8(truncatingIfNeeded: large >> 8)
            return try PdbPage(data: bytes)
        }
        #expect(try page(small: 1, large: 2).slots.count == 2)
        #expect(try page(small: 2, large: 1).slots.count == 2)
        #expect(try page(small: 2, large: 2).slots.count == 2)
        #expect(try page(small: 1, large: 0x1FFF, packedExtra: 1).slots.count == 1)
    }

    @Test("실수 숫자에서 Int로 바꿀 수 없는 값도 trap하지 않는다")
    func realIntegers() {
        for value in [Double.nan, .infinity, -.infinity, Double(Int.max), -Double.greatestFiniteMagnitude] {
            let row: LocalDBRow = ["value": .real(value)]
            #expect(row.int("value") == nil)
            #expect(row.double("value") == value || value.isNaN)
        }
        let fraction: LocalDBRow = ["value": .real(12.9)]
        let minimum: LocalDBRow = ["value": .real(Double(Int.min))]
        #expect(fraction.int("value") == 12)
        #expect(minimum.int("value") == Int.min)
    }

    @Test("SQLite BLOB는 NULL과 구별하며 빈 바이트도 보존한다")
    func sqliteBlob() throws {
        let db = try CipherDatabase(path: ":memory:", key: nil as CipherKey?, mode: .create)
        defer { db.close() }
        try db.execute("CREATE TABLE sample (value BLOB)")
        try db.run("INSERT INTO sample VALUES (?), (?), (?)", [.blob([0, 128, 255]), .blob([]), .null])
        #expect(
            try db.rows("SELECT value FROM sample").map { $0["value"] } == [.blob([0, 128, 255]), .blob([]), .null])
    }

    @Test("ANLZ는 len_file과 태그 본문 끝의 쓰지 않는 바이트를 검사하지 않는다")
    func anlzLengths() throws {
        var bytes = createAnlzFile([anlzSection("PWAV", anlzBE32(1) + anlzBE32(0) + [42, 99, 88])])
        bytes.replaceSubrange(8..<12, with: anlzBE32(1))
        #expect(try readLocalDBAnlz(bytes).first?.entries == [42])
        #expect(throws: (any Error).self) {
            try readLocalDBAnlz(bytes + [0xFF])
        }
    }

    @Test("PCO2는 짧은 항목·홀수 주석·부분 색을 원본 조건대로 읽는다")
    func extendedCueLengths() throws {
        func cue(_ extra: [UInt8]) -> [UInt8] {
            var entry = [UInt8](repeating: 0, count: 40)
            entry.replaceSubrange(0..<4, with: "PCP2".utf8)
            entry.replaceSubrange(8..<12, with: anlzBE32(40 + extra.count))
            entry[16] = 1
            return entry + extra
        }
        for count in 0...4 {
            let color = Array([UInt8(0x2A), 255, 128, 64].prefix(count))
            let entry = cue(anlzBE32(3) + [0, 65, 0xFF] + color)
            let file = createAnlzFile([anlzSection("PCO2", anlzBE32(0) + anlzBE16(1) + anlzBE16(0) + entry)])
            let result = try #require(try readLocalDBAnlz(file).first?.cues.first)
            #expect(result.comment == "A�")
            #expect(result.colorCode == (count > 0 ? 0x2A : nil))
            #expect(result.colorRed == (count > 1 ? 255 : nil))
            #expect(result.colorGreen == (count > 2 ? 128 : nil))
            #expect(result.colorBlue == (count > 3 ? 64 : nil))
        }
        let file = createAnlzFile([anlzSection("PCO2", anlzBE32(0) + anlzBE16(2) + anlzBE16(0) + cue([]) + cue([]))])
        #expect(try readLocalDBAnlz(file).first?.cues.count == 2)
        #expect(try readLocalDBAnlz(file).first?.cues.first?.comment == nil)
    }

    @Test("PCPT와 PCP2 magic을 원본처럼 검증한다")
    func cueMagic() throws {
        for (tag, magic, size) in [("PCOB", "PCPT", 56), ("PCO2", "PCP2", 40)] {
            var cue = [UInt8](repeating: 0, count: size)
            cue.replaceSubrange(0..<4, with: magic.utf8)
            cue.replaceSubrange(8..<12, with: anlzBE32(size))
            let header =
                tag == "PCOB"
                ? anlzBE32(0) + anlzBE16(0) + anlzBE16(1) + anlzBE32(0) : anlzBE32(0) + anlzBE16(1) + anlzBE16(0)
            let bytes = createAnlzFile([anlzSection(tag, header + cue)])
            #expect(try readLocalDBAnlz(bytes).first?.cues.count == 1)
            cue[0] ^= 0xFF
            #expect(throws: (any Error).self) {
                try readLocalDBAnlz(createAnlzFile([anlzSection(tag, header + cue)]))
            }
        }
    }

    @Test("PSSI 항목은 len_entry_bytes로 간격과 fill 위치를 정한다")
    func phraseEntrySize() throws {
        for size in [9, 24, 28] {
            var section = [UInt8](repeating: 0, count: 32 + size * 2)
            section.replaceSubrange(0..<4, with: "PSSI".utf8)
            section.replaceSubrange(4..<8, with: anlzBE32(32))
            section.replaceSubrange(8..<12, with: anlzBE32(section.count))
            section.replaceSubrange(12..<16, with: anlzBE32(size))
            section.replaceSubrange(16..<18, with: anlzBE16(2))
            section.replaceSubrange(18..<20, with: anlzBE16(2))
            for i in 0..<2 {
                let p = 32 + size * i
                section.replaceSubrange(p..<p + 2, with: anlzBE16(i + 1))
                section.replaceSubrange(p + 2..<p + 4, with: anlzBE16(1 + i * 32))
                section.replaceSubrange(p + 4..<p + 6, with: anlzBE16(9))
                section[p + size - 3] = 1
                section.replaceSubrange(p + size - 2..<p + size, with: anlzBE16(60 + i))
            }
            let mask: [UInt8] = [
                0xCB, 0xE1, 0xEE, 0xFA, 0xE5, 0xEE, 0xAD, 0xEE, 0xE9, 0xD2, 0xE9, 0xEB, 0xE1, 0xE9, 0xF3, 0xE8, 0xE9,
                0xF4, 0xE1,
            ]
            for i in 18..<section.count {
                section[i] ^= mask[(i - 18) % mask.count] &+ 2
            }
            let parsed = try #require(try readLocalDBAnlz(createAnlzFile([section])).first)
            #expect(parsed.phrases.map(\.phraseNumber) == [1, 2])
            #expect(parsed.phrases.map(\.fillInBeatNumber) == [60, 61])
            #expect(parsed.phrases.map(\.kind) == [.init(id: 9), .init(id: 9)])
        }
    }

}
