import Foundation

// 원본 src/devices/utils.ts

/// Converts a announce packet to a device object.
///
/// Returns null for any packet that is not a stage-3 Pro DJ Link announce. The
/// announce socket receives every UDP broadcast on its port, so foreign traffic
/// (other apps, other protocols) is normal and must be ignored, not treated as
/// an error.
///
/// 원본처럼 짧은 패킷은 `readUInt32BE(0x2c)`에서 `BufferRangeError`를 던진다.
public func deviceFromPacket(_ packet: [UInt8]) throws -> Device? {
    if packet.indexOf(PROLINK_HEADER) != 0 {
        return nil
    }

    if packet.at(0x0a) != 0x06 {
        return nil
    }

    let name = packet
        .subarray(0x0c, 0x0c + 20)
        .toString()
        .replacingOccurrences(of: "\0", with: "")

    // 원본 객체 리터럴은 id, type, macAddr, ip 순으로 읽고 ip(readUInt32BE)에서 던진다.
    // 던지면 앞의 값은 쓰이지 않으므로 던지는 읽기를 먼저 한다.
    let ip = Address4.fromInteger(try packet.readUInt32BE(0x2c))

    let device = Device(
        name: name,
        id: packet.at(0x24) ?? 0,
        // 원본은 0x30~0x34 길이 패킷에서 type이 undefined가 된다. DeviceType은 옵셔널이 아니라 0으로 둔다
        // (어느 DeviceType과도 같지 않은 것은 원본과 같다).
        type: DeviceType(rawValue: packet.at(0x34) ?? 0),
        macAddr: packet.subarray(0x26, 0x26 + 6),
        ip: ip
    )

    return device
}
