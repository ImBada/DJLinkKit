import DJLinkKit
import Foundation

// 사람이 읽는 한 줄 출력을 만드는 순수 함수.

func formatMAC(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
}

/// 장치 한 줄. 원본의 `New device: %s [id: %s]`에 종류·주소를 더한다.
func formatDevice(_ device: Device) -> String {
    "\(device.name) [id: \(device.id)] type=\(device.type) ip=\(device.ip.address) mac=\(formatMAC(device.macAddr))"
}

/// 밀리초를 `m:ss.mmm`으로.
func formatMilliseconds(_ ms: Int) -> String {
    let sign = ms < 0 ? "-" : ""
    let value = abs(ms)
    return String(format: "%@%d:%02d.%03d", sign, value / 60000, (value / 1000) % 60, value % 1000)
}

private func formatNumber(_ value: Double, _ digits: Int = 2) -> String {
    String(format: "%.\(digits)f", value)
}

/// `CDJStatus.State` 한 줄.
func formatStatus(_ s: CDJStatus.State) -> String {
    var flags: [String] = []
    if s.isOnAir { flags.append("on-air") }
    if s.isSync { flags.append("sync") }
    if s.isBpmSync { flags.append("bpm-sync") }
    if s.isMaster { flags.append("master") }
    if s.isEmergencyMode { flags.append("emergency") }
    let track =
        s.trackId == 0
        ? "no track" : "track=\(s.trackId) from=\(s.trackDeviceId)/\(s.trackSlot) type=\(s.trackType)"
    let bpm = s.trackBPM.map { formatNumber($0) } ?? "-"
    return
        "status device=\(s.deviceId) \(s.playState) \(track) bpm=\(bpm) pitch=\(formatNumber(s.effectivePitch))% beat=\(s.beatInMeasure)"
        + (flags.isEmpty ? "" : " [\(flags.joined(separator: ","))]")
}

/// 정밀 위치 한 줄.
func formatPosition(_ p: CDJStatus.PositionState) -> String {
    let bpm = p.bpm.map { formatNumber($0) } ?? "-"
    return
        "position device=\(p.deviceId) \(formatMilliseconds(p.playhead)) / \(p.trackLength)s pitch=\(formatNumber(p.pitch))% bpm=\(bpm)"
}

/// on-air 한 줄. 채널은 번호 순.
func formatOnAir(_ o: CDJStatus.OnAirStatus) -> String {
    let channels = o.channels.keys.sorted().map { "\($0)=\(o.channels[$0] == true ? "on" : "off")" }
    return "on-air device=\(o.deviceId) \(channels.joined(separator: " ")) (\(o.isSixChannel ? 6 : 4)ch)"
}

/// 미디어 슬롯 한 줄.
func formatMediaSlot(_ m: MediaSlotInfo) -> String {
    "media device=\(m.deviceId) slot=\(m.slot) name=\"\(m.name)\" tracks=\(m.trackCount) playlists=\(m.playlistCount)"
}

/// 믹서 상태 한 줄.
func formatMixerState(_ m: CDJStatus.MixerState) -> String {
    "mixer device=\(m.deviceId) \(m.deviceName) crossfader=\(m.crossfader) channels=\(m.channels.count)"
}

func formatByteCount(_ bytes: Int) -> String {
    bytes < 1024 ? "\(bytes) B" : bytes < 1024 * 1024 ? "\(bytes / 1024) KiB" : "\(bytes / (1024 * 1024)) MiB"
}

/// 메타데이터 요약(여러 줄).
func formatTrackSummary(_ track: Track) -> [String] {
    var lines = ["track \(track.id): \(track.title)"]
    if let artist = track.artist { lines.append("  artist:   \(artist.name)") }
    if let album = track.album { lines.append("  album:    \(album.name)") }
    if let genre = track.genre { lines.append("  genre:    \(genre.name)") }
    if let key = track.key { lines.append("  key:      \(key.name)") }
    lines.append("  tempo:    \(formatNumber(track.tempo))")
    lines.append("  duration: \(track.duration)s")
    if !track.fileName.isEmpty { lines.append("  file:     \(track.fileName)") }
    return lines
}

