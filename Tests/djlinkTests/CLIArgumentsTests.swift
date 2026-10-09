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
        #expect(throws: CLIUsageError("--iface에 값이 없다", subcommand: .watch)) {
            try parseArguments(["watch", "--iface", "--verbose"])
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
