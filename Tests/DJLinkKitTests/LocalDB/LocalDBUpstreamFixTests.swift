import DJLinkTestSupport
import Foundation
import Testing

@testable import DJLinkKit

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

@Suite("LocalDB 원본 버그 회귀")
struct LocalDBUpstreamFixTests {
    @Test("손상된 PDB 사슬은 시간 제한 안에 오류를 돌려준다", arguments: ["indexCycle", "lastCycle", "previousCycle"])
    func pdbChains(scenario: String) throws {
        let workerKey = "DJLINK_PDB_CHAIN_WORKER"
        if let selected = ProcessInfo.processInfo.environment[workerKey] {
            guard selected == scenario else { return }
            var builder = LocalDBPdbBuilder(kind: .export)
            builder.maxRowsPerPage = 1
            builder.add(.genres, LocalDBPdbBuilder.idNameRow(1, "시험 장르 1"))
            builder.add(.genres, LocalDBPdbBuilder.idNameRow(2, "시험 장르 2"))
            var built = builder.build()
            let table = PdbTableType.genres.rawValue
            let index = try #require(built.indexPages[table])
            let pages = try #require(built.dataPages[table])
            let candidate = try #require(built.candidates[table])
            // 종료 쪽에 도달하기 전에 순환하도록 lastPage를 빈 후보로 둔다.
            built.setU32(page: 0, offset: 0x1C + 16 * table + 12, UInt32(candidate))
            let repeatedPage: Int
            switch scenario {
            case "indexCycle":
                built.setU32(page: index, offset: 0x0C, UInt32(index))
                repeatedPage = index
            case "lastCycle":
                built.setU32(page: pages[1], offset: 0x0C, UInt32(pages[1]))
                repeatedPage = pages[1]
            default:
                built.setU32(page: pages[1], offset: 0x0C, UInt32(pages[0]))
                repeatedPage = pages[0]
            }
            #expect(throws: LocalDBPdbError.readFailed(detail: "pdb chain repeats page \(repeatedPage)")) {
                try readLocalDBPdb(Array(built.data))
            }
            print("PDB 사슬 검사 완료: \(scenario)")
            return
        }

        // 동기 리더는 취소로 멈출 수 없다. 별도 프로세스를 감시해 회귀해도 시험 실행기는 멈추지 않는다.
        let arguments = ProcessInfo.processInfo.arguments
        let bundle = try #require(arguments.first { $0.contains(".xctest/Contents/MacOS/") })
        let process = Process()
        process.executableURL = URL(filePath: arguments[0])
        process.arguments = [
            "--test-bundle-path", bundle, "--filter", "LocalDBUpstreamFixTests/pdbChains", bundle,
            "--testing-library", "swift-testing",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment[workerKey] = scenario
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        let completed = finished.wait(timeout: .now() + 3) == .success
        if !completed {
            process.terminate()
            if finished.wait(timeout: .now() + 1) != .success {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }
        try #require(completed, "PDB 사슬 검사 시간 초과: \(scenario)")
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0, "\(output)")
        #expect(output.contains("PDB 사슬 검사 완료: \(scenario)"), "\(output)")
    }

