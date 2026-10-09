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

    public init(
        iface: NetworkInterfaceInfo? = nil, vcdjId: DeviceID? = nil, vcdjName: String? = nil,
        fullStartup: Bool? = nil, announceToStagehand: Bool? = nil,
        databasePreference: DatabasePreference? = nil, logger: (any Logger)? = nil,
        connectMethod: NetworkConnectMethod? = nil
    ) {
        self.iface = iface
        self.vcdjId = vcdjId
        self.vcdjName = vcdjName
        self.fullStartup = fullStartup
        self.announceToStagehand = announceToStagehand
        self.databasePreference = databasePreference
        self.logger = logger
        self.connectMethod = connectMethod
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
    }
}

// 원본의 TypeScript 교차형·형 좁히기는 Swift에서 별도 실행 시점 형을 만들지 않는다.
public typealias ConnectedProlinkNetwork = ProlinkNetwork
