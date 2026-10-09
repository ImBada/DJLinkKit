import DJLinkControl
import DJLinkKit
import DJLinkTestSupport
import Foundation
import Testing

@testable import djlink

// 가짜 소켓·시계·파일로 CLI 실행 경로를 돌린다. 실제 소켓은 열지 않고 LAN에 아무것도 보내지 않는다.

@Suite("CLI runtime: interface scope")
@DJLinkActor
struct CLIRuntimeScopeTests {
    @Test("--iface binds every UDP socket to that interface and announces only inside its subnet")
    func explicitInterface() async throws {
        let h = CLIHarness()
        let task = h.start(["watch", "--iface", "en7"])
        await h.settle()
        #expect(h.fakeFactory.udpSockets.count == 3)
        for socket in h.fakeFactory.udpSockets { #expect(socket.boundInterfaces == ["en7"]) }

        try h.announce(try cdj(1, "192.168.1.20"))
        try h.announce(try cdj(2, "10.9.0.9"))  // 다른 LAN의 장치
        h.clock.advance(ms: 3000)
        let addresses = Set(h.announceSocket.sent.map(\.address))
        #expect(addresses == ["192.168.1.20"])
        #expect(!h.announceSocket.sent.isEmpty)

        h.abort.interrupt()
        #expect(await task.value == 130)
        #expect(h.allSocketsClosed)
    }

    @Test("without --iface the interface comes from the first device and the same limits apply")
    func autoInterface() async throws {
        let h = CLIHarness()
        let task = h.start(["status"])
        await h.settle()
        // 아직 장치가 없어 묶지도 보내지도 않는다.
        #expect(h.fakeFactory.udpSockets.allSatisfy { $0.boundInterfaces.isEmpty })
        #expect(h.totalSent == 0)

        try h.announce(try cdj(2, "10.9.0.9"))  // 맞는 인터페이스가 없는 장치는 건너뛴다
        await h.settle()
        #expect(h.fakeFactory.udpSockets.allSatisfy { $0.boundInterfaces.isEmpty })
        try h.announce(try cdj(1, "192.168.1.20"))
        await h.settle()
        for socket in h.fakeFactory.udpSockets { #expect(socket.boundInterfaces == ["en7"]) }

        h.clock.advance(ms: 3000)
        #expect(Set(h.announceSocket.sent.map(\.address)) == ["192.168.1.20"])
        h.abort.interrupt()
        #expect(await task.value == 130)
        #expect(h.allSocketsClosed)
    }

    @Test("an already discovered device picks the interface without waiting for another announce")
    func existingDevicePicksInterface() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        _ = try await session.openNetwork(options: CLICommonOptions())
        try h.announce(try cdj(1, "192.168.1.20"))
        final class Flag { var done = false }
        let flag = Flag()
        let join = Task { @DJLinkActor in
            try await session.join(options: CLICommonOptions())
            flag.done = true
        }
        await h.settle()
        let finishedWithoutNewDevice = flag.done
        h.abort.interrupt()  // 실패해도 시험이 멈추지 않게
        _ = try? await join.value
        await session.cleanup()
        #expect(finishedWithoutNewDevice)
        #expect(session.scope?.name == "en7")
    }

    @Test("waiting for peers gives up with exit code 1 after the discovery timeout and sends nothing")
    func discoveryTimeout() async throws {
        let h = CLIHarness()
        let task = h.start(["mixstatus"])
        await h.settle()
        try h.announce(try cdj(2, "10.9.0.9"))
        h.clock.advance(by: .seconds(discoveryTimeoutSeconds))
        #expect(await task.value == 1)
        #expect(h.output.errorLines.contains { $0.contains("\(discoveryTimeoutSeconds)초 안에 장치를 찾지 못했다") })
        #expect(h.totalSent == 0)
        #expect(h.allSocketsClosed)
    }

    @Test("a target device outside the interface subnet is refused")
    func targetOutsideSubnet() async throws {
        let h = CLIHarness()
        let task = h.start(["metadata", "--iface", "en7", "--device", "2", "--slot", "usb", "--track-id", "1"])
        await h.settle()
        try h.announce(try cdj(2, "10.9.0.9"))
        #expect(await task.value == 1)
        #expect(h.output.errorLines.contains { $0.contains("서브넷 밖") })
        #expect(h.totalSent == 0)
        #expect(h.allSocketsClosed)
    }

    @Test("an unknown interface name is reported with the usable names before any socket opens")
    func unknownInterface() async {
        let h = CLIHarness()
        let task = h.start(["watch", "--iface", "nope0"])
        #expect(await task.value == 1)
        #expect(h.output.errorLines.contains { $0.contains("en7") && $0.contains("en0") })
        #expect(h.fakeFactory.udpSockets.isEmpty)
    }

    @Test("fetch without --join still binds to the interface of its target before any NFS request")
    func fetchBindsInterface() async throws {
        let h = CLIHarness()
        let task = h.start([
            "fetch", "--device", "1", "--slot", "usb", "--path", "PIONEER/rekordbox/export.pdb", "--out",
            "/tmp/out.pdb",
        ])
        await h.settle()
        #expect(h.fakeFactory.udpSockets.allSatisfy { $0.boundInterfaces.isEmpty })
        try h.announce(try cdj(1, "192.168.1.20"))
        #expect(await task.value == 0)
        for socket in h.fakeFactory.udpSockets { #expect(socket.boundInterfaces == ["en7"]) }
        #expect(h.nfs.fetches == ["PIONEER/rekordbox/export.pdb"])
        #expect(h.files.published.map(\.path) == ["/tmp/out.pdb"])
        // 참여하지 않으므로 아무것도 보내지 않는다.
        #expect(h.totalSent == 0)
        #expect(h.allSocketsClosed)
    }
}

@Suite("CLI runtime: device number policy")
@DJLinkActor
struct CLIRuntimeNumberTests {
    /// 7~32번을 모두 쓰는 장치들을 announce한다. 충돌이 나면 1~6번만 남는다.
    private func crowd(_ h: CLIHarness) throws {
        for id in 7...32 { try h.announce(try cdj(id, "192.168.1.\(id + 10)", name: "CDJ-\(id)")) }
    }

    @Test("a conflict that would move to 1-6 without --allow-player-id stops before any packet carries that number")
    func conflictToPlayerNumber() async throws {
        let h = CLIHarness()
        let task = h.start(["watch", "--iface", "en7"])
        await h.settle()
        try crowd(h)
        h.clock.advance(ms: 1500)
        #expect(!h.announceSocket.sent.isEmpty)
        h.announceSocket.clearSent()

        h.announceSocket.emitMessage(conflictPacket(7))
        h.clock.advance(ms: 30_000)
        #expect(await task.value == 1)
        #expect(h.announceSocket.sent.isEmpty, "번호를 다시 고른 뒤에는 어떤 번호로도 패킷이 나가면 안 된다")
        #expect(h.output.errorLines.contains { $0.contains("6번") && $0.contains("--allow-player-id") })
        #expect(h.allSocketsClosed)
    }

    @Test("with --allow-player-id the same conflict moves to the player number and keeps running")
    func conflictAllowed() async throws {
        let h = CLIHarness()
        let task = h.start(["watch", "--iface", "en7", "--allow-player-id"])
        await h.settle()
        try crowd(h)
        h.clock.advance(ms: 1500)
        h.announceSocket.clearSent()
        h.announceSocket.emitMessage(conflictPacket(7))
        h.clock.advance(ms: 3000)
        #expect(h.announceSocket.sent.contains { $0.message[0x24] == 6 })
        h.abort.interrupt()
        #expect(await task.value == 130)
    }

    @Test("no packet ever carries a number below 7 when it is not allowed")
    func neverBelowSeven() async throws {
        let h = CLIHarness()
        let task = h.start(["watch", "--iface", "en7"])
        await h.settle()
        try crowd(h)
        h.announceSocket.emitMessage(conflictPacket(7))
        h.clock.advance(ms: 30_000)
        _ = await task.value
        for sent in h.fakeFactory.udpSockets.flatMap(\.sent) where sent.message.count > 0x24 {
            #expect(sent.message[0x24] >= 7 || sent.message[0x24] == 0)
        }
    }
}

@Suite("CLI runtime: abort and cleanup")
@DJLinkActor
struct CLIRuntimeAbortTests {
    @Test("an interrupt while waiting for peers never starts announcing and closes every socket")
    func interruptBeforeJoin() async throws {
        let h = CLIHarness()
        let task = h.start(["watch"])
        await h.settle()
        h.abort.interrupt()
        // 중단된 뒤에 장치가 보여도 참여하지 않는다.
        try h.announce(try cdj(1, "192.168.1.20"))
        h.clock.advance(ms: 10_000)
        #expect(await task.value == 130)
        #expect(h.totalSent == 0)
        #expect(h.allSocketsClosed)
        #expect(h.output.lines.contains("[info] Interrupted, closing"))
    }

    @Test("after an interrupt no further packets leave and the timers are gone")
    func noSendsAfterInterrupt() async throws {
        let h = CLIHarness()
        let task = h.start(["status", "--iface", "en7"])
        await h.settle()
        try h.announce(try cdj(1, "192.168.1.20"))
        h.clock.advance(ms: 3000)
        let before = h.totalSent
        #expect(before > 0)
        h.abort.interrupt()
        #expect(await task.value == 130)
        h.clock.advance(ms: 60_000)
        #expect(h.totalSent == before)
        #expect(h.clock.pendingTimerCount == 0)
    }

    @Test("an abort stops control packets even if the caller already holds the control service")
    func noControlSendAfterAbort() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let options = CLICommonOptions(iface: "en7")
        let network = try await session.openNetwork(options: options)
        let device = try cdj(1, "192.168.1.20")
        try h.announce(device)
        try await session.join(options: options, knownDevice: device)
        let control = try #require(network.control)
        let announced = h.totalSent

        h.abort.interrupt()
        await #expect(throws: CLIAborted.self) {
            try await control.loadTrack(device, 3, LoadSource(deviceId: 1, slot: .usb, trackType: .rb))
        }
        await #expect(throws: CLIAborted.self) { try await control.setPlayState(device, .playing) }
        #expect(h.totalSent == announced, "중단 뒤에는 제어 패킷이 한 바이트도 나가지 않는다")
        await session.cleanup()
        #expect(h.allSocketsClosed)
    }

