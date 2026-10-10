// 원본 src/virtualcdj/stagehand.ts

public let STAGEHAND_STARTUP_INTERVAL = 305
public let STAGEHAND_KEEP_ALIVE_INTERVAL = 2000

public enum StagehandStartupStage: Int, Sendable {
    case initialAnnounce = 0x0a
    case secondStageClaim = 0x02
    case keepAlive = 0x06
}

/// The protocol-layer MAC a Stagehand device embeds in its 0x02 claim and 0x06
/// keep-alive: the AlphaTheta OUI (c8:3d:fc) followed by the low three bytes of
/// the interface's own MAC.
///
/// This must stay stable for the life of the host. A CDJ-3000 records a peer by
/// the identity in its claim, and once it holds a record for our IP it ignores
/// later claims from the same IP that carry a different MAC or device number:
/// the new peer never receives the unicast status/position stream. Observed on
/// emulated CDJ-3000 firmware 3.20: a freshly randomized identity on every
/// connect() was served once and then never again until the player rebooted,
/// while the previously registered identity kept being served immediately.
public func getStagehandMac(_ iface: NetworkInterfaceInfo) -> [UInt8] {
    let ifaceMac = macBytesFromString(iface.mac)
    return [0xc8, 0x3d, 0xfc] + ifaceMac.subarray(3, 6)
}

/// Generates a random Stagehand device ID in the observed range of 141 to 211.
public func generateStagehandDeviceId() -> Int {
    Int.random(in: 141...211)
}

/// Constructs a virtual Stagehand Device.
///
/// - Parameters:
///   - iface: The network interface to use
///   - id: The device ID to use (defaults to random Stagehand ID)
///   - name: The device name (defaults to 'Stagehand'). 원본처럼 nil(undefined)이면 기본값.
///   - macAddr: The protocol-layer MAC (defaults to one derived from iface)
/// - Throws: `iface.address`가 IPv4 주소가 아니면 `AddressError`(원본 `new ip.Address4`).
public func getVirtualStagehand(
    _ iface: NetworkInterfaceInfo,
    _ id: DeviceID? = nil,
    _ name: String? = nil,
    _ macAddr: [UInt8]? = nil
) throws -> Device {
    let id = id ?? generateStagehandDeviceId()
    let name = name ?? "Stagehand"
    let macAddr = macAddr ?? getStagehandMac(iface)
    return Device(
        name: name,
        id: id,
        type: .stagehand,
        macAddr: macAddr,
        ip: try Address4(iface.address)
    )
}

private func ints(_ bytes: [UInt8]) -> [Int] {
    bytes.map(Int.init)
}

/// 원본 `Uint8Array.from(parts)`: 각 값을 8비트로 자른다.
private func uint8ArrayFrom(_ parts: [Int]) -> [UInt8] {
    parts.map { UInt8(truncatingIfNeeded: $0) }
}

/// Build Stagehand stage 0x0a packet: Initial announcement.
/// Sent 3 times at 305ms intervals.
public func makeStagehand0aPacket(_ device: Device) throws(BufferRangeError) -> [UInt8] {
    var parts = ints(PROLINK_HEADER)  // 10 bytes
    parts += [0x0a, 0x00]  // 2 bytes packet type (0x0a)
    parts += ints(try buildName(device))  // 20 bytes device name
    parts += [0x01, 0x03]  // 2 bytes protocol / structure bytes
    parts += [0x00, 0x25]  // 2 bytes packet length (37)
    parts += [DeviceType.stagehand.rawValue]  // 1 byte device type (0x05)
    return uint8ArrayFrom(parts)
}

/// Build Stagehand stage 0x02 packet: Second-stage device number claim.
/// Sent 3 times at 305ms intervals with counter N (1, 2, 3).
public func makeStagehand02Packet(_ device: Device, _ mac: [UInt8], _ counter: Int) throws(BufferRangeError) -> [UInt8] {
    var parts = ints(PROLINK_HEADER)  // 10 bytes
    parts += [0x02, 0x00]  // 2 bytes packet type (0x02)
    parts += ints(try buildName(device))  // 20 bytes device name
    parts += [0x01, 0x03]  // 2 bytes protocol / structure bytes
    parts += [0x00, 0x32]  // 2 bytes packet length (50)
    parts += device.ip.toArray()  // 4 bytes IP
    parts += ints(mac)  // 6 bytes identifier
    parts += [0x3a]  // 1 byte constant
    parts += [counter]  // 1 byte counter
    parts += [DeviceType.stagehand.rawValue]  // 1 byte device type (0x05)
    parts += [0x01]  // 1 byte constant
    return uint8ArrayFrom(parts)
}

