import DJLinkKit
import DJLinkTestSupport
import Testing

@testable import djlink

@Suite("CLI startup rejection readiness")
@DJLinkActor
struct CLIReadySafetyTests {
    @Test("a startup number rejection releases all ready waiters and exposes the rejected ID")
    func conflictReleasesReady() async throws {
        let h = CLIHarness()
        let session = h.makeSession()
        let network = try await session.openNetwork(options: CLICommonOptions(iface: "en7"))
        network.configure(
            NetworkConfig(
                iface: session.scope?.info, vcdjId: 7, fullStartup: true,
                allowsDeviceId: { $0 >= 7 }, announceTargetFilter: { $0.ip.address.hasPrefix("192.168.1.") }))
        try network.connect()
        var readyCount = 0
        let first = Task {
            await network.startupReady
            readyCount += 1
        }
        let second = Task {
            await network.startupReady
            readyCount += 1
        }
        await h.settle()
        for id in 7...32 { try h.announce(cdj(id, "192.168.1.\(id + 10)")) }
        h.announceSocket.clearSent()
        h.announceSocket.emitMessage(conflictPacket(7))
        await h.settle()
        #expect(readyCount == 2)
        #expect(network.startupRejectedDeviceId == 6)
        #expect(h.announceSocket.sent.isEmpty)
        await first.value
        await second.value
        await #expect(throws: DJLinkError("Device ID 6 is not allowed")) { try await network.waitUntilReady() }
        await session.cleanup()
    }

    @Test("an initial number rejection releases ready and reports an error")
    func initialRejection() async throws {
        let socket = FakeUDPSocket()
        let manager = DeviceManager(socket)
        let clock = TestClock()
        let announcer = Announcer(
            DeviceReference(mockDevice(id: 1)), socket, manager, networkInterface("192.168.1.100"),
            fullStartup: true, clock: clock, allowsDeviceId: { $0 >= 7 })
        #expect(throws: DJLinkError.self) { try announcer.start() }
        await #expect(throws: DJLinkError.self) { try await announcer.waitUntilReady() }
        #expect(announcer.rejectedDeviceId == 1)
        #expect(socket.sent.isEmpty)
        #expect(clock.pendingTimerCount == 0)
    }
}
