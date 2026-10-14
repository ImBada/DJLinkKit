import DJLinkKit

// 원본 src/cli/index.ts에는 인자가 없다. 우리 CLI는 하위 명령과 옵션을 직접 해석한다(외부 의존성 없음).
// 소켓을 열지 않는 순수 함수만 둔다.

/// 하위 명령.
enum CLISubcommand: String, CaseIterable, Equatable, Sendable {
    case devices
    case watch
    case status
    case metadata
    case fetch
    case mixstatus
    case control
    case passive
}

/// 제어 명령 종류.
enum ControlAction: String, CaseIterable, Equatable, Sendable {
    case load
    case play
    case pause
}

/// 인자 해석 실패. 메시지는 사용자에게 그대로 보인다.
struct CLIUsageError: Error, Equatable, Sendable {
    var message: String
    /// 실패한 하위 명령(도움말을 곁들일 때 쓴다).
    var subcommand: CLISubcommand?

    init(_ message: String, subcommand: CLISubcommand? = nil) {
        self.message = message
        self.subcommand = subcommand
    }
}

/// 네트워크에 참여하는 명령이 함께 받는 옵션.
struct CLICommonOptions: Equatable, Sendable {
    var iface: String?
    var vcdjId: Int?
    var allowPlayerId = false
    var verbose = false

    /// 실제로 쓸 가상 CDJ 번호. 주지 않으면 기본값(`DEFAULT_VCDJ_ID` = 7).
    var effectiveVcdjId: Int { vcdjId ?? DEFAULT_VCDJ_ID }
}

/// 명령마다 거는 전체 제한 시간(초)의 기본값. 넘으면 남은 작업과 소켓을 정리하고 종료 코드 1로 끝난다.
let defaultMetadataTimeoutSeconds = 15
let defaultFetchTimeoutSeconds = 300
let defaultControlTimeoutSeconds = 15

/// 장치 하나를 가리키는 곳(메타데이터·파일).
struct CLITrackTarget: Equatable, Sendable {
    var deviceId: Int
    var slot: MediaSlot
    var trackId: Int
    /// 명령 전체 제한 시간(초).
    var timeoutSeconds = defaultMetadataTimeoutSeconds
}

struct CLIFetchTarget: Equatable, Sendable {
    var deviceId: Int
    var slot: MediaSlot
    var path: String
    var out: String
    /// 가상 CDJ로 참여한 뒤 받는다. 기본은 참여하지 않고 듣기만 한다.
    var join: Bool
    /// 명령 전체 제한 시간(초).
    var timeoutSeconds = defaultFetchTimeoutSeconds
}

struct CLIControlRequest: Equatable, Sendable {
    var action: ControlAction
    var deviceId: Int
    /// `load`의 곡 위치(`--source-device`, `--slot`, `--track-id`). `play`·`pause`에는 nil.
    var load: Load?
    /// 대상 장치 이름. 정확히 같아야 보낸다(docs/PLAN.md §11).
    var confirm: String
    /// 명령 전체 제한 시간(초).
    var timeoutSeconds = defaultControlTimeoutSeconds

    struct Load: Equatable, Sendable {
        var sourceDeviceId: Int
        var slot: MediaSlot
        var trackType: TrackType
        var trackId: Int
    }
}

/// 해석한 명령.
enum CLICommand: Equatable, Sendable {
    case help(CLISubcommand?)
    case devices(seconds: Int, verbose: Bool)
    case watch(CLICommonOptions, downloadDir: String?)
    case status(CLICommonOptions, all: Bool, positionIntervalMs: Int)
    case metadata(CLICommonOptions, CLITrackTarget)
    case fetch(CLICommonOptions, CLIFetchTarget)
    case mixstatus(CLICommonOptions)
    case control(CLICommonOptions, CLIControlRequest)
    case passive(iface: String, positionIntervalMs: Int)

    /// 소켓(UDP 50000~50002)이나 패킷 캡처를 쓰는 명령인지. 이런 명령은 시작 전에 rekordbox 검사를 거친다.
    var touchesNetwork: Bool {
        if case .help = self { return false }
        return true
    }
}

/// 하위 명령 하나가 받는 옵션 목록.
private struct OptionSpec {
    var values: Set<String> = []
    var flags: Set<String> = []
    var positionals: Int = 0
}

private struct ParsedOptions {
    var values: [String: String] = [:]
    var flags: Set<String> = []
    var positionals: [String] = []
    var wantsHelp = false
}

private let commonValueOptions: Set<String> = ["iface", "vcdj-id"]
/// 정수를 받는 옵션. 값이 `-5`처럼 음수여도 옵션으로 읽지 않고 값으로 받아 범위 오류를 낸다.
private let numericValueOptions: Set<String> = [
    "seconds", "position-interval-ms", "vcdj-id", "device", "source-device", "track-id", "timeout",
]
private let commonFlagOptions: Set<String> = ["allow-player-id", "verbose"]

