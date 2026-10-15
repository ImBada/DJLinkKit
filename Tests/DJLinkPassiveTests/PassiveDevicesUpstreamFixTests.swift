import DJLinkKit
import DJLinkPassive
import DJLinkTestSupport
import Testing

@DJLinkActor
private func makePassiveManager(_ clock: TestClock) -> PassiveDeviceManager {
    let adapter = PcapAdapter(
        config: .init(iface: "en0"), backendFactory: { throw DJLinkError("시험에서 pcap을 열지 않는다") })
    return PassiveDeviceManager(adapter, clock: clock)
}

@Suite("패시브 장치 대기 원본 버그 수정")
@DJLinkActor
struct PassiveDevicesUpstreamFixTests {
    @Test("장치가 먼저 오면 해당 대기 타이머와 구독을 지운다")
    func clearsSuccessfulWaitTimer() async {
        let clock = TestClock()
        let manager = makePassiveManager(clock)
        let device = mockDevice(id: 7)
        let waiting = Task { await manager.getDeviceEnsured(7) }
        await clock.waitForTimers(atLeast: 1)
        #expect(clock.pendingTimerCount == 1)
        manager.emitter.emit(.connected, mockDevice(id: 8))
        #expect(clock.pendingTimerCount == 1)
        manager.emitter.emit(.connected, device)
        #expect(await waiting.value == device)
        #expect(clock.pendingTimerCount == 0)
        #expect(manager.emitter.listenerCount(.connected) == 0)
        clock.advance(ms: 2000)
        #expect(clock.pendingTimerCount == 0)
    }

    @Test("같은 장치를 기다리는 여러 호출의 타이머를 모두 지운다")
    func clearsAllSuccessfulWaitTimers() async {
        let clock = TestClock()
        let manager = makePassiveManager(clock)
        let device = mockDevice(id: 7)
        let first = Task { await manager.getDeviceEnsured(7, timeout: 1000) }
        let second = Task { await manager.getDeviceEnsured(7, timeout: 2000) }
        await clock.waitForTimers(atLeast: 2)
        manager.emitter.emit(.connected, device)
        #expect(await first.value == device)
        #expect(await second.value == device)
        #expect(clock.pendingTimerCount == 0)
        #expect(manager.emitter.listenerCount(.connected) == 0)
    }

    @Test("시간 제한이 먼저 지나면 타이머와 구독을 남기지 않는다")
    func timeoutCleanup() async {
        let clock = TestClock()
        let manager = makePassiveManager(clock)
        let waiting = Task { await manager.getDeviceEnsured(7, timeout: 100) }
        await clock.waitForTimers(atLeast: 1)
        clock.advance(ms: 100)
        #expect(await waiting.value == nil)
        #expect(clock.pendingTimerCount == 0)
        #expect(manager.emitter.listenerCount(.connected) == 0)
        manager.emitter.emit(.connected, mockDevice(id: 7))
    }
}
