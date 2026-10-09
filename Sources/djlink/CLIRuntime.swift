import DJLinkKit
import DJLinkPassive
import Foundation

// 실행에 필요한 바깥 세계(소켓·인터페이스·시계·파일·NFS·패시브 캡처)를 한 묶음으로 주입한다.
// 실제 실행은 `CLIRuntime.live`, 시험은 가짜(FakeSocketFactory·FakeInterfaceProvider·TestClock 등)를 넣는다.

/// 장치 알림을 기다리는 기본 시간(초).
let discoveryTimeoutSeconds = 30
/// 대상 장치가 보일 때까지 기다리는 시간(초).
let deviceWaitSeconds = 10

/// `--iface` 이름으로 IPv4 외부 주소를 고른다.
func selectInterface(
    named name: String, in interfaces: [(name: String, addresses: [NetworkInterfaceInfo])]
) -> NetworkInterfaceInfo? {
    interfaces.first { $0.name == name }?.addresses.first { $0.family == "IPv4" && !$0.internal }
}

/// 고를 수 있는 인터페이스 이름 목록(오류 안내용).
func candidateInterfaceNames(_ interfaces: [(name: String, addresses: [NetworkInterfaceInfo])]) -> [String] {
    interfaces.filter { $0.addresses.contains { $0.family == "IPv4" && !$0.internal } }.map(\.name)
}

/// NFS 읽기. 실제는 `DJLinkKit`의 NFS 함수, 시험은 가짜.
protocol CLINFS: Sendable {
    @DJLinkActor
    func fetchFile(
        device: Device, slot: MediaSlot, path: String, onProgress: (@DJLinkActor (FetchProgress) -> Void)?,
        chunkSize: Int?
    ) async throws -> [UInt8]

    @DJLinkActor
    func fetchFileRange(device: Device, slot: MediaSlot, path: String, offset: Int, length: Int) async throws -> [UInt8]

    @DJLinkActor
    func fileSize(device: Device, slot: MediaSlot, path: String) async throws -> Int
}

struct LiveCLINFS: CLINFS {
    init() {}

    @DJLinkActor
    func fetchFile(
        device: Device, slot: MediaSlot, path: String, onProgress: (@DJLinkActor (FetchProgress) -> Void)?,
        chunkSize: Int?
    ) async throws -> [UInt8] {
        try await DJLinkKit.fetchFile(
            device: device, slot: slot, path: path, onProgress: onProgress, chunkSize: chunkSize)
    }

    @DJLinkActor
    func fetchFileRange(device: Device, slot: MediaSlot, path: String, offset: Int, length: Int) async throws -> [UInt8]
    {
        try await DJLinkKit.fetchFileRange(device: device, slot: slot, path: path, offset: offset, length: length)
    }

    @DJLinkActor
    func fileSize(device: Device, slot: MediaSlot, path: String) async throws -> Int {
        try await DJLinkKit.getFileInfo(device: device, slot: slot, path: path).size
    }
}

@DJLinkActor
struct CLIRuntime {
    var socketFactory: any SocketFactory
    var interfaceProvider: any InterfaceProvider
    var clock: any DJLinkClock
    var files: any CLIFileWriter
    var nfs: any CLINFS
    /// 패시브 캡처 네트워크를 만든다(아직 시작하지 않는다). 시험은 가짜 `PcapBackend`를 넣는다.
    var makePassiveNetwork: @DJLinkActor (PassiveNetworkConfig) -> PassiveProlinkNetwork
    /// 한 번의 실행이 쓰는 중단 토큰. 시험은 자기가 쥔 토큰을 돌려줘서 원하는 때 중단한다.
    var makeAbort: @DJLinkActor () -> CLIAbort
    /// SIGINT·SIGTERM을 받아 중단 토큰을 세운다. 시험에서는 끈다.
    var installsSignalHandlers: Bool
    /// NFS 모듈의 전역 설정(소켓 공장·경로 검사)을 이 실행 동안 바꾼다. 전역이라 시험에서는 끈다.
    var configuresNFSGlobals: Bool

    static var live: CLIRuntime {
        CLIRuntime(
            socketFactory: LiveSocketFactory.shared, interfaceProvider: SystemInterfaceProvider(),
            clock: SystemClock.shared, files: POSIXFileWriter(), nfs: LiveCLINFS(),
            makePassiveNetwork: { PassiveProlinkNetwork($0) }, makeAbort: { CLIAbort() },
            installsSignalHandlers: true, configuresNFSGlobals: true)
    }
}

/// 소켓을 묶고 대화를 제한하는 인터페이스 하나. 이 서브넷 밖의 장치와는 보내지도 연결하지도 않는다.
struct CLINetworkScope: Equatable, Sendable {
    var name: String
    var info: NetworkInterfaceInfo
    var subnet: Address4

    init(name: String, info: NetworkInterfaceInfo) throws {
        self.name = name
        self.info = info
        self.subnet = try Self.subnet(of: info)
    }

    private static func subnet(of info: NetworkInterfaceInfo) throws -> Address4 {
        do {
            if let cidr = info.cidr { return try Address4(cidr) }
            // cidr이 없으면 넷마스크에서 접두 길이를 구한다.
            let prefix = try Address4(info.netmask).integerValue.nonzeroBitCount
            return try Address4("\(info.address)/\(prefix)")
        } catch {
            throw CLIRuntimeError("인터페이스 \(info.address)의 서브넷을 알 수 없다: \(error)")
        }
    }

    func contains(_ ip: Address4) -> Bool { ip.isInSubnet(subnet) }

    func contains(_ device: Device) -> Bool { contains(device.ip) }

    var description: String { "\(name) (\(subnet.address))" }
}
