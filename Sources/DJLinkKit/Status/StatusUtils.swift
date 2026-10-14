import Foundation

// 원본 src/status/utils.ts

private let MAX_INT32 = Int(pow(2.0, 32.0)) - 1
private let MAX_INT16 = Int(pow(2.0, 16.0)) - 1
private let MAX_INT9 = Int(pow(2.0, 9.0)) - 1

/// 원본은 머리말이 아니면 `Error`를 던지고, 0xc8~0xcb 길이 패킷은 `readUInt32BE(0xc8)`에서 RangeError를 던진다.
public func statusFromPacket(_ packet: [UInt8]) throws -> CDJStatus.State? {
    if packet.indexOf(PROLINK_HEADER) != 0 {
        throw DJLinkError("CDJ status packet does not start with the expected header")
    }

    // Rekordbox sends some short status packets that we can just ignore.
    if packet.count < 0xc8 {
        return nil
    }

    // No track loaded: BPM = MAX_INT16
    let rawBPM = try packet.readUInt16BE(0x92)
    let trackBPM: Double? = rawBPM == MAX_INT16 ? nil : Double(rawBPM) / 100

    // No next cue: beatsUntilCue = MAX_INT9
    let rawBeatsUntilCue = try packet.readUInt16BE(0xa4)
    let beatsUntilCue: Int? = rawBeatsUntilCue == MAX_INT9 ? nil : rawBeatsUntilCue

    // No track loaded: beat = MAX_INT32
    let rawBeat = try packet.readUInt32BE(0xa0)
    let beat: Int? = rawBeat == MAX_INT32 ? nil : rawBeat

    // 여기부터는 길이가 0xc8 이상이라 0xc8 앞의 바이트는 모두 있다.
    let flags = Int(packet[0x89])

    let status = CDJStatus.State(
        deviceId: Int(packet[0x21]),
        trackId: try packet.readUInt32BE(0x2c),
        trackDeviceId: Int(packet[0x28]),
        trackSlot: MediaSlot(rawValue: Int(packet[0x29])),
        trackType: TrackType(rawValue: Int(packet[0x2a])),
        playState: CDJStatus.PlayState(rawValue: Int(packet[0x7b])),
        isOnAir: (flags & CDJStatus.StatusFlag.onAir.rawValue) != 0,
        isSync: (flags & CDJStatus.StatusFlag.sync.rawValue) != 0,
        isBpmSync: (flags & CDJStatus.StatusFlag.bpmSync.rawValue) != 0,
        isMaster: (flags & CDJStatus.StatusFlag.master.rawValue) != 0,
        isEmergencyMode: packet[0xba] != 0,
        trackBPM: trackBPM,
        // The CDJ status packet carries four pitch values (firmware CDJ-3000 FW3.20,
        // sub_d7d610): Pitch1@0x8c and Pitch3@0xc0 are the *effective* pitch (in
        // effect / on the BPM display, from the fader or a synced master), while
        // Pitch2@0x98 and Pitch4@0xc4 track the *local fader* position. We expose
        // Pitch1 as `effectivePitch` and Pitch2 as `sliderPitch`.
        effectivePitch: try calcPitch(packet.subarray(0x8d, 0x8d + 3)),
        sliderPitch: try calcPitch(packet.subarray(0x99, 0x99 + 3)),
        beatInMeasure: Int(packet[0xa6]),
        beatsUntilCue: beatsUntilCue,
        beat: beat,
        // Player-type / capability byte (dysentery's "nx"). Guarded because the
        // length check above only guarantees 0xc8; older/short packets may not
        // reach 0xcc, in which case the field reads as 0 (version-gated to 0 anyway).
        deviceType: packet.count > 0xcc ? Int(packet[0xcc]) : 0,
        packetNum: try packet.readUInt32BE(0xc8)
    )

    return status
}

