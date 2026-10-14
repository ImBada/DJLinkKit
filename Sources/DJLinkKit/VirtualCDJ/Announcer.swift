// 원본 src/virtualcdj/index.ts

/// 원본 `new Uint8Array(iface.mac.split(':').map(s => parseInt(s, 16)))`.
/// `parseInt`가 NaN이면 0, 8비트를 넘으면 잘린다(Uint8Array 변환).
func macBytesFromString(_ mac: String) -> [UInt8] {
    mac.split(separator: ":", omittingEmptySubsequences: false).map { part in
        UInt8(truncatingIfNeeded: jsParseHexInt(String(part)) ?? 0)
    }
}

/// JS `parseInt(string, 16)`. 앞 공백·부호·`0x`를 건너뛰고 읽을 수 있는 16진 숫자까지만 읽는다. 없으면 nil(NaN).
private func jsParseHexInt(_ string: String) -> Int? {
    var scalars = Substring(string).drop { $0.isWhitespace }.unicodeScalars[...]
    var sign = 1
    if let first = scalars.first, first == "+" || first == "-" {
        sign = first == "-" ? -1 : 1
        scalars = scalars.dropFirst()
    }
    if scalars.starts(with: "0x".unicodeScalars) || scalars.starts(with: "0X".unicodeScalars) {
        scalars = scalars.dropFirst(2)
    }
    var value = 0
    var any = false
    for scalar in scalars {
        guard scalar.isASCII, let digit = Int(String(scalar), radix: 16) else { break }
        // 8비트로 자를 것이므로 넘침만 막는다(아래 32비트는 그대로 남는다).
        value = (value &* 16 &+ digit) & 0xffff_ffff
        any = true
    }
    return any ? sign * value : nil
}

/// Constructs a virtual CDJ Device.
///
/// - Parameters:
///   - iface: The network interface to use
///   - id: The device ID to use
///   - name: Optional custom name (defaults to VIRTUAL_CDJ_NAME constant). 원본처럼 nil(undefined)이면 기본값.
/// - Throws: `iface.address`가 IPv4 주소가 아니면 `AddressError`(원본 `new ip.Address4`).
public func getVirtualCDJ(_ iface: NetworkInterfaceInfo, _ id: DeviceID, _ name: String? = nil) throws -> Device {
    Device(
        name: name ?? VIRTUAL_CDJ_NAME,
        id: id,
        type: .cdj,
        macAddr: macBytesFromString(iface.mac),
        ip: try Address4(iface.address)
    )
}

/// Returns a mostly empty-state status packet. This is currently used to report
/// the virtual CDJs status, which *seems* to be required for the CDJ to send
/// metadata about some unanalyzed mp3 files.
public func makeStatusPacket(_ device: Device) -> [UInt8] {
    // NOTE: It seems that byte 0x68 and 0x75 MUST be 1 in order for the CDJ to
    //       correctly report mp3 metadata (again, only for some files).
    //       See https://github.com/brunchboy/dysentery/issues/15
    // NOTE: Byte 0xb6 MUST be 1 in order for the CDJ to not think that our
    //       device is "running an older firmware"
    var b: [UInt8] = [
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
        0x03, 0x00, 0x00, 0xf8, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x04, 0x04, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9c, 0xff, 0xfe, 0x00, 0x10, 0x00, 0x00,
        0x7f, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff,
        0xff, 0xff, 0xff, 0xff, 0x01, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x10, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0f, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]

    // The following items get replaced in this format:
    //
    //  - 0x00: 10 byte header
    //  - 0x0B: 20 byte device name
    //  - 0x21: 01 byte device ID
    //  - 0x24: 01 byte device ID
    //  - 0x7C: 04 byte firmware string

    // PLAN §9: 원본의 형식 주석대로 머리말은 0에, 이름은 0x0b에 쓴다.
    b.set(PROLINK_HEADER, 0)
    b.set([UInt8](device.name, encoding: .ascii), 0x0b)
    b.set([UInt8(truncatingIfNeeded: device.id)], 0x21)
    b.set([UInt8(truncatingIfNeeded: device.id)], 0x24)
    b.set([UInt8](VIRTUAL_CDJ_FIRMWARE, encoding: .ascii), 0x7c)

    return b
}

