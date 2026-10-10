import Foundation

// JS 문자열·숫자 규칙 중 로그·판정에 쓰는 것.

extension Double {
    /// JS `String(number)`·`JSON.stringify(number)`가 쓰는 숫자 표기. NaN·무한대는 JSON처럼 "null".
    package var jsNumberString: String {
        guard isFinite else { return "null" }
        if self == 0 { return "0" }
        if self == rounded(), Swift.abs(self) < 1e21 {
            return String(format: "%.0f", self)
        }
        let text = "\(self)"
        guard let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) else { return text }
        // Swift는 1e-4 아래에서 지수 표기를 쓰고 JS는 1e-6 아래에서만 쓴다.
        let mantissa = String(text[..<e])
        guard let exponent = Int(text[text.index(after: e)...]) else { return text }
        let negative = mantissa.hasPrefix("-")
        let digits = mantissa.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ".", with: "")
        if exponent >= -6, exponent < 0 {
            let zeros = String(repeating: "0", count: -exponent - 1)
            return (negative ? "-" : "") + "0." + zeros + digits
        }
        let body = digits.count > 1 ? "\(digits.first!).\(digits.dropFirst())" : digits
        return (negative ? "-" : "") + body + "e" + (exponent < 0 ? "-" : "+") + String(Swift.abs(exponent))
    }
}

extension String {
    /// JS `String.prototype.trim()`: WhiteSpace(U+0009, U+000B, U+000C, U+0020, U+00A0, U+FEFF, Zs)와
    /// LineTerminator(U+000A, U+000D, U+2028, U+2029)를 앞뒤에서 지운다(U+0085는 지우지 않는다).
    package func jsTrim() -> String {
        let scalars = unicodeScalars
        func isJSWhitespace(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0xFEFF, 0x2028, 0x2029: return true
            default: return scalar.properties.generalCategory == .spaceSeparator
            }
        }
        guard let start = scalars.firstIndex(where: { !isJSWhitespace($0) }),
            let end = scalars.lastIndex(where: { !isJSWhitespace($0) })
        else { return "" }
        return String(scalars[start...end])
    }
}
