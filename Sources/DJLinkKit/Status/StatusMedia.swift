// 원본 src/status/media.ts

/// Get information about the media connected to the specified slot on the
/// device.
///
/// 원본은 `{hostDevice, device, slot}` 객체 하나를 받는다. Swift에서는 같은 이름의 인자 이름표로 받는다.
/// - Parameters:
///   - hostDevice: The device asking for media info
///   - device: The target device. This is the device we'll be querying for details of
///     it's media slot.
///   - slot: The specific slot
public func makeMediaSlotRequest(hostDevice: Device, device: Device, slot: MediaSlot) throws(BufferRangeError) -> [UInt8] {
    // 원본 `Uint8Array.from([...])`: 각 값을 8비트로 자른다.
    var parts: [Int] = PROLINK_HEADER.map(Int.init)
    parts += [0x05]
    parts += try buildName(hostDevice).map(Int.init)
    parts += [0x01, 0x00]
    parts += [hostDevice.id]
    parts += [0x00, 0x0c]
    parts += hostDevice.ip.toArray()
    parts += [0x00, 0x00, 0x00, device.id]
    parts += [0x00, 0x00, 0x00, slot.rawValue]

    return parts.map { UInt8(truncatingIfNeeded: $0) }
}
