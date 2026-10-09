import DJLinkKit
import Foundation

// 원본 tests/utils.ts의 readMock. 픽스처는 Tests/DJLinkKitTests/Fixtures/에 있다.

/// 원본 `readMock(path)`: tests/_data/ 아래 파일을 읽는다.
func readMock(_ path: String) throws -> [UInt8] {
    guard let url = Bundle.module.url(forResource: path, withExtension: nil, subdirectory: "Fixtures") else {
        throw DJLinkError("fixture not found: \(path)")
    }
    return try Data(contentsOf: url).bytes
}

/// 픽스처 파일의 URL.
func fixtureURL(_ path: String) throws -> URL {
    guard let url = Bundle.module.url(forResource: path, withExtension: nil, subdirectory: "Fixtures") else {
        throw DJLinkError("fixture not found: \(path)")
    }
    return url
}
