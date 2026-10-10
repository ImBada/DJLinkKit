import Foundation
import Testing

@testable import DJLinkKit

@Suite("OneLibraryAdapter", .enabled(if: oneLibraryConnectFixtureAvailable))
@DJLinkActor struct OneLibraryConnectAdapterTests {
    @Suite("Track queries")
    @DJLinkActor struct Group0 {
        @Suite("findTrack")
        @DJLinkActor struct Group0 {
            @Test("finds a track by ID with full metadata")
            func test0() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(1)

                #expect(track != nil)
                #expect(track?.id == 1)
                #expect(track?.title == "Test Track")
                #expect(track?.mixName == "Extended Mix")
                #expect(track?.tempo == 128)
                #expect(track?.duration == 300)
                #expect(track?.rating == 5)
                #expect(track?.trackNumber == 1)
                #expect(track?.discNumber == 1)
                #expect(track?.comment == "Test comment")
                #expect(track?.filePath == "/Music/test.mp3")
                #expect(track?.fileName == "test.mp3")
                #expect(track?.fileSize == 5_000_000)
                #expect(track?.bitrate == 320)
                #expect(track?.sampleRate == 44100)
                #expect(track?.sampleDepth == 16)
                #expect(track?.playCount == 10)
                #expect(track?.autoloadHotcues == true)
                #expect(track?.kuvoPublic == true)
            }
            @Test("returns null for non-existent track")
            func test1() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(999)
                #expect(track == nil)
            }
            @Test("handles track with minimal metadata")
            func test2() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(3)