/// 원본 `Uint8Array.from(parts)`: 각 값을 8비트로 자른다.
private func uint8ArrayFrom(_ parts: [Int]) -> [UInt8] {
    parts.map { UInt8(truncatingIfNeeded: $0) }
}

private func ints(_ bytes: [UInt8]) -> [Int] {
    bytes.map(Int.init)
}

/// constructs the announce packet that is sent on the prolink network to
/// announce a devices existence.
public func makeAnnouncePacket(_ deviceToAnnounce: Device) throws(BufferRangeError) -> [UInt8] {
    let d = deviceToAnnounce

    // unknown padding bytes
    let unknown1 = [0x01, 0x02]
    // Updated on 2024-04-27 to be compatible with CDJ-3000 players that use player number 5 or 6.
    let unknown2 = [0x02, 0x00, 0x00, 0x00]

    // The packet below is constructed in the following format:
    //
    //  - 0x00: 10 byte header
    //  - 0x0A: 02 byte announce packet type
    //  - 0x0c: 20 byte device name
    //  - 0x20: 02 byte unknown
    //  - 0x22: 02 byte packet length
    //  - 0x24: 01 byte for the player ID
    //  - 0x25: 01 byte for the player type
    //  - 0x26: 06 byte mac address
    //  - 0x2C: 04 byte IP address
    //  - 0x30: 04 byte unknown
    //  - 0x34: 01 byte for the player type
    //  - 0x35: 01 byte final padding

    var parts = ints(PROLINK_HEADER)
    parts += [0x06, 0x00]
    parts += ints(try buildName(d))
    parts += unknown1
    parts += [0x00, 0x36]
    parts += [d.id]
    parts += [d.type.rawValue]
    parts += ints(d.macAddr)
    parts += d.ip.toArray()
    parts += unknown2
    parts += [d.type.rawValue]
    // Updated on 2024-04-27 to be compatible with CDJ-3000 players that use player number 5 or 6.
    parts += [0x64]

    return uint8ArrayFrom(parts)
}

/// Startup stages for the full startup protocol.
enum StartupStage: Int {
    /// Initial announcement packets (0x0a)
    case initialAnnounce = 0x0a
    /// First-stage device number claim (0x00)
    case firstStageClaim = 0x00
    /// Second-stage device number claim (0x02)
    case secondStageClaim = 0x02
    /// Final-stage device number claim (0x04)
    case finalStageClaim = 0x04
    /// Keep-alive packets (0x06)
    case keepAlive = 0x06
}

/// Build stage 0x0a packet: Initial announcement (CDJ-3000 compatible).
/// Sent 3 times at 300ms intervals.
func makeStage0aPacket(_ device: Device) throws(BufferRangeError) -> [UInt8] {
    let isHighPlayerNumber = device.id >= 5
    var parts = ints(PROLINK_HEADER)
    parts += [0x0a, 0x00]
    parts += ints(try buildName(device))
    parts += [0x01]
    parts += [isHighPlayerNumber ? 0x04 : 0x02]
    parts += [0x00, isHighPlayerNumber ? 0x26 : 0x25]
    parts += [0x01]

    if isHighPlayerNumber {
        parts.append(0x40)
    }

    return uint8ArrayFrom(parts)
}

/// Build stage 0x00 packet: First-stage device number claim (CDJ-3000 compatible).
/// Sent 3 times at 300ms intervals with counter N (1, 2, 3).
func makeStage00Packet(_ device: Device, _ counter: Int) throws(BufferRangeError) -> [UInt8] {
    let isHighPlayerNumber = device.id >= 5
    var parts = ints(PROLINK_HEADER)
    parts += [0x00, 0x00]
    parts += ints(try buildName(device))
    parts += [0x01]
    parts += [isHighPlayerNumber ? 0x03 : 0x02]
    parts += [0x00, 0x2c]
    parts += [counter]
    parts += [0x01]
    parts += ints(device.macAddr)

    return uint8ArrayFrom(parts)
}

