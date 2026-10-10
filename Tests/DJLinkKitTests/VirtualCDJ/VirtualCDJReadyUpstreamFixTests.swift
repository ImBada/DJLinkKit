import DJLinkKit
import DJLinkTestSupport
import Testing

private let readyTestInterface = NetworkInterfaceInfo(
    address: "192.168.1.100", netmask: "255.255.255.0", family: "IPv4",
    mac: "00:11:22:33:44:55", internal: false, cidr: nil)

@Suite("announcer ready 원본 버그 수정")
@DJLinkActor
struct VirtualCDJReadyUpstreamFixTests {
    private func checkWaiters(
        clock: TestClock, duration: Int, ready: @escaping @DJLinkActor () async -> Void
    ) async {
        var started = 0
        var completed: [Int] = []
        let first = Task {
            started += 1
            await ready()
            completed.append(1)
        }
        await clock.settle()
        #expect(started == 1)
        let second = Task {
            started += 1
            await ready()
            completed.append(2)
        }
        await clock.settle()
        #expect(started == 2)
        #expect(completed.isEmpty)
        clock.advance(ms: Double(duration))
        await clock.settle()
        #expect(completed.sorted() == [1, 2])
        // 수정 전에는 앞 대기자가 끝나지 않는다. 실패 시험 자체가 무한 대기하지 않게 한다.
        if completed.count == 2 {
            await first.value
            await second.value
        }
        await ready()
    }

    @Test("일반 announcer의 ready를 다시 읽어도 앞 대기자가 함께 풀린다", arguments: [false, true])
    func activeWaiters(withPolicy: Bool) async throws {
        let clock = TestClock()
        let socket = FakeUDPSocket()
        let manager = DeviceManager(socket, clock: clock)
        let policy: @Sendable (DeviceID) -> Bool = { $0 >= 7 }
        let allowsDeviceId = withPolicy ? policy : nil
        let announcer = Announcer(
            DeviceReference(try getVirtualCDJ(readyTestInterface, 7)), socket, manager, readyTestInterface,
            fullStartup: true, clock: clock, allowsDeviceId: allowsDeviceId)
        try announcer.start()
        defer { announcer.stop() }
        await checkWaiters(clock: clock, duration: STARTUP_STAGE_INTERVAL * 12, ready: { await announcer.ready })
    }

    @Test("처음 번호를 거부하면 이미 기다리던 ready와 waitUntilReady가 모두 풀린다")
    func initialRejectionWaiters() async throws {
        let clock = TestClock()
        let socket = FakeUDPSocket()
        let manager = DeviceManager(socket, clock: clock)
        let announcer = Announcer(
            DeviceReference(try getVirtualCDJ(readyTestInterface, 7)), socket, manager, readyTestInterface,
            fullStartup: true, clock: clock, allowsDeviceId: { _ in false })
        var started = 0
        var completed = 0
        let first = Task {
            started += 1
            await announcer.ready
            completed += 1
        }
        let second = Task {
            started += 1
            await #expect(throws: DJLinkError("Device ID 7 is not allowed")) {
                try await announcer.waitUntilReady()
            }
            completed += 1
        }
        await clock.settle()
        #expect(started == 2)
        #expect(completed == 0)
        #expect(throws: DJLinkError("Device ID 7 is not allowed")) { try announcer.start() }
        await clock.settle()
        #expect(completed == 2)
        if completed == 2 {
            await first.value
            await second.value
        }
        // 거부 뒤 다시 불러도 즉시 끝나고 기존 대기자는 중복 해제하지 않는다.
        await announcer.ready
        await #expect(throws: DJLinkError("Device ID 7 is not allowed")) { try await announcer.waitUntilReady() }
        #expect(throws: DJLinkError("Device ID 7 is not allowed")) { try announcer.start() }
        #expect(completed == 2)
        #expect(socket.sent.isEmpty)
        #expect(clock.pendingTimerCount == 0)
    }

    @Test("Stagehand announcer의 ready를 다시 읽어도 앞 대기자가 함께 풀린다")
    func stagehandWaiters() async throws {
        let clock = TestClock()
        let socket = FakeUDPSocket()
        let manager = DeviceManager(socket, clock: clock)
        let announcer = StagehandAnnouncer(
            DeviceReference(try getVirtualStagehand(readyTestInterface, 150)), socket, manager, readyTestInterface,
            clock: clock)
        try announcer.start()
        defer { announcer.stop() }
        await checkWaiters(clock: clock, duration: STAGEHAND_STARTUP_INTERVAL * 6, ready: { await announcer.ready })
    }
}
