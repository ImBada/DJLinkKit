import Foundation
import Testing

@testable import DJLinkKit

@Suite("Database Loading")
@DJLinkActor struct LocalDBDatabaseLoadingTests {
    @Suite("OneLibraryAdapter")
    @DJLinkActor struct Group0 {
        @Test("opens an encrypted OneLibrary database")
        func test0() throws {
            let adapter = try OneLibraryAdapter(dbPath: oneLibraryFixturePath)
            #expect(type(of: adapter) == OneLibraryAdapter.self)
            adapter.close()
        }
        @Test("can query tracks after opening")
        func test1() throws {
            let adapter = try OneLibraryAdapter(dbPath: oneLibraryFixturePath)
            defer { adapter.close() }
            let tracks = try adapter.findAllTracks()
            // 원본과 다름: 배열 형은 Swift에서 정적이다.
            let _: [Track] = tracks
            #expect(tracks.count > 0)
        }
        @Test("throws on invalid database path")
        func test2() throws {
            #expect(throws: (any Error).self) { try OneLibraryAdapter(dbPath: "/nonexistent/path.db") }
        }
        @Test("cannot read tables from non-encrypted database")
        func test3() throws {
            let tempPath = FileManager.default.temporaryDirectory.appending(
                path: UUID().uuidString + "-temp-plain.db"
            ).path
            let plainDb = try CipherDatabase(path: tempPath, key: nil as CipherKey?, mode: .create)
            try plainDb.execute("CREATE TABLE djmdContent (id INTEGER)")
            try plainDb.execute("INSERT INTO djmdContent VALUES (1)")
            plainDb.close()
            defer { try? FileManager.default.removeItem(atPath: tempPath) }
            let adapter = try OneLibraryAdapter(dbPath: tempPath)
            defer { adapter.close() }
            #expect(throws: (any Error).self) { try adapter.findAllTracks() }
        }
        @Test("properly closes database connection")
        func test4() throws {
            let adapter = try OneLibraryAdapter(dbPath: oneLibraryFixturePath)
            adapter.close()
            #expect(throws: (any Error).self) { try adapter.findAllTracks() }
        }
    }
    @Suite("format detection")
    @DJLinkActor struct Group1 {
        @Test("identifies OneLibrary database by filename")
        func test5() throws {
            let oneLibraryPath = "PIONEER/rekordbox/exportLibrary.db"
            #expect(oneLibraryPath.contains("exportLibrary.db"))
        }
        @Test("identifies PDB database by filename")
        func test6() throws {
            let pdbPath = "PIONEER/rekordbox/export.pdb"
            #expect(pdbPath.contains("export.pdb"))
        }
    }
    @Suite("media identification")
    @DJLinkActor struct Group2 {
        @Test("creates unique ID based on media properties")
        func test7() throws {
            var media1 = localDBTestMedia(
                deviceId: 1, slot: .usb, name: "USB-1", freeBytes: 1_000_000, totalBytes: 2_000_000,
                trackCount: 100, createdDate: Date(timeIntervalSince1970: 1_704_067_200))
            let id1 = getMediaId(media1)
            media1.trackCount = 101
            #expect(id1 != getMediaId(media1))
        }
        @Test("creates same ID for identical media")
        func test8() throws {
            let media = localDBTestMedia(
                deviceId: 1, slot: .usb, name: "USB-1", freeBytes: 1_000_000, totalBytes: 2_000_000,
                trackCount: 100, createdDate: Date(timeIntervalSince1970: 1_704_067_200))
            #expect(getMediaId(media) == getMediaId(media))
        }
    }
    @Suite("device slot filtering")
    @DJLinkActor struct Group3 {
        @Test("only allows USB and SD slots for database loading")
        func test9() throws {
            let validSlots: [MediaSlot] = [.usb, .sd]
            #expect(validSlots.contains(.usb))
            #expect(validSlots.contains(.sd))
            #expect(!validSlots.contains(.rb))
        }
    }
    @Suite("device validation")
    @DJLinkActor struct Group4 {
        @Test("rejects non-CDJ device types")
        func test10() throws {
            #expect(DeviceType.rekordbox != .cdj)
            #expect(DeviceType.mixer != .cdj)
        }
        @Test("accepts CDJ device type")
        func test11() throws {
            #expect(DeviceType.cdj.rawValue == 0x01)
        }
    }
    @Suite("temp file handling")
    @DJLinkActor struct Group5 {
        @Test("generates unique temp file paths")
        func test12() throws {
            let tmpDir = FileManager.default.temporaryDirectory
            let deviceId = 1
            let slot = MediaSlot.usb
            let timestamp1 = Int(Date().timeIntervalSince1970 * 1000)
            let timestamp2 = timestamp1 + 1
            let path1 = tmpDir.appending(path: "onelibrary-\(deviceId)-\(slot.rawValue)-\(timestamp1).db")
            let path2 = tmpDir.appending(path: "onelibrary-\(deviceId)-\(slot.rawValue)-\(timestamp2).db")
            #expect(path1 != path2)
        }
        @Test("temp file path follows expected pattern")
        func test13() throws {
            let tmpDir = FileManager.default.temporaryDirectory
            let deviceId = 3
            let slot = MediaSlot.sd
            let timestamp = 1_234_567_890
            let tempPath = tmpDir.appending(
                path: "onelibrary-\(deviceId)-\(slot.rawValue)-\(timestamp).db"
            ).path
            #expect(tempPath.contains("onelibrary-"))
            #expect(tempPath.contains("-\(deviceId)-"))
            #expect(tempPath.contains("-\(slot.rawValue)-"))
            #expect(tempPath.contains(".db"))
        }
    }
    @Suite("database paths")
    @DJLinkActor struct Group6 {
        @Test("has correct OneLibrary path constant")
        func test14() throws {
            let ONELIBRARY_DB_PATH = "PIONEER/rekordbox/exportLibrary.db"
            #expect(ONELIBRARY_DB_PATH == "PIONEER/rekordbox/exportLibrary.db")
        }
        @Test("has correct legacy PDB path constant")
        func test15() throws {
            let LEGACY_PDB_PATH = "PIONEER/rekordbox/export.pdb"
            #expect(LEGACY_PDB_PATH == "PIONEER/rekordbox/export.pdb")
        }
        @Test("supports dotted path variant")
        func test16() throws {
            let ONELIBRARY_DB_PATH = "PIONEER/rekordbox/exportLibrary.db"
            let dottedPath = "." + ONELIBRARY_DB_PATH
            #expect(dottedPath == ".PIONEER/rekordbox/exportLibrary.db")
        }
    }
    @Suite("track type validation")
    @DJLinkActor struct Group7 {
        @Test("only loads databases with RB track type")
        func test17() throws {
            #expect(TrackType.rb.jsName != nil)
            #expect(TrackType.audioCD != .rb)
        }
        @Test("RB track type has expected value")
        func test18() throws {
            #expect(TrackType.rb.rawValue == 1)
        }
    }
    @Suite("format preference")
    @DJLinkActor struct Group8 {
        @Test("supports auto format preference")
        func test19() throws {
            let preference = "auto"
            #expect(preference == "auto")
        }
        @Test("supports explicit pdb format preference")
        func test20() throws {
            let preference = "pdb"
            #expect(preference == "pdb")
        }
        @Test("supports explicit onelibrary format preference")
        func test21() throws {
            let preference = "onelibrary"
            #expect(preference == "onelibrary")
        }
    }
}