    @Test("첫 쪽 번호가 마지막 쪽보다 큰 비단조 사슬의 모든 산 행을 읽는다")
    func pdbNonMonotonicChain() throws {
        var builder = LocalDBPdbBuilder(kind: .export)
        builder.maxRowsPerPage = 1
        for id in 1...3 {
            builder.add(.genres, LocalDBPdbBuilder.idNameRow(id, "시험 장르 \(id)"))
        }
        var built = builder.build()
        let table = PdbTableType.genres.rawValue
        let index = try #require(built.indexPages[table])
        let pages = try #require(built.dataPages[table])
        let candidate = try #require(built.candidates[table])
        let indexRange = index * PdbPage.size..<(index + 1) * PdbPage.size
        let lastRange = pages[2] * PdbPage.size..<(pages[2] + 1) * PdbPage.size
        let indexData = built.data.subdata(in: indexRange)
        let lastData = built.data.subdata(in: lastRange)
        // 인덱스 쪽과 세 번째 데이터 쪽을 바꿔 높은 첫 쪽 → 낮은 쪽 → 더 낮은 쪽 → 마지막 쪽으로 잇는다.
        built.data.replaceSubrange(indexRange, with: lastData)
        built.data.replaceSubrange(lastRange, with: indexData)
        built.setU32(page: index, offset: 0x04, UInt32(index))
        built.setU32(page: pages[2], offset: 0x04, UInt32(pages[2]))
        built.setU32(page: 0, offset: 0x1C + 16 * table + 8, UInt32(pages[2]))
        built.setU32(page: 0, offset: 0x1C + 16 * table + 12, UInt32(pages[1]))
        built.setU32(page: pages[2], offset: 0x0C, UInt32(pages[0]))
        built.setU32(page: pages[0], offset: 0x0C, UInt32(index))
        built.setU32(page: index, offset: 0x0C, UInt32(pages[1]))
        built.setU32(page: pages[1], offset: 0x0C, UInt32(candidate))
        let tables = try readLocalDBPdb(Array(built.data))
        let rows = try #require(tables.first { $0.type == table }?.rows)
        #expect(try rows.map { try $0.readUInt32LE(0) } == [1, 3, 2])
    }

    @Test("마지막 쪽의 다음 쪽은 번호와 관계없이 읽지 않는다", arguments: ["emptyCandidate", "previousPage", "outsideFile"])
    func pdbBeyondLast(scenario: String) throws {
        var builder = LocalDBPdbBuilder(kind: .export)
        builder.add(.genres, LocalDBPdbBuilder.idNameRow(1, "시험 장르"))
        var built = builder.build()
        let table = PdbTableType.genres.rawValue
        let index = try #require(built.indexPages[table])
        let last = try #require(built.dataPages[table]?.last)
        if scenario == "emptyCandidate" {
            built.setU32(page: 0, offset: 0x1C + 16 * table + 4, UInt32(index))
        }
        built.setU32(page: last, offset: 0x0C, scenario == "outsideFile" ? .max : UInt32(index))
        let tables = try readLocalDBPdb(Array(built.data))
        let rows = try #require(tables.first { $0.type == table }?.rows)
        #expect(try rows.map { try $0.readUInt32LE(0) } == [1])
    }

    @Test("마지막 쪽에 도달하지 않아도 다음 쪽이 빈 후보면 읽기를 끝낸다")
    func pdbEmptyCandidate() throws {
        var builder = LocalDBPdbBuilder(kind: .export)
        builder.add(.genres, LocalDBPdbBuilder.idNameRow(1, "시험 장르"))
        var built = builder.build()
        let table = PdbTableType.genres.rawValue
        let index = try #require(built.indexPages[table])
        let last = try #require(built.dataPages[table]?.last)
        let candidate = try #require(built.candidates[table])
        // 빈 후보를 이미 읽은 낮은 번호 쪽으로 두고 lastPage는 도달하지 않는 쪽으로 둔다.
        built.setU32(page: 0, offset: 0x1C + 16 * table + 4, UInt32(index))
        built.setU32(page: 0, offset: 0x1C + 16 * table + 12, UInt32(candidate))
        built.setU32(page: last, offset: 0x0C, UInt32(index))
        let tables = try readLocalDBPdb(Array(built.data))
        let rows = try #require(tables.first { $0.type == table }?.rows)
        #expect(try rows.map { try $0.readUInt32LE(0) } == [1])
    }

