extension CDJStatus {
    /// 비트 포트(50001)의 0x28 패킷 한 개. CDJ-2000nexus 실기 캡처로 확인한 필드만 담는다.
    /// 곡 전체의 박 번호나 정밀 재생 위치를 나타내는 값은 아니다.
    public struct BeatState: Equatable, Hashable, Sendable {
        public var deviceId: Int
        /// 피치를 적용하기 전 곡 BPM(0x5a의 u16 / 100).
        public var trackBPM: Double
        /// 패킷의 피치 비율을 백분율로 바꾼 값. 출력 때만 반올림한다.
        public var pitch: Double
        /// 마디 안 비트 번호(1~4).
        public var beatInMeasure: Int

        /// 곡 BPM에 패킷의 피치 비율을 적용한 계산값. 별도로 수신한 필드는 아니다.
        public var effectiveBPM: Double { trackBPM * (1 + pitch / 100) }

        public init(deviceId: Int, trackBPM: Double, pitch: Double, beatInMeasure: Int) {
            self.deviceId = deviceId
            self.trackBPM = trackBPM
            self.pitch = pitch
            self.beatInMeasure = beatInMeasure
        }
    }
}
