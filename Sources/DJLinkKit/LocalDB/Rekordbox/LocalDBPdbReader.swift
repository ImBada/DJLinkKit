import Foundation

public enum LocalDBPdbError: Error, Equatable, Sendable { case readFailed(detail: String) }
public struct LocalDBPdbTable: Sendable {
    public var type: Int
    public var rows: [[UInt8]]
    public init(type: Int, rows: [[UInt8]]) {
        self.type = type
        self.rows = rows
    }
}
public typealias LocalDBPdbReader = @Sendable ([UInt8]) throws -> [LocalDBPdbTable]
// DJCrate PdbReader의 쪽·산 행 순회 부분. 원본이 쓰지 않는 exportExt·쓰기 모델은 옮기지 않는다.
public func readLocalDBPdb(_ bytes: [UInt8]) throws -> [LocalDBPdbTable] {
    let file = try PdbFile(data: bytes)
    return try file.header.tables.filter { pdbTables[Int($0.type)] != nil }.map { pointer in
        var rows: [[UInt8]] = []
        var pageRef = pointer.firstPage
        var visited: Set<UInt32> = []
        while true {
            // PLAN §9: 원본은 사슬이 순환하면 무한 루프에 빠졌다. 손상된 사슬은 기존 쪽 읽기 오류처럼 전파하고 부분 표를 돌려주지 않는다.
            guard visited.insert(pageRef).inserted else {
                throw LocalDBPdbError.readFailed(detail: "pdb chain repeats page \(pageRef)")
            }
            let page = try file.page(pageRef)
            if !page.header.isIndex {
                rows += page.slots.filter(\.isLive).map { Array(page.row($0)) }
            }
            // PLAN §9: 원본은 쪽 번호를 마지막 쪽 번호와 비교해 비단조 사슬에서 일찍 끝나거나 빈 후보 뒤로 읽었다.
            // 쪽 번호는 사슬 순서와 다를 수 있으므로 마지막 쪽과 빈 후보만 종료 경계로 쓴다.
            if pageRef == pointer.lastPage || page.header.nextPage == pointer.emptyCandidate {
                break
            }
            pageRef = page.header.nextPage
        }
        return .init(type: Int(pointer.type), rows: rows)
    }
}