/// Build stage 0x02 packet: Second-stage device number claim (CDJ-3000 compatible).
/// Sent 3 times at 300ms intervals with counter N (1, 2, 3).
func makeStage02Packet(_ device: Device, _ counter: Int) throws(BufferRangeError) -> [UInt8] {
    let isHighPlayerNumber = device.id >= 5
    var parts = ints(PROLINK_HEADER)
    parts += [0x02, 0x00]
    parts += ints(try buildName(device))
    parts += [0x01]
    parts += [isHighPlayerNumber ? 0x03 : 0x02]
    parts += [0x00, 0x32]
    parts += device.ip.toArray()
    parts += ints(device.macAddr)
    parts += [device.id]
    parts += [counter]
    parts += [0x30, 0x01, 0x01]  // auto-assign mode

    return uint8ArrayFrom(parts)
}

/// Build stage 0x04 packet: Final-stage device number claim (CDJ-3000 compatible).
/// Sent 1-3 times at 300ms intervals with counter N.
func makeStage04Packet(_ device: Device, _ counter: Int) throws(BufferRangeError) -> [UInt8] {
    let isHighPlayerNumber = device.id >= 5
    var parts = ints(PROLINK_HEADER)
    parts += [0x04, 0x00]
    parts += ints(try buildName(device))
    parts += [0x01]
    parts += [isHighPlayerNumber ? 0x03 : 0x02]
    parts += [0x00, 0x26]
    parts += [device.id]
    parts += [counter]

    return uint8ArrayFrom(parts)
}

/// Build stage 0x06 packet: Keep-alive (CDJ-3000 compatible).
/// Sent every 1.5s after startup complete.
func makeStage06Packet(_ device: Device, _ peerCount: Int) throws(BufferRangeError) -> [UInt8] {
    let isHighPlayerNumber = device.id >= 5
    var parts = ints(PROLINK_HEADER)
    parts += [0x06, 0x00]
    parts += ints(try buildName(device))
    parts += [0x01, 0x02]
    parts += [0x00, 0x36]
    parts += [device.id]
    parts += [0x01]
    parts += ints(device.macAddr)
    parts += device.ip.toArray()
    // PLAN §9: 원본은 여기에 0x30을 한 바이트 더 넣어 55바이트가 되고 장치 수가 0x31로 밀렸다.
    // CDJ-2000nexus·DJM-900NXS2 실기(2026-10-14)의 0x06은 54바이트이고 0x30이 장치 수다.
    parts += [peerCount]
    parts += [0x00, 0x00, 0x00, 0x01]
    parts += [isHighPlayerNumber ? 0x64 : 0x00]

    return uint8ArrayFrom(parts)
}

/// Check if a packet is a channel conflict (0x08) packet.
/// Returns the conflicting device ID if this is a conflict packet, null otherwise.
func parseConflictPacket(_ packet: [UInt8]) -> Int? {
    // Conflict packets are 0x29 (41) bytes long with packet type 0x08 at byte 0x0a
    if packet.count != 0x29 {
        return nil
    }

    // Check for PROLINK_HEADER
    if !packet.subarray(0, 10).bytesEqual(PROLINK_HEADER) {
        return nil
    }

    // Check packet type byte (0x0a)
    if packet[0x0a] != 0x08 {
        return nil
    }

    // Extract the device ID being defended (byte 0x24)
    return Int(packet[0x24])
}

