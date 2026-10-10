public enum NetworkConnectMethod: String, Sendable {
    case active
    case stagehand
}

/// 원본 NetworkConfig와 configure의 Partial<NetworkConfig>를 같은 형으로 받는다.
/// iface가 없는 Stagehand 진입점도 원본처럼 먼저 online 상태로 만들 수 있다.
public struct NetworkConfig: Sendable {
    public var iface: NetworkInterfaceInfo?
    public var vcdjId: DeviceID?
    public var vcdjName: String?
    public var fullStartup: Bool?
    public var announceToStagehand: Bool?
    public var databasePreference: DatabasePreference?
    public var logger: (any Logger)?
    public var connectMethod: NetworkConnectMethod?
    /// CLI 안전을 위한 추가(기본값 nil은 원본 동작: 아무 번호나 쓴다).
    /// 가상 CDJ가 쓸 번호를 허용하는지 정한다. 허용하지 않는 번호는 처음 번호이든 충돌 뒤 다시 고른 번호이든
    /// 그 번호로 announce하기 전에 거부한다.
    public var allowsDeviceId: (@Sendable (DeviceID) -> Bool)?
    /// `allowsDeviceId`가 충돌 뒤 다시 고른 번호를 거부해 announcer가 멈췄을 때 거부한 번호와 함께 한 번 부른다.
    public var onDeviceIdRejected: (@DJLinkActor (DeviceID) -> Void)?
    /// CLI 안전을 위한 추가(기본값 nil은 원본 동작: 발견한 모든 장치에 보낸다).
    /// announcer가 패킷을 보낼 장치만 고른다(예: 선택한 인터페이스의 서브넷 안의 장치).
    public var announceTargetFilter: (@Sendable (Device) -> Bool)?

    public init(
        iface: NetworkInterfaceInfo? = nil, vcdjId: DeviceID? = nil, vcdjName: String? = nil,
        fullStartup: Bool? = nil, announceToStagehand: Bool? = nil,
        databasePreference: DatabasePreference? = nil, logger: (any Logger)? = nil,
        connectMethod: NetworkConnectMethod? = nil,
        allowsDeviceId: (@Sendable (DeviceID) -> Bool)? = nil,
        onDeviceIdRejected: (@DJLinkActor (DeviceID) -> Void)? = nil,
        announceTargetFilter: (@Sendable (Device) -> Bool)? = nil
    ) {
        self.iface = iface
        self.vcdjId = vcdjId
        self.vcdjName = vcdjName
        self.fullStartup = fullStartup
        self.announceToStagehand = announceToStagehand
        self.databasePreference = databasePreference
        self.logger = logger
        self.connectMethod = connectMethod
        self.allowsDeviceId = allowsDeviceId
        self.onDeviceIdRejected = onDeviceIdRejected
        self.announceTargetFilter = announceTargetFilter
    }

    mutating func merge(_ config: NetworkConfig) {
        if let value = config.iface { iface = value }
        if let value = config.vcdjId { vcdjId = value }
        if let value = config.vcdjName { vcdjName = value }
        if let value = config.fullStartup { fullStartup = value }
        if let value = config.announceToStagehand { announceToStagehand = value }
        if let value = config.databasePreference { databasePreference = value }
        if let value = config.logger { logger = value }
        if let value = config.connectMethod { connectMethod = value }
        if let value = config.allowsDeviceId { allowsDeviceId = value }
        if let value = config.onDeviceIdRejected { onDeviceIdRejected = value }
        if let value = config.announceTargetFilter { announceTargetFilter = value }
    }
}

// 원본의 TypeScript 교차형·형 좁히기는 Swift에서 별도 실행 시점 형을 만들지 않는다.
public typealias ConnectedProlinkNetwork = ProlinkNetwork