/// 원본은 머리말이 아니면 `Error`를 던지고, 0xc0보다 짧은 0x06 패킷은 읽다가 RangeError를 던진다.
public func mediaSlotFromPacket(_ packet: [UInt8]) throws -> MediaSlotInfo? {
    if packet.indexOf(PROLINK_HEADER) != 0 {
        throw DJLinkError("CDJ media slot packet does not start with the expected header")
    }

    if packet.at(0x0a) != 0x06 {
        return nil
    }

    let name =
        packet
        .subarray(0x2c, 0x2c + 40)
        .toString()
        .replacingOccurrences(of: "\0", with: "")

    let createdDate = jsDateParse(
        packet
            .subarray(0x6c, 0x6c + 24)
            .toString()
            .replacingOccurrences(of: "\0", with: "")
    )

    // 아래 읽기 순서는 원본과 같다. 짧은 패킷은 readUInt16BE(0xa6)부터 던지고,
    // 끝의 readBigUInt64BE(0xb8)가 0xc0 이상을 요구하므로 반환될 때는 모든 바이트가 있다.
    let deviceId = packet.at(0x27) ?? 0
    let slot = packet.at(0x2b) ?? 0

    let trackCount = try packet.readUInt16BE(0xa6)
    let tracksType = packet.at(0xaa) ?? 0
    let hasSettings = (packet.at(0xab) ?? 0) != 0
    let playlistCount = try packet.readUInt16BE(0xae)
    let color = try packet.readUInt8(0xa8)
    let totalBytes = try packet.readBigUInt64BE(0xb0)
    let freeBytes = try packet.readBigUInt64BE(0xb8)

    let info = MediaSlotInfo(
        deviceId: deviceId,
        slot: MediaSlot(rawValue: slot),
        name: name,
        color: MediaColor(rawValue: color),
        createdDate: createdDate,
        freeBytes: freeBytes,
        totalBytes: totalBytes,
        tracksType: TrackType(rawValue: tracksType),
        trackCount: trackCount,
        playlistCount: playlistCount,
        hasSettings: hasSettings
    )

    return info
}

/// calcPitch converts a uint24 byte value into a float32 pitch.
///
/// The pitch information ranges from 0x000000 (meaning -100%, complete stop) to
/// 0x200000 (+100%).
private func calcPitch(_ pitch: [UInt8]) throws -> Double {
    let value = try ([0x0] + pitch).readUInt32BE()
    let relativeZero = 0x100000

    let computed = (Double(value - relativeZero) / Double(relativeZero)) * 100

    return jsToFixedNumber(computed, 2)
}

/// Parse absolute position packet from CDJ-3000+ devices.
/// These packets are sent every 30ms on port 50001 while a track is loaded.
/// Packet structure: subtype 0x00, lenr varies based on device.
///
/// 원본처럼 0x21~0x23 길이 패킷은 `readUInt16BE(0x22)`에서 RangeError를 던진다.
public func positionFromPacket(_ packet: [UInt8]) throws -> CDJStatus.PositionState? {
    if packet.indexOf(PROLINK_HEADER) != 0 {
        return nil
    }

    // PLAN §9: 같은 포트의 비트 패킷(0x28)을 위치로 읽지 않는다.
    if packet.at(0x0a) != 0x0b {
        return nil
    }

    // Check if this is a position packet (subtype 0x00)
    if packet.at(0x20) != 0x00 {
        return nil
    }

    // Check minimum length for position packet
    let lenr = try packet.readUInt16BE(0x22)
    if lenr < 0x0c || packet.count < 0x34 {
        return nil
    }

    let deviceId = Int(packet[0x21])
    let trackLength = try packet.readUInt32BE(0x24)
    let playhead = try packet.readUInt32BE(0x28)

    // Parse pitch: 32-bit signed integer representing pitch × 64 × 100
    // To get percentage: divide by 6400
    let rawPitch = try packet.readInt32BE(0x2c)
    let pitch = Double(rawPitch) / 6400

    // Parse BPM: multiply by 10, or null if 0xffffffff
    let rawBPM = try packet.readUInt32BE(0x30)
    let bpm: Double? = rawBPM == 0xffff_ffff ? nil : Double(rawBPM) / 10

    let position = CDJStatus.PositionState(
        deviceId: deviceId,
        trackLength: trackLength,
        playhead: playhead,
        pitch: pitch,
        bpm: bpm
    )

    return position
}

/// 믹서가 비트 포트(50001)로 보내는 on-air 패킷의 종류 바이트(0x0a 자리).
public let ON_AIR_PACKET_TYPE: UInt8 = 0x03

