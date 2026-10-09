import DJLinkKit
import DJLinkTestSupport
import Testing

// 원본 tests/virtualcdj/conflict.test.ts
// 원본의 mock 소켓(`on`으로 처리기를 잡아 두는 것)은 FakeUDPSocket으로, `{devices}`만 가진 mock DeviceManager는
// 실제 DeviceManager의 `devices`를 채워서, `jest.useFakeTimers()`는 TestClock으로 옮겼다.

/// Regression coverage for NP3-356: a virtual CDJ that keeps a contested player
/// number knocks the real player holding it off the network mid-set.
@Suite("Announcer device ID conflicts")
@DJLinkActor
struct VirtualCDJConflictTests {
    let mockIface = NetworkInterfaceInfo(
        address: "192.168.1.100",
        netmask: "255.255.255.0",
        family: "IPv4",
        mac: "00:11:22:33:44:55",
        internal: false,
        cidr: "192.168.1.100/24",
        scopeid: nil
    )

    // beforeEach(() => jest.useFakeTimers())
    let clock = TestClock()

    /// Build the 0x08 packet a device sends to defend a player number it owns.
    private func makeConflictPacket(_ defendedId: Int) -> [UInt8] {
        var packet = [UInt8].alloc(0x29)
        packet.set(PROLINK_HEADER, 0)
        packet[0x0a] = 0x08
        packet[0x24] = UInt8(defendedId)
        return packet
    }

    /// A peer as [device id, model name]; names are matched to channel counts.
    enum Peer: ExpressibleByIntegerLiteral {
        case id(Int)
        case named(Int, String)

        init(integerLiteral value: Int) {
            self = .id(value)
        }
    }

    struct Setup {
        let announcer: Announcer
        let vcdj: DeviceReference
        let mockSocket: FakeUDPSocket
        let sendConflict: @DJLinkActor (Int) -> Void
    }

    private func setup(_ vcdjId: Int, _ peers: [Peer], fullStartup: Bool = true) throws -> Setup {
        let mockSocket = FakeUDPSocket()

        let mockDeviceManager = DeviceManager(FakeUDPSocket(), clock: clock)
        for peer in peers {
            let (id, name): (Int, String) =
                switch peer {
                case let .id(id): (id, "CDJ-\(id)")
                case let .named(id, name): (id, name)
                }
            var device = try getVirtualCDJ(mockIface, id, name)
            // Mixers announce as their own device type, which is what tells the
            // announcer how many player numbers the rig can hand out.
            if name.hasPrefix("DJM") || name == "EUPHONIA" {
                device.type = .mixer
            }
            mockDeviceManager.devices[id] = device
        }

        let vcdj = DeviceReference(try getVirtualCDJ(mockIface, vcdjId))
        let announcer = Announcer(
            vcdj,
            mockSocket,
            mockDeviceManager,
            mockIface,
            fullStartup: fullStartup,
            clock: clock
        )

        let conflict = makeConflictPacket
        return Setup(
            announcer: announcer,
            vcdj: vcdj,
            mockSocket: mockSocket,
            sendConflict: { id in mockSocket.emitMessage(conflict(id)) }
        )
    }

    @Test("moves off a contested ID during startup")
    func movesOffContestedId() throws {
        let s = try setup(5, [1, 2, 5])

        try s.announcer.start()
        s.sendConflict(5)
        s.announcer.stop()

        #expect(s.vcdj.id != 5)
    }

    @Test("stays in the 1-6 range so remotedb queries keep working")
    func staysInPlayerRange() throws {
        // Player 5 is contested and 1, 2 are live — 6 is the only free player
        // number, and dropping to 7+ would silently lose streaming-track metadata.
        let s = try setup(5, [1, 2, 5])

        try s.announcer.start()
        s.sendConflict(5)
        s.announcer.stop()

        #expect(s.vcdj.id == 6)
    }

