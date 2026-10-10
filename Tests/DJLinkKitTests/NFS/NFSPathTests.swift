import DJLinkKit
import DJLinkTestSupport
import Testing

struct NFSPathTests {
    @Suite("parseWindowsPath")
    struct ParseWindowsPath {
        @Test("parses a Windows path with backslashes")
        func test0() throws {
            let result = parseWindowsPath("C:\\Users\\example\\Music\\track.mp3")
            #expect(result == NFSPath(mountPath: "/C/", nfsPath: "Users/example/Music/track.mp3"))
        }

        @Test("parses a Windows path with forward slashes")
        func test1() throws {
            let result = parseWindowsPath("C:/Users/example/Music/track.mp3")
            #expect(result == NFSPath(mountPath: "/C/", nfsPath: "Users/example/Music/track.mp3"))
        }

        @Test("normalizes drive letter to uppercase")
        func test2() throws {
            let result = parseWindowsPath("d:\\Music\\track.mp3")
            #expect(result == NFSPath(mountPath: "/D/", nfsPath: "Music/track.mp3"))
        }

        @Test("handles mixed separators")
        func test3() throws {
            let result = parseWindowsPath("C:\\Users/example\\Music/track.mp3")
            #expect(result == NFSPath(mountPath: "/C/", nfsPath: "Users/example/Music/track.mp3"))
        }

        @Test("returns null for a non-Windows path")
        func test4() throws {
            let result = parseWindowsPath("/PIONEER/USBANLZ/track.mp3")
            #expect(result == nil)
        }

        @Test("returns null for a relative path")
        func test5() throws {
            let result = parseWindowsPath("Music/track.mp3")
            #expect(result == nil)
        }

        @Test("returns null for an empty string")
        func test6() throws {
            let result = parseWindowsPath("")
            #expect(result == nil)
        }

        @Test("handles a file directly in the drive root")
        func test7() throws {
            let result = parseWindowsPath("C:\\track.mp3")
            #expect(result == NFSPath(mountPath: "/C/", nfsPath: "track.mp3"))
        }

    }
    @Suite("resolveNfsPath")
    struct ResolveNfsPath {
        @Test("returns static mount path for USB slot")
        func test8() throws {
            let result = resolveNfsPath(.usb, "PIONEER/USBANLZ/track.mp3")
            #expect(result == NFSPath(mountPath: "/C/", nfsPath: "PIONEER/USBANLZ/track.mp3"))
        }

        @Test("returns static mount path for SD slot")
        func test9() throws {
            let result = resolveNfsPath(.sd, "PIONEER/USBANLZ/track.mp3")
            #expect(result == NFSPath(mountPath: "/B/", nfsPath: "PIONEER/USBANLZ/track.mp3"))
        }

        @Test("extracts mount path from Windows file path for RB slot")
        func test10() throws {
            let result = resolveNfsPath(.rb, "C:\\Users\\example\\Music\\track.mp3")
            #expect(result == NFSPath(mountPath: "/C/", nfsPath: "Users/example/Music/track.mp3"))
        }

        @Test("handles RB slot with forward-slash Windows path")
        func test11() throws {
            let result = resolveNfsPath(.rb, "D:/Music/rekordbox/track.wav")
            #expect(result == NFSPath(mountPath: "/D/", nfsPath: "Music/rekordbox/track.wav"))
        }

        @Test("extracts mount path from macOS file path for RB slot")
        func test12() throws {
            let result = resolveNfsPath(.rb, "/Users/example/Music/track.mp3")
            #expect(result == NFSPath(mountPath: "/", nfsPath: "Users/example/Music/track.mp3"))
        }

        @Test("does not apply Windows parsing to USB slot paths")
        func test13() throws {
            let result = resolveNfsPath(.usb, "C:\\fake\\path.mp3")
            #expect(result == NFSPath(mountPath: "/C/", nfsPath: "C:\\fake\\path.mp3"))
        }

    }
}
