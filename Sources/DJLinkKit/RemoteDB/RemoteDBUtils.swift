public func fieldFromDescriptor(_ descriptor: LookupDescriptor) throws -> RemoteDBUInt32 {
    try RemoteDBUInt32([
        UInt8(truncatingIfNeeded: descriptor.hostDevice.id), UInt8(descriptor.menuTarget.rawValue),
        UInt8(truncatingIfNeeded: descriptor.trackSlot.rawValue),
        UInt8(truncatingIfNeeded: descriptor.trackType.rawValue),
    ])
}
@DJLinkActor public func makeRenderMessage(_ descriptor: LookupDescriptor, _ offset: Int, _ count: Int, _ total: Int)
    throws -> Message
{
    Message(
        type: .renderMenu,
        args: [
            try fieldFromDescriptor(descriptor), RemoteDBUInt32(offset), RemoteDBUInt32(count),
            RemoteDBUInt32(0), RemoteDBUInt32(total), RemoteDBUInt32(0x0c),
        ])
}
/// 원본 async generator처럼 next를 부를 때만 페이지와 항목을 읽는다.
public struct RemoteDBRenderedItems: AsyncSequence, Sendable {
    public typealias Element = Items
    let conn: Connection
    let descriptor: LookupDescriptor
    let total: Int
    let span: TelemetrySpan
    public struct AsyncIterator: AsyncIteratorProtocol {
        let source: RemoteDBRenderedItems
        var itemsRead = 0
        var pendingFooter = false
        @DJLinkActor public mutating func next() async throws -> Items? {
            if pendingFooter {
                _ = try await source.conn.readMessage(.menuFooter, source.span)
                pendingFooter = false
            }
            if itemsRead >= source.total { return nil }
            if itemsRead % 64 == 0 {
                let count = Swift.min(64, source.total - itemsRead)
                try await source.conn.writeMessage(
                    makeRenderMessage(source.descriptor, itemsRead, count, source.total), source.span)
                _ = try await source.conn.readMessage(.menuHeader, source.span)
            }
            let resp = try await source.conn.readMessage(.menuItem, source.span)
            guard case let .item(item) = try resp.data else { throw DJLinkError("Expected menu item") }
            itemsRead += 1
            pendingFooter = itemsRead % 64 == 0 || itemsRead == source.total
            return item
        }
    }
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(source: self) }
}
public func renderItems(_ conn: Connection, _ descriptor: LookupDescriptor, _ total: Int, _ span: TelemetrySpan)
    -> RemoteDBRenderedItems
{
    RemoteDBRenderedItems(conn: conn, descriptor: descriptor, total: total, span: span)
}
public func findColor(_ items: [Items]) -> Items? { items.last { (0x13...0x1b).contains($0.type.rawValue) } }
