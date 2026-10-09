import DJLinkKit
import Testing

@testable import djlink

// 전역 NFS 설정(소켓 공장·경로 검사)을 실제로 설치하고 되돌린다. 전역이라 같은 묶음 안에서도 한 번에 하나씩만 돈다.
// 설치부터 정리까지 중단점(await 대기)이 없게 짜서 다른 시험과 끼어들지 않게 한다. 실제 소켓은 열지 않는다.
@Suite("CLI NFS globals", .serialized)
@DJLinkActor
struct CLINFSGlobalsTests {
    @Test("the global path guard is installed for the run and removed when cleanup ends")
    func installsAndRemovesGuard() async throws {
        let h = CLIHarness()
        var runtime = h.makeRuntime()
        runtime.configuresNFSGlobals = true
        let session = CLISession(runtime: runtime, output: h.output, abort: h.abort)
        let device = try cdj(1, "192.168.1.20")
        var duringRun: (any Error)?
        var afterCleanup: (any Error)?

        try session.lock(session.resolveScope(named: "en7"))
        session.configureNFS()
        do {
            _ = try await DJLinkKit.fetchFile(device: device, slot: .usb, path: "PIONEER/extracted/x")
        } catch { duringRun = error }
        await session.cleanup()
        do {
            _ = try await DJLinkKit.fetchFile(device: device, slot: .usb, path: "PIONEER/extracted/x")
        } catch { afterCleanup = error }

        // 실행 중에는 우리 경로 검사가 소켓을 만들기 전에 던진다.
        let refused = try #require(duringRun as? CLIRuntimeError)
        #expect(refused.message.contains("PIONEER/extracted"))
        #expect(h.fakeFactory.udpSockets.isEmpty)
        #expect(h.nfs.requestCount == 0)
        // 정리한 뒤에는 훅이 없어 같은 경로가 검사 오류가 아니라 실제 소켓 공장(시험 프로세스에서는 거부)까지 간다.
        let leftover = try #require(afterCleanup)
        #expect(!(leftover is CLIRuntimeError), "훅이 남아 있다: \(leftover)")
        #expect(h.fakeFactory.udpSockets.isEmpty)
    }
}
