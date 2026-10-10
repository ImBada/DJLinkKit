/// `ip-address` 패키지의 `Address4`에서 원본이 쓰는 부분만 옮긴 것.
public struct Address4: Hashable, Sendable, CustomStringConvertible {
    /// 만들 때 받은 문자열 그대로(접미사 `/n` 포함). 원본의 `.address`.
    public let address: String
    /// 네 칸 값.
    public let octets: [UInt8]
    /// 접미사 길이. 접미사가 없으면 32.
    public let subnetMask: Int

    /// `new Address4(address)`. `a.b.c.d` 또는 `a.b.c.d/n`을 받는다. 틀리면 `AddressError`를 던진다.
    public init(_ address: String) throws(AddressError) {
        let parts = address.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else {
            throw AddressError("Invalid subnet mask.")
        }
        var mask = 32
        if parts.count == 2 {
            guard let value = Int(parts[1]), (0...32).contains(value) else {
                throw AddressError("Invalid subnet mask.")
            }
            mask = value
        }
        let groups = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard groups.count == 4 else {
            throw AddressError("Invalid IPv4 address.")
        }
        var octets: [UInt8] = []
        for group in groups {
            guard !group.isEmpty, group.allSatisfy(\.isASCII), group.allSatisfy(\.isNumber),
                  let value = UInt8(group)
            else {
                throw AddressError("Invalid IPv4 address.")
            }
            octets.append(value)
        }
        self.address = address
        self.octets = octets
        self.subnetMask = mask
    }

    private init(octets: [UInt8], subnetMask: Int = 32) {
        self.octets = octets
        self.subnetMask = subnetMask
        self.address = octets.map(String.init).joined(separator: ".")
    }

    /// `Address4.fromInteger(n)`
    public static func fromInteger(_ value: Int) -> Address4 {
        let v = UInt32(truncatingIfNeeded: value)
        return Address4(octets: [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)])
    }

    /// `addressMinusSuffix`
    public var addressMinusSuffix: String {
        octets.map(String.init).joined(separator: ".")
    }

    /// `correctForm()`
    public func correctForm() -> String {
        addressMinusSuffix
    }

    /// `subnet`(예: "/24")
    public var subnet: String {
        "/\(subnetMask)"
    }

    /// `toArray()`
    public func toArray() -> [Int] {
        octets.map(Int.init)
    }

    /// 32비트 정수 값(`bigInt()`).
    public var integerValue: UInt32 {
        octets.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private var maskBits: UInt32 {
        subnetMask == 0 ? 0 : UInt32.max << UInt32(32 - subnetMask)
    }

    /// `isInSubnet(address)`: 이 주소가 `address`의 서브넷 안에 있는가.
    public func isInSubnet(_ other: Address4) -> Bool {
        if subnetMask < other.subnetMask { return false }
        return integerValue & other.maskBits == other.integerValue & other.maskBits
    }

    /// `startAddress()`
    public func startAddress() -> Address4 {
        Self.fromInteger(Int(integerValue & maskBits))
    }

    /// `endAddress()`
    public func endAddress() -> Address4 {
        Self.fromInteger(Int(integerValue | ~maskBits))
    }

    public var description: String { address }

    public static func == (lhs: Address4, rhs: Address4) -> Bool {
        lhs.octets == rhs.octets && lhs.subnetMask == rhs.subnetMask
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(octets)
        hasher.combine(subnetMask)
    }
}

/// `ip-address`의 `AddressError`.
public struct AddressError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}