private func spec(for subcommand: CLISubcommand) -> OptionSpec {
    switch subcommand {
    case .devices:
        OptionSpec(values: ["seconds"], flags: ["verbose"])
    case .watch:
        OptionSpec(
            values: commonValueOptions.union(["download-dir"]), flags: commonFlagOptions)
    case .status:
        OptionSpec(values: commonValueOptions.union(["position-interval-ms"]), flags: commonFlagOptions.union(["all"]))
    case .metadata:
        OptionSpec(
            values: commonValueOptions.union(["device", "slot", "track-id", "timeout"]), flags: commonFlagOptions)
    case .fetch:
        OptionSpec(
            values: commonValueOptions.union(["device", "slot", "path", "out", "timeout"]),
            flags: commonFlagOptions.union(["join"]))
    case .mixstatus:
        OptionSpec(values: commonValueOptions, flags: commonFlagOptions)
    case .control:
        OptionSpec(
            values: commonValueOptions.union([
                "device", "source-device", "slot", "track-id", "track-type", "confirm", "timeout",
            ]),
            flags: commonFlagOptions, positionals: 1)
    case .passive:
        OptionSpec(values: ["iface", "position-interval-ms"])
    }
}

/// 값 자리에 온 인자가 옵션처럼 보이는가. `-`로 시작하는 두 글자 이상은 옵션이다. 숫자 옵션에서만 음수 정수(`-5`)를 값으로 본다.
private func looksLikeOption(_ argument: String, numeric: Bool) -> Bool {
    guard argument.hasPrefix("-"), argument.count > 1 else { return false }
    if numeric, argument.dropFirst().allSatisfy(\.isASCII), Int(argument) != nil { return false }
    return true
}

/// `--name value`, `--name=value`, 불리언 `--flag`, 위치 인자를 나눈다.
private func tokenize(_ args: ArraySlice<String>, spec: OptionSpec, subcommand: CLISubcommand) throws(CLIUsageError)
    -> ParsedOptions
{
    var parsed = ParsedOptions()
    var iterator = args.makeIterator()
    while let arg = iterator.next() {
        if arg == "--help" || arg == "-h" {
            parsed.wantsHelp = true
            continue
        }
        if arg.hasPrefix("--") && arg.count > 2 {
            var name = String(arg.dropFirst(2))
            var inlineValue: String?
            if let equals = name.firstIndex(of: "=") {
                inlineValue = String(name[name.index(after: equals)...])
                name = String(name[..<equals])
            }
            if spec.flags.contains(name) {
                if inlineValue != nil {
                    throw CLIUsageError("--\(name)은 값을 받지 않는다", subcommand: subcommand)
                }
                parsed.flags.insert(name)
            } else if spec.values.contains(name) {
                guard let value = inlineValue ?? iterator.next() else {
                    throw CLIUsageError("--\(name)에 값이 없다", subcommand: subcommand)
                }
                // 다음 인자가 옵션(`-h`·`--x`)이면 값으로 삼키지 않는다. 음수 숫자만 숫자 옵션에서 값으로 받는다.
                if inlineValue == nil, looksLikeOption(value, numeric: numericValueOptions.contains(name)) {
                    throw CLIUsageError(
                        "--\(name)에 값이 없다(다음 인자 \(value)는 옵션으로 보인다. 값이 -로 시작하면 --\(name)=값 으로 준다)",
                        subcommand: subcommand)
                }
                if parsed.values[name] != nil {
                    throw CLIUsageError("--\(name)을 두 번 줬다", subcommand: subcommand)
                }
                parsed.values[name] = value
            } else {
                throw CLIUsageError("알 수 없는 옵션: --\(name)", subcommand: subcommand)
            }
        } else if arg.hasPrefix("-") && arg.count > 1 {
            throw CLIUsageError("알 수 없는 옵션: \(arg)", subcommand: subcommand)
        } else {
            parsed.positionals.append(arg)
        }
    }
    if parsed.positionals.count > spec.positionals && !parsed.wantsHelp {
        throw CLIUsageError("예상하지 못한 인자: \(parsed.positionals[spec.positionals])", subcommand: subcommand)
    }
    return parsed
}

private func parseInt(
    _ name: String, _ value: String, in range: ClosedRange<Int>, subcommand: CLISubcommand
) throws(CLIUsageError) -> Int {
    guard let number = Int(value), range.contains(number) else {
        throw CLIUsageError(
            "--\(name)은 \(range.lowerBound)~\(range.upperBound) 사이의 정수여야 한다: \(value)", subcommand: subcommand)
    }
    return number
}

