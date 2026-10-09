import Foundation

@testable import DJLinkKit

// 원본 native-sqlite.ts. SQLCipher는 패키지 의존이라 Node ABI에 따른 skip 조건이 없다.
private func localDBFixturePath(_ name: String) -> String {
    if let url = Bundle.module.url(
        forResource: name, withExtension: "db", subdirectory: "Fixtures/localdb")
    {
        return url.path
    }
    // 원본 describeIfFixture처럼 파일이 없어도 검사 단계에서 실패하지 않는다.
    return Bundle.module.bundleURL.appending(path: "Fixtures/localdb/\(name).db").path
}
var oneLibraryFixturePath: String { localDBFixturePath("test-onelibrary") }
var oneLibraryFixtureAvailable: Bool {
    FileManager.default.fileExists(atPath: oneLibraryFixturePath)
}
var oneLibraryConnectFixturePath: String { localDBFixturePath("onelibrary-connect-test") }
var oneLibraryConnectFixtureAvailable: Bool {
    FileManager.default.fileExists(atPath: oneLibraryConnectFixturePath)
}