/// the announcer service is used to report our fake CDJ to the prolink network,
/// as if it was a real CDJ.
@DJLinkActor
public final class Announcer {
    /// The announce socket to use to make the announcements
    private let announceSocket: any UDPSocket
    /// The device manager service used to determine which devices to announce
    /// ourselves to.
    private let deviceManager: DeviceManager
    /// The virtual CDJ device to announce
    ///
    /// 원본은 넘겨받은 `Device` 객체를 그대로 쥐고 번호가 겹치면 `id`를 바꾼다. 그래서 참조 형으로 받는다.
    private let vcdj: DeviceReference
    /// The interval handle used to stop announcing
    private var intervalHandle: TimerHandle?
    /// Whether to use full startup protocol
    private let fullStartup: Bool
    /// Whether to send announcer packets to Pioneer Stagehand devices, which are
    /// normally excluded because they crash on our packets
    private let announceToStagehand: Bool
    /// Current startup stage (only used when fullStartup is enabled)
    private var currentStage: StartupStage = .initialAnnounce
    /// Packet counter within current stage (1, 2, 3)
    private var stageCounter = 0
    /// Listener for incoming conflict packets
    private var conflictListener: SocketListener?
    /// Network interface for the virtual CDJ
    private let iface: NetworkInterfaceInfo
    /// Logger instance for diagnostic output
    private let logger: any Logger
    /// 시작 절차가 끝나거나 번호 정책이 거부할 때 함께 풀 ready 대기자들.
    private var startupWaiters: [CheckedContinuation<Void, Never>] = []
    /// CLI 안전 정책이 거부한 번호. 기본 정책 nil에서는 항상 nil이다.
    public private(set) var rejectedDeviceId: DeviceID?