    @Test("장치를 제거하면 모든 매체의 활성·대체 DB를 한 번씩 닫는다")
    @DJLinkActor func deviceRemoval() async throws {
        let devices = LocalDBFakeDeviceSource()
        var other = localDBTestCDJ
        other.id = 4
        devices.devices[other.id] = other
        let status = LocalDBFakeMediaSlotSource()
        let fs = LocalDBFakeFileSystem()
        let clock = TestClock()
        var adapters: [LocalDBFakeAdapter] = []
        func makeAdapter(_ type: DatabaseType) -> LocalDBFakeAdapter {
            let adapter = LocalDBFakeAdapter(type: type, rows: [])
            adapters.append(adapter)
            return adapter
        }
        let dependencies = LocalDBDependencies(
            fetchFile: { _ in [] }, fileSystem: fs,
            makeOneLibraryAdapter: { _ in makeAdapter(.oneLibrary) },
            makeMetadataORM: { makeAdapter(.pdb) }, hydrateDatabase: { _ in })
        let local = LocalDatabase(
            hostDevice: localDBTestHost, deviceManager: devices, statusEmitter: status,
            dependencies: dependencies, clock: clock)
        // 같은 장치의 USB·SD와 교체된 USB 매체를 캐시하고 각각 대체 DB까지 연다.
        for media in [
            localDBTestMedia(), localDBTestMedia(slot: .sd), localDBTestMedia(name: "교체한 시험 매체"),
            localDBTestMedia(deviceId: other.id),
        ] {
            status.media = media
            clock.advance(ms: 1)
            _ = try await local.findTrack(media.deviceId, media.slot, 1)
        }
        #expect(adapters.count == 8)
        #expect(fs.writes.count == 4)
        let removed = Array(adapters.prefix(6))
        let retained = Array(adapters.suffix(2))
        for handler in devices.handlers { handler(localDBTestCDJ) }
        #expect(removed.allSatisfy { $0.closeCalls == 1 })
        #expect(retained.allSatisfy { $0.closeCalls == 0 })
        #expect(fs.unlinks == fs.writes.prefix(3).map(\.0))
        #expect(local.getDatabaseType(3, .usb) == nil)
        #expect(local.getDatabaseType(3, .sd) == nil)
        #expect(local.getDatabaseType(other.id, .usb) == .oneLibrary)
        local.disconnectForDevice(localDBTestCDJ)
        #expect(removed.allSatisfy { $0.closeCalls == 1 })
        #expect(fs.unlinks.count == 3)
        local.disconnectForDevice(other)
        #expect(retained.allSatisfy { $0.closeCalls == 1 })
        #expect(fs.unlinks == fs.writes.map(\.0))
    }

    @Test("OneLibrary 열기 실패는 임시 파일을 지운 뒤 기존 선택 정책을 따른다", arguments: [DatabasePreference.auto, .oneLibrary])
    @DJLinkActor func oneLibraryOpenFailure(preference: DatabasePreference) async throws {
        let fs = LocalDBFakeFileSystem()
        let pdb = LocalDBFakeAdapter(type: .pdb, rows: [])
        var openedPaths: [String] = []
        var downloads: [String] = []
        let dependencies = LocalDBDependencies(
            fetchFile: { options in
                downloads.append(options.path)
                return [1, 2, 3]
            }, fileSystem: fs,
            makeOneLibraryAdapter: { path in
                openedPaths.append(path)
                throw DJLinkError("시험용 OneLibrary 열기 실패")
            }, makeMetadataORM: { pdb }, hydrateDatabase: { _ in })
        let local = LocalDatabase(
            hostDevice: localDBTestHost, deviceManager: LocalDBFakeDeviceSource(),
            statusEmitter: LocalDBFakeMediaSlotSource(), preference: preference, dependencies: dependencies)
        if preference == .oneLibrary {
            await #expect(throws: DJLinkError("OneLibrary database not found and preference is set to oneLibrary only"))
            {
                _ = try await local.get(3, .usb)
            }
            #expect(!downloads.contains { $0.hasSuffix("export.pdb") })
        } else {
            let loaded = try await local.get(3, .usb)
            #expect((loaded as? LocalDBFakeAdapter) === pdb)
            #expect(downloads.contains { $0.hasSuffix("export.pdb") })
        }
        #expect(fs.writes.count == 1)
        #expect(openedPaths == fs.writes.map(\.0))
        #expect(fs.unlinks == openedPaths)
        local.disconnectForDevice(localDBTestCDJ)
        #expect(fs.unlinks == openedPaths)
    }

