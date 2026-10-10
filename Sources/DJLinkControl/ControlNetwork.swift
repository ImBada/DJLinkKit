import DJLinkKit

extension ProlinkNetwork {
    /// Get the ``Control`` service. This service can be used to control the
    /// Playstate of CDJs on the network.
    ///
    /// 원본 `get control()`(연결 전에는 null). Control은 DJLinkKit에 기대는 별도 타깃이라 network가 connect 때
    /// 만들 수 없어서, 처음 읽을 때 그 연결의 소켓·가상 장치 참조로 만든다. 같은 연결에서는 같은 Control을 돌려주고,
    /// 다음 connect에서는 새로 만든다.
    public var control: Control? {
        guard let vcdj = connectionDeviceReference else { return nil }
        if let control = extensionServices["DJLinkControl.Control"] as? Control { return control }
        let control = Control(connectionBeatSocket, vcdj, connectionStatusSocket)
        extensionServices["DJLinkControl.Control"] = control
        return control
    }
}
