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
            // 손상된 사슬은 기존 쪽 읽기 오류처럼 전파하고 부분 표를 돌려주지 않는다.
            guard visited.insert(pageRef).inserted else {
                throw LocalDBPdbError.readFailed(detail: "pdb chain repeats page \(pageRef)")
            }
            let page = try file.page(pageRef)
            if !page.header.isIndex {
                rows += page.slots.filter(\.isLive).map { Array(page.row($0)) }
            }
            // 쪽 번호는 사슬 순서와 다를 수 있으므로 마지막 쪽과 빈 후보만 종료 경계로 쓴다.
            if pageRef == pointer.lastPage || page.header.nextPage == pointer.emptyCandidate {
                break
            }
            pageRef = page.header.nextPage
        }
        return .init(type: Int(pointer.type), rows: rows)
    }
}
