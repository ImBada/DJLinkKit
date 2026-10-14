import DJLinkKit
import Testing

@testable import djlink

@Suite("CLI argument parsing")
struct CLIArgumentsTests {
    @Test("no arguments and --help print the top-level help")
    func help() throws {
        #expect(try parseArguments([]) == .help(nil))
        #expect(try parseArguments(["--help"]) == .help(nil))
        #expect(try parseArguments(["help", "watch"]) == .help(.watch))
    }

    @Test("every subcommand accepts --help")
    func subcommandHelp() throws {
        for subcommand in CLISubcommand.allCases {
            #expect(try parseArguments([subcommand.rawValue, "--help"]) == .help(subcommand))
            #expect(try parseArguments([subcommand.rawValue, "-h"]) == .help(subcommand))
        }
    }

    @Test("unknown subcommands and options are rejected")
    func unknown() {
        #expect(throws: CLIUsageError("알 수 없는 하위 명령: nope")) { try parseArguments(["nope"]) }
        #expect(throws: CLIUsageError("알 수 없는 옵션: --bogus", subcommand: .watch)) {
            try parseArguments(["watch", "--bogus"])
        }
        #expect(throws: CLIUsageError("알 수 없는 옵션: -x", subcommand: .status)) { try parseArguments(["status", "-x"]) }
        #expect(throws: CLIUsageError("예상하지 못한 인자: extra", subcommand: .status)) {
            try parseArguments(["status", "extra"])
        }
    }

    @Test("devices defaults to 5 seconds and checks the range")
    func devices() throws {
        #expect(try parseArguments(["devices"]) == .devices(seconds: 5, verbose: false))
        #expect(try parseArguments(["devices", "--seconds", "12"]) == .devices(seconds: 12, verbose: false))
        #expect(try parseArguments(["devices", "--seconds=3", "--verbose"]) == .devices(seconds: 3, verbose: true))
        #expect(throws: CLIUsageError.self) { try parseArguments(["devices", "--seconds", "0"]) }
        #expect(throws: CLIUsageError.self) { try parseArguments(["devices", "--seconds", "abc"]) }
        #expect(throws: CLIUsageError.self) { try parseArguments(["devices", "--seconds"]) }
    }

    @Test("a value option does not swallow the next option")
    func missingValue() {
        #expect(throws: CLIUsageError.self) { try parseArguments(["watch", "--iface", "--verbose"]) }
        // 값이 아예 없을 때
        #expect(throws: CLIUsageError("--iface에 값이 없다", subcommand: .watch)) {
            try parseArguments(["watch", "--iface"])
        }
    }

    /// 값이 필요한 옵션 뒤에 옵션처럼 보이는 인자가 오면 그것을 값으로 삼키지 않고 거부한다(도움말도 삼키지 않는다).
    @Test("every value option refuses a following -h, --x or -x instead of swallowing it")
    func valueOptionsDoNotSwallowOptions() throws {
        let cases: [(subcommand: String, prefix: [String], option: String)] = [
            ("watch", [], "--iface"), ("watch", [], "--vcdj-id"), ("watch", [], "--download-dir"),
            ("status", [], "--position-interval-ms"), ("devices", [], "--seconds"),
            ("mixstatus", [], "--iface"),
            ("metadata", ["--slot", "usb", "--track-id", "1"], "--device"),
            ("metadata", ["--device", "1", "--track-id", "1"], "--slot"),
            ("metadata", ["--device", "1", "--slot", "usb"], "--track-id"),
            ("metadata", ["--device", "1", "--slot", "usb", "--track-id", "1"], "--timeout"),
            ("fetch", ["--device", "1", "--slot", "usb", "--out", "o"], "--path"),
            ("fetch", ["--device", "1", "--slot", "usb", "--path", "a"], "--out"),
            ("control", ["play", "--device", "1"], "--confirm"),
            ("passive", [], "--iface"), ("passive", [], "--position-interval-ms"),
        ]
        for item in cases {
            for next in ["-h", "--help", "--x", "--verbose", "-x", "-abc"] {
                let arguments = [item.subcommand] + item.prefix + [item.option, next]
                #expect(throws: CLIUsageError.self, "\(arguments)") { try parseArguments(arguments) }
            }
        }
        // 값 뒤에 -h가 오면 도움말이다.
        #expect(try parseArguments(["watch", "--iface", "en7", "-h"]) == .help(.watch))
    }

    @Test("a negative number is a value only for numeric options, and then fails its range check")
    func negativeNumbers() throws {
        for arguments in [
            ["devices", "--seconds", "-5"], ["watch", "--vcdj-id", "-7"], ["status", "--position-interval-ms", "-1"],
            ["metadata", "--device", "-1", "--slot", "usb", "--track-id", "1"],
            ["metadata", "--device", "1", "--slot", "usb", "--track-id", "-3"],
            ["metadata", "--device", "1", "--slot", "usb", "--track-id", "1", "--timeout", "-9"],
        ] {
            #expect(throws: CLIUsageError.self, "\(arguments)") { try parseArguments(arguments) }
            // 범위 오류로 거부하므로 "값이 없다"가 아니다.
            do {
                _ = try parseArguments(arguments)
            } catch {
                #expect(error.message.contains("사이의 정수"), "\(arguments): \(error.message)")
            }
        }
        // 숫자가 아닌 옵션은 음수 모양도 값으로 받지 않는다. `--iface=-1`처럼 등호로 주면 받는다.
        #expect(throws: CLIUsageError.self) { try parseArguments(["watch", "--iface", "-1"]) }
        #expect(throws: CLIUsageError.self) { try parseArguments(["watch", "--download-dir", "-1"]) }
        #expect(
            try parseArguments(["watch", "--iface=-1", "--download-dir=-out"])
                == .watch(CLICommonOptions(iface: "-1"), downloadDir: "-out"))
        // 값 하나짜리 `-`는 옵션이 아니다.
        #expect(try parseArguments(["watch", "--download-dir", "-"]) == .watch(CLICommonOptions(), downloadDir: "-"))
    }

    @Test("an inline value can hold anything, including dashes")
    func inlineValues() throws {
        #expect(
            try parseArguments(["watch", "--iface=--weird"])
                == .watch(CLICommonOptions(iface: "--weird"), downloadDir: nil))
        #expect(throws: CLIUsageError("--iface가 비어 있다", subcommand: .watch)) {
            try parseArguments(["watch", "--iface="])
        }
    }

    @Test("an option given twice is rejected")
    func duplicate() {
        #expect(throws: CLIUsageError("--iface을 두 번 줬다", subcommand: .watch)) {
            try parseArguments(["watch", "--iface", "en0", "--iface", "en1"])
        }
    }

    @Test("watch downloads only when --download-dir is given")
    func watch() throws {
        #expect(try parseArguments(["watch"]) == .watch(CLICommonOptions(), downloadDir: nil))
        let command = try parseArguments(["watch", "--iface", "en7", "--vcdj-id", "9", "--download-dir", "out"])
        #expect(
            command
                == .watch(
                    CLICommonOptions(iface: "en7", vcdjId: 9, allowPlayerId: false, verbose: false), downloadDir: "out")
        )
        #expect(throws: CLIUsageError.self) { try parseArguments(["watch", "--download-dir", ""]) }
    }

    @Test("virtual CDJ ids 1-6 need --allow-player-id")
    func playerIds() throws {
        for id in 1...6 {
            #expect(throws: CLIUsageError.self) { try parseArguments(["watch", "--vcdj-id", String(id)]) }
            let command = try parseArguments(["watch", "--vcdj-id", String(id), "--allow-player-id"])
            guard case .watch(let options, _) = command else {
                Issue.record("watch가 아니다")
                return
            }
            #expect(options.vcdjId == id)
            #expect(options.allowPlayerId)
        }
        #expect(throws: CLIUsageError.self) { try parseArguments(["status", "--vcdj-id", "0"]) }
        #expect(throws: CLIUsageError.self) { try parseArguments(["status", "--vcdj-id", "33"]) }
        #expect(throws: CLIUsageError.self) { try parseArguments(["mixstatus", "--vcdj-id", "x"]) }
        // 기본값은 7
        #expect(CLICommonOptions().effectiveVcdjId == 7)
        #expect(try parseArguments(["mixstatus", "--vcdj-id", "7"]) != .help(nil))
    }

    @Test("status takes --all and a position interval")
    func status() throws {
        #expect(try parseArguments(["status"]) == .status(CLICommonOptions(), all: false, positionIntervalMs: 500))
        #expect(
            try parseArguments(["status", "--all", "--position-interval-ms", "0"])
                == .status(CLICommonOptions(), all: true, positionIntervalMs: 0))
        #expect(throws: CLIUsageError.self) { try parseArguments(["status", "--position-interval-ms", "-1"]) }
    }

    @Test("metadata requires device, slot and track id")
    func metadata() throws {
        let command = try parseArguments(["metadata", "--device", "2", "--slot", "usb", "--track-id", "42"])
        #expect(command == .metadata(CLICommonOptions(), CLITrackTarget(deviceId: 2, slot: .usb, trackId: 42)))
        #expect(
            try parseArguments(["metadata", "--device=1", "--slot=SD", "--track-id=7"])
                == .metadata(CLICommonOptions(), CLITrackTarget(deviceId: 1, slot: .sd, trackId: 7)))
        #expect(throws: CLIUsageError("--device이 필요하다", subcommand: .metadata)) {
            try parseArguments(["metadata", "--slot", "usb", "--track-id", "1"])
        }
        #expect(throws: CLIUsageError.self) {
            try parseArguments(["metadata", "--device", "1", "--slot", "cd", "--track-id", "1"])
        }
        #expect(throws: CLIUsageError.self) {
            try parseArguments(["metadata", "--device", "1", "--slot", "rb", "--track-id", "1"])
        }
        #expect(throws: CLIUsageError.self) {
            try parseArguments(["metadata", "--device", "1", "--slot", "usb", "--track-id", "0"])
        }
    }

    @Test("fetch parses its target and refuses never-read paths")
    func fetch() throws {
        let command = try parseArguments([
            "fetch", "--device", "1", "--slot", "usb", "--path", "PIONEER/rekordbox/export.pdb", "--out", "export.pdb",
        ])
        #expect(
            command
                == .fetch(
                    CLICommonOptions(),
                    CLIFetchTarget(
                        deviceId: 1, slot: .usb, path: "PIONEER/rekordbox/export.pdb", out: "export.pdb", join: false)))
        for path in ["PIONEER/extracted/x", "/PIONEER/CDP/a", "PIONEER/djprofile.nxs", "../x"] {
            #expect(throws: CLIUsageError.self) {
                try parseArguments(["fetch", "--device", "1", "--slot", "usb", "--path", path, "--out", "o"])
            }
        }
        #expect(throws: CLIUsageError.self) {
            try parseArguments(["fetch", "--device", "1", "--slot", "usb", "--path", "a"])
        }
        guard
            case .fetch(_, let target) = try parseArguments([
                "fetch", "--device", "1", "--slot", "sd", "--path", "a", "--out", "o", "--join",
            ])
        else {
            Issue.record("fetch가 아니다")
            return
        }
        #expect(target.join)
    }

    @Test("control refuses to parse without --confirm")
    func controlNeedsConfirm() {
        for action in ["play", "pause"] {
            #expect(throws: CLIUsageError.self) { try parseArguments(["control", action, "--device", "1"]) }
            #expect(throws: CLIUsageError.self) {
                try parseArguments(["control", action, "--device", "1", "--confirm", ""])
            }
        }
        #expect(throws: CLIUsageError.self) {
            try parseArguments(["control", "load", "--device", "1", "--slot", "usb", "--track-id", "3"])
        }
        #expect(throws: CLIUsageError.self) { try parseArguments(["control"]) }
        #expect(throws: CLIUsageError.self) {
            try parseArguments(["control", "eject", "--device", "1", "--confirm", "x"])
        }
    }

    @Test("control play and pause take only the device and confirm")
    func controlPlayPause() throws {
        let command = try parseArguments(["control", "play", "--device", "2", "--confirm", "CDJ-3000"])
        #expect(
            command
                == .control(
                    CLICommonOptions(),
                    CLIControlRequest(action: .play, deviceId: 2, load: nil, confirm: "CDJ-3000")))
        #expect(throws: CLIUsageError("--slot은 load에만 쓴다", subcommand: .control)) {
            try parseArguments(["control", "pause", "--device", "2", "--slot", "usb", "--confirm", "CDJ-3000"])
        }
    }

    @Test("play and pause only go to players 1-4, which have a slot in the playstate packet")
    func controlPlayPauseDeviceRange() throws {
        for action in ["play", "pause"] {
            for id in [1, 2, 3, 4] {
                #expect(
                    try parseArguments(["control", action, "--device", String(id), "--confirm", "x"]) != .help(nil))
            }
            // 5 이상은 패킷에 칸이 없다. 0과 33은 장치 번호 범위 밖이다.
            for id in [5, 6, 17, 32, 0, 33] {
                #expect(throws: CLIUsageError.self, "\(action) \(id)") {
                    try parseArguments(["control", action, "--device", String(id), "--confirm", "x"])
                }
            }
        }
        do {
            _ = try parseArguments(["control", "pause", "--device", "5", "--confirm", "CDJ-3000"])
            Issue.record("5번이 거부되지 않았다")
        } catch {
            #expect(error.subcommand == .control)
            #expect(error.message.contains("1~4번 플레이어"))
        }
    }

    @Test("the old --unverified-playstate flag is no longer accepted")
    func unverifiedFlagRemoved() {
        for arguments in [
            ["control", "play", "--device", "2", "--confirm", "x", "--unverified-playstate"],
            [
                "control", "load", "--device", "2", "--slot", "usb", "--track-id", "9", "--confirm", "x",
                "--unverified-playstate",
            ],
            ["status", "--unverified-playstate"],
        ] {
            #expect(throws: CLIUsageError.self, "\(arguments)") { try parseArguments(arguments) }
        }
    }

    @Test("metadata, fetch and control take --timeout with a default and a range")
    func timeouts() throws {
        guard
            case .metadata(_, let meta) = try parseArguments([
                "metadata", "--device", "1", "--slot", "usb", "--track-id", "1",
            ])
        else { return }
        #expect(meta.timeoutSeconds == 15)
        guard
            case .metadata(_, let metaLong) = try parseArguments([
                "metadata", "--device", "1", "--slot", "usb", "--track-id", "1", "--timeout", "40",
            ])
        else { return }
        #expect(metaLong.timeoutSeconds == 40)
        guard
            case .fetch(_, let fetch) = try parseArguments([
                "fetch", "--device", "1", "--slot", "usb", "--path", "a", "--out", "o",
            ])
        else { return }
        #expect(fetch.timeoutSeconds == 300)
        guard
            case .fetch(_, let fetchShort) = try parseArguments([
                "fetch", "--device", "1", "--slot", "usb", "--path", "a", "--out", "o", "--timeout=5",
            ])
        else { return }
        #expect(fetchShort.timeoutSeconds == 5)
        guard
            case .control(_, let load) = try parseArguments([
                "control", "load", "--device", "2", "--slot", "usb", "--track-id", "9", "--confirm", "x", "--timeout",
                "30",
            ])
        else { return }
        #expect(load.timeoutSeconds == 30)
        for value in ["0", "3601", "x", ""] {
            #expect(throws: CLIUsageError.self, "\(value)") {
                try parseArguments([
                    "metadata", "--device", "1", "--slot", "usb", "--track-id", "1", "--timeout", value,
                ])
            }
        }
        // 지속 실행 명령에는 제한 시간 옵션이 없다.
        #expect(throws: CLIUsageError("알 수 없는 옵션: --timeout", subcommand: .watch)) {
            try parseArguments(["watch", "--timeout", "5"])
        }
    }

    @Test("control load takes a source, slot and track id")
    func controlLoad() throws {
        let command = try parseArguments([
            "control", "load", "--device", "2", "--slot", "rb", "--track-id", "9", "--source-device", "17",
            "--confirm", "CDJ-3000",
        ])
        #expect(
            command
                == .control(
                    CLICommonOptions(),
                    CLIControlRequest(
                        action: .load, deviceId: 2,
                        load: .init(sourceDeviceId: 17, slot: .rb, trackType: .rb, trackId: 9), confirm: "CDJ-3000")))
        guard
            case .control(_, let request) = try parseArguments([
                "control", "load", "--device", "2", "--slot", "usb", "--track-id", "9", "--track-type", "unanalyzed",
                "--confirm", "x",
            ])
        else {
            Issue.record("control이 아니다")
            return
        }
        #expect(request.load == .init(sourceDeviceId: 2, slot: .usb, trackType: .unanalyzed, trackId: 9))
        #expect(throws: CLIUsageError.self) {
            try parseArguments([
                "control", "load", "--device", "2", "--slot", "usb", "--track-id", "9", "--track-type", "cd",
                "--confirm", "x",
            ])
        }
    }

    @Test("passive requires --iface")
    func passive() throws {
        #expect(try parseArguments(["passive", "--iface", "en7"]) == .passive(iface: "en7", positionIntervalMs: 500))
        #expect(throws: CLIUsageError("--iface이 필요하다", subcommand: .passive)) { try parseArguments(["passive"]) }
        #expect(throws: CLIUsageError.self) { try parseArguments(["passive", "--iface", "en7", "--vcdj-id", "9"]) }
    }

    @Test("network commands report that they touch the network")
    func touchesNetwork() throws {
        #expect(CLICommand.help(nil).touchesNetwork == false)
        #expect(try parseArguments(["devices"]).touchesNetwork)
        #expect(try parseArguments(["passive", "--iface", "en7"]).touchesNetwork)
    }
}