    @Test("대체 OneLibrary 열기 실패도 임시 파일을 지우고 한 번만 시도한다")
    @DJLinkActor func oneLibraryAlternateFailure() async throws {
        let fs = LocalDBFakeFileSystem()
        let pdb = LocalDBFakeAdapter(type: .pdb, rows: [])
        let dependencies = LocalDBDependencies(
            fetchFile: { _ in [] }, fileSystem: fs,
            makeOneLibraryAdapter: { _ in throw DJLinkError("시험용 대체 DB 열기 실패") },
            makeMetadataORM: { pdb }, hydrateDatabase: { _ in })
        let local = LocalDatabase(
            hostDevice: localDBTestHost, deviceManager: LocalDBFakeDeviceSource(),
            statusEmitter: LocalDBFakeMediaSlotSource(), preference: .pdb, dependencies: dependencies)
        _ = try await local.get(3, .usb)
        local.preference = .auto
        _ = try await local.findTrack(3, .usb, 1)
        _ = try await local.findTrack(3, .usb, 2)
        #expect(fs.writes.count == 1)
        #expect(fs.unlinks == fs.writes.map(\.0))
        #expect(local.getDatabaseType(3, .usb) == .pdb)
        local.disconnectForDevice(localDBTestCDJ)
        #expect(pdb.closeCalls == 1)
        #expect(fs.unlinks.count == 1)
    }

    @Test("OneLibrary 파일 처리의 실패와 성공에서 임시 파일 수명을 지킨다", arguments: ["write", "unlink", "fetch", "success"])
    @DJLinkActor func oneLibraryFileLifetime(scenario: String) async throws {
        let fs = LocalDBFailingFileSystem()
        fs.failWrite = scenario == "write"
        fs.failUnlink = scenario == "unlink"
        let oneLibrary = LocalDBFakeAdapter(type: .oneLibrary, rows: [])
        let pdb = LocalDBFakeAdapter(type: .pdb, rows: [])
        var openCalls = 0
        let dependencies = LocalDBDependencies(
            fetchFile: { options in
                if scenario == "fetch", options.path.hasSuffix("exportLibrary.db") {
                    throw DJLinkError("시험용 다운로드 실패")
                }
                return [1, 2, 3]
            }, fileSystem: fs,
            makeOneLibraryAdapter: { _ in
                openCalls += 1
                if scenario == "success" { return oneLibrary }
                throw DJLinkError("시험용 OneLibrary 열기 실패")
            }, makeMetadataORM: { pdb }, hydrateDatabase: { _ in })
        let local = LocalDatabase(
            hostDevice: localDBTestHost, deviceManager: LocalDBFakeDeviceSource(),
            statusEmitter: LocalDBFakeMediaSlotSource(), dependencies: dependencies)
        let loaded = try await local.get(3, .usb)
        #expect(loaded?.type == (scenario == "success" ? .oneLibrary : .pdb))
        if scenario == "fetch" {
            #expect(fs.writes.isEmpty)
            #expect(fs.unlinks.isEmpty)
            #expect(openCalls == 0)
        } else {
            #expect(fs.writes.count == 1)
            #expect(openCalls == (scenario == "write" ? 0 : 1))
            #expect(fs.unlinks == (scenario == "success" ? [] : fs.writes))
        }
        local.disconnectForDevice(localDBTestCDJ)
        #expect(fs.unlinks == fs.writes)
        #expect(oneLibrary.closeCalls == (scenario == "success" ? 1 : 0))
    }

