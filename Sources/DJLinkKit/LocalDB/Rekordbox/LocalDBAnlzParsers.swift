// 원본 localdb/rekordbox/anlz-parsers.ts. Kaitai 대신 주입 가능한 리더의 형을 받는다.
public struct LocalDBAnlzCue: Equatable, Sendable {
    public var hotCue: Int
    public var status: Int
    public var type: Int
    public var time: Double
    public var loopTime: Double?
    public var colorId: Int?
    public var loopNumerator: Int?
    public var loopDenominator: Int?
    public var lenComment: Int
    public var comment: String?
    public var colorCode: Int?
    public var colorRed: Int?
    public var colorGreen: Int?
    public var colorBlue: Int?
    public init(
        hotCue: Int = 0, status: Int = 1, type: Int = 1, time: Double = 0, loopTime: Double? = nil,
        colorId: Int? = nil, loopNumerator: Int? = nil, loopDenominator: Int? = nil,
        lenComment: Int = 0, comment: String? = nil, colorCode: Int? = nil,
        colorRed: Int? = nil, colorGreen: Int? = nil, colorBlue: Int? = nil
    ) {
        self.hotCue = hotCue
        self.status = status
        self.type = type
        self.time = time
        self.loopTime = loopTime
        self.colorId = colorId
        self.loopNumerator = loopNumerator
        self.loopDenominator = loopDenominator
        self.lenComment = lenComment
        self.comment = comment
        self.colorCode = colorCode
        self.colorRed = colorRed
        self.colorGreen = colorGreen
        self.colorBlue = colorBlue
    }
}
public enum LocalDBAnlzPhraseKind: Equatable, Sendable {
    case number(Int)
    case object(id: Int)
    // 원본 Kaitai unknown_tag: mood가 high·mid·low 밖이면 kind는 id가 없는 빈 객체다.
    case unknownTag

    public init(id: Int) {
        self = .object(id: id)
    }

    // unknownTag는 원본 `entry.kind.id`처럼 undefined(nil)다.
    public var id: Int? {
        switch self {
        case .number(let id), .object(let id): id
        case .unknownTag: nil
        }
    }
}
public struct LocalDBAnlzPhrase: Equatable, Sendable {
    public var phraseNumber: Int
    public var beatNumber: Int
    public var kind: LocalDBAnlzPhraseKind
    public var fillIn: Int
    public var fillInBeatNumber: Int
    public init(
        phraseNumber: Int, beatNumber: Int, kind: LocalDBAnlzPhraseKind,
        fillIn: Int = 0, fillInBeatNumber: Int = 0
    ) {
        self.phraseNumber = phraseNumber
        self.beatNumber = beatNumber
        self.kind = kind
        self.fillIn = fillIn
        self.fillInBeatNumber = fillInBeatNumber
    }

