import DJLinkKit
import Foundation
import Testing

// 원본 metadata-connect/test/label.test.ts
//
// Record label extraction (NP3-364).
//
// The label is the one field a DJ cares about that no tag format agreed on:
// ID3 has a frame for it, Vorbis has three competing field names, and MP4 has
// no atom at all and stores it as a freeform field. Each of these fixtures is
// the minimum valid file that carries a label in one of those ways.

// ---------------------------------------------------------------- ID3 (mp3)

/// A v2.3/2.4 frame: 4-byte id, 4-byte big-endian size, 2 flag bytes.
private func id3v23Frame(_ id: String, _ value: String) -> [UInt8] {
    let body = [UInt8.zero] + [UInt8](value, encoding: .latin1)
    var header = [UInt8].alloc(10)
    header.set([UInt8](id, encoding: .ascii), 0)
    header.writeUInt32BE(body.count, 4)
    return header + body
}

/// A v2.2 frame: 3-byte id and 3-byte size, no flags.
private func id3v22Frame(_ id: String, _ value: String) -> [UInt8] {
    let body = [UInt8.zero] + [UInt8](value, encoding: .latin1)
    var header = [UInt8].alloc(6)
    header.set([UInt8](id, encoding: .ascii), 0)
    // writeUIntBE(length, 3, 3)
    header[3] = UInt8((body.count >> 16) & 0xff)
    header[4] = UInt8((body.count >> 8) & 0xff)
    header[5] = UInt8(body.count & 0xff)
    return header + body
}

private func id3Tag(_ majorVersion: Int, _ frames: [[UInt8]]) -> [UInt8] {
    let body = [UInt8].concat(frames)
    var header = [UInt8].alloc(10)
    header.set([UInt8]("ID3", encoding: .ascii), 0)
    header[3] = UInt8(majorVersion)
    // Tag size is syncsafe: 7 bits per byte so it can never look like a frame sync
    header[6] = UInt8((body.count >> 21) & 0x7f)
    header[7] = UInt8((body.count >> 14) & 0x7f)
    header[8] = UInt8((body.count >> 7) & 0x7f)
    header[9] = UInt8(body.count & 0x7f)
    return header + body
}

// --------------------------------------------------------------- FLAC

private func vorbisComment(_ fields: [String]) -> [UInt8] {
    let vendor = [UInt8]("reference libFLAC", encoding: .utf8)
    var parts: [[UInt8]] = [.alloc(4), vendor, .alloc(4)]
    parts[0].writeUInt32LE(vendor.count, 0)
    parts[2].writeUInt32LE(fields.count, 0)

    for field in fields {
        let encoded = [UInt8](field, encoding: .utf8)
        var length = [UInt8].alloc(4)
        length.writeUInt32LE(encoded.count, 0)
        parts.append(length)
        parts.append(encoded)
    }

    let body = [UInt8].concat(parts)
    // Block header: last-block flag in the top bit, then type, then 24-bit length
    var blockHeader = [UInt8].alloc(4)
    blockHeader[0] = 0x80 | 4 // last block, VORBIS_COMMENT
    // writeUIntBE(length, 1, 3)
    blockHeader[1] = UInt8((body.count >> 16) & 0xff)
    blockHeader[2] = UInt8((body.count >> 8) & 0xff)
    blockHeader[3] = UInt8(body.count & 0xff)

    return [UInt8]("fLaC", encoding: .ascii) + blockHeader + body
}

// --------------------------------------------------------------- MP4

private func atom(_ type: String, _ parts: [UInt8]...) -> [UInt8] {
    let body = [UInt8].concat(parts)
    var header = [UInt8].alloc(8)
    header.writeUInt32BE(body.count + 8, 0)
    header.set([UInt8](type, encoding: .latin1), 4)
    return header + body
}

/// An iTunes freeform atom: the namespace, the field name, then the value.
private func freeformAtom(_ name: String, _ value: String) -> [UInt8] {
    atom(
        "----",
        atom("mean", .alloc(4), [UInt8]("com.apple.iTunes", encoding: .utf8)),
        atom("name", .alloc(4), [UInt8](name, encoding: .utf8)),
        // data atom: 4 bytes type, 4 bytes locale, then the value
        atom("data", .alloc(8), [UInt8](value, encoding: .utf8))
    )
}

private func mp4File(_ items: [UInt8]...) -> [UInt8] {
    [UInt8].concat([
        atom("ftyp", [UInt8]("M4A \0\0\0\0", encoding: .latin1)),
        // meta carries 4 bytes of version/flags before its children, unlike every
        // other container atom
        atom("moov", atom("udta", atom("meta", .alloc(4), atom("ilst", [UInt8].concat(items))))),
    ])
}

// ----------------------------------------------------------------- tests

@Suite("record label extraction")
struct MetadataConnectLabelTests {
    @Suite("ID3")
    struct ID3 {
        @Test("reads the label from a v2.3 TPUB frame")
        func readsTheLabelFromAV23TPUBFrame() async {
            let file = id3Tag(3, [
                id3v23Frame("TIT2", "Strobe"),
                id3v23Frame("TPUB", "Anjunadeep"),
            ])

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "mp3"))