    @Test("keeps the same device object so remotedb and control follow the new ID")
    func keepsSameDeviceObject() throws {
        // remotedb, localdb and control are handed this exact object when the
        // network connects; replacing it would leave us announcing as one ID and
        // querying as another.
        let s = try setup(5, [5])

        try s.announcer.start()
        let before = s.vcdj
        s.sendConflict(5)
        s.announcer.stop()

        #expect(s.vcdj === before)
        #expect(s.vcdj.id == 6)
    }

    @Test("answers a conflict raised after startup has finished")
    func answersConflictAfterStartup() throws {
        // The listener used to be torn down when keep-alive began ~4s in, so a
        // player powering on later fought us for the slot forever.
        let s = try setup(5, [1, 2])

        try s.announcer.start()

        // Run out the startup stages (4 stages x 3 packets @ 300ms) into keep-alive
        clock.advance(ms: 5000)
        #expect(s.mockSocket.offCount == 0)

        s.sendConflict(5)
        s.announcer.stop()

        #expect(s.vcdj.id == 6)
    }

    @Test("ignores a conflict defending another device ID")
    func ignoresOtherIds() throws {
        let s = try setup(5, [1, 2])

        try s.announcer.start()
        s.sendConflict(2)
        s.announcer.stop()

        #expect(s.vcdj.id == 5)
    }

    @Test("keeps announcing after moving to the new ID")
    func keepsAnnouncingAfterMove() throws {
        let s = try setup(5, [1, 5])

        try s.announcer.start()
        s.sendConflict(5)

        // Run the restarted startup sequence out into keep-alive, then look only
        // at the keep-alive packets, which carry the device ID at byte 0x24.
        clock.advance(ms: 5000)
        s.mockSocket.clearSent()
        clock.advance(ms: 3000)
        s.announcer.stop()

        #expect(!s.mockSocket.sent.isEmpty)
        let announcedIds = s.mockSocket.sent.map { Int($0.message[0x24]) }
        #expect(Set(announcedIds) == Set([s.vcdj.id]))
    }

    @Test("stops announcing when every ID is occupied")
    func stopsWhenAllOccupied() throws {
        let allIds = (1...32).map { Peer.id($0) }
        let s = try setup(5, allIds)

        try s.announcer.start()
        s.sendConflict(5)
        s.mockSocket.clearSent()

        clock.advance(ms: 5000)

        #expect(s.mockSocket.sent.isEmpty)
    }

    @Test("detaches the conflict listener on stop")
    func detachesListenerOnStop() throws {
        let s = try setup(5, [1])

        try s.announcer.start()
        s.announcer.stop()

        // 원본 `expect(mockSocket.off).toHaveBeenCalledWith('message', expect.any(Function))`
        #expect(s.mockSocket.offCount == 1)
        #expect(s.mockSocket.messageListenerCount == 0)
    }

    @Test("moves above the mixer, not just to the next free number")
    func movesAboveMixer() throws {
        // A DJM-V10 can assign every number 1-6, so 6 sitting free is not ours to
        // take — the player on channel 6 would arrive and contest it too.
        let s = try setup(5, [1, 2, 5, .named(33, "DJM-V10")])

        try s.announcer.start()
        s.sendConflict(5)
        s.announcer.stop()

        #expect(s.vcdj.id == 7)
    }

    @Test("stays in the remotedb range when the mixer leaves room")
    func staysInRemoteDbRange() throws {
        let s = try setup(5, [1, 2, 5, .named(33, "DJM-A9")])

        try s.announcer.start()
        s.sendConflict(5)
        s.announcer.stop()

        #expect(s.vcdj.id == 6)
    }

    @Test("watches for conflicts even without the full startup protocol")
    func watchesWithoutFullStartup() throws {
        let s = try setup(5, [1, 5], fullStartup: false)

        try s.announcer.start()
        s.sendConflict(5)
        s.announcer.stop()

        #expect(s.vcdj.id == 6)
    }
}
