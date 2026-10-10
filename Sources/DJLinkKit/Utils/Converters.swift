// 원본 src/utils/converters.ts

/// Extracts a specific bitmask, shifting it to the bitmask.
///
/// JS 비트 연산처럼 32비트 부호 있는 정수로 계산한다. `Math.log2(mask & -mask)`는 가장 낮은 1비트의 자리다.
public func extractBitMask(_ val: Int, _ mask: Int) -> Int {
    let mask32 = Int32(truncatingIfNeeded: mask)
    let masked = Int32(truncatingIfNeeded: val) & mask32
    let lowest = mask32 & (0 &- mask32)
    // 원본에서 log2(0) = -Infinity, log2(음수) = NaN이고 둘 다 시프트 수 0이 된다.
    let shift = lowest <= 0 ? 0 : lowest.trailingZeroBitCount
    return Int(masked >> shift)
}

/// Pioneer colors are 3 bits, convert this to a percentage.
public func extractColor(_ val: Int, _ mask: Int) -> Double {
    Double(extractBitMask(val, mask)) / Double(0b111)
}

/// Utility to generate an filled with byte offsets for each segment
///
/// 원본 `new Array(byteLength / segmentSize)`는 나누어떨어지지 않으면 RangeError("Invalid array length")를 던진다.
public func makeOffsetArray(_ byteLength: Int, _ segmentSize: Int) throws -> [Int] {
    guard segmentSize != 0, byteLength % segmentSize == 0, byteLength / segmentSize >= 0 else {
        throw DJLinkError("Invalid array length")
    }
    return (0..<(byteLength / segmentSize)).map { $0 * segmentSize }
}

/// Convert raw waveform HD data into the structured WaveformHD type
public func convertWaveformHDData(_ data: [UInt8]) throws -> WaveformHD {
    // Two byte bit representation for the color waveform.
    //
    // | f  e  d | c  b  a | 9  8  7 | 6  5  4  3  2 | 1   0 |
    // [   red   |  green  |   blue  |     height    | ~ | ~ ]
    let redMask = 0b11100000_00000000
    let greenMask = 0b00011100_00000000
    let blueMask = 0b00000011_10000000
    let heightMask = 0b00000000_01111100

    let ec = extractColor

    return try makeOffsetArray(data.count, 0x02)
        .map { byteOffset in try data.readUInt16BE(byteOffset) }
        .map { v in
            WaveformHDSegment(
                height: extractBitMask(v, heightMask),
                color: [ec(v, redMask), ec(v, greenMask), ec(v, blueMask)]
            )
        }
}