private func requireValue(
    _ parsed: ParsedOptions, _ name: String, subcommand: CLISubcommand
) throws(CLIUsageError) -> String {
    guard let value = parsed.values[name], !value.isEmpty else {
        throw CLIUsageError("--\(name)이 필요하다", subcommand: subcommand)
    }
    return value
}

private func parseTimeout(
    _ parsed: ParsedOptions, default defaultSeconds: Int, subcommand: CLISubcommand
) throws(CLIUsageError) -> Int {
    guard let value = parsed.values["timeout"] else { return defaultSeconds }
    return try parseInt("timeout", value, in: 1...3600, subcommand: subcommand)
}

/// `usb`·`sd`(·`rb`) 이름을 슬롯으로.
func parseSlotName(_ name: String, allowRB: Bool = false) -> MediaSlot? {
    switch name.lowercased() {
    case "usb": .usb
    case "sd": .sd
    case "rb" where allowRB: .rb
    default: nil
    }
}

private func parseSlot(
    _ parsed: ParsedOptions, allowRB: Bool = false, subcommand: CLISubcommand
) throws(CLIUsageError) -> MediaSlot {
    let value = try requireValue(parsed, "slot", subcommand: subcommand)
    guard let slot = parseSlotName(value, allowRB: allowRB) else {
        throw CLIUsageError(
            "--slot은 \(allowRB ? "usb, sd, rb" : "usb, sd") 중 하나여야 한다: \(value)", subcommand: subcommand)
    }
    return slot
}

private func parseCommonOptions(
    _ parsed: ParsedOptions, subcommand: CLISubcommand
) throws(CLIUsageError) -> CLICommonOptions {
    var options = CLICommonOptions()
    if let iface = parsed.values["iface"] {
        guard !iface.isEmpty else { throw CLIUsageError("--iface가 비어 있다", subcommand: subcommand) }
        options.iface = iface
    }
    if let value = parsed.values["vcdj-id"] {
        options.vcdjId = try parseInt("vcdj-id", value, in: 1...MAX_DEVICE_ID, subcommand: subcommand)
    }
    options.allowPlayerId = parsed.flags.contains("allow-player-id")
    options.verbose = parsed.flags.contains("verbose")
    // 안전 규칙: 1~6은 --allow-player-id를 같이 줄 때만 허용한다.
    if let violation = checkVirtualCDJId(options.effectiveVcdjId, allowPlayerId: options.allowPlayerId) {
        throw CLIUsageError(violation.message, subcommand: subcommand)
    }
    return options
}

/// 인자 목록(프로그램 이름 제외)을 명령으로 해석한다.
func parseArguments(_ arguments: [String]) throws(CLIUsageError) -> CLICommand {
    guard let first = arguments.first else { return .help(nil) }
    if first == "--help" || first == "-h" || first == "help" {
        if first == "help", arguments.count > 1 {
            guard let topic = CLISubcommand(rawValue: arguments[1]) else {
                throw CLIUsageError("알 수 없는 하위 명령: \(arguments[1])")
            }
            return .help(topic)
        }
        return .help(nil)
    }
    guard let subcommand = CLISubcommand(rawValue: first) else {
        throw CLIUsageError("알 수 없는 하위 명령: \(first)")
    }
    let parsed = try tokenize(arguments.dropFirst(), spec: spec(for: subcommand), subcommand: subcommand)
    if parsed.wantsHelp { return .help(subcommand) }

    switch subcommand {
    case .devices:
        var seconds = 5
        if let value = parsed.values["seconds"] {
            seconds = try parseInt("seconds", value, in: 1...3600, subcommand: subcommand)
        }
        return .devices(seconds: seconds, verbose: parsed.flags.contains("verbose"))

    case .watch:
        let options = try parseCommonOptions(parsed, subcommand: subcommand)
        if let dir = parsed.values["download-dir"], dir.isEmpty {
            throw CLIUsageError("--download-dir가 비어 있다", subcommand: subcommand)
        }
        return .watch(options, downloadDir: parsed.values["download-dir"])

    case .status:
        let options = try parseCommonOptions(parsed, subcommand: subcommand)
        var interval = 500
        if let value = parsed.values["position-interval-ms"] {
            interval = try parseInt("position-interval-ms", value, in: 0...60000, subcommand: subcommand)
        }
        return .status(options, all: parsed.flags.contains("all"), positionIntervalMs: interval)

    case .metadata:
        let options = try parseCommonOptions(parsed, subcommand: subcommand)
        let device = try parseInt(
            "device", try requireValue(parsed, "device", subcommand: subcommand), in: 1...MAX_DEVICE_ID,
            subcommand: subcommand)
        let slot = try parseSlot(parsed, subcommand: subcommand)
        let trackId = try parseInt(
            "track-id", try requireValue(parsed, "track-id", subcommand: subcommand), in: 1...Int(Int32.max),
            subcommand: subcommand)
        let timeout = try parseTimeout(parsed, default: defaultMetadataTimeoutSeconds, subcommand: subcommand)
        return .metadata(
            options, CLITrackTarget(deviceId: device, slot: slot, trackId: trackId, timeoutSeconds: timeout))

    case .fetch:
        let options = try parseCommonOptions(parsed, subcommand: subcommand)
        let device = try parseInt(
            "device", try requireValue(parsed, "device", subcommand: subcommand), in: 1...MAX_DEVICE_ID,
            subcommand: subcommand)
        let slot = try parseSlot(parsed, subcommand: subcommand)
        let path = try requireValue(parsed, "path", subcommand: subcommand)
        let out = try requireValue(parsed, "out", subcommand: subcommand)
        // 안전 규칙: 펌웨어 쪽 영역은 NFS로도 읽지 않는다. 경로를 받는 즉시 거부한다.
        if let violation = checkNeverRead(path) {
            throw CLIUsageError(violation.message, subcommand: subcommand)
        }
        let timeout = try parseTimeout(parsed, default: defaultFetchTimeoutSeconds, subcommand: subcommand)
        return .fetch(
            options,
            CLIFetchTarget(
                deviceId: device, slot: slot, path: path, out: out, join: parsed.flags.contains("join"),
                timeoutSeconds: timeout))

    case .mixstatus:
        return .mixstatus(try parseCommonOptions(parsed, subcommand: subcommand))

    case .control:
        return try parseControl(parsed)

    case .passive:
        let iface = try requireValue(parsed, "iface", subcommand: subcommand)
        var interval = 500
        if let value = parsed.values["position-interval-ms"] {
            interval = try parseInt("position-interval-ms", value, in: 0...60000, subcommand: subcommand)
        }
        return .passive(iface: iface, positionIntervalMs: interval)
    }
}

