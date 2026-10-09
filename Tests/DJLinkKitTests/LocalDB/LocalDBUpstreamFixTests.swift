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
}