    @Test("after an abort a session creates no sockets, joins nothing and refuses NFS paths")
    func nothingNewAfterAbort() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        h.abort.interrupt()
        await #expect(throws: CLIAborted.self) { _ = try await session.openNetwork(options: CLICommonOptions()) }
        await #expect(throws: CLIAborted.self) { try await session.join(options: CLICommonOptions()) }
        #expect(throws: CLIAborted.self) { try session.guardNFS("PIONEER/rekordbox/export.pdb") }
        #expect(h.fakeFactory.udpSockets.isEmpty)
        #expect(throws: CLIAborted.self) { _ = try session.sockets.createUDPSocket(reuseAddr: true) }
        #expect(throws: CLIAborted.self) { _ = try session.sockets.createTCPConnection() }
        var spawned = false
        session.spawn { spawned = true }
        await h.settle()
        #expect(!spawned)
    }

    @Test("an interrupt during the download writes no file and exits 130")
    func interruptDuringFetch() async throws {
        let h = CLIHarness()
        h.nfs.duringFetch = { [abort = h.abort] in abort.interrupt() }
        let task = h.start([
            "fetch", "--device", "1", "--slot", "usb", "--path", "PIONEER/rekordbox/export.pdb", "--out",
            "/tmp/out.pdb",
        ])
        await h.settle()
        try h.announce(try cdj(1, "192.168.1.20"))
        #expect(await task.value == 130)
        #expect(h.files.writes == 0)
        #expect(h.allSocketsClosed)
    }

    @Test("the watch download writes nothing once aborted, even if the file arrives afterwards")
    func watchWritesNothingAfterAbort() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let db = FakeNetworkDatabase(track: makeTrack(), file: [9, 9, 9])
        db.beforeFileReturns = { [abort = h.abort] in abort.interrupt() }
        await session.handleTrackChange(makeState(), db: db, downloadDir: "/tmp/dl")
        #expect(h.files.writes == 0)
        await session.cleanup()
    }

    @Test("a hung download is cut off by the timeout: exit 1, nothing written, sockets closed")
    func fetchTimeout() async throws {
        let h = CLIHarness()
        h.nfs.hangs = true
        let task = h.start([
            "fetch", "--device", "1", "--slot", "usb", "--path", "a", "--out", "/tmp/out.bin", "--timeout", "20",
        ])
        await h.settle()
        try h.announce(try cdj(1, "192.168.1.20"))
        await h.settle()
        h.clock.advance(by: .seconds(20))
        #expect(await task.value == 1)
        #expect(h.output.errorLines.contains { $0.contains("제한 시간 20초") })
        #expect(h.files.writes == 0)
        #expect(h.allSocketsClosed)
    }

    @Test("a metadata command that never finds its device times out with exit 1 and sends nothing")
    func metadataTimeout() async throws {
        let h = CLIHarness()
        let task = h.start([
            "metadata", "--iface", "en7", "--device", "1", "--slot", "usb", "--track-id", "1", "--timeout", "5",
        ])
        await h.settle()
        h.clock.advance(by: .seconds(5))
        #expect(await task.value == 1)
        #expect(h.output.errorLines.contains { $0.contains("제한 시간 5초") })
        #expect(h.totalSent == 0)
        #expect(h.allSocketsClosed)
        #expect(h.clock.pendingTimerCount == 0)
    }

    @Test("a failed bring-up closes the sockets it already created")
    func bringUpFailureClosesSockets() async throws {
        let failing = FailingBindFactory(failingIndex: 1)
        let h = CLIHarness(socketFactory: failing, fake: failing.inner)
        let task = h.start(["status", "--iface", "en7"])
        #expect(await task.value == 1)
        #expect(failing.inner.udpSockets.count == 3)
        #expect(failing.inner.udpSockets.allSatisfy { $0.isClosed })
        #expect(h.output.errorLines.contains { $0.contains("bind failed") })
    }

    @Test("sockets created outside bringOnline (for example NFS RPC sockets) are closed at the end")
    func extraSocketsClosed() async throws {
        let h = CLIHarness()
        let tcp = FakeTCPConnection(clock: h.clock)
        h.fakeFactory.makeTCPConnection = { tcp }
        let session = h.makeSession()
        _ = try await session.openNetwork(options: CLICommonOptions(iface: "en7"))
        let rpc = try session.sockets.createUDPSocket(reuseAddr: false)
        _ = try session.sockets.createTCPConnection()
        #expect(h.fakeFactory.udpSockets.count == 4)
        #expect((rpc as? GuardedUDPSocket)?.inner as? FakeUDPSocket === h.fakeFactory.udpSockets[3])
        #expect(h.fakeFactory.udpSockets[3].boundInterfaces == ["en7"], "나중에 만든 소켓도 같은 인터페이스에 묶인다")
        await session.cleanup()
        #expect(h.allSocketsClosed)
        #expect(!tcp.isOpen)
        // 다시 불러도 안전하다.
        await session.cleanup()
    }
}

