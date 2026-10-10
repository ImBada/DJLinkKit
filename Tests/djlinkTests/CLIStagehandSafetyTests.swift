import DJLinkKit
import Testing

@testable import djlink

@Suite("Stagehand CLI policy refusal")
@DJLinkActor
struct CLIStagehandSafetyTests {
    @Test("each unsupported safety policy refuses Stagehand before sending any bytes")
    func refusesPolicies() async throws {
        let policies = [
            NetworkConfig(allowsDeviceId: { _ in true }),
            NetworkConfig(onDeviceIdRejected: { _ in }),
            NetworkConfig(announceTargetFilter: { _ in true }),
        ]
        for policy in policies {
            let h = CLIHarness()
            let session = h.makeSession()
            let network = try await session.openNetwork(options: CLICommonOptions(iface: "en7"))
            network.configure(NetworkConfig(iface: session.scope?.info, connectMethod: .stagehand))
            network.configure(policy)
            #expect(throws: DJLinkError.self) { try network.connect() }
            #expect(h.totalSent == 0)
            #expect(!network.isConnected())
            #expect(h.clock.pendingTimerCount == 0)
            await session.cleanup()
        }
    }
}
