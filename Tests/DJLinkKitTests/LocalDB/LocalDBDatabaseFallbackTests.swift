import Foundation
import Testing

@testable import DJLinkKit

@Suite("LocalDatabase.findTrack (NP3-399)")
@DJLinkActor struct LocalDBDatabaseFallbackTests {
    @Test("answers from the active database and leaves the other file alone when the row agrees")
    func test0() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase()
        let result = try await local.findTrack(3, .usb, 3078, .init(trackBPM: 126))
        #expect(result.track?.title == "Purpura - Focused (Original Mix)")
        #expect(result.switchedTo == nil)
        #expect(harness.downloadsOf("export.pdb") == 0)
        #expect(local.getDatabaseType(deviceId: 3, slot: .usb) == .oneLibrary)
    }
    @Test("does not question the active row when the player reports no BPM")
    func test1() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase()
        let result = try await local.findTrack(3, .usb, 3078, .init(trackBPM: nil))
        #expect(result.track?.title == "Purpura - Focused (Original Mix)")
        #expect(harness.downloadsOf("export.pdb") == 0)
    }
    @Test("loads the legacy PDB when OneLibrary has no such row, and switches the slot to it")
    func test2() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase()
        let result = try await local.findTrack(3, .usb, 32657, .init(trackBPM: 128))
        #expect(result.track?.title == "The track deck 3 is playing")
        #expect(result.switchedTo == .pdb)
        #expect(harness.downloadsOf("export.pdb") == 1)
        #expect(local.getDatabaseType(deviceId: 3, slot: .usb) == .pdb)
    }
    @Test("switches when the OneLibrary row exists but its BPM is not what the player shows")
    func test3() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase()
        let result = try await local.findTrack(3, .usb, 3078, .init(trackBPM: 130))
        #expect(result.track?.title == "The track deck 5 is playing")
        #expect(result.switchedTo == .pdb)
    }
    @Test("serves every later lookup from the switched database without another download")
    func test4() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase()
        _ = try await local.findTrack(3, .usb, 32657, .init(trackBPM: 128))
        let next = try await local.findTrack(3, .usb, 3078, .init(trackBPM: 130))
        let adapter = try await local.get(3, .usb)
        #expect(next.track?.title == "The track deck 5 is playing")
        #expect(next.switchedTo == nil)
        #expect(adapter?.type == .pdb)
        #expect(harness.downloadsOf("export.pdb") == 1)
        #expect(harness.downloadsOf("exportLibrary.db") == 1)
    }
    @Test("switches back if a later track is only confirmed by the other format")
    func test5() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase()
        _ = try await local.findTrack(3, .usb, 32657, .init(trackBPM: 128))
        let result = try await local.findTrack(3, .usb, 500, .init(trackBPM: 140))
        #expect(result.track?.title == "Only in OneLibrary")
        #expect(result.switchedTo == .oneLibrary)
        #expect(local.getDatabaseType(deviceId: 3, slot: .usb) == .oneLibrary)
    }
    @Test("keeps the active row when the stick has no other format to check against")
    func test6() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase()
        harness.files = ["exportLibrary.db"]
        let result = try await local.findTrack(3, .usb, 3078, .init(trackBPM: 130))
        #expect(result.track?.title == "Purpura - Focused (Original Mix)")
        #expect(result.switchedTo == nil)
        #expect(local.getDatabaseType(deviceId: 3, slot: .usb) == .oneLibrary)
    }
    @Test("reports a plain miss when neither format holds the track")
    func test7() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase()
        let result = try await local.findTrack(3, .usb, 99999, .init(trackBPM: 120))
        #expect(result.track == nil)
        #expect(result.adapter != nil)
    }
    @Test("tries the missing file only once per stick")
    func test8() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase()
        harness.files = ["exportLibrary.db"]
        _ = try await local.findTrack(3, .usb, 32657, .init(trackBPM: 128))
        _ = try await local.findTrack(3, .usb, 46216, .init(trackBPM: 124))
        #expect(harness.downloadsOf("export.pdb") == 2)
    }
    @Test("does not reach for the other format when a single format is forced")
    func test9() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase(.oneLibrary)
        let result = try await local.findTrack(3, .usb, 32657, .init(trackBPM: 128))
        #expect(result.track == nil)
        #expect(harness.downloadsOf("export.pdb") == 0)
    }
    @Test("reports no database for a slot with no media")
    func test10() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase()
        let deviceManager = LocalDBFakeDeviceSource()
        deviceManager.devices = [:]
        let empty = LocalDatabase(
            hostDevice: localDBTestHost, deviceManager: deviceManager,
            statusEmitter: LocalDBFakeMediaSlotSource(), preference: .auto)
        let result = try await empty.findTrack(3, .usb, 1, .init())
        #expect(result.adapter == nil)
        #expect(result.track == nil)
        #expect(result.switchedTo == nil)
        #expect(type(of: local) == LocalDatabase.self)
    }
    @Test("closes both databases when the device leaves")
    func test11() async throws {
        let harness = LocalDBFallbackHarness()
        let local = harness.makeLocalDatabase()
        _ = try await local.findTrack(3, .usb, 32657, .init(trackBPM: 128))
        let active = try await local.get(3, .usb)
        local.disconnectForDevice(localDBTestCDJ)
        #expect((active as? LocalDBFakeAdapter)?.closeCalls ?? 0 > 0)
        #expect(harness.oneLibrary.closeCalls > 0)
        #expect(local.getDatabaseType(deviceId: 3, slot: .usb) == nil)
    }
}