@Suite("CLI runtime: exit codes")
@DJLinkActor
struct CLIRuntimeExitCodeTests {
    @Test("the continuous commands end with 130 on Ctrl-C", arguments: ["watch", "status", "mixstatus"])
    func continuousCommands(name: String) async throws {
        let h = CLIHarness()
        let task = h.start([name, "--iface", "en7"])
        await h.settle()
        h.abort.interrupt()
        #expect(await task.value == 130)
        #expect(h.allSocketsClosed)
    }

    @Test("devices lists what it heard and ends 0, or 130 with the list when interrupted")
    func devices() async throws {
        let h = CLIHarness()
        let task = h.start(["devices", "--seconds", "5"])
        await h.settle()
        try h.announce(try cdj(1, "192.168.1.20"))
        h.clock.advance(by: .seconds(5))
        #expect(await task.value == 0)
        #expect(h.output.lines.contains { $0.contains("CDJ-3000 [id: 1]") })
        #expect(h.totalSent == 0)
        #expect(h.allSocketsClosed)

        let h2 = CLIHarness()
        let task2 = h2.start(["devices", "--seconds", "5"])
        await h2.settle()
        try h2.announce(try cdj(2, "192.168.1.21"))
        h2.abort.interrupt()
        #expect(await task2.value == 130)
        #expect(h2.output.lines.contains { $0.contains("[id: 2]") })
    }

