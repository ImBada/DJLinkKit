import DJLinkKit
import Testing

// 원본 tests/virtualcdj/device-id.test.ts

/// 원본의 `{name, type}` 객체.
private struct NamedDevice: DeviceLike {
    var name: String
    var type: DeviceType
}

/// 원본의 `{id, type}` 객체.
private struct IdDevice: QueryIdDeviceLike {
    var id: DeviceID
    var type: DeviceType
}

private func mixer(_ name: String) -> NamedDevice { NamedDevice(name: name, type: .mixer) }
private func player(_ name: String) -> NamedDevice { NamedDevice(name: name, type: .cdj) }

@Suite("playerNumberCeiling")
struct VirtualCDJPlayerNumberCeilingTests {
    @Test("reads the channel count off a known mixer")
    func knownMixer() {
        #expect(playerNumberCeiling([mixer("DJM-A9")]) == 4)
        #expect(playerNumberCeiling([mixer("DJM-V5")]) == 3)
        #expect(playerNumberCeiling([mixer("DJM-450")]) == 2)
    }

    @Test("knows the six-channel flagships are not four-channel")
    func sixChannelFlagships() {
        // The app's own capability table caps these at 4 for its mixer signal
        // model; using that number here would put us on player 5 of a rig that
        // can hand player 5 out.
        #expect(playerNumberCeiling([mixer("DJM-V10")]) == 6)
        #expect(playerNumberCeiling([mixer("DJM-V10-LF")]) == 6)
    }

    @Test("assumes four channels for a mixer it does not recognise")
    func unknownMixer() {
        #expect(playerNumberCeiling([mixer("DJM-9000XZ")]) == DEFAULT_MIXER_PLAYER_CEILING)
    }

    @Test("counts an all-in-one by the players built into it")
    func allInOne() {
        #expect(playerNumberCeiling([player("XDJ-AZ")]) == 4)
        #expect(playerNumberCeiling([player("XDJ-RX3")]) == 2)
    }

    @Test("has nothing to say about plain players")
    func plainPlayers() {
        #expect(playerNumberCeiling([player("CDJ-3000"), player("CDJ-3000")]) == nil)
    }

    @Test("takes the largest rig when several mixers share a network")
    func largestRig() {
        #expect(playerNumberCeiling([mixer("DJM-A9"), mixer("DJM-V10")]) == 6)
    }

    @Test("matches model names regardless of case and padding")
    func caseAndPadding() {
        #expect(playerNumberCeiling([mixer("  djm-v10  ")]) == 6)
    }
}

@Suite("pickAvailableDeviceId")
struct VirtualCDJPickAvailableDeviceIdTests {
    @Suite("with a mixer to reason from")
    struct WithMixer {
        private func pick(_ usedIds: [Int], _ playerCeiling: Int) -> DeviceID? {
            pickAvailableDeviceId(usedIds, .init(preferPlayerRange: true, playerCeiling: playerCeiling))
        }

        @Test("sits just above the numbers the mixer can hand out")
        func justAboveMixer() {
            #expect(pick([1, 2, 3, 4, 33], 4) == 5)  // DJM-A9
            #expect(pick([1, 2, 3, 33], 3) == 4)  // DJM-V5
            #expect(pick([1, 2, 33], 2) == 3)  // DJM-450
        }

        @Test("leaves the remotedb range entirely on a six-channel rig")
        func sixChannelRig() {
            // A DJM-V10 can assign every number 1-6, so none of them is ours to
            // take — even the ones sitting free right now.
            #expect(pick([1, 2, 33], 6) == 7)
        }

        @Test("does not care how many players are actually plugged in")
        func ignoresPluggedInCount() {
            // Two CDJs on a DJM-A9 today, but channels 3 and 4 are still the
            // mixer's to hand out.
            #expect(pick([1, 2, 33], 4) == 5)
        }

        @Test("climbs within the range when the slot above the players is taken")
        func climbsWithinRange() {
            #expect(pick([1, 2, 5, 33], 4) == 6)
        }

        @Test("goes outside the remotedb range before contending with a player")
        func goesOutsideBeforeContending() {
            // 5 and 6 gone, so metadata is lost either way — take an ID no player
            // can be assigned rather than one channel 3 could claim.
            #expect(pick([1, 2, 5, 6, 33], 4) == 7)
        }

        @Test("contends for a free player slot only as a last resort")
        func contendsAsLastResort() {
            let allHigh = (0..<(MAX_DEVICE_ID - 4)).map { $0 + 5 }
            #expect(pick(allHigh + [1, 2], 4) == 4)
        }

