import DJLinkKit
import Testing

@testable import djlink

private func makeState(
    deviceId: Int = 1, trackId: Int = 5, playState: CDJStatus.PlayState = .playing, beat: Int = 1, pitch: Double = 0,
    isOnAir: Bool = false
) -> CDJStatus.State {
    CDJStatus.State(
        deviceId: deviceId, trackId: trackId, trackDeviceId: deviceId, trackSlot: .usb, trackType: .rb,
        playState: playState, isOnAir: isOnAir, isSync: false, isBpmSync: false, isMaster: false,
        isEmergencyMode: false, trackBPM: 128, effectivePitch: pitch, sliderPitch: pitch, beatInMeasure: beat,
        beatsUntilCue: nil, beat: nil, deviceType: 0x1f, packetNum: 0)
}

@Suite("CLI output formatting")
struct CLIFormatTests {
    @Test("log lines carry the signale-like kind")
    func logLine() {
        #expect(formatLogLine(.await, "Bringing up prolink network") == "[await] Bringing up prolink network")
        #expect(formatLogLine(.star, "x") == "[star] x")
    }

    @Test("warnings and errors go to the error stream")
    func streams() {
        let output = BufferCLIOutput()
        output.log(.info, "a")
        output.log(.warn, "b")
        output.log(.error, "c")
        #expect(output.lines == ["[info] a"])
        #expect(output.errorLines == ["[warn] b", "[error] c"])
    }

    @Test("the logger hides debug lines unless verbose")
    func loggerLevels() {
        let quiet = BufferCLIOutput()
        let quietLogger = CLILogger(output: quiet, verbose: false)
        quietLogger.debug("d")
        quietLogger.trace("t")
        quietLogger.info("i", 1, "x")
        #expect(quiet.errorLines == ["[info] i 1 x"])
        let loud = BufferCLIOutput()
        let loudLogger = CLILogger(output: loud, verbose: true)
        loudLogger.debug("d")
        loudLogger.trace("t")
        #expect(loud.errorLines == ["[debug] d", "[trace] t"])
    }

    @Test("devices are formatted with id, type, address and mac")
    func device() throws {
        let device = Device(
            name: "CDJ-3000", id: 2, type: .cdj, macAddr: [0xc8, 0x3d, 0xfc, 0, 1, 0xff],
            ip: try Address4("192.168.1.20"))
        #expect(formatDevice(device) == "CDJ-3000 [id: 2] type=CDJ ip=192.168.1.20 mac=c8:3d:fc:00:01:ff")
    }

    @Test("milliseconds are formatted as m:ss.mmm")
    func milliseconds() {
        #expect(formatMilliseconds(0) == "0:00.000")
        #expect(formatMilliseconds(61_234) == "1:01.234")
        #expect(formatMilliseconds(-1_500) == "-0:01.500")
    }

    @Test("status lines show play state, track and flags")
    func status() {
        let line = formatStatus(makeState(isOnAir: true))
        #expect(line.contains("device=1"))
        #expect(line.contains("Playing"))
        #expect(line.contains("track=5"))
        #expect(line.contains("bpm=128.00"))
        #expect(line.contains("[on-air]"))
        #expect(formatStatus(makeState(trackId: 0)).contains("no track"))
    }

    @Test("on-air channels are listed in order")
    func onAir() {
        let line = formatOnAir(
            .init(deviceId: 33, channels: [2: false, 1: true, 3: false, 4: true], isSixChannel: false))
        #expect(line == "on-air device=33 1=on 2=off 3=off 4=on (4ch)")
    }

    @Test("position lines show the playhead")
    func position() {
        let line = formatPosition(.init(deviceId: 2, trackLength: 300, playhead: 65_500, pitch: 3.26, bpm: nil))
        #expect(line == "position device=2 1:05.500 / 300s pitch=3.26% bpm=-")
    }