    @Test("passive ends with 130 on Ctrl-C and stops the capture")
    func passiveInterrupt() async throws {
        let h = CLIHarness()
        let task = h.start(["passive", "--iface", "en7"])
        await h.settle()
        #expect(h.backend.opened == ["en7"])
        h.abort.interrupt()
        #expect(await task.value == 130)
        #expect(h.backend.closed)
        #expect(h.fakeFactory.udpSockets.isEmpty)
    }

    @Test("a capture error is printed and ends with 1 after cleanup")
    func passiveCaptureError() async throws {
        let h = CLIHarness()
        let task = h.start(["passive", "--iface", "en7"])
        await h.settle()
        let handler = try #require(h.backend.errorHandler)
        handler(DJLinkError("pcap broke"))
        #expect(await task.value == 1)
        #expect(h.output.errorLines.contains { $0.contains("pcap broke") })
        #expect(h.backend.closed)
    }

    @Test("a capture that cannot start exits 1 and closes it")
    func passiveStartFailure() async throws {
        let h = CLIHarness()
        h.backend.openError = DJLinkError("no bpf access")
        let task = h.start(["passive", "--iface", "en7"])
        #expect(await task.value == 1)
        #expect(h.output.errorLines.contains { $0.contains("패시브 캡처를 시작하지 못했다") })
        #expect(h.backend.closed)
    }

    @Test("a failed waveform lookup still prints the rest but exits 1; a missing waveform is not a failure")
    func metadataFailureVersusMissing() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let target = CLITrackTarget(deviceId: 1, slot: .usb, trackId: 5)