/// Parse on-air status packet from DJM mixer.
/// The mixer broadcasts which channels are currently audible.
/// Supports both 4-channel (subtype 0x00) and 6-channel (subtype 0x03) variants.
///
/// Packet structure:
/// - 4-channel: subtype 0x00, length 0x0009 (9 data bytes: F1 F2 F3 F4 00 00 00 00 00)
/// - 6-channel: subtype 0x03, length 0x0011 (17 data bytes: F1 F2 F3 F4 00 00 00 00 00 F5 F6 00 30 00 00 00 00 00)
///
/// 원본처럼 머리말 뒤가 0x24보다 짧으면 `readUInt16BE(0x22)`에서 RangeError를 던진다.
public func onAirFromPacket(_ packet: [UInt8]) throws -> CDJStatus.OnAirStatus? {
    if packet.indexOf(PROLINK_HEADER) != 0 {
        return nil
    }

    let subtype = packet.at(0x20)
    let lenr = try packet.readUInt16BE(0x22)

    // Check for 4-channel variant (subtype 0x00, length 0x0009)
    // PLAN §9: DJM-900NXS2(2026-10-14 실기)의 4채널 패킷은 subtype이 0x02이고 0x2d(45)바이트다.
    // 원본은 subtype 0x00과 0x2e바이트 이상만 받아 실제 패킷을 버렸다. 데이터 9바이트는 0x2c에서 끝난다.
    if (subtype == 0x00 || subtype == 0x02) && lenr == 0x0009 && packet.count >= 0x2d {
        let deviceId = Int(packet[0x21])
        let channels = [
            1: packet[0x24] != 0x00,
            2: packet[0x25] != 0x00,
            3: packet[0x26] != 0x00,
            4: packet[0x27] != 0x00,
        ]

        let onAir = CDJStatus.OnAirStatus(
            deviceId: deviceId,
            channels: channels,
            isSixChannel: false
        )

        return onAir
    }

    // Check for 6-channel variant (subtype 0x03, length 0x0011)
    if subtype == 0x03 && lenr == 0x0011 && packet.count >= 0x36 {
        let deviceId = Int(packet[0x21])
        let channels = [
            1: packet[0x24] != 0x00,
            2: packet[0x25] != 0x00,
            3: packet[0x26] != 0x00,
            4: packet[0x27] != 0x00,
            5: packet[0x2e] != 0x00,
            6: packet[0x2f] != 0x00,
        ]

        let onAir = CDJStatus.OnAirStatus(
            deviceId: deviceId,
            channels: channels,
            isSixChannel: true
        )

        return onAir
    }

    return nil
}

/// Parse unicast mixer state packet from DJM-A9 (packet type 0x39 on port 50002).
public func mixerStateFromPacket(_ packet: [UInt8]) -> CDJStatus.MixerState? {
    if packet.indexOf(PROLINK_HEADER) != 0 {
        return nil
    }

    // Verify packet type 0x39
    if packet.at(10) != 0x39 {
        return nil
    }

    if packet.count < 266 {
        return nil
    }

    let deviceName =
        packet
        .subarray(11, 30)
        .toString()
        .replacingOccurrences(of: "\0", with: "")
        .jsTrimmed()

    let crossfader = Int(packet[180])

    var channels: [Int: CDJStatus.ChannelState] = [:]
    for ch in 1...4 {
        let offset = 36 + (ch - 1) * 24

        var crossfaderAssign: CDJStatus.CrossfaderAssign = .thru
        let assignVal = packet[offset + 12]
        if assignVal == 0x01 {
            crossfaderAssign = .a
        } else if assignVal == 0x02 {
            crossfaderAssign = .b
        }

        channels[ch] = CDJStatus.ChannelState(
            trim: Int(packet[offset + 1]),
            eqHi: Int(packet[offset + 3]),
            eqMid: Int(packet[offset + 4]),
            eqLow: Int(packet[offset + 6]),
            colorFx: Int(packet[offset + 7]),
            fader: Int(packet[offset + 11]),
            crossfaderAssign: crossfaderAssign
        )
    }

    return CDJStatus.MixerState(
        deviceId: 33,  // Mixers are typically device 33 on ProDJLink
        deviceName: deviceName,
        channels: channels,
        crossfader: crossfader
    )
}

/// Parse unicast VU meter packet from DJM-A9 (packet type 0x58 on port 50001).
/// Contains 15 sample-tuples (16-bit BE left/right levels) per channel.
public func vuFromPacket(_ packet: [UInt8]) -> CDJStatus.VUState? {
    if packet.indexOf(PROLINK_HEADER) != 0 {
        return nil
    }

    // Verify packet type 0x58
    if packet.at(10) != 0x58 {
        return nil
    }

    if packet.count < 584 {
        return nil
    }

    var channels: [Int: [CDJStatus.VUFrame]] = [:]

    for ch in 1...4 {
        let chOffset = 44 + (ch - 1) * 60  // 15 frames * 4 bytes per frame = 60 bytes
        var frames: [CDJStatus.VUFrame] = []
        for i in 0..<15 {
            let frameOffset = chOffset + i * 4
            // 길이를 584 이상으로 확인했으므로 읽기는 실패하지 않는다.
            frames.append(
                CDJStatus.VUFrame(
                    left: (try? packet.readUInt16BE(frameOffset)) ?? 0,
                    right: (try? packet.readUInt16BE(frameOffset + 2)) ?? 0
                ))
        }
        channels[ch] = frames
    }

    return CDJStatus.VUState(
        deviceId: 33,  // Mixers are typically device 33 on ProDJLink
        channels: channels
    )
}

// MARK: - JS 동작을 흉내 내는 작은 도우미

