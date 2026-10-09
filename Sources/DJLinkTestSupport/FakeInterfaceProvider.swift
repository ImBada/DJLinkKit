import DJLinkKit
import Foundation

/// 원본 시험의 `jest.mock('os')`로 바꾼 `networkInterfaces()`를 대신한다.
public final class FakeInterfaceProvider: InterfaceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var value: [(name: String, addresses: [NetworkInterfaceInfo])]

    public init(_ interfaces: [(name: String, addresses: [NetworkInterfaceInfo])] = []) {
        value = interfaces
    }

    /// 시험 도중 값을 바꾼다(`mockReturnValue`).
    public func set(_ interfaces: [(name: String, addresses: [NetworkInterfaceInfo])]) {
        lock.withLock { value = interfaces }
    }

    public func networkInterfaces() -> [(name: String, addresses: [NetworkInterfaceInfo])] {
        lock.withLock { value }
    }
}