        let missing = FakeNetworkDatabase(track: makeTrack(), file: nil)
        #expect(try await session.printMetadata(db: missing, target: target) == 0)
        #expect(h.output.lines.contains("waveform: none"))

        let failing = FakeNetworkDatabase(track: makeTrack(), file: nil)
        failing.waveformError = DJLinkError("waveform lookup failed")
        let output2 = BufferCLIOutput()
        let session2 = CLISession(runtime: h.makeRuntime(), output: output2, abort: CLIAbort())
        #expect(try await session2.printMetadata(db: failing, target: target) == 1)
        #expect(output2.errorLines.contains { $0.contains("waveform lookup failed") })
        #expect(output2.lines.contains { $0.contains("cues") || $0.contains("cue") })

        let analysisFails = FakeNetworkDatabase(track: makeTrack(), file: nil)
        analysisFails.analysisError = DJLinkError("analysis lookup failed")
        let output3 = BufferCLIOutput()
        let session3 = CLISession(runtime: h.makeRuntime(), output: output3, abort: CLIAbort())
        #expect(try await session3.printMetadata(db: analysisFails, target: target) == 1)
        #expect(output3.errorLines.contains { $0.contains("analysis lookup failed") })

        let noTrack = FakeNetworkDatabase(track: nil, file: nil)
        let session4 = CLISession(runtime: h.makeRuntime(), output: BufferCLIOutput(), abort: CLIAbort())
        #expect(try await session4.printMetadata(db: noTrack, target: target) == 1)
    }
}

@Suite("CLI runtime: control")
@DJLinkActor
struct CLIRuntimeControlTests {
    @Test("a wrong confirmation name exits 2, never joins and sends nothing")
    func wrongConfirmation() async throws {
        let h = CLIHarness()
        let task = h.start([
            "control", "load", "--iface", "en7", "--device", "1", "--slot", "usb", "--track-id", "3",
            "--confirm", "CDJ-2000",
        ])
        await h.settle()
        try h.announce(try cdj(1, "192.168.1.20"))
        #expect(await task.value == 2)
        #expect(h.totalSent == 0)
        #expect(h.allSocketsClosed)
    }

    @Test("a confirmed load goes only to the target on the bound interface")
    func confirmedLoad() async throws {
        let h = CLIHarness()
        let task = h.start([
            "control", "load", "--iface", "en7", "--device", "1", "--slot", "usb", "--track-id", "3",
            "--confirm", "CDJ-3000",
        ])
        await h.settle()
        try h.announce(try cdj(1, "192.168.1.20"))
        try h.announce(try cdj(2, "10.9.0.9"))
        await h.settle()
        h.clock.advance(by: .seconds(3))
        #expect(await task.value == 0)
        let loads = h.statusSocket.sent.filter { $0.port == STATUS_PORT }
        #expect(loads.count == 1)
        #expect(loads.first?.address == "192.168.1.20")
        #expect(h.beatSocket.sent.isEmpty)
        #expect(!h.fakeFactory.udpSockets.flatMap(\.sent).contains { $0.address == "10.9.0.9" })
        #expect(h.allSocketsClosed)
    }

    @Test("play and pause are refused at execution time too, before any socket opens")
    func playPauseRefusedAtRuntime() async {
        let h = CLIHarness()
        let device5 = CLIControlRequest(
            action: .pause, deviceId: 5, load: nil, confirm: "CDJ-3000", unverifiedPlaystate: true)
        #expect(await h.start(.control(CLICommonOptions(), device5)).value == 2)
        let unflagged = CLIControlRequest(action: .play, deviceId: 2, load: nil, confirm: "CDJ-3000")
        #expect(await h.start(.control(CLICommonOptions(), unflagged)).value == 2)
        let device4 = CLIControlRequest(
            action: .play, deviceId: 4, load: nil, confirm: "CDJ-3000", unverifiedPlaystate: true)
        #expect(await h.start(.control(CLICommonOptions(), device4)).value == 2)
        #expect(h.fakeFactory.udpSockets.isEmpty)
    }

    @Test("an allowed play reaches only the target through the beat socket")
    func allowedPlay() async throws {
        let h = CLIHarness()
        let request = CLIControlRequest(
            action: .play, deviceId: 2, load: nil, confirm: "CDJ-3000", unverifiedPlaystate: true)
        let task = h.start(.control(CLICommonOptions(iface: "en7"), request))
        await h.settle()
        try h.announce(try cdj(2, "192.168.1.21"))
        await h.settle()
        h.clock.advance(by: .seconds(3))
        #expect(await task.value == 0)
        let sent = h.beatSocket.sent
        #expect(sent.count == 1)
        #expect(sent.first?.address == "192.168.1.21")
        #expect(sent.first?.port == BEAT_PORT)
    }
}