                #expect(track != nil)
                #expect(track?.id == 3)
                #expect(track?.title == "Unknown Track")
                #expect(track?.tempo == 0)
                #expect(track?.artist == nil)
                #expect(track?.album == nil)
                #expect(track?.genre == nil)
                #expect(track?.key == nil)
                #expect(track?.color == nil)
                #expect(track?.label == nil)
                #expect(track?.artwork == nil)
            }
        }
        @Suite("findAllTracks")
        @DJLinkActor struct Group1 {
            @Test("returns all tracks")
            func test3() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let tracks = try adapter.findAllTracks()

                #expect(tracks.count == 5)
                #expect(tracks.map { $0.id } == [1, 2, 3, 4, 5])
            }
            @Test("includes full metadata for each track")
            func test4() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let tracks = try adapter.findAllTracks()
                let track1 = tracks.first { $0.id == 1 }

                #expect(track1?.title == "Test Track")
                #expect(track1?.artist != nil)
                #expect(track1?.artist?.name == "Test Artist")
            }
        }
        @Suite("relations")
        @DJLinkActor struct Group2 {
            @Test("populates artist relation")
            func test5() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(1)

                #expect(track?.artist != nil)
                #expect(track?.artist?.id == 1)
                #expect(track?.artist?.name == "Test Artist")
            }
            @Test("populates remixer relation")
            func test6() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(1)

                #expect(track?.remixer != nil)
                #expect(track?.remixer?.id == 3)
                #expect(track?.remixer?.name == "Remixer One")
            }
            @Test("populates album relation")
            func test7() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(1)

                #expect(track?.album != nil)
                #expect(track?.album?.id == 1)
                #expect(track?.album?.name == "Test Album")
            }
            @Test("populates genre relation")
            func test8() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(1)

                #expect(track?.genre != nil)
                #expect(track?.genre?.id == 1)
                #expect(track?.genre?.name == "Electronic")
            }
            @Test("populates key relation")
            func test9() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(1)

                #expect(track?.key != nil)
                #expect(track?.key?.id == 1)
                #expect(track?.key?.name == "Am")
            }
            @Test("populates color relation")
            func test10() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(1)

                #expect(track?.color != nil)
                #expect(track?.color?.id == 1)
                #expect(track?.color?.name == "Pink")
            }
            @Test("populates label relation")
            func test11() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(1)

                #expect(track?.label != nil)
                #expect(track?.label?.id == 1)
                #expect(track?.label?.name == "Test Label")
            }
            @Test("populates artwork relation")
            func test12() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(1)

                #expect(track?.artwork != nil)
                #expect(track?.artwork?.id == 1)
                #expect(track?.artwork?.path == "/PIONEER/USBANLZ/P001/0001/artwork.jpg")
            }
            @Test("handles null relations gracefully")
            func test13() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(2)

                #expect(track?.remixer == nil)
                #expect(track?.label == nil)
                #expect(track?.artwork == nil)
            }
        }
        @Suite("unit conversions")
        @DJLinkActor struct Group3 {
            @Test("converts BPM from bpmx100")
            func test14() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track1 = try adapter.findTrack(1)
                let track2 = try adapter.findTrack(2)

                #expect(track1?.tempo == 128)
                #expect(track2?.tempo == 140)
            }
            @Test("reads duration as seconds")
            func test15() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track1 = try adapter.findTrack(1)
                let track2 = try adapter.findTrack(2)

                #expect(track1?.duration == 300)
                #expect(track2?.duration == 240)
            }
            @Test("handles zero BPM")
            func test16() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let track = try adapter.findTrack(3)
                #expect(track?.tempo == 0)
            }
        }
    }
    @Suite("Cue queries")
    @DJLinkActor struct Group1 {
        @Suite("findCues")
        @DJLinkActor struct Group0 {
            @Test("finds all cues for a track")
            func test17() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let cues = try adapter.findCues(1)
                #expect(cues.count == 4)
            }
            @Test("returns empty array for track with no cues")
            func test18() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let cues = try adapter.findCues(2)
                #expect(cues == [])
            }
            @Test("returns empty array for non-existent track")
            func test19() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let cues = try adapter.findCues(999)
                #expect(cues == [])
            }
        }
        @Suite("cue types")
        @DJLinkActor struct Group1 {
            @Test("identifies memory cue (kind=0, no loop)")
            func test20() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let cues = try adapter.findCues(1)
                let memoryCue = cues.first { $0.type == "cue_point" }

                #expect(memoryCue != nil)
                #expect(memoryCue?.offset == 0)
            }
            @Test("identifies hot cue (kind=1-8, no loop)")
            func test21() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let cues = try adapter.findCues(1)
                let hotCue = cues.first { $0.type == "hot_cue" && $0.button?.rawValue == 1 }

                #expect(hotCue != nil)
                #expect(hotCue?.offset == 32000)
            }
            @Test("identifies loop (has outUsec)")
            func test22() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let cues = try adapter.findCues(1)
                let loop = cues.first { $0.type == "loop" }

                #expect(loop != nil)
                if let loop, loop.length != nil {
                    #expect(loop.length == 16000)
                }
            }
            @Test("identifies hot loop (hot cue with loop)")
            func test23() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let cues = try adapter.findCues(1)
                let hotLoop = cues.first { $0.type == "hot_loop" }

                #expect(hotLoop != nil)
                if let hotLoop, hotLoop.button != nil, hotLoop.length != nil {
                    #expect(hotLoop.button?.rawValue == 2)
                    #expect(hotLoop.length == 8000)
                }
            }
        }
        @Suite("cue metadata")
        @DJLinkActor struct Group2 {
            @Test("includes cue offset in milliseconds")
            func test24() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let cues = try adapter.findCues(1)
                let offsets = cues.map { $0.offset }

                #expect(offsets.contains(0))
                #expect(offsets.contains(32000))
                #expect(offsets.contains(64000))
                #expect(offsets.contains(128000))
            }
            @Test("includes label (cueComment)")
            func test25() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let cues = try adapter.findCues(1)
                let hotCue = cues.first { $0.type == "hot_cue" }

                #expect(hotCue?.label == "Drop")
            }
        }
    }
    @Suite("Playlist queries")
    @DJLinkActor struct Group2 {
        @Suite("findPlaylist")
        @DJLinkActor struct Group0 {
            @Test("finds root-level playlists and folders")
            func test26() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let result = try adapter.findPlaylist()

                #expect(result.playlists.count == 2)
                #expect(result.folders.count == 1)
            }
            @Test("returns playlists with correct properties")
            func test27() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let result = try adapter.findPlaylist()
                let favorites = result.playlists.first { $0.name == "My Favorites" }

                #expect(favorites != nil)
                #expect(favorites?.id == 1)
                #expect(favorites?.isFolder == false)
            }
            @Test("returns folders with correct properties")
            func test28() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let result = try adapter.findPlaylist()
                let djSets = result.folders.first { $0.name == "DJ Sets" }

                #expect(djSets != nil)
                #expect(djSets?.id == 2)
                #expect(djSets?.isFolder == true)
            }
            @Test("finds nested playlists within folder")
            func test29() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let root = try adapter.findPlaylist()
                let folderId = try #require(root.folders.first { $0.name == "DJ Sets" }).id
                let nested = try adapter.findPlaylist(folderId)

                #expect(nested.playlists.count == 2)
                #expect(nested.playlists.map { $0.name }.contains("Club Night"))
                #expect(nested.playlists.map { $0.name }.contains("Festival"))
                #expect(nested.folders.count == 0)
            }
        }
        @Suite("findPlaylistContents")
        @DJLinkActor struct Group1 {
            @Test("returns track IDs in playlist order")
            func test30() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let contents = try adapter.findPlaylistContents(1)
                #expect(contents == [1, 2, 4])
            }
            @Test("returns empty array for empty playlist")
            func test31() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let contents = try adapter.findPlaylistContents(5)
                #expect(contents == [])
            }
            @Test("returns empty array for non-existent playlist")
            func test32() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let contents = try adapter.findPlaylistContents(999)
                #expect(contents == [])
            }
            @Test("returns correct contents for nested playlist")
            func test33() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let contents = try adapter.findPlaylistContents(3)
                #expect(contents == [1, 4, 5])
            }
        }
    }
    @Suite("MyTag queries")
    @DJLinkActor struct Group3 {
        @Suite("findMyTags")
        @DJLinkActor struct Group0 {
            @Test("finds root-level tags and folders")
            func test34() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let result = try adapter.findMyTags()

                #expect(result.tags.count == 2)
                #expect(result.folders.count == 1)
            }
            @Test("identifies folders correctly")
            func test35() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let result = try adapter.findMyTags()
                let folder = result.folders.first { $0.name == "Energy" }

                #expect(folder != nil)
                #expect(folder?.isFolder == true)
            }
            @Test("identifies tags correctly")
            func test36() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let result = try adapter.findMyTags()
                let tag = result.tags.first { $0.name == "Favorites" }

                #expect(tag != nil)
                #expect(tag?.isFolder == false)
            }
            @Test("finds nested tags within folder")
            func test37() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let root = try adapter.findMyTags()
                let folderId = try #require(root.folders.first { $0.name == "Energy" }).id
                let nested = try adapter.findMyTags(folderId)

                #expect(nested.tags.count == 2)
                #expect(nested.folders.count == 0)
            }
        }
        @Suite("findMyTagById")
        @DJLinkActor struct Group1 {
            @Test("finds tag by ID")
            func test38() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let tag = try adapter.findMyTagById(1)

                #expect(tag != nil)
                #expect(tag?.name == "Favorites")
                #expect(tag?.isFolder == false)
            }
            @Test("finds folder by ID")
            func test39() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let folder = try adapter.findMyTagById(2)

                #expect(folder != nil)
                #expect(folder?.name == "Energy")
                #expect(folder?.isFolder == true)
            }
            @Test("returns null for non-existent ID")
            func test40() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let tag = try adapter.findMyTagById(999)
                #expect(tag == nil)
            }
        }
        @Suite("findMyTagContents")
        @DJLinkActor struct Group2 {
            @Test("returns track IDs for tag")
            func test41() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let contents = try adapter.findMyTagContents(1)
                #expect(contents == [1, 4])
            }
            @Test("returns empty array for tag with no contents")
            func test42() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let contents = try adapter.findMyTagContents(2)
                #expect(contents == [])
            }
        }
        @Suite("findMyTagsForTrack")
        @DJLinkActor struct Group3 {
            @Test("finds all tags containing a track")
            func test43() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let tags = try adapter.findMyTagsForTrack(1)

                #expect(tags.count == 3)
                #expect(tags.map { $0.name }.contains("Favorites"))
                #expect(tags.map { $0.name }.contains("High Energy"))
                #expect(tags.map { $0.name }.contains("Classics"))
            }
            @Test("returns empty array for track not in any tags")
            func test44() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let tags = try adapter.findMyTagsForTrack(3)
                #expect(tags == [])
            }
        }
    }
    @Suite("History queries")
    @DJLinkActor struct Group4 {
        @Suite("findHistorySessions")
        @DJLinkActor struct Group0 {
            @Test("returns all history sessions")
            func test45() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let sessions = try adapter.findHistorySessions()
                #expect(sessions.count == 3)
            }
            @Test("returns sessions with correct properties")
            func test46() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let sessions = try adapter.findHistorySessions()
                let session = sessions.first { $0.name == "2024-01-01" }

                #expect(session != nil)
                #expect(session?.id == 1)
            }
        }
        @Suite("findHistoryContents")
        @DJLinkActor struct Group1 {
            @Test("returns track IDs in play order")
            func test47() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let contents = try adapter.findHistoryContents(1)
                #expect(contents == [1, 2, 4])
            }
            @Test("returns correct contents for different session")
            func test48() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let contents = try adapter.findHistoryContents(2)
                #expect(contents == [4, 5, 1])
            }
            @Test("returns empty array for non-existent session")
            func test49() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let contents = try adapter.findHistoryContents(999)
                #expect(contents == [])
            }
        }
    }
    @Suite("HotCueBankList queries")
    @DJLinkActor struct Group5 {
        @Suite("findHotCueBankLists")
        @DJLinkActor struct Group0 {
            @Test("returns all bank lists")
            func test50() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let lists = try adapter.findHotCueBankLists()
                #expect(lists.count == 2)
            }
            @Test("returns bank lists with correct properties")
            func test51() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let lists = try adapter.findHotCueBankLists()

                #expect(lists.map { $0.name }.contains("Bank A"))
                #expect(lists.map { $0.name }.contains("Bank B"))
            }
        }
        @Suite("findHotCueBankListCues")
        @DJLinkActor struct Group1 {
            @Test("returns cue IDs for bank list")
            func test52() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let lists = try adapter.findHotCueBankLists()
                let bankA = lists.first { $0.name == "Bank A" }
                let cues = try adapter.findHotCueBankListCues(try #require(bankA).id)

                #expect(cues == [2, 4])
            }
            @Test("returns empty array for non-existent bank list")
            func test53() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let cues = try adapter.findHotCueBankListCues(999)
                #expect(cues == [])
            }
        }
    }
    @Suite("Menu configuration queries")
    @DJLinkActor struct Group6 {
        @Suite("findMenuItems")
        @DJLinkActor struct Group0 {
            @Test("returns all menu items")
            func test54() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let items = try adapter.findMenuItems()
                #expect(items.count == 5)
            }
            @Test("returns menu items with correct properties")
            func test55() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let items = try adapter.findMenuItems()
                let genre = items.first { $0.name == "Genre" }

                #expect(genre != nil)
                #expect(genre?.kind == 128)
            }
        }
        @Suite("findVisibleCategories")
        @DJLinkActor struct Group1 {
            @Test("returns only visible categories")
            func test56() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let categories = try adapter.findVisibleCategories()

                #expect(categories.count == 4)
            }
            @Test("does not include hidden categories")
            func test57() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let categories = try adapter.findVisibleCategories()
                let trackCategory = categories.first { $0.name == "Track" }

                #expect(trackCategory == nil)
            }
        }
        @Suite("findVisibleSortOptions")
        @DJLinkActor struct Group2 {
            @Test("returns only visible sort options")
            func test58() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let sorts = try adapter.findVisibleSortOptions()

                #expect(sorts.count == 3)
            }
        }
    }
    @Suite("Property queries")
    @DJLinkActor struct Group7 {
        @Suite("getProperty")
        @DJLinkActor struct Group0 {
            @Test("returns device property")
            func test59() throws {
                let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
                defer { adapter.close() }
                let property = try adapter.getProperty()

                #expect(property != nil)
                #expect(property?.deviceName == "Test Device")
            }
        }
    }
    @Suite("Edge cases")
    @DJLinkActor struct Group8 {
        @Test("handles multiple calls without issues")
        func test60() throws {
            let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
            defer { adapter.close() }
            let tracks1 = try adapter.findAllTracks()
            let tracks2 = try adapter.findAllTracks()

            #expect(tracks1.count == tracks2.count)
        }
        @Test("handles concurrent-like access")
        func test61() throws {
            let adapter = try OneLibraryAdapter(dbPath: oneLibraryConnectFixturePath)
            defer { adapter.close() }
            let tracks = try adapter.findAllTracks()
            let playlists = try adapter.findPlaylist()
            let tags = try adapter.findMyTags()

            #expect(tracks.count == 5)
            #expect(playlists.playlists.count == 2)
            #expect(tags.tags.count == 2)
        }
    }
}
