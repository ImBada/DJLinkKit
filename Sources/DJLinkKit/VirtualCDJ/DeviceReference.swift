// 원본에 없는 형. 원본 network.ts는 가상 CDJ `Device` 객체 하나를 Announcer·StagehandHeartbeat·RemoteDatabase·
// LocalDatabase·Control에 같이 넘기고, Announcer는 번호가 겹치면 그 객체의 `id`를 그 자리에서 바꾼다
// (`this.#vcdj.id = newId`). 모두가 바뀐 번호를 따라가는 것이 원본 동작이다.
// Swift `Device`는 값 형이라 같은 객체를 나눠 쥐는 뜻을 이 참조 형으로 옮긴다.

/// 여러 서비스가 나눠 쥐는 가상 장치(원본에서 같은 `Device` 객체를 가리키는 참조).
///
/// `vcdj.id`, `vcdj.name`처럼 `Device` 칸을 그대로 읽고 쓸 수 있다. 지금 값 전체는 `device`.
@DJLinkActor
@dynamicMemberLookup
public final class DeviceReference {
    /// 지금 장치 값.
    public var device: Device

    public nonisolated init(_ device: Device) {
        self.device = device
    }

    public subscript<T>(dynamicMember keyPath: WritableKeyPath<Device, T>) -> T {
        get { device[keyPath: keyPath] }
        set { device[keyPath: keyPath] = newValue }
    }
}
