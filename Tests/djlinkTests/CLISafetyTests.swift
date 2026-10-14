import DJLinkKit
import Testing

@testable import djlink

private struct FakeProcessLister: ProcessLister {
    var names: [String] = []
    var failure: (any Error)?

    func processNames() throws -> [String] {
        if let failure { throw failure }
        return names
    }
}

@Suite("CLI safety rules")
struct CLISafetyTests {
    @Test("rekordbox and rekordboxAgent are detected by name")
    func detectRekordbox() {
        #expect(isRekordboxProcessName("rekordbox"))
        #expect(isRekordboxProcessName("rekordboxAgent"))
        #expect(isRekordboxProcessName("RekordboxAgent"))
        #expect(isRekordboxProcessName("rekordbox Helper"))
        #expect(!isRekordboxProcessName("djlink"))
        #expect(!isRekordboxProcessName("Finder"))
        #expect(!isRekordboxProcessName("my-rekordbox"))
    }

    @Test("the Darwin lister reads this machine's process names without spawning anything")
    func darwinLister() throws {
        let names = try DarwinProcessLister().processNames()
        #expect(names.contains("launchd"))
        #expect(!names.contains(""))
    }

    @Test("running rekordbox processes are listed once and sorted")
    func listRekordbox() {
        #expect(
            rekordboxProcesses(in: ["launchd", "rekordboxAgent", "rekordbox", "rekordbox", "Safari"])
                == ["rekordbox", "rekordboxAgent"])
        #expect(rekordboxProcesses(in: ["launchd", "Safari"]).isEmpty)
    }

    @Test("the check passes when no rekordbox process is running")
    func passes() {
        #expect(checkRekordboxNotRunning(lister: FakeProcessLister(names: ["launchd", "Safari"])) == nil)
    }

    @Test("the check refuses and names the process when rekordbox is running")
    func refuses() throws {
        let violation = try #require(
            checkRekordboxNotRunning(lister: FakeProcessLister(names: ["launchd", "rekordboxAgent"])))
        #expect(violation.message.contains("rekordboxAgent"))
        #expect(violation.message.contains("50000"))
    }

    @Test("the check refuses when the process list cannot be read")
    func failsClosed() throws {
        let violation = try #require(
            checkRekordboxNotRunning(lister: FakeProcessLister(failure: CLISafetyViolation(message: "no access"))))
        #expect(violation.message.contains("확인하지 못해"))
        #expect(violation.message.contains("no access"))
        struct Other: Error {}
        #expect(checkRekordboxNotRunning(lister: FakeProcessLister(failure: Other())) != nil)
    }

    @Test("virtual CDJ ids below 7 need allowPlayerId")
    func virtualCdjId() {
        for id in 1...6 {
            #expect(checkVirtualCDJId(id, allowPlayerId: false) != nil)
            #expect(checkVirtualCDJId(id, allowPlayerId: true) == nil)
        }
        #expect(checkVirtualCDJId(7, allowPlayerId: false) == nil)
        #expect(checkVirtualCDJId(DEFAULT_VCDJ_ID, allowPlayerId: false) == nil)
        #expect(checkVirtualCDJId(32, allowPlayerId: false) == nil)
    }

    @Test("never-read paths are refused however they are spelled")
    func neverRead() {
        let refused = [
            "PIONEER/extracted", "PIONEER/extracted/a/b", "/PIONEER/extracted/a", "pioneer/EXTRACTED/x",
            "PIONEER/CDP", "PIONEER/cdp/file", "C:\\PIONEER\\CDP\\x", "./PIONEER//extracted", "PIONEER/djprofile.nxs",
            "djprofile.nxs", "/DJPROFILE.NXS", "a/b/djprofile.nxs", "PIONEER/rekordbox/../extracted", "../etc",
            ".PIONEER/extracted/x", "./.PIONEER/CDP/a", "..PIONEER/extracted",
        ]
        // 구성 요소 끝의 점·공백은 FAT·Windows가 걷어낸다.
        let trailing = [
            "PIONEER./extracted", "PIONEER /extracted", "PIONEER/extracted.", "PIONEER/extracted ",
            "PIONEER/extracted. . ", "PIONEER/CDP...", "pioneer. ./cdp/x", "djprofile.nxs.", "DJPROFILE.NXS ",
            "a/djprofile.nxs. .", "C:\\PIONEER.\\CDP.\\x", ".PIONEER./Extracted /x",
        ]
        for path in trailing { #expect(checkNeverRead(path) != nil, "\(path)") }
        // 상위 폴더 참조의 변형.
        for path in ["PIONEER/.../extracted", "a/.. /b", "../x", "a/. ./b", "a/.../b"] {
            #expect(checkNeverRead(path) != nil, "\(path)")
        }
        // FAT 8.3 별칭 꼴(이름 8자 이하가 `~숫자`로 끝남)은 무슨 이름인지 알 수 없어 거부한다.
        let aliases = [
            "PIONEER/EXTRAC~1", "PIONEER/extrac~1/x", "PIONEE~1/EXTRACTED", "PIONEER/CDP~1", "DJPROF~1.NXS",
            "PIONEER/rekordbox/EXPORT~1.PDB", "Contents/Artist/track~1.mp3", "PIONE~10/x",
        ]
        for path in aliases {
            let violation = checkNeverRead(path)
            #expect(violation != nil, "\(path)")
            #expect(violation?.message.contains("~") == true, "\(path)")
        }
        for path in refused { #expect(checkNeverRead(path) != nil, "\(path)") }
        let allowed = [
            "PIONEER/rekordbox/export.pdb", "PIONEER/rekordbox/exportLibrary.db",
            "PIONEER/USBANLZ/P016/0000875E/ANLZ0000.DAT",
            "/Contents/Artist/track.mp3", "PIONEER/extractedx", "PIONEER", "extracted", "a.b/c.d", "PIONEER/.hidden/x",
            // 8.3 별칭 꼴이 아닌 `~`는 곡 이름에 쓰일 수 있어 막지 않는다.
            "a~b/c.mp3", "Contents/Artist ~ Remix/track~mix.mp3", "~", "Contents/long name~1.mp3",
            "Contents/Artist. Name/track.mp3", ".PIONEER/rekordbox/export.pdb", "C:\\Contents\\a.mp3", "a/./b", "a/ /b",
        ]
        for path in allowed { #expect(checkNeverRead(path) == nil, "\(path)") }
    }

    @Test("play and pause are allowed only for players 1-4, which have a slot in the packet")
    func playStateRange() throws {
        for id in [1, 2, 3, 4] { #expect(checkPlayStateAllowed(deviceId: id) == nil, "\(id)") }
        for id in [0, 5, 6, 7, 17, 32] {
            let violation = try #require(checkPlayStateAllowed(deviceId: id), "\(id)")
            #expect(violation.message.contains("1~4번 플레이어"))
        }
    }

    @Test("control needs the exact device name")
    func controlConfirm() {
        let device = Device(
            name: "CDJ-3000", id: 2, type: .cdj, macAddr: [0, 1, 2, 3, 4, 5], ip: try! Address4("192.168.1.20"))
        #expect(checkControlConfirmation(device: device, confirm: "CDJ-3000") == nil)
        #expect(checkControlConfirmation(device: device, confirm: "cdj-3000") != nil)
        #expect(checkControlConfirmation(device: device, confirm: "CDJ-3000 ") != nil)
        #expect(checkControlConfirmation(device: device, confirm: "CDJ") != nil)
        #expect(checkControlConfirmation(device: device, confirm: "") != nil)
        #expect(checkControlConfirmation(device: device, confirm: "2") != nil)
    }

    @Test("download file names lose their directories and reject empty names")
    func downloadNames() {
        #expect(safeDownloadFileName("song.mp3") == "song.mp3")
        #expect(safeDownloadFileName("a/b/song.mp3") == "song.mp3")
        #expect(safeDownloadFileName("..\\..\\song.mp3") == "song.mp3")
        #expect(safeDownloadFileName("/etc/passwd") == "passwd")
        #expect(safeDownloadFileName("") == nil)
        #expect(safeDownloadFileName("..") == nil)
        #expect(safeDownloadFileName("a/..") == nil)
        #expect(safeDownloadFileName("/") == nil)
        #expect(safeDownloadFileName("  ") == nil)
    }
}
