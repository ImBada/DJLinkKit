// 원본 src/constants.ts

/// The default virtual CDJ ID to use.
///
/// Out of the 1-6 player range, so it can never collide with a real CDJ.
/// Remotedb metadata still works from here: the 1-6 restriction applies to the
/// device-ID byte inside remotedb messages, which RemoteDatabase picks
/// per-connection independently of the announced ID.
public let DEFAULT_VCDJ_ID = 0x07

/// The port on which devices on the prolink network announce themselves.
public let ANNOUNCE_PORT = 50000

/// The port on which devices on the prolink network send beat timing information.
public let BEAT_PORT = 50001

/// The port on which devices on the prolink network announce themselves.
public let STATUS_PORT = 50002

/// The amount of time in ms between sending each announcement packet.
public let ANNOUNCE_INTERVAL = 1500

/// The interval in ms between startup stage packets (0x0a, 0x00, 0x02, 0x04).
public let STARTUP_STAGE_INTERVAL = 300

/// All UDP packets on the PRO DJ LINK network start with this magic header.
public let PROLINK_HEADER: [UInt8] = [
    0x51, 0x73, 0x70, 0x74, 0x31,
    0x57, 0x6d, 0x4a, 0x4f, 0x4c,
]

/// VirtualCDJName is the name given to the Virtual CDJ device.
public let VIRTUAL_CDJ_NAME = "ProLink-Connect"

/// VirtualCDJFirmware is a string indicating the firmware version reported with
/// status packets.
public let VIRTUAL_CDJ_FIRMWARE = "3.20"

/// CDJs use device IDs 1-6. Devices outside this range (e.g. Stagehand at 154)
/// should not be queried for media slots or databases as they may crash.
public let MIN_CDJ_DEVICE_ID = 1
public let MAX_CDJ_DEVICE_ID = 6