    // 이슈 #22
    @Test("같은 종류의 PCOB·PCO2 태그를 덮어쓰지 않고 파일 순서대로 잇는다")
    @DJLinkActor func anlzCueListsConcatenate() async throws {
        let track = LocalDBAnlzTrackReference(analyzePath: "/ANLZ0000")
        // DAT: 핫 큐 목록(1) 뒤에 메모리 목록(0)이 온다.
        let dat = createAnlzFile([
            anlzCueList(
                type: 1,
                [
                    anlzCue(hotCue: 1, type: 1, time: 1000, loopTime: 0xffff_ffff),
                    anlzCue(hotCue: 2, type: 2, time: 2000, loopTime: 3000),
                ]),
            anlzCueList(
                type: 0,
                [
                    anlzCue(hotCue: 0, type: 1, time: 4000, loopTime: 0xffff_ffff),
                    anlzCue(hotCue: 0, type: 2, time: 5000, loopTime: 6000),
                ]),
        ])
        let datResult = try await loadAnlz(track, type: "DAT", anlzResolver: { _ in dat })
        #expect(
            datResult.cueAndLoops == [
                .hotCue(.init(offset: 1000, button: .A)),
                .hotLoop(.init(offset: 2000, button: .B, length: 1000)),
                .cuePoint(.init(offset: 4000)),
                .loop(.init(offset: 5000, length: 1000)),
            ])
        // EXT: 핫 큐 D 목록 뒤의 빈 메모리 PCOB가 앞 목록을 지우지 않고, PCO2 두 목록도 잇는다.
        let ext = createAnlzFile([
            anlzCueList(type: 1, [anlzCue(hotCue: 4, type: 1, time: 7000, loopTime: 0xffff_ffff)]),
            anlzCueList(type: 0, []),
            anlzExtendedCueList(type: 1, [anlzExtendedCue(hotCue: 1, type: 1, time: 1000, loopTime: 0)]),
            anlzExtendedCueList(
                type: 0,
                [
                    anlzExtendedCue(hotCue: 0, type: 1, time: 4000, loopTime: 0),
                    anlzExtendedCue(hotCue: 0, type: 2, time: 5000, loopTime: 6000),
                ]),
        ])
        let extResult = try await loadAnlz(track, type: "EXT", anlzResolver: { _ in ext })
        #expect(extResult.cueAndLoops == [.hotCue(.init(offset: 7000, button: .D))])
        #expect(
            extResult.extendedCues == [
                .init(hotCue: 1, type: 1, time: 1000),
                .init(hotCue: 0, type: 1, time: 4000),
                .init(hotCue: 0, type: 2, time: 5000, loopTime: 6000),
            ])
    }

    // 이슈 #26. 고친 원본 버그가 아니라 원본 Kaitai 동작으로 되돌린 것이다.
    @Test("알 수 없는 mood의 PSSI도 EXT 전체를 실패시키지 않고 원본 Kaitai 배치대로 읽는다")
    @DJLinkActor func unknownMoodSongStructure() async throws {
        // rekordbox처럼 kind u2가 있는 24바이트 항목 두 개를 평문으로 쓰고 mood만 4로 둔다.
        var plain = [UInt8](repeating: 0, count: 32 + 24 * 2)
        plain.replaceSubrange(0..<4, with: "PSSI".utf8)
        plain.replaceSubrange(4..<8, with: anlzBE32(32))
        plain.replaceSubrange(8..<12, with: anlzBE32(plain.count))
        plain.replaceSubrange(12..<16, with: anlzBE32(24))
        plain.replaceSubrange(16..<18, with: anlzBE16(2))
        plain.replaceSubrange(18..<20, with: anlzBE16(4))
        plain.replaceSubrange(26..<28, with: anlzBE16(128))
        plain[30] = 3
        // 항목 0(32..<56): 번호 1, 박자 1, kind 1, +19 = 5, fill_in 1, fill 박자 60.
        plain.replaceSubrange(32..<34, with: anlzBE16(1))
        plain.replaceSubrange(34..<36, with: anlzBE16(1))
        plain.replaceSubrange(36..<38, with: anlzBE16(1))
        plain[51] = 5
        plain[53] = 1
        plain.replaceSubrange(54..<56, with: anlzBE16(60))
        // 항목 1(56..<80): 번호 2, 박자 33, kind 2, fill_in 1, fill 박자 64.
        plain.replaceSubrange(56..<58, with: anlzBE16(2))
        plain.replaceSubrange(58..<60, with: anlzBE16(33))
        plain.replaceSubrange(60..<62, with: anlzBE16(2))
        plain[77] = 1
        plain.replaceSubrange(78..<80, with: anlzBE16(64))
        let hd = createWaveSection("PWV5", numEntries: 1, entryBytes: 2, unknown: true, data: [0xff, 0xfc])
        let color = createWaveSection(
            "PWV4", numEntries: 1, entryBytes: 6, unknown: true, data: [10, 20, 30, 40, 50, 60])
        let detail = createWaveSection("PWV3", numEntries: 2, entryBytes: 1, unknown: true, data: [0x00, 0xff])
        let bytes = createAnlzFile([hd, maskPSSI(plain), color, detail])
        let section = try #require(try readLocalDBAnlz(bytes).first { $0.fourcc == "PSSI" })
        #expect(section.mood == 4)
        #expect(section.phrases.map(\.kind) == [.unknownTag, .unknownTag])
        let result = try await loadAnlz(
            LocalDBAnlzTrackReference(analyzePath: "/ANLZ0000"), type: .ext, anlzResolver: { _ in bytes })
        // PSSI 앞뒤의 파형 태그도 그대로 남는다.
        #expect(result.waveformHd == [.init(height: 31, color: [1, 1, 1])])
        #expect(result.waveformColorPreview == [10, 20, 30, 40, 50, 60])
        #expect(result.waveformDetail == [0, 255])
        // 기대값은 원본 rekordbox_anlz.ksy의 song_structure_entry 배치로 손으로 셌다.
        // mood 4는 kind가 0바이트 unknown_tag라 항목이 22바이트다(2 + 2 + 0 + (24 - 9) + 1 + 2).
        // 항목 0(32~): 번호 1, 박자 1, fill_in은 +19 바이트(5), fill 박자는 +20~21(0x0001, 원래 fill_in 1).
        // 항목 1(54~): 번호는 원래 항목 0의 fill 박자(60), 박자는 원래 항목 1의 번호(2), fill_in은 0.
        // makeSongStructure는 mood를 'high'로, kind를 undefined로, phraseType을 'Unknown'으로 둔다.
        #expect(
            result.songStructure
                == .init(
                    mood: .high, bank: .hot, endBeat: 128,
                    phrases: [
                        .init(index: 1, beat: 1, kind: nil, phraseType: "Unknown", fill: 5, fillBeat: 1),
                        .init(index: 60, beat: 2, kind: nil, phraseType: "Unknown"),
                    ]))
    }

    // 이슈 #26
    @Test("알 수 없는 mood의 PSSI 항목은 len_entry_bytes보다 2바이트 짧게 읽고 그만큼만 요구한다")
    func unknownMoodPhraseLength() throws {
        func file(length: Int, lenEntryBytes: Int) -> [UInt8] {
            // mood 0에서 원본이 읽는 22바이트 배치로 항목 두 개를 쓴다.
            var plain = [UInt8](repeating: 0, count: 32 + 22 * 2)
            plain.replaceSubrange(0..<4, with: "PSSI".utf8)
            plain.replaceSubrange(4..<8, with: anlzBE32(32))
            plain.replaceSubrange(12..<16, with: anlzBE32(lenEntryBytes))
            plain.replaceSubrange(16..<18, with: anlzBE16(2))
            for i in 0..<2 {
                let p = 32 + 22 * i
                plain.replaceSubrange(p..<p + 2, with: anlzBE16(i + 1))
                plain.replaceSubrange(p + 2..<p + 4, with: anlzBE16(1 + 32 * i))
                plain[p + 19] = 1
                plain.replaceSubrange(p + 20..<p + 22, with: anlzBE16(60 + i))
            }
            plain = Array(plain.prefix(length))
            plain.replaceSubrange(8..<12, with: anlzBE32(length))
            return createAnlzFile([maskPSSI(plain)])
        }
        let parsed = try #require(try readLocalDBAnlz(file(length: 32 + 22 * 2, lenEntryBytes: 24)).first)
        #expect(parsed.mood == 0)
        #expect(parsed.phrases.map(\.phraseNumber) == [1, 2])
        #expect(parsed.phrases.map(\.beatNumber) == [1, 33])
        #expect(parsed.phrases.map(\.kind) == [.unknownTag, .unknownTag])
        #expect(parsed.phrases.map(\.fillIn) == [1, 1])
        #expect(parsed.phrases.map(\.fillInBeatNumber) == [60, 61])
        // 한 바이트 모자라면 원본 Kaitai도 마지막 fill 박자를 읽다 EOF로 실패한다.
        #expect(throws: (any Error).self) {
            try readLocalDBAnlz(file(length: 32 + 22 * 2 - 1, lenEntryBytes: 24))
        }
        // len_entry_bytes가 9보다 작으면 원본은 음수 길이를 건너뛰려다 실패한다.
        #expect(throws: (any Error).self) {
            try readLocalDBAnlz(file(length: 32 + 22 * 2, lenEntryBytes: 8))
        }
    }
}