    private func finishStartupWaiters() {
        let waiters = startupWaiters
        startupWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func reject(_ id: DeviceID) {
        rejectedDeviceId = id
        stop()
        finishStartupWaiters()
        onDeviceIdRejected?(id)
    }

    /// 안전 정책 거부를 오류로 구별하며 startup이 끝날 때까지 기다린다.
    public func waitUntilReady() async throws {
        await ready
        if let rejectedDeviceId { throw DJLinkError("Device ID \(rejectedDeviceId) is not allowed") }
    }
    private let clock: any DJLinkClock
    /// CLI 안전을 위한 추가(기본값 nil은 원본 동작). 허용하지 않는 번호로는 announce하지 않는다.
    private let allowsDeviceId: (@Sendable (DeviceID) -> Bool)?
    /// 충돌 뒤 다시 고른 번호를 `allowsDeviceId`가 거부하면 announcer를 멈춘 뒤 부른다.
    private let onDeviceIdRejected: (@DJLinkActor (DeviceID) -> Void)?
    /// CLI 안전을 위한 추가(기본값 nil은 원본 동작). 패킷을 보낼 장치를 고른다.
    private let announceTargetFilter: (@Sendable (Device) -> Bool)?

    public init(
        _ vcdj: DeviceReference,
        _ announceSocket: any UDPSocket,
        _ deviceManager: DeviceManager,
        _ iface: NetworkInterfaceInfo,
        fullStartup: Bool = false,
        announceToStagehand: Bool = false,
        logger: any Logger = noopLogger,
        clock: any DJLinkClock = SystemClock.shared,
        allowsDeviceId: (@Sendable (DeviceID) -> Bool)? = nil,
        onDeviceIdRejected: (@DJLinkActor (DeviceID) -> Void)? = nil,
        announceTargetFilter: (@Sendable (Device) -> Bool)? = nil
    ) {
        self.allowsDeviceId = allowsDeviceId
        self.onDeviceIdRejected = onDeviceIdRejected
        self.announceTargetFilter = announceTargetFilter
        self.vcdj = vcdj
        self.announceSocket = announceSocket
        self.deviceManager = deviceManager
        self.iface = iface
        self.fullStartup = fullStartup
        self.announceToStagehand = announceToStagehand
        self.logger = logger
        self.clock = clock
    }

    /// Returns a promise that resolves when the startup protocol completes.
    /// Resolves immediately if fullStartup is disabled.
    ///
    /// PLAN §9: 반복해서 읽어도 앞 ready 대기자를 덮어쓰지 않는다.
    public var ready: Void {
        get async {
            if rejectedDeviceId != nil { return }
            if !fullStartup {
                return
            }
            if currentStage == .keepAlive {
                return
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                startupWaiters.append(continuation)
            }
        }
    }

    /// - Throws: 원본처럼 처음 보내는 패킷의 브로드캐스트 주소를 만들지 못하면(`iface` 주소가 틀리면) 던진다.
    public func start() throws {
        // CLI 안전을 위한 추가: 처음 번호도 허용하지 않으면 아무것도 보내지 않는다.
        if let allowsDeviceId, !allowsDeviceId(vcdj.id) {
            reject(vcdj.id)
            throw DJLinkError("Device ID \(vcdj.id) is not allowed")
        }
        armConflictListener()

        if fullStartup {
            try startFullStartup()
        } else {
            try startKeepAlive()
        }
    }

    /// Listen for another device defending the ID we are announcing as.
    ///
    /// The listener stays armed for the announcer's whole life, not just during
    /// startup. A player that powers on after us can claim our ID at any point,
    /// and until it is answered both devices fight over the slot — which is what
    /// knocks a live CDJ off the network.
    private func armConflictListener() {
        if conflictListener != nil {
            return
        }

        conflictListener = announceSocket.onMessage { [weak self] msg, _ in
            guard let self else { return }
            let conflictDeviceId = parseConflictPacket(msg)
            if conflictDeviceId == self.vcdj.id {
                self.logger.warn("Device ID \(self.vcdj.id) is already in use. Finding alternative...")
                // 원본은 소켓 'message' 처리기 안에서 던지면 Node 프로세스가 죽는다. 여기서는 잡고 넘어간다.
                try? self.handleConflict()
            }
        }
    }

    /// Start the full startup protocol with stage progression.
    private func startFullStartup() throws {
        currentStage = .initialAnnounce
        stageCounter = 0

        try sendStagePackets()
    }

    /// Handle a device ID conflict by finding an available ID and restarting.
    private func handleConflict() throws {
        // Stop announcing under the contested ID
        clearTimer()

        // Stay in whichever range we were already in, so a conflict on player 5
        // looks for another free player number first rather than jumping the
        // whole device out of the range the DJ configured it into.
        //
        // The mixer decides which of those numbers are actually safe: a player can
        // only be assigned a number its mixer has a channel for, so anything above
        // that is out of reach of the rig that just contested us.
        let devices = orderedDevices()
        let newId = pickAvailableDeviceId(
            devices.map(\.id),
            PickDeviceIdOptions(
                preferPlayerRange: vcdj.id <= REMOTEDB_MAX_DEVICE_ID,
                playerCeiling: playerNumberCeiling(devices)
            )
        )

        guard let newId else {
            logger.error("No available device IDs. All 32 slots are occupied.")
            stop()
            return
        }

        // CLI 안전을 위한 추가: 허용하지 않는 번호로 옮겨 가지 않는다. 그 번호로 announce하기 전에 멈춘다.
        if let allowsDeviceId, !allowsDeviceId(newId) {
            logger.error("Device ID \(newId) is not allowed. Stopping the announcer.")
            reject(newId)
            return
        }

        logger.info("Switching to device ID \(newId)")

        // Mutate in place rather than building a replacement device. The remotedb,
        // localdb and control services were all handed this same object when the
        // network connected and read `.id` when they build packets, so swapping
        // the reference here would leave us announcing as one ID and querying as
        // another.
        vcdj.id = newId

        // Re-announce under the new ID
        if fullStartup {
            currentStage = .initialAnnounce
            stageCounter = 0
            try sendStagePackets()
        } else {
            try startKeepAlive()
        }
    }

    /// Clear whichever timer is currently driving announcements. Startup stages
    /// use a timeout, keep-alive uses an interval.
    private func clearTimer() {
        if let intervalHandle {
            // 원본은 clearTimeout과 clearInterval을 둘 다 부른다. 손잡이 공간이 하나라 한 번이면 된다.
            clock.clearTimer(intervalHandle)
            self.intervalHandle = nil
        }
    }

    /// 원본 `[...deviceManager.devices.values()]`. 원본 Map은 넣은 순서로 돌지만 Swift 사전은 순서가 없어 id 순으로 돈다.
    private func orderedDevices() -> [Device] {
        deviceManager.devices.sorted { $0.key < $1.key }.map(\.value)
    }

    /// Sends a packet by unicast to every discovered device.
    ///
    /// Pioneer Stagehand is excluded by default (it crashes on our packets)
    /// unless announceToStagehand is enabled.
    ///
    /// When nothing has been discovered yet, falls back to a subnet broadcast —
    /// but only when announceToStagehand is enabled, because a broadcast reaches
    /// every host including Stagehand. In normal operation the virtual CDJ is
    /// found via unicast replies to peers' own announce broadcasts, so skipping
    /// this cold-start broadcast costs nothing.
    private func sendPacket(_ packet: [UInt8]) throws {
        let devices = orderedDevices().filter {
            (announceToStagehand || !$0.name.lowercased().contains("stagehand"))
                && (announceTargetFilter?($0) ?? true)
        }
        for device in devices {
            announceSocket.send(packet, port: ANNOUNCE_PORT, address: device.ip.address)
        }

        // Cold-start discovery broadcast — gated; see the method doc above.
        if devices.isEmpty && announceToStagehand {
            let broadcastAddr = try getBroadcastAddress(iface)
            announceSocket.send(packet, port: ANNOUNCE_PORT, address: broadcastAddr)
        }
    }

    /// Send packets for the current startup stage and progress to next stage.
    private func sendStagePackets() throws {
        stageCounter += 1

        // Build packet for current stage
        let packet: [UInt8]
        switch currentStage {
        case .initialAnnounce:
            packet = try makeStage0aPacket(vcdj.device)
        case .firstStageClaim:
            packet = try makeStage00Packet(vcdj.device, stageCounter)
        case .secondStageClaim:
            packet = try makeStage02Packet(vcdj.device, stageCounter)
        case .finalStageClaim:
            packet = try makeStage04Packet(vcdj.device, stageCounter)
        case .keepAlive:
            // Transition to keep-alive mode
            try startKeepAlive()
            finishStartupWaiters()
            return
        }

        try sendPacket(packet)

        // Progress to next packet or stage
        if stageCounter >= 3 {
            // Move to next stage
            advanceStage()
        }

        // Schedule next packet (300ms for startup stages)
        intervalHandle = clock.setTimeout(.ms(Double(STARTUP_STAGE_INTERVAL))) { [self] in
            // 원본은 타이머 콜백에서 던지면 Node 프로세스가 죽는다. 여기서는 잡고 넘어간다.
            try? sendStagePackets()
        }
    }

    /// Advance to the next startup stage.
    private func advanceStage() {
        stageCounter = 0

        switch currentStage {
        case .initialAnnounce:
            currentStage = .firstStageClaim
        case .firstStageClaim:
            currentStage = .secondStageClaim
        case .secondStageClaim:
            currentStage = .finalStageClaim
        case .finalStageClaim:
            currentStage = .keepAlive
        case .keepAlive:
            break
        }
    }

    /// Start sending keep-alive packets (final stage or when fullStartup is disabled).
    private func startKeepAlive() throws {
        clearTimer()

        let sendKeepAlive = { @DJLinkActor [self] () throws in
            let peerCount = deviceManager.devices.count + 1  // +1 for ourselves
            let packet =
                try fullStartup
                ? makeStage06Packet(vcdj.device, peerCount)
                : makeAnnouncePacket(vcdj.device)

            try sendPacket(packet)
        }

        // Send first keep-alive immediately
        try sendKeepAlive()

        // Then schedule regular keep-alives
        intervalHandle = clock.setInterval(.ms(Double(ANNOUNCE_INTERVAL))) {
            // 원본은 타이머 콜백에서 던지면 Node 프로세스가 죽는다. 여기서는 잡고 넘어간다.
            try? sendKeepAlive()
        }
    }

    public func stop() {
        clearTimer()

        // Remove conflict listener if active
        if let conflictListener {
            announceSocket.off(conflictListener)
            self.conflictListener = nil
        }
    }
}
