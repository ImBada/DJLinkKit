// 원본 onelibrary-connect/src/connection.ts. legacy = 4는 첫 읽기 전에 적용한다.
public func openOneLibraryDb(_ dbPath: String) throws -> CipherDatabase {
    try CipherDatabase(
        path: dbPath, key: .passphrase(getEncryptionKey()), mode: .readOnly, validate: false,
        cipherCompatibility: 4)
}
