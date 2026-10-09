import Foundation

extension MetadataConnect {
    /// ID3v2 텍스트 인코딩 바이트가 가리키는 인코딩(원본 `'latin1' | 'utf8' | 'utf16le' | 'utf16be'`).
    enum TextEncoding {
        case latin1
        case utf8
        case utf16le
        case utf16be

        var isUtf16: Bool { self == .utf16le || self == .utf16be }

        // Node에는 utf16be가 없어 원본은 바이트를 맞바꿔 utf16le로 읽는다. 기반의 `.utf16be`가 같은 결과를 낸다.
        var nodeEncoding: NodeEncoding {
            switch self {
            case .latin1: .latin1
            case .utf8: .utf8
            case .utf16le: .utf16le
            case .utf16be: .utf16be
            }
        }
    }

    /// Detect image type from magic bytes
    public static func detectImageType(_ data: [UInt8]) -> ArtworkMimeType? {
        if data.count < 4 { return nil }
        if data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff { return .jpeg }
        if data[0] == 0x89 && data.toString(.ascii, 1, 4) == "PNG" { return .png }
        if data.toString(.ascii, 0, 3) == "GIF" { return .gif }
        return nil
    }

    /// Normalize a MIME type string to a supported artwork type
    public static func normalizeMimeType(_ mimeType: String) -> ArtworkMimeType {
        let lower = mimeType.lowercased()
        if lower.contains("png") { return .png }
        if lower.contains("gif") { return .gif }
        return .jpeg
    }

    /// 범위를 넘는 위치는 JS의 `undefined`처럼 0으로 본다(`undefined & 0x7f === 0`).
    static func byteOrZero(_ buffer: [UInt8], _ index: Int) -> Int {
        index >= 0 && index < buffer.count ? Int(buffer[index]) : 0
    }

    /// Read a syncsafe integer (ID3v2 format)
    /// Each byte only uses 7 bits
    static func readSyncsafe(_ buffer: [UInt8], _ offset: Int = 0) -> Int {
        ((byteOrZero(buffer, offset) & 0x7f) << 21)
            | ((byteOrZero(buffer, offset + 1) & 0x7f) << 14)
            | ((byteOrZero(buffer, offset + 2) & 0x7f) << 7)
            | (byteOrZero(buffer, offset + 3) & 0x7f)
    }

    /// Get text encoding from ID3v2 encoding byte
    static func getTextEncoding(_ encodingByte: Int) -> TextEncoding {
        switch encodingByte {
        case 0: .latin1
        case 1: .utf16le
        case 2: .utf16be
        case 3: .utf8
        default: .latin1
        }
    }

    /// Read a null-terminated string from a buffer
    static func readNullTerminatedString(
        _ buffer: [UInt8],
        _ offset: Int,
        _ encoding: TextEncoding
    ) -> (value: String, bytesConsumed: Int) {
        let isUtf16 = encoding.isUtf16
        var end = offset

        if isUtf16 {
            while end < buffer.count - 1 {
                if buffer[end] == 0 && buffer[end + 1] == 0 { break }
                end += 2
            }
        } else {
            while end < buffer.count && buffer[end] != 0 { end += 1 }
        }

        let value = buffer.toString(encoding.nodeEncoding, offset, end)
        return (value, end - offset + (isUtf16 ? 2 : 1))
    }

    /// Parse a BPM string to a number
    /// Handles formats like "128", "128.5", "128 BPM"
    static func parseBpm(_ value: String) -> Double? {
        // /[\d.]+/ — 처음 나오는 숫자·점 덩어리
        guard let match = firstRun(of: value, where: { isAsciiDigit($0) || $0 == "." }) else { return nil }
        let num = jsParseFloat(match)
        if num.isNaN || num <= 0 || num > 500 { return nil }
        return (num * 10).rounded(.toNearestOrAwayFromZero) / 10 // Round to 1 decimal place
    }

    /// Parse a year string to a number
    /// Handles formats like "2024", "2024-01-15", "2024/01/15"
    static func parseYear(_ value: String) -> Int? {
        guard let year = firstFourDigits(value) else { return nil }
        if year < 1900 || year > 2100 { return nil }
        return year
    }

    /// Clean up text by removing null characters and trimming
    static func cleanText(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        // Remove null characters and trim
        let cleaned = jsTrim(String(String.UnicodeScalarView(value.unicodeScalars.filter { $0 != "\0" })))
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: JS 문자열 도우미

    static func isAsciiDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x30 && scalar.value <= 0x39
    }

    /// 정규식 `/\d{4}/`의 첫 일치를 `parseInt(…, 10)`한 값.
    static func firstFourDigits(_ value: String) -> Int? {
        let scalars = Array(value.unicodeScalars)
        var i = 0
        while i + 4 <= scalars.count {
            if scalars[i..<(i + 4)].allSatisfy(isAsciiDigit) {
                return Int(String(String.UnicodeScalarView(scalars[i..<(i + 4)])))
            }
            i += 1
        }
        return nil
    }

    /// 조건을 만족하는 문자가 이어진 첫 덩어리(`/[…]+/`의 `match[0]`).
    private static func firstRun(of value: String, where predicate: (Unicode.Scalar) -> Bool) -> String? {
        var run = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            if predicate(scalar) {
                run.append(scalar)
            } else if !run.isEmpty {
                break
            }
        }
        return run.isEmpty ? nil : String(run)
    }

    /// `parseFloat`: 숫자와 점으로만 된 문자열의 앞쪽 십진수를 읽는다(읽을 게 없으면 NaN).
    private static func jsParseFloat(_ value: String) -> Double {
        var integer = ""
        var fraction = ""
        var seenDot = false
        for scalar in value.unicodeScalars {
            if isAsciiDigit(scalar) {
                if seenDot { fraction.unicodeScalars.append(scalar) } else { integer.unicodeScalars.append(scalar) }
            } else if scalar == "." && !seenDot {
                seenDot = true
            } else {
                break
            }
        }
        if integer.isEmpty && fraction.isEmpty { return .nan }
        return Double("\(integer.isEmpty ? "0" : integer).\(fraction.isEmpty ? "0" : fraction)") ?? .nan
    }

    /// JS `String.prototype.trim`이 지우는 문자(공백·줄 끝 문자).
    private static func isJsWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0d, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff:
            true
        default:
            false
        }
    }

    static func jsTrim(_ value: String) -> String {
        var scalars = Substring(value).unicodeScalars[...]
        while let first = scalars.first, isJsWhitespace(first) { scalars = scalars.dropFirst() }
        while let last = scalars.last, isJsWhitespace(last) { scalars = scalars.dropLast() }
        return String(scalars)
    }
}
