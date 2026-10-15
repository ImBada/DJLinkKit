import DJLinkKit
import DJLinkPassive
import DJLinkTestSupport
import Testing

/// 닫힌 횟수와 연 횟수를 세는 가짜 백엔드. 실제 pcap은 열지 않는다.
@DJLinkActor
private final class WatchPcapBackend: PcapBackend {
    var opens = 0
    var closes = 0
    func deviceList() throws -> [CapDeviceListEntry] { [] }
    func open(device: String, filter: String, bufSize: Int, bufferSize: Int) throws { opens += 1 }
    func onPacket(_ handler: @escaping @DJLinkActor ([UInt8], Bool) -> Void) {}
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) {}
    func close() { closes += 1 }
}

/// `if_nametoindex`를 대신하는 값. 시험이 인터페이스 번호를 바꾼다(0 = 인터페이스가 사라짐).
@DJLinkActor
private final class FakeInterfaceIndex {
    var value: UInt32
    var lookups: [String] = []
    init(_ value: UInt32) { self.value = value }
    func lookup(_ name: String) -> UInt32 {
        lookups.append(name)
        return value
    }
}

@DJLinkActor
private struct Watched {
    let adapter: PcapAdapter
    let backend: WatchPcapBackend
    let clock: TestClock
    let index: FakeInterfaceIndex
    let errors: ErrorLog
}

@DJLinkActor
private final class ErrorLog {
    var messages: [String] = []
}

@DJLinkActor
private func makeWatched(index start: UInt32 = 12, platform: String = "darwin", iface: String = "en8") -> Watched {
    let backend = WatchPcapBackend()
    let clock = TestClock()
    let index = FakeInterfaceIndex(start)
    let adapter = PcapAdapter(
        config: .init(iface: iface), backend: backend, platform: platform,
        interfaceProvider: FakeInterfaceProvider([]), clock: clock, interfaceIndex: { index.lookup($0) })
    let errors = ErrorLog()
    adapter.on(.error) { errors.messages.append(String(describing: $0)) }
    return Watched(adapter: adapter, backend: backend, clock: clock, index: index, errors: errors)
}

@Suite("패시브 캡처 인터페이스 사라짐 수정")
@DJLinkActor
struct PassivePcapUpstreamFixTests {
    @Test("인터페이스 번호가 0이 되면 오류를 한 번 내고 캡처를 멈추고 백엔드를 닫는다")
    func interfaceDisappears() throws {
        let w = makeWatched()
        try w.adapter.start()
        #expect(w.adapter.isCapturing)
        #expect(w.backend.opens == 1)
        w.clock.advance(ms: 1000)
        #expect(w.errors.messages.isEmpty)

        w.index.value = 0
        w.clock.advance(ms: 1000)
        #expect(w.errors.messages.count == 1)
        #expect(w.errors.messages[0].contains("en8"))
        #expect(!w.adapter.isCapturing)
        #expect(w.backend.closes == 1)
        #expect(w.clock.pendingTimerCount == 0)

        // 멈춘 뒤에는 더 보지 않는다.
        w.clock.advance(ms: 10_000)
        #expect(w.errors.messages.count == 1)
        #expect(w.backend.closes == 1)
    }

    @Test("어댑터를 다시 꽂아 번호가 바뀌어도 같은 오류로 멈춘다")
    func interfaceIndexChanges() throws {
        let w = makeWatched()
        try w.adapter.start()
        w.index.value = 13
        w.clock.advance(ms: 1000)
        #expect(w.errors.messages.count == 1)
        #expect(w.errors.messages[0].contains("en8"))
        #expect(!w.adapter.isCapturing)
        #expect(w.backend.closes == 1)
        #expect(w.clock.pendingTimerCount == 0)
    }

    @Test("번호가 그대로면 몇 번을 확인해도 오류가 없고 캡처가 이어진다")
    func unchangedIndexIsQuiet() throws {
        let w = makeWatched()
        try w.adapter.start()
        w.clock.advance(ms: 120_000)
        #expect(w.errors.messages.isEmpty)
        #expect(w.adapter.isCapturing)
        #expect(w.backend.closes == 0)
        #expect(w.clock.pendingTimerCount == 1)
        // 시작할 때 한 번, 이어서 1초마다 한 번씩 본다.
        #expect(w.index.lookups.count == 1 + 120)
        #expect(Set(w.index.lookups) == ["en8"])
    }

    @Test("stop()이 감시 타이머를 지운다")
    func stopClearsTimer() throws {
        let w = makeWatched()
        try w.adapter.start()
        #expect(w.clock.pendingTimerCount == 1)
        w.adapter.stop()
        #expect(w.clock.pendingTimerCount == 0)
        #expect(w.backend.closes == 1)
        let lookups = w.index.lookups.count
        w.index.value = 0
        w.clock.advance(ms: 10_000)
        #expect(w.errors.messages.isEmpty)
        #expect(w.index.lookups.count == lookups)
    }

    @Test("win32는 장치 이름이 달라 감시하지 않는다")
    func win32HasNoWatcher() throws {
        let w = makeWatched(platform: "win32", iface: "Ethernet")
        try w.adapter.start()
        #expect(w.adapter.isCapturing)
        #expect(w.clock.pendingTimerCount == 0)
        w.index.value = 0
        w.clock.advance(ms: 10_000)
        #expect(w.errors.messages.isEmpty)
        #expect(w.adapter.isCapturing)
        #expect(w.index.lookups.isEmpty)
    }

    @Test("시작할 때 번호를 찾지 못하는 이름은 감시하지 않는다")
    func unknownNameAtStartHasNoWatcher() throws {
        let w = makeWatched(index: 0, iface: "any")
        try w.adapter.start()
        #expect(w.adapter.isCapturing)
        #expect(w.clock.pendingTimerCount == 0)
        w.clock.advance(ms: 10_000)
        #expect(w.errors.messages.isEmpty)
        #expect(w.adapter.isCapturing)
    }

    @Test("사라진 뒤 다시 start()하면 새 번호를 기준으로 감시한다")
    func restartsWithNewIndex() throws {
        let w = makeWatched()
        try w.adapter.start()
        w.index.value = 0
        w.clock.advance(ms: 1000)
        #expect(!w.adapter.isCapturing)

        w.index.value = 14
        try w.adapter.start()
        #expect(w.adapter.isCapturing)
        #expect(w.backend.opens == 2)
        #expect(w.clock.pendingTimerCount == 1)
        w.clock.advance(ms: 5000)
        #expect(w.errors.messages.count == 1)
        #expect(w.adapter.isCapturing)
    }

    @Test("stop 없이 어댑터를 해제해도 감시 타이머가 남지 않는다")
    func releaseWithoutStopClearsTimer() async throws {
        let clock = TestClock()
        var adapter: PcapAdapter? = PcapAdapter(
            config: .init(iface: "en8"), backend: WatchPcapBackend(), platform: "darwin",
            interfaceProvider: FakeInterfaceProvider([]), clock: clock, interfaceIndex: { _ in 12 })
        try adapter?.start()
        #expect(clock.pendingTimerCount == 1)
        weak let released = adapter
        adapter = nil
        #expect(released == nil)
        for _ in 0..<1000 where clock.pendingTimerCount != 0 { await Task.yield() }
        #expect(clock.pendingTimerCount == 0)
    }
}
