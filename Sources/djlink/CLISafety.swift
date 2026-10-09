import DJLinkKit
import Darwin
import Foundation

// docs/PLAN.md §11 "실기와 CLI" 안전 규칙. 라이브러리(1:1) 동작에는 넣지 않고 CLI에서만 건다.
// 판단은 소켓 없이 확인할 수 있는 순수 함수로 두고, 프로세스 목록만 주입한다.

/// 안전 규칙 위반. 메시지는 사용자에게 그대로 보인다.
struct CLISafetyViolation: Error, Equatable, Sendable {
    var message: String
}

// MARK: - 가상 CDJ 번호

/// 가상 CDJ 번호 규칙: 기본 7, 1~6(실제 플레이어 번호)은 `--allow-player-id`를 같이 줄 때만 허용한다.
func checkVirtualCDJId(_ id: Int, allowPlayerId: Bool) -> CLISafetyViolation? {
    if MIN_CDJ_DEVICE_ID...MAX_CDJ_DEVICE_ID ~= id && !allowPlayerId {
        return CLISafetyViolation(
            message: "가상 CDJ 번호 \(id)은 실제 플레이어(1~6)가 쓰는 번호다. 7 이상을 쓰거나, 일부러 고른 경우에만 --allow-player-id를 같이 준다")
    }
    return nil
}

// MARK: - rekordbox 프로세스 검사

/// 같은 Mac에서 도는 프로세스 이름을 돌려준다. 시험은 가짜를 넣는다.
protocol ProcessLister: Sendable {
    func processNames() throws -> [String]
}

/// Darwin `sysctl(KERN_PROC_ALL)`로 읽는다. 하위 프로세스를 띄우지 않는다.
/// 다른 사용자 프로세스도 `p_comm`을 읽을 수 있다(`proc_name`은 권한이 없으면 비어 돌아온다).
/// `p_comm`은 16글자까지만 담지만 `rekordbox`·`rekordboxAgent`는 그 안이다.
struct DarwinProcessLister: ProcessLister {
    init() {}

    func processNames() throws -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        // 목록이 읽는 사이에 늘 수 있어 ENOMEM이면 몇 번 다시 읽는다.
        for _ in 0..<5 {
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { break }
            let stride = MemoryLayout<kinfo_proc>.stride
            var buffer = [UInt8](repeating: 0, count: size + 64 * stride)
            var filled = buffer.count
            if sysctl(&mib, UInt32(mib.count), &buffer, &filled, nil, 0) != 0 {
                if errno == ENOMEM { continue }
                break
            }
            return buffer.withUnsafeBytes { raw in
                (0..<(filled / stride)).map { index in
                    var comm = raw.baseAddress!.advanced(by: index * stride)
                        .assumingMemoryBound(to: kinfo_proc.self).pointee.kp_proc.p_comm
                    return withUnsafeBytes(of: &comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                }
            }
        }
        throw CLISafetyViolation(message: "프로세스 목록을 읽지 못했다(sysctl KERN_PROC_ALL 실패)")
    }
}

/// rekordbox 계열 프로세스 이름인지(대소문자 무시). `rekordbox`, `rekordboxAgent`, `rekordbox Helper …`를 잡는다.
func isRekordboxProcessName(_ name: String) -> Bool {
    name.lowercased().hasPrefix("rekordbox")
}

/// 돌고 있는 rekordbox 계열 프로세스 이름(중복 없이 정렬).
func rekordboxProcesses(in names: [String]) -> [String] {
    Array(Set(names.filter(isRekordboxProcessName))).sorted()
}

/// 같은 Mac에서 rekordbox·rekordboxAgent가 돌고 있으면 UDP 50000~50002를 잡지 않는다(잡으면 rekordbox LINK가 망가질 수 있다).
/// 확인하지 못했을 때도 거부한다.
func checkRekordboxNotRunning(lister: any ProcessLister) -> CLISafetyViolation? {
    let names: [String]
    do {
        names = try lister.processNames()
    } catch let violation as CLISafetyViolation {
        return CLISafetyViolation(message: "rekordbox가 꺼져 있는지 확인하지 못해 시작하지 않는다: \(violation.message)")
    } catch {
        return CLISafetyViolation(message: "rekordbox가 꺼져 있는지 확인하지 못해 시작하지 않는다: \(error)")
    }
    let running = rekordboxProcesses(in: names)
    guard running.isEmpty else {
        return CLISafetyViolation(
            message:
                "같은 Mac에서 \(running.joined(separator: ", "))가 돌고 있다. UDP 50000~50002를 잡으면 rekordbox LINK가 망가질 수 있어 시작하지 않는다. rekordbox와 rekordboxAgent를 모두 끝낸 뒤 다시 실행한다"
        )
    }
    return nil
}

// MARK: - 읽지 않는 경로

/// docs/PLAN.md §13의 `UsbLayout.neverRead`와 같은 뜻. NFS로도 열거·읽기·복사하지 않는다.
/// 경로는 `/`·`\` 모두 구분자로 보고, 드라이브 글자와 `.`·빈 칸을 걷어낸 뒤 대소문자 없이 견준다.
func checkNeverRead(_ path: String) -> CLISafetyViolation? {
    var components = path.replacingOccurrences(of: "\\", with: "/")
        .split(separator: "/", omittingEmptySubsequences: true)
        .map { String($0) }
        .filter { $0 != "." }
    if let first = components.first, first.count == 2, first.hasSuffix(":") { components.removeFirst() }
    let lowered = components.map { $0.lowercased() }
    if lowered.contains("..") {
        return CLISafetyViolation(message: "경로에 상위 폴더(..)를 쓸 수 없다: \(path)")
    }
    if lowered.contains("djprofile.nxs") {
        return CLISafetyViolation(message: "djprofile.nxs는 읽지 않는다: \(path)")
    }
    for index in lowered.indices where lowered[index] == "pioneer" && index + 1 < lowered.count {
        let next = lowered[index + 1]
        if next == "extracted" || next == "cdp" {
            return CLISafetyViolation(message: "PIONEER/extracted·PIONEER/CDP는 읽지 않는다: \(path)")
        }
    }
    return nil
}

// MARK: - 제어 확인

/// `--confirm`이 대상 장치 이름과 정확히 같을 때만 보낸다(대소문자·공백 포함).
func checkControlConfirmation(device: Device, confirm: String) -> CLISafetyViolation? {
    guard !confirm.isEmpty, device.name == confirm else {
        return CLISafetyViolation(
            message:
                "--confirm \"\(confirm)\"이 장치 \(device.id)의 이름 \"\(device.name)\"과 같지 않다. 아무것도 보내지 않았다")
    }
    return nil
}

// MARK: - 내려받기 파일 이름

/// 장치가 알려 준 파일 이름을 `--download-dir` 안에 쓸 안전한 이름으로 바꾼다.
/// 경로 구분자는 마지막 조각만 남기고, 비었거나 `.`·`..`이면 nil.
func safeDownloadFileName(_ name: String) -> String? {
    let last =
        name.replacingOccurrences(of: "\\", with: "/")
        .split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
    let cleaned = last.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespaces)
    guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { return nil }
    return cleaned
}
