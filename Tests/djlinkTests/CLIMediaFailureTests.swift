import DJLinkKit
import DJLinkTestSupport
import Testing

@testable import djlink

@Suite("CLI media lookup failure")
@DJLinkActor
struct CLIMediaFailureTests {
    @Test("media request failure makes the metadata command exit with code 1")
    func metadataExit() async throws {
        let h = CLIHarness()
        let run = h.start(["metadata", "--iface", "en7", "--device", "1", "--slot", "usb", "--track-id", "5"])
        await h.settle()
        h.fakeFactory.udpSockets[2].sendError = DJLinkError("media lookup failed")
        try h.announce(try cdj(1, "192.168.1.20"))
        #expect(await run.value == 1)
        #expect(h.output.errorLines.contains { $0.contains("media lookup failed") })
        #expect(h.nfs.requestCount == 0)
        #expect(h.allSocketsClosed)
    }
}
