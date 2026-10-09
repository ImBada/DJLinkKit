import DJLinkKit
import Foundation

// 원본 tests/utils.ts

/// 원본 `mockDevice(extra)`. 바꿀 칸만 넘긴다.
public func mockDevice(
    id: DeviceID = 1,
    type: DeviceType = .cdj,
    name: String = "CDJ-test",
    ip: Address4 = try! Address4("10.0.0.1"),
    macAddr: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06],
    lastActive: Date? = nil
) -> Device {
    Device(name: name, id: id, type: type, macAddr: macAddr, ip: ip, lastActive: lastActive)
}

/// 원본 시험의 `jest.fn()`처럼 불린 인자를 모은다.
@DJLinkActor
public final class CallRecorder<Value> {
    public private(set) var calls: [Value] = []

    public nonisolated init() {}

    public func record(_ value: Value) {
        calls.append(value)
    }

    /// `(value) -> Void` 콜백으로 쓴다.
    public var handler: @DJLinkActor (Value) -> Void {
        { [unowned self] in self.record($0) }
    }

    public var callCount: Int { calls.count }
    public var wasCalled: Bool { !calls.isEmpty }
    public var lastCall: Value? { calls.last }

    /// `mockClear`·`mockReset`
    public func clear() {
        calls.removeAll()
    }
}