    @Test("summaries handle missing data")
    func summaries() {
        #expect(formatBeatGridSummary(nil) == "beatgrid: none")
        #expect(formatBeatGridSummary([]) == "beatgrid: none")
        let grid = [BeatGridBeat(offset: 100, count: 1, bpm: 128), BeatGridBeat(offset: 2_000, count: 2, bpm: 128)]
        #expect(formatBeatGridSummary(grid) == "beatgrid: 2 beats, first=0:00.100 bpm=128.00, last=0:02.000")
        #expect(formatWaveformSummary(nil) == "waveform: none")
        #expect(
            formatWaveformSummary(Waveforms(waveformHd: [.init(height: 1, color: [0, 0, 0])]))
                == "waveform: hd=1 segments")
        #expect(formatCueSummary(nil, extended: nil) == "cues: none")
        #expect(formatCueSummary([], extended: nil) == "cues: db: 0")
        let extended = [
            ExtendedCue(hotCue: 1, type: 1, time: 0), ExtendedCue(hotCue: 0, type: 2, time: 1, loopTime: 2),
        ]
        #expect(formatCueSummary(nil, extended: extended) == "cues: anlz: 2 (hot=1 loops=1)")
    }

    @Test("byte counts are readable")
    func bytes() {
        #expect(formatByteCount(10) == "10 B")
        #expect(formatByteCount(2048) == "2 KiB")
        #expect(formatByteCount(5 * 1024 * 1024) == "5 MiB")
    }

    @Test("the status filter prints only when the key values change")
    func statusFilter() {
        var filter = StatusLineFilter(all: false)
        let r1 = filter.line(for: makeState(beat: 1))
        #expect(r1 != nil)
        // 박 번호만 바뀐 상태는 건너뛴다.
        let r2 = filter.line(for: makeState(beat: 2))
        #expect(r2 == nil)
        let r3 = filter.line(for: makeState(beat: 3))
        #expect(r3 == nil)
        // 재생 상태가 바뀌면 낸다.
        let r4 = filter.line(for: makeState(playState: .cued))
        #expect(r4 != nil)
        // 피치가 바뀌면 낸다.
        let r5 = filter.line(for: makeState(playState: .cued, pitch: 1.5))
        #expect(r5 != nil)
        // 다른 장치는 따로 센다.
        let r6 = filter.line(for: makeState(deviceId: 2))
        #expect(r6 != nil)
        let r7 = filter.line(for: makeState(deviceId: 2))
        #expect(r7 == nil)
    }

    @Test("the status filter prints everything with --all")
    func statusFilterAll() {
        var filter = StatusLineFilter(all: true)
        let r8 = filter.line(for: makeState(beat: 1))
        #expect(r8 != nil)
        let r9 = filter.line(for: makeState(beat: 1))
        #expect(r9 != nil)
    }

    @Test("the throttle holds a key back until the interval has passed")
    func throttle() {
        var throttle = LineThrottle(intervalMs: 500)
        let r10 = throttle.shouldEmit(key: 1, nowMs: 1_000)
        #expect(r10)
        let r11 = throttle.shouldEmit(key: 1, nowMs: 1_499)
        #expect(!r11)
        let r12 = throttle.shouldEmit(key: 2, nowMs: 1_100)
        #expect(r12)
        let r13 = throttle.shouldEmit(key: 1, nowMs: 1_500)
        #expect(r13)
        var all = LineThrottle(intervalMs: 0)
        let r14 = all.shouldEmit(key: 1, nowMs: 1_000)
        #expect(r14)
        let r15 = all.shouldEmit(key: 1, nowMs: 1_000)
        #expect(r15)
    }

    @Test("interfaces are chosen by name, IPv4 and non-internal only")
    func interfaces() {
        let lo = NetworkInterfaceInfo(
            address: "127.0.0.1", netmask: "255.0.0.0", family: "IPv4", mac: "00:00:00:00:00:00", internal: true,
            cidr: "127.0.0.1/8")
        let v6 = NetworkInterfaceInfo(
            address: "fe80::1", netmask: "ffff:ffff:ffff:ffff::", family: "IPv6", mac: "aa:bb:cc:dd:ee:ff",
            internal: false, cidr: nil, scopeid: 1)
        let v4 = NetworkInterfaceInfo(
            address: "192.168.1.10", netmask: "255.255.255.0", family: "IPv4", mac: "aa:bb:cc:dd:ee:ff",
            internal: false,
            cidr: "192.168.1.10/24")
        let list: [(name: String, addresses: [NetworkInterfaceInfo])] = [
            ("lo0", [lo]), ("en0", [v6, v4]), ("en5", [v6]),
        ]
        #expect(selectInterface(named: "en0", in: list) == v4)
        #expect(selectInterface(named: "lo0", in: list) == nil)
        #expect(selectInterface(named: "en5", in: list) == nil)
        #expect(selectInterface(named: "missing", in: list) == nil)
        #expect(candidateInterfaceNames(list) == ["en0"])
    }
}
