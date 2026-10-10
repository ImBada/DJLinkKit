// 원본 localdb/utils.ts
public func makeCueLoopEntry(
    isCue: Bool, isLoop: Bool, offset: Double, length: Double, button: HotcueButton?
) -> CueAndLoop? {
    // 원본처럼 버튼이 있으면 isCue가 false여도 핫 큐로 만든다.
    if let button {
        if isLoop { return .hotLoop(.init(offset: offset, button: button, length: length)) }
        return .hotCue(.init(offset: offset, button: button))
    }
    if isLoop { return .loop(.init(offset: offset, length: length)) }
    if isCue { return .cuePoint(.init(offset: offset)) }
    return nil
}

// JS substring은 UTF-16 코드 단위를 기준으로 한다.
func localDBTrimAnalyzePath(_ path: String) -> String {
    let units = Array(path.utf16)
    return String(decoding: units.prefix(max(0, units.count - 4)), as: UTF16.self)
}
