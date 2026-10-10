/// 원본의 `throw new Error(message)`. 시험은 문구로 비교하므로 문구를 원본 그대로 둔다.
public struct DJLinkError: Error, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Node `Buffer`의 읽기·쓰기 위치가 범위를 벗어났을 때 나는 `RangeError`(ERR_OUT_OF_RANGE·ERR_BUFFER_OUT_OF_BOUNDS).
public struct BufferRangeError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    /// Node가 내는 문구를 그대로 만든다.
    static func offset(_ offset: Int, size: Int, length: Int) -> BufferRangeError {
        if length - size < 0 {
            return BufferRangeError("Attempt to access memory outside buffer bounds")
        }
        return BufferRangeError(
            "The value of \"offset\" is out of range. It must be >= 0 and <= \(length - size). Received \(offset)"
        )
    }

    public var description: String { message }
}

extension Error {
    /// JS `err.message`. 다른 오류는 설명 문구를 쓴다.
    public var jsMessage: String {
        switch self {
        case let error as DJLinkError: error.message
        case let error as BufferRangeError: error.message
        default: String(describing: self)
        }
    }
}