    public init(
        phraseNumber: Int, beatNumber: Int, kind: Int, fillIn: Int = 0, fillInBeatNumber: Int = 0
    ) {
        self.init(
            phraseNumber: phraseNumber, beatNumber: beatNumber, kind: .number(kind),
            fillIn: fillIn, fillInBeatNumber: fillInBeatNumber)
    }
}
public struct LocalDBAnlzBeat: Equatable, Sendable {
    public var time: Double
    public var tempo: Double
    public var beatNumber: Int
    public init(time: Double, tempo: Double, beatNumber: Int) {
        self.time = time
        self.tempo = tempo
        self.beatNumber = beatNumber
    }
}
public struct LocalDBAnlzSection: Equatable, Sendable {
    public var fourcc: String
    public var beats: [LocalDBAnlzBeat]
    public var cues: [LocalDBAnlzCue]
    public var entries: [UInt8]
    public var lenEntries: Int
    public var mood: Int
    public var bank: Int
    public var endBeat: Int
    public var phrases: [LocalDBAnlzPhrase]
    public var thresholdLow: Int
    public var thresholdMid: Int
    public var thresholdHigh: Int
    public init(
        fourcc: String = "", beats: [LocalDBAnlzBeat] = [], cues: [LocalDBAnlzCue] = [],
        lenEntries: Int = 0, entries: [UInt8] = [], mood: Int = 1, bank: Int = 0, endBeat: Int = 0,
        phrases: [LocalDBAnlzPhrase] = [], thresholdLow: Int = 0, thresholdMid: Int = 0,
        thresholdHigh: Int = 0
    ) {
        self.fourcc = fourcc
        self.beats = beats
        self.cues = cues
        self.entries = entries
        self.lenEntries = lenEntries
        self.mood = mood
        self.bank = bank
        self.endBeat = endBeat
        self.phrases = phrases
        self.thresholdLow = thresholdLow
        self.thresholdMid = thresholdMid
        self.thresholdHigh = thresholdHigh
    }
}
public func makeBeatGrid(_ data: LocalDBAnlzSection) -> BeatGrid {
    data.beats.map { .init(offset: $0.time, count: $0.beatNumber, bpm: $0.tempo / 100) }
}
public func makeCueAndLoop(_ data: LocalDBAnlzSection) -> [CueAndLoop] {
    data.cues.compactMap { entry in
        makeCueLoopEntry(
            isCue: entry.type == 1, isLoop: entry.type == 2, offset: entry.time,
            length: (entry.loopTime ?? .nan) - entry.time,
            button: entry.hotCue == 0 ? nil : .init(rawValue: entry.hotCue))
    }
}
public func makeWaveformHd(_ data: LocalDBAnlzSection) throws -> WaveformHD {
    // 원본 new Array(byteLength / 2)는 홀수 바이트 수에서 실패한다.
    guard data.entries.count % 2 == 0 else { throw DJLinkError("Invalid array length") }
    // 원본 utils/converters.ts의 16비트 HD 색·높이 계산.
    return try stride(from: 0, to: data.entries.count, by: 2).map { i in
        let value = Int(try data.entries.readUInt16BE(i))
        return .init(
            height: (value >> 2) & 0x1f,
            color: [
                Double((value >> 13) & 7) / 7, Double((value >> 10) & 7) / 7, Double((value >> 7) & 7) / 7,
            ])
    }
}
public func makeExtendedCues(_ data: LocalDBAnlzSection) -> [ExtendedCue] {
    data.cues.map { entry in
        var cue = ExtendedCue(hotCue: entry.hotCue, type: entry.type, time: entry.time)
        if entry.type == 2 { cue.loopTime = entry.loopTime }
        if let id = entry.colorId, id > 0 { cue.colorId = id }
        if let code = entry.colorCode, code > 0 {
            cue.colorCode = code
            cue.colorRgb = .init(
                r: entry.colorRed ?? 0, g: entry.colorGreen ?? 0, b: entry.colorBlue ?? 0)
        }
        if entry.lenComment > 0, let text = entry.comment, !text.isEmpty {
            let comment = String(text.reversed().drop(while: { $0 == "\0" }).reversed())
            if !comment.isEmpty { cue.comment = comment }
        }
        if let numerator = entry.loopNumerator, numerator > 0 {
            cue.loopNumerator = numerator
            cue.loopDenominator = entry.loopDenominator ?? 1
        }
        return cue
    }
}
public func makeSongStructure(_ data: LocalDBAnlzSection) -> SongStructure {
    let mood: SongStructure.Mood = [1: .high, 2: .mid, 3: .low][data.mood] ?? .high
    let banks: [SongStructure.Bank] = [
        .default, .cool, .natural, .hot, .subtle, .warm, .vivid, .club_1, .club_2,
    ]
    let bank = banks.indices.contains(data.bank) ? banks[data.bank] : .default
    let maps: [SongStructure.Mood: [Int: String]] = [
        .high: [1: "Intro", 2: "Up", 3: "Down", 5: "Chorus", 6: "Outro"],
        .mid: [
            1: "Intro", 2: "Verse 1", 3: "Verse 2", 4: "Verse 3", 5: "Verse 4", 6: "Verse 5",
            7: "Verse 6", 8: "Bridge", 9: "Chorus", 10: "Outro",
        ],
        .low: [
            1: "Intro", 2: "Verse 1", 3: "Verse 1", 4: "Verse 1", 5: "Verse 2", 6: "Verse 2",
            7: "Verse 2", 8: "Bridge", 9: "Chorus", 10: "Outro",
        ],
    ]
    return .init(
        mood: mood, bank: bank, endBeat: data.endBeat,
        phrases: data.phrases.map { entry in
            .init(
                index: entry.phraseNumber, beat: entry.beatNumber, kind: entry.kind.id,
                // 원본 phraseTypeMap[mood][undefined]도 없는 키라 'Unknown'이다.
                phraseType: entry.kind.id.flatMap { maps[mood]?[$0] } ?? "Unknown",
                fill: entry.fillIn > 0 ? entry.fillIn : nil,
                fillBeat: entry.fillIn > 0 ? entry.fillInBeatNumber : nil)
        })
}
public func makeWaveformPreview(_ data: LocalDBAnlzSection) -> WaveformPreviewData {
    .init(data: data.entries)
}
public func makeWaveform3BandPreview(_ data: LocalDBAnlzSection) -> Waveform3BandPreview {
    .init(numEntries: data.lenEntries, data: data.entries)
}
public func makeWaveform3BandDetail(_ data: LocalDBAnlzSection) -> Waveform3BandDetail {
    .init(numEntries: data.lenEntries, data: data.entries)
}
public func makeVocalConfig(_ data: LocalDBAnlzSection) -> VocalConfig {
    .init(
        thresholdLow: data.thresholdLow, thresholdMid: data.thresholdMid,
        thresholdHigh: data.thresholdHigh)
}
