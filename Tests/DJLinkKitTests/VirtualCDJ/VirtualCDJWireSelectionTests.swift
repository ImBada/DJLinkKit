import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 tests/virtualcdj/wire-selection.test.ts

/// The player-number choice keys off `device.name` and `device.type` as they
/// come off the wire. Everything else is unit-tested against hand-built device
/// objects, which cannot catch the table being keyed on a string the parser
/// never produces — null padding, a type byte read from the wrong offset, a
/// model name that arrives differently than it is written down.
///
/// These tests push real announce packets through the real parser and the real
/// DeviceManager, and only then ask which player number we would take.
@Suite("player number selection from announce packets")
@DJLinkActor
struct VirtualCDJWireSelectionTests {
    // A real DeviceManager arms a 10s disconnect timer per device; without fake
    // timers those keep the jest process alive after the run.
    // (원본 beforeEach/afterEach의 가짜 타이머는 TestClock 주입으로 옮겼다.)
    let clock = TestClock()

    private func announcePacketFor(_ id: Int, _ name: String, _ type: DeviceType) -> [UInt8] {
        let device = Device(
            name: name,
            id: id,
            type: type,
            macAddr: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55],
            ip: try! Address4("192.168.1.10")
        )
        return try! makeAnnouncePacket(device)
    }

    /// A DeviceManager fed by the packets a rig would broadcast, exactly as
    /// bringOnline() wires it to the announce socket.
    private func rigOnTheNetwork(_ peers: [(Int, String, DeviceType)]) -> DeviceManager {
        let socket = FakeUDPSocket()

        let deviceManager = DeviceManager(socket, clock: clock)
        for (id, name, type) in peers {
            socket.emitMessage(announcePacketFor(id, name, type))
        }

        return deviceManager
    }

    private func chosenPlayerNumber(_ deviceManager: DeviceManager) -> DeviceID? {
        let devices = Array(deviceManager.devices.values)
        return pickAvailableDeviceId(
            devices.map(\.id),
            .init(preferPlayerRange: true, playerCeiling: playerNumberCeiling(devices))
        )
    }

    @Test("reads a model name back off the wire without padding")
    func readsModelName() throws {
        let deviceManager = rigOnTheNetwork([(33, "DJM-V10", .mixer)])

        let mixer = try #require(deviceManager.devices[33])
        // buildName pads to 20 bytes; if that padding survived, no table lookup
        // would ever match.
        #expect(mixer.name == "DJM-V10")
        #expect(mixer.type == .mixer)
    }

    @Test("takes player 5 on a real DJM-A9 rig")
    func djmA9Rig() {
        let deviceManager = rigOnTheNetwork([
            (1, "CDJ-3000", .cdj),
            (2, "CDJ-3000", .cdj),
            (33, "DJM-A9", .mixer),
        ])

        #expect(playerNumberCeiling(deviceManager.devices.values) == 4)
        #expect(chosenPlayerNumber(deviceManager) == 5)
    }

    @Test("takes player 7 on a real DJM-V10 rig")
    func djmV10Rig() {
        let deviceManager = rigOnTheNetwork([
            (1, "CDJ-3000", .cdj),
            (2, "CDJ-3000", .cdj),
            (33, "DJM-V10", .mixer),
        ])

        #expect(chosenPlayerNumber(deviceManager) == 7)
    }

    @Test("takes player 4 on a real DJM-V5 rig")
    func djmV5Rig() {
        let deviceManager = rigOnTheNetwork([
            (1, "CDJ-3000", .cdj),
            (33, "DJM-V5", .mixer),
        ])

        #expect(chosenPlayerNumber(deviceManager) == 4)
    }

    @Test("never lands on a player number a CDJ announced")
    func neverLandsOnAnnouncedNumber() throws {
        // The reported rig: a second CDJ-3000 sitting on player 5, which is what
        // the old hardcoded choice collided with.
        let deviceManager = rigOnTheNetwork([
            (1, "CDJ-3000", .cdj),
            (5, "CDJ-3000", .cdj),
            (33, "DJM-A9", .mixer),
        ])

        let chosen = chosenPlayerNumber(deviceManager)

        #expect(chosen == 6)
        #expect(deviceManager.devices[try #require(chosen)] == nil)
    }

    @Test("falls back to the 1-6 sweep when the rig has no mixer")
    func noMixer() {
        let deviceManager = rigOnTheNetwork([
            (1, "CDJ-3000", .cdj),
            (2, "CDJ-3000", .cdj),
        ])

        #expect(playerNumberCeiling(deviceManager.devices.values) == nil)
        #expect(chosenPlayerNumber(deviceManager) == 6)
    }

    @Test("reads the mixer even when it announces after the players")
    func mixerAnnouncesLast() {
        // Discovery order is whatever the network delivers; the DJM is usually
        // not first, which is why the choice waits for discovery to settle.
        let deviceManager = rigOnTheNetwork([
            (1, "CDJ-3000", .cdj),
            (2, "CDJ-3000", .cdj),
            (3, "CDJ-3000", .cdj),
            (33, "DJM-V10", .mixer),
        ])

        #expect(chosenPlayerNumber(deviceManager) == 7)
    }

    @Test("would have taken a live player number before the fix")
    func oldHardcodedChoice() {
        // Pins the regression itself: the old code used a constant 5 regardless
        // of what was on the network.
        let deviceManager = rigOnTheNetwork([
            (1, "CDJ-3000", .cdj),
            (5, "CDJ-3000", .cdj),
            (33, "DJM-A9", .mixer),
        ])

        let hardcodedOldChoice = 5
        #expect(deviceManager.devices[hardcodedOldChoice] != nil)
        #expect(chosenPlayerNumber(deviceManager) != hardcodedOldChoice)
    }
}