/// JS `+x.toFixed(digits)`. 2진 값의 정확한 십진 전개로 반올림한다.
/// 원본 calcPitch 값(k·100/2^20)은 반올림 경계에 정확히 걸리지 않으므로 printf 반올림과 JS 반올림이 같다.
private func jsToFixedNumber(_ value: Double, _ digits: Int) -> Double {
    Double(String(format: "%.\(digits)f", value)) ?? .nan
}

extension String {
    /// JS `String.prototype.trim()`. 공백과 줄바꿈(유니코드 공백 포함)을 앞뒤에서 지운다.
    fileprivate func jsTrimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
    }
}

/// JS `new Date(string)`.
///
/// ECMAScript 날짜·시간 문자열 형식(`YYYY`, `YYYY-MM`, `YYYY-MM-DD`, 뒤에 `THH:mm[:ss[.sss]]`와 `Z`·`±HH:mm`)만 읽는다.
/// 원본(V8)처럼 날짜만 있으면 UTC, 시간이 있는데 오프셋이 없으면 지역 시간이다.
/// V8의 그 밖의 옛 형식은 옮기지 않았다. 읽지 못하면 `Invalid Date`처럼 시각이 NaN인 `Date`를 돌려준다.
private func jsDateParse(_ string: String) -> Date {
    let invalid = Date(timeIntervalSince1970: .nan)
    let chars = Array(string.unicodeScalars)
    var index = 0

    func digits(_ count: Int) -> Int? {
        guard index + count <= chars.count else { return nil }
        var value = 0
        for i in index..<(index + count) {
            guard chars[i].isASCII, let digit = Int(String(chars[i])) else { return nil }
            value = value * 10 + digit
        }
        index += count
        return value
    }

    func take(_ scalar: Unicode.Scalar) -> Bool {
        guard index < chars.count, chars[index] == scalar else { return false }
        index += 1
        return true
    }

    // 연도: YYYY 또는 ±YYYYYY
    var year: Int
    if index < chars.count, chars[index] == "+" || chars[index] == "-" {
        let negative = chars[index] == "-"
        index += 1
        guard let value = digits(6) else { return invalid }
        if negative && value == 0 { return invalid }
        year = negative ? -value : value
    } else {
        guard let value = digits(4) else { return invalid }
        year = value
    }

    var month = 1
    var day = 1
    if take("-") {
        guard let value = digits(2), (1...12).contains(value) else { return invalid }
        month = value
        if take("-") {
            guard let value = digits(2), (1...31).contains(value) else { return invalid }
            day = value
        }
    }

    var hour = 0
    var minute = 0
    var second = 0
    var millisecond = 0
    var hasTime = false
    var offsetMinutes: Int?
    if take("T") {
        hasTime = true
        guard let h = digits(2), take(":"), let m = digits(2) else { return invalid }
        hour = h
        minute = m
        if take(":") {
            guard let s = digits(2) else { return invalid }
            second = s
            if take(".") {
                // 소수 초는 숫자가 하나 이상. 앞 세 자리만 쓴다.
                let start = index
                while index < chars.count, chars[index].isASCII, ("0"..."9").contains(chars[index]) { index += 1 }
                guard index > start else { return invalid }
                let fraction = String(String.UnicodeScalarView(chars[start..<index]))
                let padded = (fraction + "00").prefix(3)
                millisecond = Int(padded) ?? 0
            }
        }
        if hour > 24 || minute > 59 || second > 59 { return invalid }
        if hour == 24 && (minute != 0 || second != 0 || millisecond != 0) { return invalid }
        if take("Z") {
            offsetMinutes = 0
        } else if index < chars.count, chars[index] == "+" || chars[index] == "-" {
            let sign = chars[index] == "-" ? -1 : 1
            index += 1
            guard let oh = digits(2), take(":"), let om = digits(2), oh <= 23, om <= 59 else { return invalid }
            offsetMinutes = sign * (oh * 60 + om)
        }
    }
    guard index == chars.count else { return invalid }

    // 그레고리력 날짜에서 1970-01-01부터의 날 수(proleptic).
    func daysFromCivil(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y - 1 : y
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    let days = daysFromCivil(year, month, day)
    var ms = Double(days) * 86_400_000
    ms += Double(hour * 3_600_000 + minute * 60_000 + second * 1000 + millisecond)

    if let offsetMinutes {
        ms -= Double(offsetMinutes) * 60_000
    } else if hasTime {
        // 오프셋 없는 날짜·시간은 지역 시간이다.
        let guess = Date(timeIntervalSince1970: ms / 1000)
        ms -= Double(TimeZone.current.secondsFromGMT(for: guess)) * 1000
    }

    // JS Date의 범위(±8.64e15 ms)를 넘으면 Invalid Date.
    guard abs(ms) <= 8.64e15 else { return invalid }
    return Date(timeIntervalSince1970: ms / 1000)
}
