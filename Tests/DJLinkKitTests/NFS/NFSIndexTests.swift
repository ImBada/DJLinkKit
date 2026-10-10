import DJLinkKit
import DJLinkTestSupport
import Testing

struct NFSIndexTests {
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

        @Test("uppercases the drive letter")
        func test2() throws {
            let result = parseWindowsPath("d:\\Music\\track.mp3")
            #expect(result == NFSPath(mountPath: "/D/", nfsPath: "Music/track.mp3"))
        }

        @Test("converts all backslashes to forward slashes")
        func test3() throws {
            let result = parseWindowsPath(
                "C:\\Users\\example\\Music\\PioneerDJ\\Imported from Device\\Contents\\track.mp3")
            #expect(
                result
                    == NFSPath(
                        mountPath: "/C/", nfsPath: "Users/example/Music/PioneerDJ/Imported from Device/Contents/track.mp3"
                    ))
        }

        @Test("returns null for macOS paths")
        func test4() throws {
            let result = parseWindowsPath("/Users/example/Music/track.mp3")
            #expect(result == nil)
        }

        @Test("returns null for relative paths")
        func test5() throws {
            let result = parseWindowsPath("Music/track.mp3")
            #expect(result == nil)
        }

    }
    @Suite("resolveNfsPath")
    struct ResolveNfsPath {
        @Suite("RB slot (rekordbox link)")
        struct RBSlot {
            @Test("resolves Windows path to NFS mount and path")
            func test6() throws {
                let result = resolveNfsPath(.rb, "C:/Users/example/Music/PioneerDJ/track.mp3")
                #expect(result == NFSPath(mountPath: "/C/", nfsPath: "Users/example/Music/PioneerDJ/track.mp3"))
            }

            @Test("resolves Windows backslash path to NFS mount and path")
            func test7() throws {
                let result = resolveNfsPath(.rb, "C:\\Users\\example\\Music\\track.mp3")
                #expect(result == NFSPath(mountPath: "/C/", nfsPath: "Users/example/Music/track.mp3"))
            }

            @Test("resolves macOS absolute path")
            func test8() throws {
                let result = resolveNfsPath(.rb, "/Users/example/Music/track.mp3")
                #expect(result == NFSPath(mountPath: "/", nfsPath: "Users/example/Music/track.mp3"))
            }

        }
        @Suite("USB slot")
        struct USBSlot {
            @Test("uses /C/ mount for USB slot")
            func test9() throws {
                let result = resolveNfsPath(.usb, "PIONEER/USBANLZ/track.mp3")
                #expect(result == NFSPath(mountPath: "/C/", nfsPath: "PIONEER/USBANLZ/track.mp3"))
            }

        }
        @Suite("SD slot")
        struct SDSlot {
            @Test("uses /B/ mount for SD slot")
            func test10() throws {
                let result = resolveNfsPath(.sd, "PIONEER/USBANLZ/track.mp3")
                #expect(result == NFSPath(mountPath: "/B/", nfsPath: "PIONEER/USBANLZ/track.mp3"))
            }

        }
    }
    @Suite("getPortmapPort")
    struct GetPortmapPort {
        @Test("returns 50111 for rekordbox devices")
        func test11() throws {
            let device = mockDevice(
                id: 1, type: .rekordbox, name: "rekordbox", ip: try Address4("192.168.1.2"),
                macAddr: [UInt8](repeating: 0, count: 6))
            #expect(getPortmapPort(device) == REKORDBOX_PORTMAP_PORT)
            #expect(getPortmapPort(device) == 50111)
        }

        @Test("returns 111 for CDJ devices")
        func test12() throws {
            let device = mockDevice(
                id: 1, type: .cdj, name: "CDJ-3000", ip: try Address4("192.168.1.2"),
                macAddr: [UInt8](repeating: 0, count: 6))
            #expect(getPortmapPort(device) == STANDARD_PORTMAP_PORT)
            #expect(getPortmapPort(device) == 111)
        }

        @Test("returns 111 for mixer devices")
        func test13() throws {
            let device = mockDevice(
                id: 1, type: .mixer, name: "DJM-900NXS2", ip: try Address4("192.168.1.2"),
                macAddr: [UInt8](repeating: 0, count: 6))
            #expect(getPortmapPort(device) == STANDARD_PORTMAP_PORT)
        }

    }
    @Suite("portmap port constants")
    struct PortmapConstants {
        @Test("standard portmap port is 111")
        func test14() throws {
            #expect(STANDARD_PORTMAP_PORT == 111)
        }

        @Test("rekordbox portmap port is 50111")
        func test15() throws {
            #expect(REKORDBOX_PORTMAP_PORT == 50111)
        }

    }
}
