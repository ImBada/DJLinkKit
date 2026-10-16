# DJLinkKit

PRO DJ LINK 네트워크를 다루는 Swift 패키지.

- 장치 발견, 가상 CDJ로 네트워크 참여
- CDJ·믹서 상태, 비트, 정밀 위치, on-air
- remotedb·NFS로 메타데이터, 파형, 앨범아트, 음원 파일 받기
- USB DB(PDB·OneLibrary)와 ANLZ 읽기
- mixstatus, 제어 명령, libpcap 패시브 모드
- Mac 라이브러리를 CDJ에 내주는 Link Export 서버

> [!WARNING]
> 실제 장비가 있는 네트워크에 참여하는 라이브러리다. 공연 중인 네트워크에서는 쓰지 말 것. 자세한 내용은 [안전 안내](#안전-안내) 참고.

## 요구 사항

- macOS 15 이상
- Swift 6.2 이상

## 설치

```swift
dependencies: [
    .package(url: "https://github.com/ImBada/DJLinkKit", exact: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "DJLinkKit", package: "DJLinkKit")]),
]
```

SQLCipher는 [SQLCipher.swift](https://github.com/sqlcipher/SQLCipher.swift) 4.19.0 패키지로 받는다. 같은 앱에서 SQLCipher를 쓴다면 자체 `.binaryTarget(name: "SQLCipher", …)`을 두지 말고 이 패키지에 의존한다. 타깃 이름이 겹쳐 SwiftPM이 그래프를 거부한다.

## 사용 예

```swift
import DJLinkKit

@DJLinkActor
func run() async throws {
    let network = try await bringOnline()

    // 처음 보이는 장치로 인터페이스를 고른다. 가상 CDJ 번호는 기본값 7이다.
    try await network.autoconfigFromPeers()
    try network.connect()

    network.statusEmitter?.on(.status) { state in
        guard state.trackId != 0, let db = network.db else { return }
        Task { @DJLinkActor in
            let track = try await db.getMetadata(
                .init(
                    deviceId: state.trackDeviceId, trackSlot: state.trackSlot,
                    trackType: state.trackType, trackId: state.trackId))
            print("deck \(state.deviceId): \(track?.title ?? "-")")
        }
    }
}
```

## 모듈

| 모듈 | 설명 |
|---|---|
| `DJLinkKit` | 핵심 라이브러리. 장치, 가상 CDJ, 상태·위치, remotedb·NFS, localdb, 메타데이터·앨범아트, mixstatus |
| `DJLinkControl` | 곡 올리기, 재생·정지, Stagehand 설정. 장비를 직접 움직이므로 따로 뺐다 |
| `DJLinkPassive` | libpcap으로 듣기만 하는 패시브 모드. BPF 권한이 필요하다 |
| `DJLinkExport` | Link Export 서버. Mac의 곡·메타데이터·분석을 CDJ에 내준다 |
| `djlink` | 실기 확인용 CLI. [docs/cli.md](docs/cli.md) |

## 안전 안내

- 가상 CDJ 번호는 7 이상을 쓴다. 1~6은 실제 플레이어 번호라 겹치면 공연 중인 덱이 영향을 받는다.
- 시험용 스위치에 장비 한두 대만 묶어서 쓴다. 공연이나 리허설 중인 네트워크에서는 돌리지 않는다.
- 같은 Mac에서 rekordbox·rekordboxAgent가 켜져 있으면 쓰지 않는다. UDP 50000~50002를 같이 잡아 rekordbox LINK가 망가질 수 있다.
- `DJLinkExport`는 이 검사를 스스로 하지 않는다. 서버는 17·18번(무선 41번)으로 참여하고 UDP 50000~50002, TCP 12523, portmap 50111, NFS 2049를 연다. 호스트 앱이 rekordbox와 `nfsd`를 끄고 인터페이스를 지정해 띄워야 한다. 자세한 규칙은 [LINK-EXPORT-PLAN.md](docs/LINK-EXPORT-PLAN.md)의 "호스트 안전 규칙".
- macOS 27에서는 `getifaddrs`가 돌려주는 MAC이 `02:00:00:00:00:00`으로 가려진다. 가상 CDJ와 Link Export는 이 값을 그대로 알리므로, 같은 망의 Mac 여러 대가 같은 MAC을 쓰게 된다([#41](https://github.com/ImBada/DJLinkKit/issues/41)).

`djlink` CLI는 위 규칙을 스스로 검사한다. 목록은 [docs/cli.md](docs/cli.md#안전-규칙)에 있다.

## 상태

실기는 CDJ-2000nexus 2대와 DJM-900NXS2로만 확인했다. CDJ-3000, 6채널 믹서, 실제 pcap 캡처는 아직 확인하지 못했다. 확인한 범위는 [PLAN §8](docs/PLAN.md)과 [Link Export 실기 기록](docs/LINK-EXPORT-HARDWARE.md)에 있다.

## 개발

```bash
swift test
```

시험은 실제 소켓을 열지 않고 LAN에 아무것도 보내지 않는다. 루프백 시험과 로컬 CI는 [docs/testing.md](docs/testing.md) 참고.

## 라이선스

[GPL-2.0-or-later](LICENSE). 이 패키지를 링크해 배포하는 프로그램도 GPL 조건을 따라야 한다.

제3자 고지는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), 범위별 저작권은 [COPYRIGHT.md](COPYRIGHT.md), 프로토콜 지식의 출처는 [PROVENANCE.md](PROVENANCE.md)에 있다.

AlphaTheta(Pioneer DJ)와 관계없는 독립 프로젝트다. AlphaTheta, Pioneer DJ, PRO DJ LINK, CDJ, rekordbox는 각 소유자의 상표다.

## Thanks To

DJLinkKit은 Chris Le의 [alphatheta-connect](https://github.com/chrisle/alphatheta-connect)를 Swift로 옮긴 것이다. 함께 쓰는 [onelibrary-connect](https://github.com/chrisle/onelibrary-connect)와 [metadata-connect](https://github.com/chrisle/metadata-connect)도 옮겼다. Link Export 서버는 같은 저자의 [rbxport](https://github.com/chrisle/rbxport)를 옮겼다. 원본 동작을 그대로 옮긴 뒤, 실기에서 찾은 버그 등 일부를 고쳤다. 고정 커밋은 [UPSTREAM.md](UPSTREAM.md)에, 고친 목록은 [PLAN §9](docs/PLAN.md)에 있다.
