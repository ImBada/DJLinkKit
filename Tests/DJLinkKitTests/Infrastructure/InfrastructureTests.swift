@testable import DJLinkKit
import DJLinkTestSupport
import Testing

// 포트 기반(EventHub·TestClock·FakeUDPSocket·바이트 도우미) 자체 시험. 원본 시험 대응이 아니다.

@DJLinkActor
private final class Sample: EventEmitting {
    let emitter = EventHub<Sample>()
    let clock: any DJLinkClock

    init(clock: any DJLinkClock) {
        self.clock = clock
    }

    func waitForPing(timeout: Duration) async -> Int? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            final class State {
                var finished = false
                var subscription: EventSubscription?
            }
            let state = State()
            let timer = clock.setTimeout(timeout) {
                guard !state.finished else { return }
                state.finished = true
                if let subscription = state.subscription { self.off(subscription) }
                continuation.resume(returning: nil)
            }
            state.subscription = on(.ping) { value in
                guard !state.finished else { return }
                state.finished = true
                self.clock.clearTimeout(timer)
                continuation.resume(returning: value)
            }
        }
    }
}

extension EventName where Owner == Sample, Payload == Int {
    static var ping: Self { .init("ping") }
}

extension EventName where Owner == Sample, Payload == String {
    static var named: Self { .init("named") }
}

@Suite("Infrastructure")
@DJLinkActor
struct InfrastructureTests {
    @Test("event hub delivers in order and honours once/off")
    func eventHub() {
        let sample = Sample(clock: TestClock())
        var seen: [String] = []
        sample.on(.ping) { seen.append("a\($0)") }
        let b = sample.on(.ping) { seen.append("b\($0)") }
        sample.once(.ping) { seen.append("once\($0)") }
        sample.on(.named) { seen.append($0) }
        sample.emitter.emit(.ping, 1)
        sample.off(b)
        sample.emitter.emit(.ping, 2)
        sample.emitter.emit(.named, "x")
        #expect(seen == ["a1", "b1", "once1", "a2", "x"])
    }

    @Test("test clock fires timers like jest fake timers")
    func testClock() {
        let clock = TestClock()
        var fired: [String] = []
        clock.setTimeout(.ms(100)) { fired.append("t100") }
        let interval = clock.setInterval(.ms(40)) { fired.append("i\(Int(clock.currentTime.inMilliseconds))") }
        clock.setTimeout(.ms(40)) {
            fired.append("t40")
            clock.setTimeout(.ms(10)) { fired.append("nested") }
        }
        clock.advance(ms: 75)
        #expect(fired == ["i40", "t40", "nested"])
        clock.advance(ms: 50)
        #expect(fired == ["i40", "t40", "nested", "i80", "t100", "i120"])
        clock.clearInterval(interval)
        clock.runAllTimers()
        #expect(clock.pendingTimerCount == 0)
    }

    @Test("async wait resolves through clock and events")
    func asyncWait() async {
        let clock = TestClock()
        let sample = Sample(clock: clock)
        let timedOut = Task { await sample.waitForPing(timeout: .ms(150)) }
        await clock.waitForTimers(atLeast: 1)
        clock.advance(ms: 150)
        #expect(await timedOut.value == nil)

        let received = Task { await sample.waitForPing(timeout: .ms(150)) }
        await clock.waitForTimers(atLeast: 1)
        sample.emitter.emit(.ping, 7)
        #expect(await received.value == 7)
    }

    @Test("fake socket records sends and delivers messages")
    func fakeSocket() async throws {
        let socket = FakeUDPSocket()
        var got: [[UInt8]] = []
        let listener = socket.onMessage { got.append($0) }
        socket.emitMessage([1, 2, 3])
        socket.off(listener)
        socket.emitMessage([4])
        #expect(got == [[1, 2, 3]])
        let sent = try await udpSend(socket, [9, 9], 50000, "10.0.0.255")
        #expect(sent == 2)
        #expect(socket.sent == [.init(message: [9, 9], port: 50000, address: "10.0.0.255")])
    }

    @Test("byte helpers read like Node Buffer")
    func bytes() throws {
        let buf: [UInt8] = [0x00, 0x01, 0xff, 0xfe, 0x41, 0x42]
        #expect(try buf.readUInt16BE(0) == 1)
        #expect(try buf.readInt16BE(2) == -2)
        #expect(try buf.readUInt32LE(0) == 0xfeff_0100)
        #expect(buf.toString(.ascii, 4) == "AB")
        #expect(buf.subarray(-2) == [0x41, 0x42])
        #expect(throws: BufferRangeError.self) { try buf.readUInt32BE(4) }
        let slice = buf[2...]
        #expect(try slice.readUInt8(0) == 0xff)
    }

    @Test("address4 matches ip-address behaviour")
    func address4() throws {
        let iface = try Address4("192.168.1.10/24")
        #expect(iface.endAddress().address == "192.168.1.255")
        #expect(try Address4("192.168.1.77").isInSubnet(iface))
        #expect(!(try Address4("192.168.2.77").isInSubnet(iface)))
        #expect(Address4.fromInteger(0x0a00_0001).address == "10.0.0.1")
        #expect(throws: AddressError.self) { try Address4("not-an-ip") }
    }

    // 루프백 시험(DJLINK_LOOPBACK_TESTS=1)에서는 실제 소켓을 허용하므로 그때는 돌리지 않는다.
    @Test("live sockets are refused inside the test process", .enabled(if: !TestProcess.loopbackTestsEnabled))
    func liveSocketGuard() {
        #expect(TestProcess.isRunning)
        #expect(throws: DJLinkError.self) { try LiveSocketFactory.shared.createUDPSocket(reuseAddr: true) }
    }
}

@Suite("JS string helpers")
struct JSStringHelperTests {
    @Test("numbers print like JS")
    func numbers() {
        #expect(128.0.jsNumberString == "128")
        #expect(2020.0.jsNumberString == "2020")
        #expect(0.1.jsNumberString == "0.1")
        #expect(0.00001.jsNumberString == "0.00001")
        #expect(0.0000001.jsNumberString == "1e-7")
        #expect(1e16.jsNumberString == "10000000000000000")
        #expect(1e21.jsNumberString == "1e+21")
        #expect((-0.0).jsNumberString == "0")
        #expect(Double.nan.jsNumberString == "null")
        #expect(128.5.jsNumberString == "128.5")
    }

    @Test("trim matches JS whitespace")
    func trim() {
        #expect("\u{FEFF} a \u{2028}".jsTrim() == "a")
        #expect("\u{0085}".jsTrim() == "\u{0085}")
        #expect("   ".jsTrim() == "")
    }
}
