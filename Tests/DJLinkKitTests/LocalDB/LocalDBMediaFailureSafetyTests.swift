import Testing

@testable import DJLinkKit

@Suite("Local database opt-in media errors")
@DJLinkActor
struct LocalDBMediaFailureSafetyTests {
    @Test("default hides media failure while the CLI opt-in reports it")
    func mediaFailure() async throws {
        let status = LocalDBFakeMediaSlotSource()
        status.error = DJLinkError("media lookup failed")
        let baseline = LocalDatabase(
            hostDevice: localDBTestHost, deviceManager: LocalDBFakeDeviceSource(), statusEmitter: status)
        #expect(try await baseline.get(3, .usb) == nil)
        let guarded = LocalDatabase(
            hostDevice: localDBTestHost, deviceManager: LocalDBFakeDeviceSource(), statusEmitter: status,
            throwsOnMediaQueryFailure: true)
        await #expect(throws: DJLinkError("media lookup failed")) { _ = try await guarded.get(3, .usb) }
    }
}
