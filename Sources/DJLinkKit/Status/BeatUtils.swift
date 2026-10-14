/// 비트 포트(50001)의 독립 비트 패킷 종류.
public let BEAT_PACKET_TYPE: UInt8 = 0x28

/// CDJ-2000nexus에서 확인한 96바이트 0x28 패킷을 읽는다(PROVENANCE §D).
/// 다른 종류·형식과 잘린 패킷은 버린다. 미확인 시간 필드는 해석하지 않는다.
public func beatFromPacket(_ packet: [UInt8]) -> CDJStatus.BeatState? {
    guard packet.count == 0x60,
        packet.prefix(PROLINK_HEADER.count).elementsEqual(PROLINK_HEADER),
        packet[0x0a] == BEAT_PACKET_TYPE,
        packet[0x20] == 0x00,
        (1...4).contains(packet[0x5c]),
        let length = try? packet.readUInt16BE(0x22), length == 0x003c,
        let rawPitch = try? packet.readUInt32BE(0x54),
        let rawBPM = try? packet.readUInt16BE(0x5a)
    else { return nil }

    return CDJStatus.BeatState(
        deviceId: Int(packet[0x21]), trackBPM: Double(rawBPM) / 100,
        pitch: (Double(rawPitch) / Double(0x100000) - 1) * 100,
        beatInMeasure: Int(packet[0x5c]))
}
