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
        repeat {
            let page = try file.page(pageRef)
            pageRef = page.header.nextPage
            if !page.header.isIndex {
                rows += page.slots.filter(\.isLive).map { Array(page.row($0)) }
            }
        } while pageRef <= pointer.lastPage
        return .init(type: Int(pointer.type), rows: rows)
    }
}