/// 원본 cue_entry 배치의 56바이트 PCPT 항목.
private func anlzCue(hotCue: Int, type: UInt8, time: Int, loopTime: Int) -> [UInt8] {
    let body: [UInt8] =
        anlzBE32(hotCue) + anlzBE32(1) + anlzBE32(0x10000) + anlzBE16(0xffff) + anlzBE16(0xffff) + [type, 0]
        + anlzBE16(1000) + anlzBE32(time) + anlzBE32(loopTime) + [UInt8](repeating: 0, count: 16)
    return anlzSection("PCPT", body, headerLength: 28)
}

/// 원본 cue_tag: 목록 형(1 핫 큐, 0 메모리)과 항목 수를 머리에 둔 PCOB 태그.
private func anlzCueList(type: Int, _ cues: [[UInt8]]) -> [UInt8] {
    anlzSection(
        "PCOB", anlzBE32(type) + anlzBE16(0) + anlzBE16(cues.count) + anlzBE32(0) + cues.flatMap { $0 },
        headerLength: 24)
}

/// 원본 cue_extended_entry의 가장 짧은 40바이트 PCP2 항목(주석·색 없음).
private func anlzExtendedCue(hotCue: Int, type: UInt8, time: Int, loopTime: Int) -> [UInt8] {
    var entry = [UInt8](repeating: 0, count: 40)
    entry.replaceSubrange(0..<4, with: "PCP2".utf8)
    entry.replaceSubrange(4..<8, with: anlzBE32(16))
    entry.replaceSubrange(8..<12, with: anlzBE32(40))
    entry.replaceSubrange(12..<16, with: anlzBE32(hotCue))
    entry[16] = type
    entry.replaceSubrange(20..<24, with: anlzBE32(time))
    entry.replaceSubrange(24..<28, with: anlzBE32(loopTime))
    return entry
}

