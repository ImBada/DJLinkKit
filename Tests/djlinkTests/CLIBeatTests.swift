import DJLinkKit
import DJLinkTestSupport
import Testing

@testable import djlink

/// CDJ-2000nexus 1번의 실제 비트 패킷. 장치 이름·비트·템포만 있고 곡 정보는 없다.
private func capturedCLIBeat() -> [UInt8] {
    let hex =
        "5173707431576d4a4f4c2843444a2d323030306e6578757300000000000000010001003c0000016a000002d3000005a6000005a600000b4c00000b4cffffffffffffffffffffffffffffffffffffffffffffffff000f9ba5000040d801000001"
    return stride(from: 0, to: hex.count, by: 2).map {
        let start = hex.index(hex.startIndex, offsetBy: $0)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    }
}

/// 실제 pcap 대신 가짜 백엔드에 넣을 Ethernet/IPv4/UDP 프레임.
private func cliBeatFrame(_ payload: [UInt8]) -> [UInt8] {
    var frame = [UInt8].alloc(42)
    frame.writeUInt16BE(0x0800, 12)
    frame[14] = 0x45
    frame.writeUInt16BE(28 + payload.count, 16)
    frame[23] = 17
    frame.writeUInt32BE(0xc0a80114, 26)
    frame.writeUInt32BE(0xc0a801ff, 30)
    frame.writeUInt16BE(BEAT_PORT, 34)
    frame.writeUInt16BE(BEAT_PORT, 36)
    frame.writeUInt16BE(8 + payload.count, 38)
    return frame + payload
}

@Suite("CLI 비트 출력")
@DJLinkActor
struct CLIBeatTests {
    @Test("비트 출력은 곡 BPM과 피치를 적용한 계산 BPM을 구분한다")
    func formatsCapturedBeat() throws {
        let beat = try #require(beatFromPacket(capturedCLIBeat()))
        #expect(formatBeat(beat) == "beat device=1 beat=1 bpm=166.00 pitch=-2.45% effective-bpm=161.93")
    }

    @Test("status는 같은 비트 값도 패킷마다 내고 짧은 패킷은 버린다")
    func statusPrintsEveryBeat() async throws {
        let h = CLIHarness()
        let run = h.start(["status", "--iface", "en7"])
        await h.settle()
        try h.announce(try cdj(1, "192.168.1.20"))
        await h.settle()
        let packet = capturedCLIBeat()
        let source = RemoteInfo(address: "192.168.1.20", port: BEAT_PORT, size: 0)
        h.beatSocket.emitMessage(packet, from: source)
        h.beatSocket.emitMessage(packet, from: source)
        h.beatSocket.emitMessage(Array(packet.prefix(95)), from: source)
        #expect(h.output.lines.filter { $0.hasPrefix("beat ") }.count == 2)
        #expect(!h.output.lines.contains { $0.hasPrefix("position ") })
        h.abort.interrupt()
        #expect(await run.value == 130)
        #expect(h.allSocketsClosed)
    }

    @Test("passive는 비트 프레임을 출력하고 malformed 비트 뒤에도 캡처를 유지한다")
    func passivePrintsBeat() async throws {
        let h = CLIHarness()
        let run = h.start(["passive", "--iface", "en7"])
        await h.settle()
        let packet = capturedCLIBeat()
        h.backend.emitPacket(cliBeatFrame(Array(packet.prefix(95))))
        h.backend.emitPacket(cliBeatFrame(packet))
        #expect(h.output.lines.filter { $0.hasPrefix("beat ") }.count == 1)
        #expect(h.output.lines.contains { $0.contains("effective-bpm=161.93") })
        #expect(!run.isFinished)
        #expect(h.fakeFactory.udpSockets.isEmpty)
        h.abort.interrupt()
        #expect(await run.value == 130)
        #expect(h.backend.closed)
    }
}