@Suite("CLI runtime: files")
@DJLinkActor
struct CLIRuntimeFileTests {
    @Test("fetch refuses an existing output before opening any socket")
    func fetchExistingOutput() async {
        let h = CLIHarness(existingFiles: ["/tmp/out.bin"])
        let task = h.start([
            "fetch", "--device", "1", "--slot", "usb", "--path", "a", "--out", "/tmp/out.bin",
        ])
        #expect(await task.value == 1)
        #expect(h.output.errorLines.contains { $0.contains("이미 있다") })
        #expect(h.fakeFactory.udpSockets.isEmpty)
        #expect(h.files.writes == 0)
    }

    @Test("a file that appears while downloading is not overwritten")
    func fetchLosesRace() async throws {
        let h = CLIHarness()
        h.files.state.withLock { $0.publishError = CLIFileExistsError(path: "/tmp/out.bin") }
        let task = h.start(["fetch", "--device", "1", "--slot", "usb", "--path", "a", "--out", "/tmp/out.bin"])
        await h.settle()
        try h.announce(try cdj(1, "192.168.1.20"))
        #expect(await task.value == 1)
        #expect(h.output.errorLines.contains { $0.contains("덮어쓰지 않는다") })
        #expect(h.files.published.isEmpty)
    }

    @Test("a never-read path given straight to the executor is refused before any NFS request")
    func fetchNeverReadAtRuntime() async throws {
        let h = CLIHarness()
        let target = CLIFetchTarget(
            deviceId: 1, slot: .usb, path: "PIONEER/extracted/x", out: "/tmp/out.bin", join: false)
        let task = h.start(.fetch(CLICommonOptions(), target))
        await h.settle()
        try h.announce(try cdj(1, "192.168.1.20"))
        #expect(await task.value == 1)
        #expect(h.nfs.requestCount == 0)
        #expect(h.files.writes == 0)
    }

    @Test("watch downloads under a name with device, slot and track number")
    func watchFileName() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let db = FakeNetworkDatabase(track: makeTrack(), file: [7, 7])
        await session.handleTrackChange(makeState(deviceId: 1, trackId: 5), db: db, downloadDir: "/tmp/dl")
        #expect(h.files.directories == ["/tmp/dl"])
        #expect(h.files.published.map(\.path) == ["/tmp/dl/1-usb-5-a.mp3"])
        #expect(h.files.published.first?.data == [7, 7])
        // 같은 파일 이름이 다른 장치·곡에서 와도 서로 덮어쓰지 않는다.
        await session.handleTrackChange(makeState(deviceId: 2, trackId: 9, slot: .sd), db: db, downloadDir: "/tmp/dl")
        #expect(h.files.published.map(\.path) == ["/tmp/dl/1-usb-5-a.mp3", "/tmp/dl/2-sd-9-a.mp3"])
    }

    @Test("watch does not query a device that sits outside the interface subnet")
    func watchSkipsForeignDevice() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        _ = try await session.openNetwork(options: CLICommonOptions(iface: "en7"))
        try h.announce(try cdj(3, "10.9.0.9"))  // 같은 번호를 쓰는 다른 LAN의 장치
        let db = FakeNetworkDatabase(track: makeTrack(), file: [1])
        await session.handleTrackChange(
            makeState(deviceId: 1, trackId: 5, trackDeviceId: 3), db: db, downloadDir: "/tmp/dl")
        #expect(db.metadataRequests == 0)
        #expect(db.fileRequests == 0)
        #expect(h.files.writes == 0)
        #expect(h.output.errorLines.contains { $0.contains("서브넷 밖") })
        await session.cleanup()
    }

    @Test("watch skips a file that already exists instead of overwriting it")
    func watchExistingFile() async throws {
        let h = CLIHarness(existingFiles: ["/tmp/dl/1-usb-5-a.mp3"])
        let session = h.makeSession()
        let db = FakeNetworkDatabase(track: makeTrack(), file: [7, 7])
        await session.handleTrackChange(makeState(deviceId: 1, trackId: 5), db: db, downloadDir: "/tmp/dl")
        #expect(h.files.published.isEmpty)
        #expect(h.output.errorLines.contains { $0.contains("덮어쓰지 않는다") })
    }

    @Test("watch without --download-dir writes nothing and a never-read track path is not downloaded")
    func watchNoDirectory() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let db = FakeNetworkDatabase(track: makeTrack(), file: [7])
        await session.handleTrackChange(makeState(), db: db, downloadDir: nil)
        #expect(h.files.writes == 0)
        #expect(db.fileRequests == 0)
        let hidden = FakeNetworkDatabase(track: makeTrack(filePath: "PIONEER/extracted/x"), file: [7])
        await session.handleTrackChange(makeState(), db: hidden, downloadDir: "/tmp/dl")
        #expect(hidden.fileRequests == 0)
        #expect(h.files.writes == 0)
    }
}