        @Test("returns null when every ID is occupied")
        func allOccupied() {
            let allIds = (0..<MAX_DEVICE_ID).map { $0 + 1 }
            #expect(pick(allIds, 4) == nil)
        }
    }

    @Suite("with no mixer on the network")
    struct WithoutMixer {
        private func pick(_ usedIds: [Int]) -> DeviceID? {
            pickAvailableDeviceId(usedIds, .init(preferPlayerRange: true))
        }

        @Test("works down from the top of the range")
        func worksDown() {
            // Nothing says how high player numbers will go, and players number
            // themselves upwards from 1.
            #expect(pick([]) == REMOTEDB_MAX_DEVICE_ID)
            #expect(pick([1, 2, 3, 4]) == 6)
            #expect(pick([1, 2, 5, 6]) == 4)
        }

        @Test("falls back above 6 when every player number is taken")
        func fallsBackAboveSix() {
            #expect(pick([1, 2, 3, 4, 5, 6]) == 7)
        }
    }

    @Suite("preferring the high range")
    struct PreferringHighRange {
        private func pick(_ usedIds: [Int]) -> DeviceID? {
            pickAvailableDeviceId(usedIds)
        }

        @Test("starts just above the remotedb range")
        func startsAboveRemoteDb() {
            #expect(pick([]) == 7)
        }

        @Test("climbs past occupied high IDs")
        func climbsPastOccupied() {
            #expect(pick([7, 8, 9]) == 10)
        }

        @Test("drops into the 1-6 range only once 7-32 is full")
        func dropsIntoPlayerRange() {
            let highIds = (0..<(MAX_DEVICE_ID - 6)).map { $0 + 7 }
            #expect(pick(highIds) == 6)
            #expect(pick(highIds + [6]) == 5)
        }
    }

    @Test("accepts any iterable of used IDs")
    func anyIterable() {
        #expect(pickAvailableDeviceId(Set([7, 8])) == 9)
        #expect(pickAvailableDeviceId([7: "a"].keys) == 8)
    }
}

@Suite("pickRemoteDbQueryId")
struct VirtualCDJPickRemoteDbQueryIdTests {
    private func cdj(_ id: Int) -> IdDevice { IdDevice(id: id, type: .cdj) }
    private func mixerAt(_ id: Int) -> IdDevice { IdDevice(id: id, type: .mixer) }
    private func rekordbox(_ id: Int) -> IdDevice { IdDevice(id: id, type: .rekordbox) }

    @Test("poses as a live player that is not the target")
    func posesAsLivePlayer() {
        // Satisfies the strictest documented (nexus-era) rules: 1-4, present on
        // the network, not the player being queried.
        #expect(pickRemoteDbQueryId(2, [cdj(1), cdj(2)]) == 1)
        #expect(pickRemoteDbQueryId(1, [cdj(1), cdj(2)]) == 2)
        #expect(pickRemoteDbQueryId(5, [cdj(3), cdj(5)]) == 3)
    }

    @Test("takes the lowest free 1-6 ID when the target is the only player")
    func lowestFreeId() {
        // Verified on CDJ-3000: IDs of absent players are answered too.
        #expect(pickRemoteDbQueryId(2, [cdj(2)]) == 1)
        #expect(pickRemoteDbQueryId(1, [cdj(1)]) == 2)
    }

    @Test("ignores mixers and rekordbox when looking for players to pose as")
    func ignoresMixersAndRekordbox() {
        #expect(pickRemoteDbQueryId(2, [cdj(2), mixerAt(33), rekordbox(17)]) == 1)
    }

    @Test("never returns an ID above the remotedb range")
    func neverAboveRange() {
        let rigs: [[IdDevice]] = [
            [cdj(1)],
            [cdj(1), cdj(2), cdj(3), cdj(4), cdj(5), cdj(6), mixerAt(33)],
            [mixerAt(33)],
        ]
        for rig in rigs {
            for target in [1, 2, 3, 4, 5, 6] {
                #expect(pickRemoteDbQueryId(target, rig) <= REMOTEDB_MAX_DEVICE_ID)
            }
        }
    }

    @Test("answers the full-rig case with the lowest other player")
    func fullRig() {
        let rig = [cdj(1), cdj(2), cdj(3), cdj(4), cdj(5), cdj(6)]
        #expect(pickRemoteDbQueryId(3, rig) == 1)
        #expect(pickRemoteDbQueryId(1, rig) == 2)
    }
}