/// 원본 cue_extended_tag: 목록 형(1 핫 큐, 0 메모리)과 항목 수를 머리에 둔 PCO2 태그.
private func anlzExtendedCueList(type: Int, _ cues: [[UInt8]]) -> [UInt8] {
    anlzSection(
        "PCO2", anlzBE32(type) + anlzBE16(cues.count) + anlzBE16(0) + cues.flatMap { $0 }, headerLength: 20)
}

/// 평문 PSSI 태그(머리 포함)의 18바이트 뒤에 원본과 같은 마스크(열쇠 + len_entries)를 씌운다.
private func maskPSSI(_ plain: [UInt8]) -> [UInt8] {
    var section = plain
    let count = (Int(section[16]) << 8) | Int(section[17])
    let mask: [UInt8] = [
        0xCB, 0xE1, 0xEE, 0xFA, 0xE5, 0xEE, 0xAD, 0xEE, 0xE9, 0xD2, 0xE9, 0xEB, 0xE1, 0xE9, 0xF3, 0xE8, 0xE9,
        0xF4, 0xE1,
    ]
    for i in 18..<section.count {
        section[i] ^= mask[(i - 18) % mask.count] &+ UInt8(truncatingIfNeeded: count)
    }
    return section
}

@DJLinkActor private final class LocalDBFailingFileSystem: LocalDBFileSystem {
    let tmpdir = "/tmp"
    var writes: [String] = []
    var unlinks: [String] = []
    var failWrite = false
    var failUnlink = false
    func writeFileSync(_ path: String, _ data: [UInt8]) throws {
        // 일부 바이트를 쓴 뒤 실패하는 경우에도 파일이 남았다고 가정한다.
        writes.append(path)
        if failWrite { throw DJLinkError("시험용 파일 쓰기 실패") }
    }
    func unlinkSync(_ path: String) throws {
        unlinks.append(path)
        if failUnlink { throw DJLinkError("시험용 파일 삭제 실패") }
    }
}