/// Build Stagehand stage 0x06 packet: Keep-alive.
/// Sent every 2.0s after startup complete.
public func makeStagehand06Packet(_ device: Device, _ mac: [UInt8]) throws(BufferRangeError) -> [UInt8] {
    var parts = ints(PROLINK_HEADER)  // 10 bytes
    parts += [0x06, 0x00]  // 2 bytes packet type (0x06)
    parts += ints(try buildName(device))  // 20 bytes device name
    parts += [0x01, 0x03]  // 2 bytes protocol / structure bytes
    parts += [0x00, 0x36]  // 2 bytes packet length (54)
    parts += [device.id]  // 1 byte device number
    parts += [0x01]  // 1 byte constant
    parts += ints(mac)  // 6 bytes identifier
    parts += device.ip.toArray()  // 4 bytes IP
    parts += [0x01, 0x00, 0x00, 0x00]  // 4 bytes constant
    parts += [DeviceType.stagehand.rawValue]  // 1 byte device-type (0x05)
    parts += [0x20]  // 1 byte trailing byte
    return uint8ArrayFrom(parts)
}

@DJLinkActor
public final class StagehandAnnouncer {
    private let announceSocket: any UDPSocket
    /// 원본처럼 network가 넘긴 가상 장치 객체를 같이 쥔다(``DeviceReference``).
    private let vcdj: DeviceReference
    private var intervalHandle: TimerHandle?
    private var currentStage: StagehandStartupStage = .initialAnnounce
    private var stageCounter = 0
    private let iface: NetworkInterfaceInfo
    private let logger: any Logger
    private var onStartupComplete: (@DJLinkActor () -> Void)?
    private let mac: [UInt8]
    private let clock: any DJLinkClock

    /// `deviceManager`는 원본처럼 받기만 하고 쓰지 않는다.
    public init(
        _ vcdj: DeviceReference,
        _ announceSocket: any UDPSocket,
        _ deviceManager: DeviceManager,
        _ iface: NetworkInterfaceInfo,
        logger: any Logger = noopLogger,
        clock: any DJLinkClock = SystemClock.shared
    ) {
        self.vcdj = vcdj
        self.announceSocket = announceSocket
        self.iface = iface
        self.logger = logger
        self.mac = vcdj.device.macAddr
        self.clock = clock
    }

    /// 원본 getter처럼 부를 때마다 기다리는 쪽을 새로 걸고 앞의 것을 덮어쓴다(마지막 것만 풀린다).
    public var ready: Void {
        get async {
            if currentStage == .keepAlive {
                return
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                onStartupComplete = { continuation.resume() }
            }
        }
    }

    /// - Throws: 원본처럼 `iface`로 브로드캐스트 주소를 만들지 못하면 던진다.
    public func start() throws {
        logger.info("Starting Stagehand announcer: device name \"\(vcdj.name)\", ID \(vcdj.id)")
        try startStartup()
    }

    private func startStartup() throws {
        currentStage = .initialAnnounce
        stageCounter = 0
        try sendStagePackets()
    }

    private func sendPacket(_ packet: [UInt8]) throws {
        let broadcastAddr = try getBroadcastAddress(iface)
        announceSocket.send(packet, port: ANNOUNCE_PORT, address: broadcastAddr)
    }

    private func sendStagePackets() throws {
        stageCounter += 1

        let packet: [UInt8]
        switch currentStage {
        case .initialAnnounce:
            packet = try makeStagehand0aPacket(vcdj.device)
            logger.debug("Stagehand sending stage 0x0a (announce) packet \(stageCounter)/3")
        case .secondStageClaim:
            packet = try makeStagehand02Packet(vcdj.device, mac, stageCounter)
            logger.debug("Stagehand sending stage 0x02 (claim) packet \(stageCounter)/3")
        case .keepAlive:
            logger.info("Stagehand join sequence complete, transitioning to keep-alive")
            try startKeepAlive()
            onStartupComplete?()
            onStartupComplete = nil
            return
        }

        try sendPacket(packet)

        if stageCounter >= 3 {
            advanceStage()
        }

        intervalHandle = clock.setTimeout(.ms(Double(STAGEHAND_STARTUP_INTERVAL))) { [self] in
            // 원본은 타이머 콜백에서 던지면 Node 프로세스가 죽는다. 여기서는 잡고 넘어간다.
            try? sendStagePackets()
        }
    }

    private func advanceStage() {
        stageCounter = 0

        switch currentStage {
        case .initialAnnounce:
            currentStage = .secondStageClaim
        case .secondStageClaim:
            currentStage = .keepAlive
        case .keepAlive:
            break
        }
    }

    private func startKeepAlive() throws {
        if let intervalHandle {
            clock.clearTimeout(intervalHandle)
            self.intervalHandle = nil
        }

        let sendKeepAlive = { @DJLinkActor [self] () throws in
            let packet = try makeStagehand06Packet(vcdj.device, mac)
            logger.debug("Stagehand sending keep-alive packet")
            try sendPacket(packet)
        }

        try sendKeepAlive()

        intervalHandle = clock.setInterval(.ms(Double(STAGEHAND_KEEP_ALIVE_INTERVAL))) {
            // 원본은 타이머 콜백에서 던지면 Node 프로세스가 죽는다. 여기서는 잡고 넘어간다.
            try? sendKeepAlive()
        }
    }

    public func stop() {
        logger.info("Stopping Stagehand announcer")
        if let intervalHandle {
            // 원본은 clearInterval과 clearTimeout을 둘 다 부른다. 손잡이 공간이 하나라 한 번이면 된다.
            clock.clearTimer(intervalHandle)
            self.intervalHandle = nil
        }
    }
}