@Suite("CLI runtime: NFS path checks")
@DJLinkActor
struct CLIRuntimeNFSGuardTests {
    private let device = mockDevice(ip: try! Address4("192.168.1.20"))

    @Test("every database fetch path goes through the never-read check before NFS")
    func databaseFetch() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let fetch = session.guardedDBDependencies().fetchFile
        for path in ["PIONEER/extracted/a", "PIONEER/CDP/b", "PIONEER/djprofile.nxs", ".PIONEER/extracted/c"] {
            await #expect(throws: CLIRuntimeError.self, "\(path)") { _ = try await fetch(device, .usb, path, nil, nil) }
        }
        #expect(h.nfs.requestCount == 0)
        // 분석 파일(ANLZ)은 읽는다.
        _ = try await fetch(device, .usb, "PIONEER/USBANLZ/P016/0000875E/ANLZ0000.DAT", nil, 8192)
        #expect(h.nfs.fetches == ["PIONEER/USBANLZ/P016/0000875E/ANLZ0000.DAT"])
    }

    @Test("local database loading goes through the same check")
    func localDatabaseFetch() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let fetch = session.guardedLocalDBDependencies().fetchFile
        await #expect(throws: CLIRuntimeError.self) {
            _ = try await fetch(LocalDBFetchFileOptions(device: device, slot: .usb, path: "PIONEER/extracted/x"))
        }
        #expect(h.nfs.requestCount == 0)
        _ = try await fetch(LocalDBFetchFileOptions(device: device, slot: .usb, path: ".PIONEER/rekordbox/export.pdb"))
        #expect(h.nfs.fetches == [".PIONEER/rekordbox/export.pdb"])
    }

    @Test("artwork extraction reads through the check as well")
    func artworkSource() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let source = CLIGuardedArtworkSource(session: session)
        await #expect(throws: CLIRuntimeError.self) {
            _ = try await source.getFileInfo(device: device, slot: .usb, path: "PIONEER/CDP/x")
        }
        await #expect(throws: CLIRuntimeError.self) {
            _ = try await source.fetchFileRange(
                device: device, slot: .usb, path: "PIONEER/extracted/x", offset: 0, length: 4)
        }
        let extract = session.guardedDBDependencies().extractArtworkFromDevice
        await #expect(throws: CLIRuntimeError.self) {
            _ = try await extract(device, .usb, "PIONEER/extracted/x", noopLogger)
        }
        #expect(h.nfs.requestCount == 0)
        #expect(try await source.getFileInfo(device: device, slot: .usb, path: "Contents/a.mp3").size == 3)
        #expect(h.nfs.sizes == ["Contents/a.mp3"])
    }

    @Test("once aborted even an allowed path is not requested")
    func abortedFetch() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        h.abort.interrupt()
        await #expect(throws: CLIAborted.self) {
            _ = try await session.guardedDBDependencies().fetchFile(
                device, .usb, "PIONEER/rekordbox/export.pdb", nil, nil)
        }
        await #expect(throws: CLIAborted.self) {
            _ = try await session.guardedLocalDBDependencies().fetchFile(
                LocalDBFetchFileOptions(device: device, slot: .usb, path: "PIONEER/rekordbox/export.pdb"))
        }
        #expect(h.nfs.requestCount == 0)
    }

    @Test("the temporary OneLibrary file is not written after an abort")
    func localFileSystem() async throws {
        let h = CLIHarness()
        let system = CLIGuardedLocalFileSystem(abort: h.abort)
        h.abort.interrupt()
        #expect(throws: CLIAborted.self) { try system.writeFileSync("/tmp/djlink-should-not-exist.db", [1]) }
        #expect(!FileManager.default.fileExists(atPath: "/tmp/djlink-should-not-exist.db"))
    }
}

@Suite("CLI runtime: socket registry")
@DJLinkActor
struct CLISocketRegistryTests {
    @Test("binding an interface covers sockets that exist and sockets created later")
    func bindsExistingAndFuture() throws {
        let fake = FakeSocketFactory()
        let registry = CLISocketRegistry(inner: fake, abort: CLIAbort())
        _ = try registry.createUDPSocket(reuseAddr: true)
        try registry.bindInterface(name: "en7")
        _ = try registry.createUDPSocket(reuseAddr: true)
        #expect(fake.udpSockets.map(\.boundInterfaces) == [["en7"], ["en7"]])
        #expect(registry.boundInterfaceName == "en7")
    }