/// 그리드 요약: 박 수와 처음·끝 박.
func formatBeatGridSummary(_ grid: BeatGrid?) -> String {
    guard let grid, let first = grid.first, let last = grid.last else { return "beatgrid: none" }
    return
        "beatgrid: \(grid.count) beats, first=\(formatMilliseconds(Int(first.offset))) bpm=\(formatNumber(first.bpm)), last=\(formatMilliseconds(Int(last.offset)))"
}

/// 파형 요약.
func formatWaveformSummary(_ waveforms: Waveforms?) -> String {
    guard let waveforms else { return "waveform: none" }
    var parts: [String] = []
    if let hd = waveforms.waveformHd { parts.append("hd=\(hd.count) segments") }
    if let preview = waveforms.waveformPreview { parts.append("preview=\(preview.count)") }
    if let detailed = waveforms.waveformDetailed { parts.append("detailed=\(detailed.count)") }
    if let color = waveforms.waveformColorPreview { parts.append("colorPreview=\(color.count) bytes") }
    return "waveform: " + (parts.isEmpty ? "empty" : parts.joined(separator: ", "))
}

/// 큐·루프 요약. DB의 큐(`cueAndLoops`)와 ANLZ 확장 큐(`extendedCues`)를 종류별로 센다.
func formatCueSummary(_ cues: [CueAndLoop]?, extended: [ExtendedCue]?) -> String {
    var parts: [String] = []
    if let cues {
        var counts: [String: Int] = [:]
        for cue in cues { counts[cue.type, default: 0] += 1 }
        parts.append(
            "db: " + (counts.isEmpty ? "0" : counts.keys.sorted().map { "\($0)=\(counts[$0]!)" }.joined(separator: " "))
        )
    }
    if let extended {
        let loops = extended.filter { $0.type == 2 }.count
        parts.append("anlz: \(extended.count) (hot=\(extended.filter { $0.hotCue > 0 }.count) loops=\(loops))")
    }
    return "cues: " + (parts.isEmpty ? "none" : parts.joined(separator: "; "))
}

// MARK: - 출력 줄이기

/// 장치마다 마지막으로 낸 상태의 핵심 값. 박 번호·패킷 번호처럼 늘 바뀌는 값은 뺀다.
struct StatusKey: Equatable, Hashable {
    var trackId: Int
    var trackDeviceId: Int
    var trackSlot: MediaSlot
    var playState: CDJStatus.PlayState
    var isOnAir: Bool
    var isSync: Bool
    var isMaster: Bool
    var trackBPM: Int?
    var pitch: Int

    init(_ s: CDJStatus.State) {
        trackId = s.trackId
        trackDeviceId = s.trackDeviceId
        trackSlot = s.trackSlot
        playState = s.playState
        isOnAir = s.isOnAir
        isSync = s.isSync
        isMaster = s.isMaster
        trackBPM = s.trackBPM.map { Int(($0 * 100).rounded()) }
        pitch = Int((s.effectivePitch * 100).rounded())
    }
}

/// 상태 패킷은 CDJ마다 초당 여러 번 온다. 핵심 값이 바뀔 때만 한 줄을 낸다(`all`이면 모두).
struct StatusLineFilter {
    private var last: [Int: StatusKey] = [:]
    let all: Bool

    init(all: Bool) { self.all = all }

    mutating func line(for state: CDJStatus.State) -> String? {
        let key = StatusKey(state)
        if !all && last[state.deviceId] == key { return nil }
        last[state.deviceId] = key
        return formatStatus(state)
    }
}

/// 같은 키는 `intervalMs`가 지나야 다시 낸다. 정밀 위치는 30ms마다 와서 줄인다.
struct LineThrottle {
    private var lastMs: [Int: Double] = [:]
    let intervalMs: Int

    init(intervalMs: Int) { self.intervalMs = intervalMs }

    mutating func shouldEmit(key: Int, nowMs: Double) -> Bool {
        if let previous = lastMs[key], nowMs - previous < Double(intervalMs) { return false }
        lastMs[key] = nowMs
        return true
    }
}