            #expect(metadata?.title == "Strobe")
            #expect(metadata?.label == "Anjunadeep")
        }

        @Test("reads the label from a v2.2 TPB frame")
        func readsTheLabelFromAV22TPBFrame() async {
            let file = id3Tag(2, [id3v22Frame("TPB", "Drumcode")])

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "mp3"))

            #expect(metadata?.label == "Drumcode")
        }

        @Test("does not mistake the artist frame for the label")
        func doesNotMistakeTheArtistFrameForTheLabel() async {
            // TPE1 and TPUB share a prefix with the shorter v2.2 ids the matcher also
            // accepts, so a sloppy prefix match would read the artist as the label.
            let file = id3Tag(3, [id3v23Frame("TPE1", "deadmau5")])

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "mp3"))

            #expect(metadata?.artist == "deadmau5")
            #expect(metadata?.label == nil)
        }

        @Test("leaves the label unset when the file has no publisher frame")
        func leavesTheLabelUnsetWhenTheFileHasNoPublisherFrame() async {
            let file = id3Tag(3, [id3v23Frame("TIT2", "Untagged")])

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "mp3"))

            #expect(metadata?.label == nil)
        }

        @Test("reads the label from an AIFF file, which carries an ID3 chunk")
        func readsTheLabelFromAnAIFFFileWhichCarriesAnID3Chunk() async {
            let id3 = id3Tag(3, [id3v23Frame("TPUB", "Hyperdub")])
            var chunk = [UInt8].alloc(8)
            chunk.set([UInt8]("ID3 ", encoding: .ascii), 0)
            chunk.writeUInt32BE(id3.count, 4)

            let form = [UInt8]("AIFF", encoding: .ascii) + chunk + id3
            var header = [UInt8].alloc(8)
            header.set([UInt8]("FORM", encoding: .ascii), 0)
            header.writeUInt32BE(form.count, 4)

            let metadata = await MetadataConnect.extractMetadata(
                MetadataConnect.createBufferReader(header + form, "aiff")
            )

            #expect(metadata?.label == "Hyperdub")
        }
    }

    @Suite("FLAC")
    struct FLAC {
        // 원본 it.each: 인자마다 한 번씩 돈다. 문구의 %s는 인자 값이 들어가는 자리다.
        @Test("reads the label from the %s comment", arguments: ["LABEL", "PUBLISHER", "ORGANIZATION"])
        func readsTheLabelFromTheComment(_ field: String) async {
            let file = vorbisComment(["\(field)=Kompakt"])

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "flac"))

            #expect(metadata?.label == "Kompakt")
        }

        @Test("matches the field name case-insensitively")
        func matchesTheFieldNameCaseInsensitively() async {
            let file = vorbisComment(["label=Ostgut Ton"])

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "flac"))

            #expect(metadata?.label == "Ostgut Ton")
        }

        @Test("prefers LABEL when a tagger has written more than one of them")
        func prefersLABELWhenATaggerHasWrittenMoreThanOneOfThem() async {
            let file = vorbisComment(["ORGANIZATION=Distributor", "LABEL=Warp Records"])

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "flac"))

            #expect(metadata?.label == "Warp Records")
        }

        @Test("leaves the label unset when no label comment is present")
        func leavesTheLabelUnsetWhenNoLabelCommentIsPresent() async {
            let file = vorbisComment(["ARTIST=Aphex Twin"])

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "flac"))

            #expect(metadata?.artist == "Aphex Twin")
            #expect(metadata?.label == nil)
        }
    }

    @Suite("MP4")
    struct MP4 {
        @Test("reads the label from a freeform LABEL atom")
        func readsTheLabelFromAFreeformLABELAtom() async {
            let file = mp4File(freeformAtom("LABEL", "Defected"))

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "m4a"))

            #expect(metadata?.label == "Defected")
        }

        @Test("reads the label from a freeform PUBLISHER atom")
        func readsTheLabelFromAFreeformPUBLISHERAtom() async {
            let file = mp4File(freeformAtom("PUBLISHER", "Toolroom"))

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "m4a"))

            #expect(metadata?.label == "Toolroom")
        }

        @Test("ignores freeform atoms holding some other field")
        func ignoresFreeformAtomsHoldingSomeOtherField() async {
            // Every freeform atom has the same '----' type, so the name atom is the
            // only thing separating the label from the dozens of other fields
            // taggers stash here.
            let file = mp4File(freeformAtom("MOOD", "Peak Time"))

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "m4a"))

            #expect(metadata?.label == nil)
        }

        @Test("finds the label among other freeform atoms")
        func findsTheLabelAmongOtherFreeformAtoms() async {
            let file = mp4File(
                freeformAtom("MOOD", "Peak Time"),
                freeformAtom("LABEL", "Innervisions"),
                freeformAtom("ENERGY", "8")
            )

            let metadata = await MetadataConnect.extractMetadata(MetadataConnect.createBufferReader(file, "m4a"))

            #expect(metadata?.label == "Innervisions")
        }
    }
}