    @Test("a socket that cannot be bound fails loudly and is still tracked for closing")
    func bindFailure() async throws {
        let fake = FakeSocketFactory()
        let registry = CLISocketRegistry(inner: fake, abort: CLIAbort())
        _ = try registry.createUDPSocket(reuseAddr: true)
        fake.udpSockets[0].boundInterfaceError = DJLinkError("IP_BOUND_IF failed")
        #expect(throws: DJLinkError("IP_BOUND_IF failed")) { try registry.bindInterface(name: "en7") }
        fake.udpSockets[0].boundInterfaceError = nil
        await registry.closeAll()
        #expect(fake.udpSockets[0].isClosed)
    }

    @Test("a send after the abort is dropped and reported as an error")
    func sendDropped() async throws {
        let fake = FakeSocketFactory()
        let abort = CLIAbort()
        let registry = CLISocketRegistry(inner: fake, abort: abort)
        let socket = try registry.createUDPSocket(reuseAddr: true)
        socket.send([1], port: 50000, address: "192.168.1.20")
        #expect(fake.udpSockets[0].sent.count == 1)
        abort.interrupt()
        await #expect(throws: CLIAborted.self) { try await udpSend(socket, [2], 50000, "192.168.1.20") }
        socket.send([3], port: 50000, address: "192.168.1.20")
        #expect(fake.udpSockets[0].sent.count == 1)
        await #expect(throws: CLIAborted.self) { _ = try await socket.bind(port: 1, address: nil) }
    }

    @Test("TCP connections stop connecting and writing once aborted")
    func tcpStops() async throws {
        let fake = FakeSocketFactory()
        let tcp = FakeTCPConnection()
        fake.makeTCPConnection = { tcp }
        let abort = CLIAbort()
        let registry = CLISocketRegistry(inner: fake, abort: abort)
        let connection = try registry.createTCPConnection()
        try await connection.connect(port: 12523, host: "192.168.1.20")
        try await connection.write([1])
        abort.interrupt()
        await #expect(throws: CLIAborted.self) { try await connection.connect(port: 1, host: "192.168.1.20") }
        await #expect(throws: CLIAborted.self) { try await connection.write([2]) }
        #expect(tcp.writes == [[1]])
        await registry.closeAll()
        #expect(!tcp.isOpen)
    }

    @Test("closing twice is harmless")
    func closeTwice() async throws {
        let fake = FakeSocketFactory()
        let registry = CLISocketRegistry(inner: fake, abort: CLIAbort())
        let socket = try registry.createUDPSocket(reuseAddr: true)
        try await udpClose(socket)
        await registry.closeAll()
        #expect(registry.openUDPSocketCount == 0)
    }
}

/// `NetworkDatabase`의 가짜. 곡·파일·오류를 정한 대로 돌려준다.
@DJLinkActor
final class FakeNetworkDatabase: NetworkDatabase {
    let track: Track?
    let file: [UInt8]?
    var waveformError: (any Error)?
    var analysisError: (any Error)?
    var beforeFileReturns: (@DJLinkActor () -> Void)?
    private(set) var fileRequests = 0
    private(set) var metadataRequests = 0
    var hostDevice: Device { mockDevice(id: 7) }

    nonisolated init(track: Track?, file: [UInt8]?) {
        self.track = track
        self.file = file
    }

    func getDatabaseType(_ deviceId: DeviceID, _ slot: MediaSlot) -> DatabaseType? { nil }
    func getMetadata(_ opts: GetMetadata.Options) async throws -> Track? {
        metadataRequests += 1
        return track
    }

    func getFile(_ opts: GetFile.Options) async throws -> [UInt8]? {
        fileRequests += 1
        beforeFileReturns?()
        return file
    }

    func getArtworkThumbnail(_ opts: GetArtworkThumbnail.Options) async throws -> [UInt8]? { nil }
    func getArtwork(_ opts: GetArtworkFromFile.Options) async -> [UInt8]? { nil }

    func getWaveforms(_ opts: GetWaveforms.Options) async throws -> Waveforms? {
        if let waveformError { throw waveformError }
        return nil
    }

    func getTrackAnalysis(_ opts: GetTrackAnalysis.Options) async throws -> TrackAnalysis? {
        if let analysisError { throw analysisError }
        return nil
    }

    func getPlaylist(_ opts: GetPlaylist.Options) async throws -> PlaylistContents? { nil }
}
