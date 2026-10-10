import Foundation
import zlib

// 원본 onelibrary-connect/src/encryption.ts
private let BLOB = Array(
    "PN_1dH8$oLJY)16j_RvM6qphWw`476>;C1cWmI#se(PG`j}~xAjlufj?`#0i{;=glh(SkW)y0>n?YEiD`l%t(".utf8)
private let BLOB_KEY = Array("657f48f84c437cc1".utf8)
func base85Decode(_ input: [UInt8]) throws -> [UInt8] {
    let alphabet = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~".utf8)
    var result: [UInt8] = []
    for i in stride(from: 0, to: input.count, by: 5) {
        let chunk = input.subarray(i, i + 5)
        var value: UInt64 = 0
        for char in chunk {
            guard let v = alphabet.firstIndex(of: char) else {
                throw DJLinkError("Invalid base85 character: \(String(UnicodeScalar(char)))")
            }
            value = value * 85 + UInt64(v)
        }
        let bytes = [
            UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value),
        ]
        result += bytes.prefix(chunk.count == 5 ? 4 : chunk.count - 1)
    }
    return result
}
public func getEncryptionKey() throws -> String {
    let decoded = try base85Decode(BLOB)
    let xored = decoded.enumerated().map { $0.element ^ BLOB_KEY[$0.offset % BLOB_KEY.count] }
    var output = [UInt8](repeating: 0, count: 65536)
    var length = uLongf(output.count)
    let code = xored.withUnsafeBufferPointer { source in
        output.withUnsafeMutableBufferPointer { target in
            uncompress(target.baseAddress, &length, source.baseAddress, uLong(source.count))
        }
    }
    guard code == Z_OK else { throw DJLinkError("Failed to inflate encryption key") }
    let key = String(decoding: output.prefix(Int(length)), as: UTF8.self)
    guard key.hasPrefix("r8gd") else { throw DJLinkError("Invalid encryption key derived") }
    return key
}
