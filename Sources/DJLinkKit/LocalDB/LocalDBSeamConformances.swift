// localdb가 기대는 모양에 1단계 형을 잇는다(원본은 DeviceManager·StatusEmitter를 그대로 받는다).

extension DeviceManager: LocalDBDeviceSource {
    /// 원본 `deviceManager.on(event, handler)`를 이벤트 이름 문자열로 받는다.
    public func on(_ event: String, _ handler: @escaping @DJLinkActor (Device) -> Void) {
        switch event {
        case "connected": on(.connected, handler)
        case "disconnected": on(.disconnected, handler)
        case "announced": on(.announced, handler)
        default: break
        }
    }
}

extension StatusEmitter: LocalDBMediaSlotSource {}
