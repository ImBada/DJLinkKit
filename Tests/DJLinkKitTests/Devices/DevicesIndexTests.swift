import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 tests/devices/index.spec.ts
// `jest.mock('src/devices/utils')`는 DeviceManager의 `deviceFromPacket` 주입으로, `jest.useFakeTimers()`는 TestClock으로 옮겼다.

/// 원본 `dfpMock`(`deviceFromPacket as jest.Mock`).
@DJLinkActor
private final class DeviceFromPacketMock {
    private(set) var calls: [[UInt8]] = []
    private var implementation: @DJLinkActor ([UInt8]) throws -> Device? = { _ in nil }

    func mockReturnValue(_ device: Device?) {
        implementation = { _ in device }
    }

    func mockImplementation(_ body: @escaping @DJLinkActor ([UInt8]) throws -> Device?) {
        implementation = body
    }

    func call(_ packet: [UInt8]) throws -> Device? {
        calls.append(packet)
        return try implementation(packet)
    }
}

@Suite("DeviceManager")
@DJLinkActor
struct DevicesIndexTests {
    // 원본은 describe 안에서 소켓 하나를 모든 시험이 같이 쓴다. Swift Suite는 시험마다 새 인스턴스라
    // 시험마다 새 소켓이 된다. 앞 시험의 DeviceManager가 남아 같이 듣는 것은 기대값에 영향이 없다.
    let mockSocket = FakeUDPSocket()
    private let dfpMock = DeviceFromPacketMock()
    let clock = TestClock()

    private func makeManager(deviceTimeout: Int) -> DeviceManager {
        let dfpMock = self.dfpMock
        return DeviceManager(
            mockSocket,
            config: .init(deviceTimeout: deviceTimeout),
            clock: clock,
            deviceFromPacket: { try dfpMock.call($0) }
        )
    }

    @Test("produces device lifecycle events")
    func lifecycleEvents() {
        let dm = makeManager(deviceTimeout: 100)

        let announceFn = CallRecorder<Device>()
        dm.on(.announced, announceFn.handler)

        let connectedFn = CallRecorder<Device>()
        dm.on(.connected, connectedFn.handler)

        let disconnectedFn = CallRecorder<Device>()
        dm.on(.disconnected, disconnectedFn.handler)

        // Mocked message value
        let deadBeef: [UInt8] = [0xde, 0xad, 0xbe, 0xef]

        let deviceExample = mockDevice()

        dfpMock.mockReturnValue(deviceExample)

        // Trigger device announcement
        mockSocket.emitMessage(deadBeef)

        #expect(dfpMock.calls.contains(deadBeef))
        #expect(connectedFn.calls.contains(deviceExample))
        #expect(announceFn.calls.contains(deviceExample))
        #expect(dm.devices.count == 1)
        #expect(dm.devices[1] == deviceExample)

        // Reset our emitter mocks for the next announcement
        announceFn.clear()
        connectedFn.clear()

        // Move forward 75ms, the device should not have timed out yet
        clock.advance(ms: 75)

        // Trigger device announcement
        mockSocket.emitMessage(deadBeef)

        #expect(!connectedFn.wasCalled)
        #expect(announceFn.calls.contains(deviceExample))

        // Device is still kept alive, as it has not expired since its last
        // announcement
        clock.advance(ms: 75)

        // Device will now timeout
        clock.advance(ms: 25)
        #expect(disconnectedFn.calls.contains(deviceExample))
        #expect(dm.devices.count == 0)

        // Reconfigure for longer timeout
        dm.reconfigure(.init(deviceTimeout: 500))

        // Device reconnects and emits a new connection event
        connectedFn.clear()
        mockSocket.emitMessage(deadBeef)

        #expect(connectedFn.calls.contains(deviceExample))

        disconnectedFn.clear()

        // Device will not timeout with reconfigured timeout
        clock.advance(ms: 400)
        #expect(!disconnectedFn.wasCalled)

        // Device will now timeout
        clock.advance(ms: 100)
        #expect(disconnectedFn.calls.contains(deviceExample))
    }

    @Test("does not announce invalid announce packets")
    func invalidAnnouncePackets() {
        let dm = makeManager(deviceTimeout: 100)

        let announceFn = CallRecorder<Device>()
        dm.on(.announced, announceFn.handler)

        dfpMock.mockReturnValue(nil)

        // Trigger device announcement
        mockSocket.emitMessage([])

        #expect(!announceFn.wasCalled)
        #expect(dm.devices.count == 0)
    }

    @Test("swallows parse errors instead of crashing the socket")
    func swallowsParseErrors() {
        // A malformed/truncated datagram can make deviceFromPacket throw. The
        // handler runs directly on the UDP 'message' event, so an uncaught throw
        // here crashes the process (NP3-446).
        let dm = makeManager(deviceTimeout: 100)

        let announceFn = CallRecorder<Device>()
        dm.on(.announced, announceFn.handler)

        dfpMock.mockImplementation { _ in
            throw DJLinkError("boom")
        }

        // 원본 `expect(() => mockSocket.emit(...)).not.toThrow()`: Swift에서 emitMessage는 던지지 않는 함수라
        // 처리기가 오류를 밖으로 내지 않고 끝나는 것만 확인한다.
        mockSocket.emitMessage([])
        #expect(!announceFn.wasCalled)
        #expect(dm.devices.count == 0)
    }

    @Test("does not announce or track virtual CDJ announcements")
    func ignoresVirtualCDJ() {
        let dm = makeManager(deviceTimeout: 100)

        let announceFn = CallRecorder<Device>()
        dm.on(.announced, announceFn.handler)

        let deviceExample = mockDevice(name: VIRTUAL_CDJ_NAME)

        dfpMock.mockReturnValue(deviceExample)

        // Trigger device announcement
        mockSocket.emitMessage([])

        #expect(!announceFn.wasCalled)
        #expect(dm.devices.count == 0)
    }

    @Test("waits for a device to appear using getDeviceEnsured")
    func getDeviceEnsuredWaits() async {
        let dm = makeManager(deviceTimeout: 100)

        let deviceExample = mockDevice()
        let gotDevice = Task { await dm.getDeviceEnsured(1) }
        // 원본 async 함수는 첫 await까지 동기로 돌며 구독과 타이머를 건다. 그때까지 기다린다.
        await clock.waitForTimers(atLeast: 1)

        clock.advance(ms: 75)

        dfpMock.mockReturnValue(deviceExample)

        // Trigger device announcement
        mockSocket.emitMessage([])

        #expect(await gotDevice.value == deviceExample)
    }

    @Test("timesout when waiting for device using getDeviceEnsured")
    func getDeviceEnsuredTimesOut() async {
        let dm = makeManager(deviceTimeout: 100)

        let gotDevice = Task { await dm.getDeviceEnsured(1, timeout: 150) }
        await clock.waitForTimers(atLeast: 1)

        clock.advance(ms: 150)
        #expect(await gotDevice.value == nil)
    }

    @Test("immedaitely returns a device when it already exists using getDeviceEnsured")
    func getDeviceEnsuredExisting() async {
        let dm = makeManager(deviceTimeout: 100)
        let deviceExample = mockDevice()
        dfpMock.mockReturnValue(deviceExample)
        mockSocket.emitMessage([])

        #expect(await dm.getDeviceEnsured(1, timeout: 100) == deviceExample)
    }
}
