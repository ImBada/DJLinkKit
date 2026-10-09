/// 원본의 data[i]는 범위를 넘으면 undefined다. Int?로 높이의 undefined를 보존하고,
/// 나눗셈으로 생긴 NaN은 Double에 그대로 둔다. 기반의 정상 파형 형은 바꾸지 않는다.
public struct RemoteDBWaveformPreviewSegment: Equatable, Sendable {
    public var height: Int?
    public var whiteness: Double
    public init(height: Int?, whiteness: Double) {
        self.height = height
        self.whiteness = whiteness
    }
}
public typealias RemoteDBWaveformPreview = [RemoteDBWaveformPreviewSegment]

public struct RemoteDBSuccess: Equatable, Sendable {
    public var itemsAvailable: Int
    public init(itemsAvailable: Int) { self.itemsAvailable = itemsAvailable }
}
/// 원본의 {...null, color, label}도 담는다. 이 경우 type·offset 칸이 없다.
public enum RemoteDBAdvancedCueEntry: Equatable, Sendable {
    case cue(CueAndLoop)
    case untyped(color: CueColor?, label: String)
}
public enum RemoteDBResponseData: Equatable, Sendable {
    case null, success(RemoteDBSuccess), item(Items), artwork([UInt8]), beatGrid(BeatGrid)
    case advancedCueAndLoops([RemoteDBAdvancedCueEntry])
    case cueAndLoops([CueAndLoop]), waveformPreview(RemoteDBWaveformPreview), waveformDetailed(WaveformDetailed),
        waveformHD(
            WaveformHD)
}
public func responseTransform(_ type: Response, _ args: [Field]) throws -> RemoteDBResponseData {
    switch type {
    case .success: return .success(RemoteDBSuccess(itemsAvailable: try fieldNumber(args, 1)))
    case .error, .menuHeader, .menuFooter: return .null
    case .menuItem: return .item(try fieldsToItem(args))
    case .artwork: return .artwork(try fieldBinary(args, 3))
    case .beatGrid:
        let data = try fieldBinary(args, 3).subarray(0x14)
        return .beatGrid(
            try remoteDBOffsets(data.count, 0x10).map { offset in
                BeatGridBeat(
                    offset: Double(try data.readUInt32LE(offset + 4)), count: try data.readUInt8(offset),
                    bpm: Double(try data.readUInt16LE(offset + 2)) / 100)
            })
    case .waveformPreview:
        let data = try fieldBinary(args, 3)
        return .waveformPreview(
            try remoteDBOffsets(800, 2).map { offset in
                RemoteDBWaveformPreviewSegment(
                    height: data.at(offset),
                    whiteness: data.at(offset + 1).map { Double($0) / 7 } ?? .nan)
            })
    case .waveformDetailed:
        return .waveformDetailed(
            try fieldBinary(args, 3).map { byte in
                WaveformSegment(height: Int(byte & 0x1f), whiteness: Double(byte >> 5) / 7)
            })
    case .waveformHD:
        let data = try fieldBinary(args, 3).subarray(0x34)
        return .waveformHD(
            try remoteDBOffsets(data.count, 2).map { offset in
                let value = try data.readUInt16BE(offset)
                return WaveformHDSegment(
                    height: (value & 0x7c) >> 2,
                    color: [Double(value >> 13 & 7) / 7, Double(value >> 10 & 7) / 7, Double(value >> 7 & 7) / 7])
            })
    case .cueAndLoop:
        let data = try fieldBinary(args, 3)
        return .cueAndLoops(
            try remoteDBOffsets(data.count, 0x24).compactMap { offset in
                let entry = data.subarray(offset, offset + 0x24)
                let frames = try entry.readUInt32LE(0x0c)
                let end = try entry.readUInt32LE(0x10)
                return remoteDBMakeCueLoopEntry(
                    isCue: try entry.readUInt8(1) != 0, isLoop: try entry.readUInt8(0) != 0,
                    offset: Double(frames) / 150 * 1000, length: Double(end - frames) / 150 * 1000,
                    button: try entry.readUInt8(2))
            })
    case .advCueAndLoops:
        let data = try fieldBinary(args, 3)
        var entries: [[UInt8]] = []
        var offset = 0
        while offset < data.count {
            let length = try data.readUInt32LE(offset)
            entries.append(data.subarray(offset, offset + length))
            offset += length
        }
        let converted: [RemoteDBAdvancedCueEntry] = try entries.compactMap { entry in
            let kind = try entry.readUInt8(6)
            if kind == 0 { return nil }
            let frames = try entry.readUInt32LE(0x0c)
            let end = try entry.readUInt32LE(0x10)
            var label: String?
            var color: CueColor?
            if entry.count != 0x38 {
                let labelByteLength = try entry.readUInt16LE(0x48)
                label = entry.subarray(0x4a, 0x4a + labelByteLength).subarray(0, -2).toString(.utf16le)
                color = entry.at(0x4a + labelByteLength + 4).map { CueColor(rawValue: $0) }
            }
            if let cue = remoteDBMakeCueLoopEntry(
                isCue: kind == 1, isLoop: kind == 2, offset: Double(frames) / 150 * 1000,
                length: Double(end - frames) / 150 * 1000, button: try entry.readUInt8(4), label: label, color: color)
            {
                return .cue(cue)
            }
            // 원본은 긴 항목에서 null을 펼쳐도 color·label 객체가 되어 filter를 통과한다.
            if let label { return .untyped(color: color, label: label) }
            return nil
        }
        let cues = converted.compactMap { entry -> CueAndLoop? in
            if case let .cue(cue) = entry { return cue }
            return nil
        }
        return cues.count == converted.count ? .cueAndLoops(cues) : .advancedCueAndLoops(converted)
    default: throw DJLinkError("Representation of non-responses is not currently supported")
    }
}
private func remoteDBOffsets(_ byteLength: Int, _ segmentSize: Int) throws -> [Int] {
    guard byteLength % segmentSize == 0 else { throw DJLinkError("Invalid array length") }
    return stride(from: 0, to: byteLength, by: segmentSize).map { $0 }
}
/// 4단계 makeCueLoopEntry와 같은 동작. 다른 트랙의 파일을 수정하지 않기 위한 지역 seam.
private func remoteDBMakeCueLoopEntry(
    isCue: Bool, isLoop: Bool, offset: Double, length: Double, button: Int,
    label: String? = nil, color: CueColor? = nil
) -> CueAndLoop? {
    if button != 0 {
        if isLoop {
            return .hotLoop(
                Hotloop(
                    offset: offset, label: label, color: color, button: HotcueButton(rawValue: button), length: length))
        }
        return .hotCue(Hotcue(offset: offset, label: label, color: color, button: HotcueButton(rawValue: button)))
    }
    if isLoop { return .loop(Loop(offset: offset, label: label, color: color, length: length)) }
    if isCue { return .cuePoint(CuePoint(offset: offset, label: label, color: color)) }
    return nil
}