private func parseControl(_ parsed: ParsedOptions) throws(CLIUsageError) -> CLICommand {
    let subcommand = CLISubcommand.control
    guard let actionName = parsed.positionals.first else {
        throw CLIUsageError("load, play, pause 중 하나를 줘야 한다", subcommand: subcommand)
    }
    guard let action = ControlAction(rawValue: actionName) else {
        throw CLIUsageError("알 수 없는 제어 동작: \(actionName) (load, play, pause)", subcommand: subcommand)
    }
    let options = try parseCommonOptions(parsed, subcommand: subcommand)
    // 안전 규칙: --confirm 없이는 아무것도 열지 않고 거부한다.
    guard let confirm = parsed.values["confirm"], !confirm.isEmpty else {
        throw CLIUsageError(
            "제어 명령은 --confirm \"<장치 이름>\" 없이는 보내지 않는다. 아무것도 보내지 않았다", subcommand: subcommand)
    }
    let device = try parseInt(
        "device", try requireValue(parsed, "device", subcommand: subcommand), in: 1...MAX_DEVICE_ID,
        subcommand: subcommand)
    if action != .load, let violation = checkPlayStateAllowed(deviceId: device) {
        // 재생 상태 패킷에 칸이 없는 번호에는 play·pause를 보내지 않는다(docs/PLAN.md §9).
        throw CLIUsageError(violation.message, subcommand: subcommand)
    }
    let timeout = try parseTimeout(parsed, default: defaultControlTimeoutSeconds, subcommand: subcommand)
    var load: CLIControlRequest.Load?
    if action == .load {
        let slot = try parseSlot(parsed, allowRB: true, subcommand: subcommand)
        let trackId = try parseInt(
            "track-id", try requireValue(parsed, "track-id", subcommand: subcommand), in: 1...Int(Int32.max),
            subcommand: subcommand)
        let source = try parseInt(
            "source-device", parsed.values["source-device"] ?? String(device), in: 1...MAX_DEVICE_ID,
            subcommand: subcommand)
        var trackType = TrackType.rb
        if let name = parsed.values["track-type"] {
            switch name.lowercased() {
            case "rb": trackType = .rb
            case "unanalyzed": trackType = .unanalyzed
            default: throw CLIUsageError("--track-type은 rb, unanalyzed 중 하나여야 한다: \(name)", subcommand: subcommand)
            }
        }
        load = .init(sourceDeviceId: source, slot: slot, trackType: trackType, trackId: trackId)
    } else {
        for name in ["source-device", "slot", "track-id", "track-type"] where parsed.values[name] != nil {
            throw CLIUsageError("--\(name)은 load에만 쓴다", subcommand: subcommand)
        }
    }
    return .control(
        options,
        CLIControlRequest(
            action: action, deviceId: device, load: load, confirm: confirm, timeoutSeconds: timeout))
}
