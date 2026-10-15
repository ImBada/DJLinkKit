# DJLinkKit(가칭) — alphatheta-connect Swift 포팅 계획

작성 2026-10-10. TypeScript 라이브러리 alphatheta-connect를 Swift 패키지로 1:1 옮긴다. 원본 시험은 입력과 기대값을 그대로 둔 채 하나씩 옮겨 모두 통과시킨다. 다 옮긴 뒤 DJCrate가 이 패키지를 불러 쓴다(§13).

## 1. 목표와 범위

**목표**

- 원본의 공개 동작을 Swift로 똑같이 옮긴다. 대상은 다음과 같다.
  - 장치 발견, 가상 CDJ로 참여·번호 정하기
  - CDJ·믹서 상태, 정밀 위치, on-air
  - remotedb로 메타데이터·파형·그리드·큐·재생 목록 받기
  - NFS로 파일 받기, USB DB(`export.pdb`·`exportLibrary.db`)와 ANLZ 읽기
  - 앨범아트·태그, mixstatus, 제어 명령, 패시브(pcap) 모드, CLI
- 원본 시험 531개(41개 파일)를 하나씩 옮겨 모두 통과시킨다. 원본 저장소에 기대고 있는 두 저장소의 시험도 함께 옮긴다(§2).
- 펌웨어 분석에 근거한 원본 지식도 옮긴다(§10).

**범위 밖**

- `src/remote/`(HTTP 서버·Hue 조명)와 `src/utils/telemetry.ts`의 Sentry 보고. 원본 시험이 0개라 시험 수는 줄지 않는다. telemetry를 부르는 자리는 아무것도 하지 않는 함수로 둔다.
- CDJ에 라이브러리를 내주는 쪽(Link Export 서버)은 이 TypeScript 원본 포트의 범위 밖이다. 사용자의 추가 요청으로 rbxport를 원본으로 한 [별도 서버 이식 단계](LINK-EXPORT-PLAN.md)를 진행한다.
- 1:1을 마치기 전에 기능을 더하거나 버그를 고치는 일(§9).

## 2. 원본 (고정 커밋)

| 저장소 | 커밋 | 라이선스 | 쓰는 부분 |
|---|---|---|---|
| [chrisle/alphatheta-connect](https://github.com/chrisle/alphatheta-connect) | `7496991` (v0.28.5, 2026-10-04) | MIT, Copyright (c) 2013 Evan Purkhiser | 범위 밖을 뺀 전부 |
| [chrisle/onelibrary-connect](https://github.com/chrisle/onelibrary-connect) | `ac3edd3` (2026-09-26) | MIT | `getEncryptionKey`, `OneLibraryAdapter`, `openOneLibraryDb`과 형들. 시험 1개 파일 |
| [chrisle/metadata-connect](https://github.com/chrisle/metadata-connect) | `c2ae262` (2026-09-08) | MIT | `extractMetadata`, `isExtensionSupported`, `FileReader`(부분 읽기). 시험 2개 파일 |

- alphatheta-connect는 두 저장소를 `file:../`로 불러온다. 그래서 세 저장소를 같은 부모 폴더 아래에 나란히 받는다(예: `~/src/upstream/`).
- 받은 원본은 읽기만 한다. 그 안에서 npm이나 스크립트를 돌리지 않는다. 원본 시험을 실제로 돌려 기대값을 확인할 일이 생기면 그때 따로 정한다.

## 3. 결정 사항 (기본값, 바꿀 수 있음)

| 항목 | 기본값 | 이유 |
|---|---|---|
| 패키지 이름 | 가칭 `DJLinkKit` | AlphaTheta·PRO DJ LINK는 상표라서 이름에 넣지 않는다. README에 "PRO DJ LINK 호환, AlphaTheta와 관계없는 독립 프로젝트"라고 고지한다 |
| 플랫폼 | macOS 15 이상, swift-tools 6.2, Swift 6 언어 모드(엄격 동시성) | macOS 15부터 로컬 네트워크 권한이 생겼다. Linux는 지원하지 않는다 |
| localdb | 1:1로 옮긴다(원본 시험 234개) | kaitai `.ksy`(EPL-1.0)는 옮기지 않는다. 파서는 같은 저작자의 MIT 코드인 DJCrate 리더를 출발점으로 쓴다(§7) |
| control | 옮긴다. 별도 product `DJLinkControl` | 공연 중인 장비를 움직이는 기능이다. 쓰는 쪽이 골라서 넣게 한다 |
| passive | 옮긴다. 별도 product `DJLinkPassive`, 마지막 단계 | libpcap과 BPF 권한이 필요하다 |
| CLI | `djlink` 실행 파일로 옮긴다 | 실기 확인에 쓴다 |
| 시험 실행 시점 | 단계마다 시험과 코드를 옮긴 뒤, 사용자가 "구현 완료"라고 하면 그 단계 시험을 돌린다 | 사용자의 작업 방식 |

## 4. "1:1"의 뜻

**같아야 하는 것**

- 공개 API의 이름·인자·결과. Swift 관례에 맞춘 이름 변환만 허용한다(§6).
- 보내는 패킷의 바이트와, 받은 패킷을 읽은 결과.
- 시간 상수와 상태가 바뀌는 순서. 예를 들면 다음과 같다.
  - keep-alive 1.5초
  - 시작 패킷 300ms 간격으로 3번
  - 10초 동안 소식이 없으면 장치가 끊긴 것으로 본다
  - remotedb 접속과 미디어 슬롯 응답의 제한 시간 10초
  - NFS는 1초 기다린 뒤 다시 보낸다
- 원본 시험의 입력과 기대값. 원본의 버그도 그대로 옮긴다(§9).

**달라도 되는 것**

- 시험을 준비하는 코드. `jest.mock`과 가짜 타이머는 주입한 가짜로 바꾼다(§6).
- Node 전용 의존성의 내부 구현(§6).
- 내부 자료 구조. 예를 들어 메모리 SQLite ORM은 시험이 보는 결과만 같으면 다르게 만들어도 된다.

**시험 대응 규칙**

- 원본 파일 하나는 Swift 시험 파일 하나로 옮긴다.
- 원본 `describe`는 `@Suite`로, `it('문구')`는 `@Test("문구")`로 옮긴다. 문구는 원본 영어 그대로 둔다.
- 원본에 `it.each`·`describe.each`는 없다(고정 커밋 기준).

## 5. 구조

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DJLinkKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DJLinkKit", targets: ["DJLinkKit"]),
        .library(name: "DJLinkControl", targets: ["DJLinkControl"]),
        .library(name: "DJLinkPassive", targets: ["DJLinkPassive"]),
        .executable(name: "djlink", targets: ["djlink"]),
    ],
    dependencies: [
        // SQLCipher: §7 참고
    ],
    targets: [
        .target(name: "DJLinkKit", dependencies: [/* SQLCipher */]),
        .target(name: "DJLinkControl", dependencies: ["DJLinkKit"]),
        .systemLibrary(name: "CPcap"),  // module.modulemap에서 link "pcap"
        .target(name: "DJLinkPassive", dependencies: ["DJLinkKit", "CPcap"]),
        .executableTarget(name: "djlink", dependencies: ["DJLinkKit", "DJLinkControl"]),
        .target(name: "DJLinkTestSupport", dependencies: ["DJLinkKit"]),
        .testTarget(name: "DJLinkKitTests", dependencies: ["DJLinkKit", "DJLinkTestSupport"], resources: [.copy("Fixtures")]),
        .testTarget(name: "DJLinkControlTests", dependencies: ["DJLinkControl", "DJLinkTestSupport"]),
        .testTarget(name: "DJLinkPassiveTests", dependencies: ["DJLinkPassive", "DJLinkTestSupport"]),
    ]
)
```

타깃 사이에서만 보여야 하는 내부 API는 `package` 접근 수준으로 둔다.

| 원본 | Swift |
|---|---|
| `src/constants.ts`, `types.ts`, `entities.ts`, `index.ts`, `network.ts`, `logger.ts` | `Sources/DJLinkKit/` 바로 아래 |
| `src/utils/` (`udp.ts` 포함) | `Sources/DJLinkKit/Utils/`, `Sources/DJLinkKit/Socket/` |
| `src/devices/` | `Sources/DJLinkKit/Devices/` |
| `src/status/` | `Sources/DJLinkKit/Status/` |
| `src/virtualcdj/` | `Sources/DJLinkKit/VirtualCDJ/` |
| `src/remotedb/` | `Sources/DJLinkKit/RemoteDB/` |
| `src/nfs/` | `Sources/DJLinkKit/NFS/` |
| `src/localdb/`, onelibrary-connect | `Sources/DJLinkKit/LocalDB/`, `Sources/DJLinkKit/LocalDB/OneLibrary/` |
| `src/db/` | `Sources/DJLinkKit/DB/` |
| `src/artwork/`, `src/metadata.ts`, metadata-connect | `Sources/DJLinkKit/Artwork/`, `Sources/DJLinkKit/Metadata/` |
| `src/mixstatus/` | `Sources/DJLinkKit/MixStatus/` |
| `src/control/` | `Sources/DJLinkControl/` |
| `src/passive/` | `Sources/DJLinkPassive/` |
| `src/cli/` | `Sources/djlink/` |
| `src/remote/`, `src/utils/telemetry.ts` | 옮기지 않음. telemetry는 아무것도 하지 않는 함수로 |

파일 단위 대응표는 0단계에서 `docs/port-map.md`로 만든다. 칸은 원본 파일, Swift 파일, 상태(안 함/옮김/통과)다.

## 6. Node → Swift 바꿈표

| 원본 | Swift | 시험에서 |
|---|---|---|
| `dgram`(UDP) | `UDPSocket` 프로토콜. 실제 구현은 BSD 소켓과 DispatchSource로, `SO_REUSEADDR`·`SO_BROADCAST`를 켜고 `0.0.0.0`에 바인드한다. Network.framework는 브로드캐스트를 지원하지 않아 쓰지 않는다 | `FakeUDPSocket`: 보낸 바이트를 기록하고, 받은 패킷을 주입한다 |
| `net`·`promise-socket`(TCP) | `TCPConnection` 프로토콜. 실제 구현은 `NWConnection` | `FakeTCPConnection`: 정해 둔 순서대로 주고받는다 |
| `setTimeout`·`setInterval`, jest 가짜 타이머(6개 파일) | `any Clock<Duration>`을 주입한다 | 직접 만든 `TestClock`(`advance(by:)`) |
| `EventEmitter`, `strict-event-emitter-types` | 구독자 여럿에게 나눠 주는 `EventHub<Event>`(AsyncStream 기반) | 그대로 |
| `os.networkInterfaces` | `InterfaceProvider`(`getifaddrs`) | 가짜 |
| `child_process`(`ioreg`·`networksetup`·`arp`) | `getifaddrs`(AF_LINK)와 sysctl로 같은 값을 얻는다 | 가짜 |
| `fs`, `path` | `FileManager`. mock하는 시험 1개 파일은 `FileSystem` 프로토콜로 | 임시 폴더 |
| `crypto.createHash` | CryptoKit | |
| `async-mutex` | actor | |
| `promise-retry`, `promise-timeout` | `withRetry`·`withTimeout(clock:)` 도우미 | `TestClock` |
| `lru_map` | 작은 `LRUCache` | |
| `js-xdr` | XDR 인코더·디코더를 직접 구현 | |
| `iconv-lite` | `String.Encoding`(UTF-16BE·LE 등) | |
| `ip-address` | `IPv4Address`·`IPv4CIDR`를 직접 구현 | |
| `lodash` | 표준 라이브러리 | |
| `kaitai-struct`와 `.ksy`(EPL-1.0) | 옮기지 않는다. DJCrate 리더를 옮겨 쓴다(§7) | |
| `better-sqlite3-multiple-ciphers` | 메모리 ORM은 SQLite로, OneLibrary는 SQLCipher로 | 픽스처 DB |
| `signale`(logger) | `os.Logger` | |
| `jest.mock`(모듈 바꿔치기, 11개 파일) | 위에서 프로토콜로 주입한 자리에 가짜를 넣는다 | |

원본 테스트가 mock하는 모듈은 `onelibrary-connect`(5), `src/localdb/rekordbox`(4), `src/localdb`(4), `os`(2)와, 한 번씩 쓰는 telemetry·remotedb·nfs·hydrator·orm·anlz ksy·devices/utils·db·kaitai-struct·fs·child_process다. 괄호 안은 그 모듈을 mock하는 시험 파일 수다.

## 7. localdb와 DJCrate 리더

**원본 구조**

- kaitai로 `export.pdb`와 ANLZ를 읽어 메모리 SQLite(`MetadataORM`)에 채우고, 그 위에서 질의한다.
- OneLibrary는 onelibrary-connect로 SQLCipher DB를 연다.

**옮기는 방법**

- kaitai `.ksy` 2개(Deep Symmetry crate-digger 출신, EPL-1.0)는 쓰지 않는다.
- 대신 DJCrate(MIT, 같은 저작자)의 리더를 옮겨 출발점으로 삼는다.
  - `Sources/RekordboxKit/Usb/DeviceLibrary/`: `PdbFile`·`PdbReader`·`PdbRows`
  - `Sources/RekordboxKit/Usb/OneLibrary/`(`OneLibraryReader`), `Sources/RekordboxKit/CipherDatabase.swift`
  - `Sources/RekordboxKit/AnlzFile.swift`, `Anlz*.swift`, `Usb/Anlz/`(큐·마스크·경로 태그)
  - DJCrate THIRD_PARTY_NOTICES에서 이 리더들에 해당하는 항목도 같이 옮긴다: pyrekordbox·baken·rekordbox_converter(MIT), 칸 위치만 참고한 rekordcrate(MPL-2.0)·Crate Digger 문서(EPL-2.0).
- 이 리더 위에 원본 localdb의 바깥 모양을 그대로 만든다. 맞춰야 할 것은 형, 필드 이름, 빈 값 처리, 2EX, 노래 구조, 보컬 설정이다.
- DJCrate 리더와 원본 시험의 결과가 다르면 원본 시험이 정답이다(1:1).
- `CipherDatabase`를 옮기면 DJCrate의 cold-open 경쟁 시험도 같이 옮긴다. SQLCipher 초기화 경쟁은 DJCrate에서 실제로 겪은 문제다.

**SQLCipher**

- DJCrate는 지금 `binaryTarget`으로 `SQLCipher.xcframework` 4.19.0을 직접 선언한다. 이 패키지도 같은 이름의 타깃을 선언하면, DJCrate에 붙일 때 서로 부딪친다.
- 그래서 이 패키지는 [SQLCipher.swift](https://github.com/sqlcipher/SQLCipher.swift) 패키지에 의존한다(4.19.0). DJCrate도 붙일 때 같은 패키지 의존으로 바꾼다.
- 그 패키지가 SPM product를 내주는지는 0단계에서 확인한다.

**픽스처**

- 원본의 `tests/localdb/fixtures/test-onelibrary.db`는 들여오기 전에 열어서 개인 데이터와 토큰이 없는지 본다. 공개 저장소이기 때문이다.

## 8. 단계

각 단계는 이 순서로 진행한다.

1. 원본 시험을 옮긴다.
2. 원본 코드를 옮긴다.
3. 사용자가 "구현 완료"라고 하면 그 단계와 앞 단계의 시험을 돌린다.
4. 끝 조건을 확인한다.

**끝 조건**(모든 단계 공통)

- `scripts/port-status.sh`에서 원본 `it(` 수와 옮긴 `@Test` 수가 같다.
- 그 단계와 앞 단계의 시험이 모두 통과한다.
- 실제 소켓을 연 시험이 0개다.

| 단계 | 원본 | 원본 시험(파일: 개수) | 합 |
|---|---|---|---|
| 0 뼈대 | — | — | 0 |
| 1 기초·상태 | `constants`·`types`·`entities`, `utils/`, `devices/`, `status/` | `tests/utils/index` 8, `tests/devices/index` 7, `tests/devices/utils` 3, `tests/status/utils` 14, `tests/status/position` 7, `tests/status/on-air` 8, `src/status/stagehand-gating` 2 | 49 |
| 2 가상 CDJ·네트워크 | `virtualcdj/`, `network.ts`, `index.ts` | `src/virtualcdj/heartbeat` 7, `tests/virtualcdj/conflict` 11, `device-id` 25, `stagehand` 8, `startup` 23, `wire-selection` 8, `tests/network/stagehand-identity` 2 | 84 |
| 3 remotedb·NFS | `remotedb/`, `nfs/` | `tests/remotedb/connection` 4, `fields` 13, `src/nfs/index` 16, `tests/nfs/path` 14 | 47 |
| 4 localdb | `localdb/`, onelibrary-connect | `tests/localdb/`: `anlz-2ex-integration` 20, `anlz-parsers-2ex` 18, `anlz-parsers-cue-nulls` 2, `anlz-parsers-cues` 3, `anlz-parsers-extended-cues` 5, `anlz-parsers-song-structure` 5, `anlz-parsing` 31, `database-fallback` 12, `database-loading` 22, `edge-cases` 44, `load-anlz-vocal-config` 10, `onelibrary-adapter` 62. 여기에 onelibrary-connect 시험 1개 파일 | 234 + α |
| 5 db·앨범아트·태그 | `db/`, `artwork/`, `metadata.ts`, metadata-connect | `tests/db/blankMetadata` 4, `getMetadata` 13, `getPlaylist` 3, `getWaveforms` 8, `tests/artwork/extraction.integration` 5, `parsers` 13. 여기에 metadata-connect 시험 2개 파일 | 46 + α |
| 6 mixstatus | `mixstatus/` | `tests/mixstatus/index` 29 | 29 |
| 7 제어 | `control/` | `tests/control/load` 2, `stagehand` 9 | 11 |
| 8 패시브 | `passive/` | `tests/passive/alphatheta` 22, `pcap-adapter` 9 | 31 |
| 9 CLI·실기 확인 | `cli/` | — | 0 |
| 합 | | 41개 파일 | 531 + α |

**0단계 할 일**

- `Package.swift`와 폴더 뼈대
- `LICENSE`, `THIRD_PARTY_NOTICES.md`, `PROVENANCE.md`, `UPSTREAM.md`, `AGENTS.md`(§14), `docs/port-map.md`
- `DJLinkTestSupport`: `FakeUDPSocket`, `FakeTCPConnection`, `TestClock`, `FakeInterfaceProvider`
- `scripts/port-status.sh`: 원본 시험 파일별 `it(` 수와, 대응하는 Swift 파일의 `@Test` 수를 나란히 보여 주고 다르면 실패한다. 원본 위치는 `UPSTREAM_DIR` 환경 변수로 받는다.
- CI: `swift test`와 `scripts/port-status.sh`를 돌린다. 처음에는 GitHub Actions macOS 러너로 했고, 2026-10-10부터 GitHub Actions는 끄고 로컬 `scripts/ci.sh`로 돌린다.
- SQLCipher.swift 패키지에 product가 있는지 확인(§7)
- 펌웨어 근거가 있는 곳을 다시 찾아 `PROVENANCE.md`에 적는다(§10)

**9단계 실기 확인 순서**

- 환경: 시험용 스위치에 CDJ 1~2대와 믹서만 묶는다. 공연이나 리허설 중인 네트워크는 쓰지 않는다. 같은 Mac의 rekordbox·rekordboxAgent는 꺼 둔다.
- 순서:
  1. 장치 목록
  2. 7번으로 참여하기, 번호가 겹치면 옮기기
  3. 상태·정밀 위치·on-air
  4. remotedb로 메타데이터·파형·그리드·큐 받기
  5. NFS로 `export.pdb`·`exportLibrary.db`·ANLZ 받기
  6. mixstatus
  7. 마지막에 따로 제어 명령
- 캡처: 확인하면서 받은 패킷을 pcap으로 남겨 회귀 시험 픽스처로 쓴다. 개인 곡이 없는 시험용 USB로만 캡처한다.

**실기 확인 기록**

- 2026-10-14, CDJ-2000nexus 1대(1번), 믹서 없음, Mac `en14`(169.254.0.0/16), 가상 CDJ 7번. sudo가 없어 pcap 캡처와 `passive`는 하지 못했다.
  - 됨: 장치 목록, 7번으로 참여, 상태(재생 상태·곡·BPM·피치·master·마디 안 비트), `watch`, 메타데이터·비트 그리드·파형·큐, NFS로 `export.pdb`·`exportLibrary.db` 받기, `djprofile.nxs` 거부, 곡 올리기, Ctrl-C 정리(종료 코드 130, 남은 소켓 없음).
  - 메타데이터는 remotedb가 아니라 NFS로 받은 USB DB에서 왔다. CDJ의 rekordbox 곡은 원본도 localdb로 읽는다(`getTrackLookupStrategy`). 그래서 remotedb 질의 번호(§11 메모)는 이번에 보지 못했다.
  - 원본 재생 상태 패킷으로 1번에 `pause`를 보내면 계속 재생했다. 네 칸을 하나씩 바꿔 보내 칸 i가 플레이어 i+1이고 0 = 시작, 1 = 정지(cue), 2 = 그대로임을 확인하고 고쳤다(§9). 고친 패킷으로 play·pause가 두 번씩 맞게 동작했다.
  - mixstatus는 믹서가 없으면 on-air가 꺼져 있어, 기본 설정(`useOnAirStatus`)에서는 `stopped`만 나고 `nowPlaying`·`setStarted`는 나지 않는다(원본과 같다).
- 2026-10-14(두 번째), CDJ-2000nexus 2대(1·2번)와 DJM-900NXS2(33번), Mac `en8`. sudo가 없어 50000~50002를 듣기만 하는 UDP 소켓(`SO_REUSEPORT`)으로 브로드캐스트를 받아 비교했다.
  - play·pause: 고친 패킷으로 1번 재생 → 2번 재생 → 1번 정지 → 2번 정지를 보내 매번 대상 덱만 바뀌었다. 원본 패킷도 대상 IP로만 가고 CDJ는 자기 칸만 읽어, 원본에서도 다른 덱은 움직이지 않았다. 원본의 실제 문제는 `pause`가 대상을 멈추지 못하는 것이다.
  - 곡 올리기: 1번 USB의 곡을 2번 덱에 올렸다.
  - on-air: DJM-900NXS2는 on-air 패킷(0x03, 45바이트, `0x20` = 0x02)을 50001로 보낸다. 원본은 50002에서만 읽고 4채널은 `0x20` = 0x00·46바이트 이상만 받아 하나도 읽지 못했다. 고친 뒤 `status`에 on-air 줄이 나오고 CDJ 상태의 on-air 표시와 맞는다(§9).
  - keep-alive(0x06): CDJ-2000nexus·DJM-900NXS2 모두 54바이트이고 `0x30`이 장치 수다. 우리 것은 55바이트였다. 고친 뒤에도 CDJ가 가상 CDJ에 상태를 보내고 제어가 된다(§9).
  - mixstatus: on-air인 2번 재생 → `set started`·`now playing`, on-air가 아닌 1번 재생은 보고하지 않음, 정지 30초 뒤 `set ended`, 같은 덱·같은 곡으로 다시 재생 → `set started`·`now playing`(PR #3 고치기 확인).
- 남은 것: pcap(sudo, 전체 캡처, 인터페이스가 사라질 때의 패시브), 분석하지 않은 곡(remotedb 질의 번호), 가상 CDJ 하나 더(번호 겹침), CDJ-3000(정밀 위치), 6채널 믹서(on-air 6채널 변형).
- 2026-10-14(비트 패킷 표본), 같은 CDJ-2000nexus 2대와 DJM-900NXS2, Mac `en8`, 가상 CDJ 7번.
  - 기존 CLI로 각 덱을 재생·cue로 바꾸며 듣기 전용 UDP 소켓으로 0x28을 덱마다 33개씩 받았다. 모두 96바이트였다. 장치 번호·마디 안 비트·곡 BPM·피치는 CDJ 상태와 맞고 정지하면 비트 패킷이 멈췄다.
  - 1번은 BPM 166·피치 약 -2.45%, 2번은 BPM 168·약 -0.15%였고 두 덱 모두 1~4로 순환했다. 2번의 첫 시도에는 platter-held 상태여서 표본이 없었고, 다시 재생해 정상 표본을 받았다. 끝난 뒤 두 덱은 cue 상태이며 2번이 master다.
  - 확인한 필드로 `CDJStatus.BeatState`·`beatFromPacket`·능동/패시브 `beatEmitter`와 CLI 비트 출력을 추가했다([이슈 #7](https://github.com/ImBada/DJLinkKit/issues/7)). 사용자 완료 신호 뒤 새 시험 15개와 전체 로컬 CI(993개, 조건부 시험 포함)가 실패 없이 통과했고 원본 시험 622개·44개 파일도 모두 일치했다. 독립 코드 리뷰에서 결함은 나오지 않았다.
  - 새 CLI `status`로 덱을 하나씩 재생해 각 16개 비트를 받았다. 마디 안 비트가 1~4로 순환하고 정지 뒤 0x28 출력은 멈췄으며 on-air도 67개 함께 받았다. Ctrl-C 종료 코드 130과 소켓 정리를 확인했다. 실제 패시브 캡처는 BPF 권한이 없어 [#6](https://github.com/ImBada/DJLinkKit/issues/6)에 남긴다.
  - 앞부분 시간 필드, 양수 피치·sync·역재생과 다른 기종은 미확인이다. 상세 근거는 PROVENANCE §D에 둔다.


- 2026-10-14~15(능동 연결 안정성), CDJ-2000nexus 2대(1·2번)와 DJM-900NXS2(33번), Mac `en8`. 사용자가 물리 연결과 전원을 바꾸고, 기존 debug CLI로 확인했다. 패키지 코드·시험은 바꾸지 않았다.
  - 2번 CDJ LAN: 같은 `status --all`에서 상태 수신 중단과 약 10초 알림 시간 제한 뒤 이탈을 확인했다. 재연결 뒤 같은 프로세스가 2번을 다시 발견하고 상태를 받았다. 1번과 믹서 수신은 유지됐다. 2번의 LINK 곡은 연결 해제 때 풀려 Empty가 됐고, 확인 후 원래 곡을 다시 올렸다.
  - 1번 USB: 같은 `watch`에서 메타데이터를 읽은 뒤 USB를 안전 제거·분리했다. 프로세스는 오류 없이 유지됐고, 재삽입 후 원래 곡을 다시 올리자 같은 메타데이터를 다시 출력했다. 같은 매체의 캐시 재사용 여부와 조회 결과는 구별한다.
  - 1번 전원: 같은 `watch`에서 이탈·재발견을 확인했다. 이탈 때 기존 임시 DB 핸들이 모두 닫히고 본체가 삭제됐다. 다시 켜고 같은 곡을 올렸을 때 watch는 재조회하지 않았지만, 새 `metadata` 호출은 기존과 같은 결과를 정상 반환했다. 같은 곡 ID 중복 억제 문제는 [#17](https://github.com/ImBada/DJLinkKit/issues/17)에 기록했다.
  - Mac LAN: USB 랜 어댑터를 유지한 채 LAN 케이블만 분리했다. 같은 `status --all`에서 세 장비 모두 이탈했고 CLI는 살아 있었다. 재연결 후 macOS가 이전과 같은 IPv4 주소를 다시 받은 뒤 세 장비 재발견·두 덱 상태·on-air 수신이 같은 프로세스에서 재개됐다. 다른 IPv4 주소로 변경되는 경우와 USB 랜 어댑터 자체 제거는 확인하지 않았다.
  - 임시 파일 결함: 이탈 때 DB 본체는 지워져도 `-wal`·`-shm`이 남았고 Ctrl-C 정상 종료(130) 뒤에도 남았다. CLI가 본체 삭제 시 경로를 정리 목록에서 빼는 것이 원인이다([#16](https://github.com/ImBada/DJLinkKit/issues/16)). 이번 watch와 후속 metadata 호출이 만든 잔존 부속 파일 4개는 열린 핸들이 없는 것을 확인한 뒤 해당 실행의 파일만 직접 정리했다.
  - 종료: 관찰 CLI는 모두 Ctrl-C로 종료 코드 130을 반환했고 남은 djlink·관찰 프로세스는 없다. 마지막 상태는 두 덱 모두 원래 곡의 cue 상태이며 1번이 master다. 1번 피치는 전원 재시작 뒤 -2.50%로 보고됐고 피치 설정은 코드에서 변경하지 않았다. 원시 로그는 저장소 밖에 둔다.
  - 범위: 현재 rb 곡은 NFS/LocalDB 경로여서 이 결과를 remotedb 재접속 확인으로 쓰지 않는다(#9). 실제 pcap·패시브 인터페이스 제거 확인도 별도다(#6·#8).


- 2026-10-15(#16·#17 수정 후 실기 재확인), 같은 두 CDJ와 믹서·Mac `en8`, 가상 CDJ 7번. 수정된 debug CLI `watch` 하나를 유지했다.
  - 처음 두 덱의 메타데이터를 읽은 뒤 사용자가 1번 전원을 껐다. 이탈 처리와 임시 DB 핸들 종료를 확인했다.
  - 1번을 다시 켜고 같은 곡을 cue 상태로 올리자 같은 watch가 장치를 재발견하고 이전과 일치하는 메타데이터를 다시 출력했다. 기존 watch의 재조회 누락(#17)이 수정됐음을 확인했다.
  - 재시작 전후 DB 본체·WAL·SHM 경로를 확인하고 Ctrl-C로 watch를 종료했다. 정상 종료 코드 130 뒤 확인한 경로 6개 중 남은 파일은 0개였다. 이전과 달리 수동 삭제 없이 정리됐다(#16).
  - 개인 곡 제목·경로·DB 내용은 공개 기록에 넣지 않고 원시 로그는 저장소 밖에 둔다. 실제 소켓을 열지 않는 회귀 시험 15개와 전체 로컬 CI도 통과했다.

## 9. 1:1 이후 고칠 것

1:1이 모두 통과한 뒤에 고친다. 하나마다 실패하는 시험을 먼저 더하고, 따로 커밋한다. 1:1 기준선은 `port/one-to-one` 브랜치(PR #1)이고, 고친 것은 그 위의 `fix/upstream-bugs` 브랜치(PR #2)에 쌓아 main에 합쳤다(§12). 원본 대응 시험의 기대값을 바꿔야 했던 곳은 그 시험 위에 `// PLAN §9:` 주석을 단다. 새 시험은 영역마다 `*UpstreamFixTests.swift`에 둔다.

**고친 것**(2026-10-10, PR #2)

- status: 정밀 위치 파서가 패킷 종류 바이트(0x0a = 0x0b)를 보지 않아 같은 50001 포트의 비트 패킷도 위치로 읽었다(`src/status/utils.ts:132`). 능동·패시브 모두 고쳤다.
- devices: `getDeviceEnsured`가 장치가 먼저 와도 시간 제한 타이머를 지우지 않았다.
- virtualcdj: announcer의 `ready`를 다시 부르면 앞서 기다리던 쪽이 풀리지 않았다 / `makeStatusPacket`이 머리말을 0x0b에 썼다(정의만 있고 쓰이지 않는 함수).
- network: `bringOnline`에서 bind가 실패하면 앞서 만든 소켓을 닫지 않았다.
- mixstatus: 같은 곡을 다시 틀면 30초 뒤 재생 중에 `setEnded`가 났다 / `isSetActive`가 돌아가지 않아 두 번째 세트에서 `setStarted`가 나지 않았다 / `setMayStop`이 두 번 불리면 앞 타이머를 지울 수 없었다 / 같은 데크에서 같은 곡으로 새 세트를 시작하면 `nowPlaying`·`setStarted`가 모두 나지 않았다(중복 억제 `lastEmittedTrackId`가 세트가 끝나도 남았다, PR #3).
- localdb: PDB 쪽 사슬이 순환하면 무한 루프에 빠졌다(이제 오류), 쪽 번호 비교로 비단조 사슬에서 일찍 끝나거나 빈 후보 뒤로 읽었다(이제 링크를 따라 마지막 쪽·빈 후보에서 종료) / 장치 제거 때 첫 DB만 닫았다 / OneLibrary 열기에 실패하면 임시 파일이 남았다.
- metadata-connect·artwork: mp4 문자열 atom(`©nam` 등)이 맞지 않았다 / ID3 프레임 ID 앞부분 비교로 `TCOM`·`TCOP`이 장르로 읽혔다 / 값이 모두 비어도 결과가 null이 아니었다 / APIC의 BOM 검사 위치(겉으로 드러나는 동작 변화 없음) / ID3 v2.3 확장 헤더 크기에 4바이트가 빠졌다.
- passive: UDP 길이를 두 번 빼서 payload 끝 8바이트가 잘리고 표준 announce가 short format으로 읽혔다.

**고친 것**(2026-10-14, 실기 확인 뒤)

- 제어: 재생 상태 패킷(`src/control/index.ts`)이 칸 번호(0–3)를 `device.id`와 견주고 나머지 칸을 0(시작)으로 채웠다. 대상이 한 칸 어긋나 1번에 보낸 `pause`가 1번을 계속 재생시켰고(CDJ-2000nexus 실기), 다른 플레이어 칸에는 시작을 실었다. 이제 칸 `device.id - 1`에 명령을 싣고 나머지 칸은 2(그대로)로 채운다. 칸이 없는 번호(1~4 밖)와 재생·cue 밖의 재생 상태는 보내지 않고 오류를 낸다(원본은 0, 즉 시작을 보냈다). `djlink`의 `--unverified-playstate`는 없앴고 `play`·`pause`는 1~4번에만 보낸다. CDJ 두 대에서 대상 덱만 움직이는 것을 확인했다. 패킷은 대상 IP로만 가고 CDJ는 자기 칸만 읽으므로, 원본에서도 다른 덱이 움직이지는 않았다.
- status: on-air 패킷을 상태 소켓(50002)에서만 읽었다(`src/status/index.ts:122`). DJM-900NXS2는 50001로 보낸다. 4채널 파서도 `0x20` = 0x00과 0x2e바이트 이상만 받아 실제 패킷(`0x20` = 0x02, 0x2d바이트)을 버렸다. 이제 능동·패시브 모두 50001의 종류 0x03 패킷도 읽고, 4채널은 `0x20`이 0x00·0x02이고 0x2d바이트 이상이면 받는다. 6채널 변형은 장비가 없어 그대로 두었다.
- virtualcdj: keep-alive(stage 0x06)에 원본이 0x30 한 바이트를 더 넣어 55바이트가 되고 장치 수가 0x31로 밀렸다. 실제 장비처럼 54바이트에 0x30이 장치 수가 되게 고쳤다.

**고친 것**(2026-10-15, CLI 연결 복구)

- CLI 임시 DB 정리: 장치 이탈 때 본체를 먼저 삭제하면 부속 파일이 정리 목록에서 빠졌다([#16](https://github.com/ImBada/DJLinkKit/issues/16)). 별도 소유 경로 목록을 유지해 본체 미존재·삭제 실패와 무관하게 정확한 WAL·SHM·journal을 종료 때 정리한다. 다른 파일은 정리하지 않으며, 정리 시작 뒤 새 임시 쓰기는 거부한다. 부속 파일 삭제 실패는 다음 정리 호출에서 재시도한다.
- CLI watch: 원본 `src/cli/index.ts`도 재생 덱별 곡 ID만 비교하고 조회 전에 기록해, 원본 장치·슬롯·종류 변경과 같은 곡의 재접속·일시 실패를 놓쳤다([#17](https://github.com/ImBada/DJLinkKit/issues/17)). 변경 감지 키에 원본 장치·슬롯·종류·곡 ID를 넣고 재생 덱이나 원본 장치가 이탈·재발견되면 기록을 무효화한다. 실패는 다음 상태 패킷에서 1초 이상 간격으로 최초 포함 최대 3회 조회하며 새 곡·연결 전에는 횟수를 초기화하지 않는다. 이전 조회의 늦은 결과·오류·파일 게시 안내도 버린다. 선택적 다운로드 실패는 성공한 메타데이터를 재조회하게 만들지 않는다.
- 회귀 시험 15개를 추가했다. 관련 시험 22개, 전체 로컬 CI(1,008개 선언, 조건부 시험 포함), 원본 시험 622개·44개 파일 대조가 모두 통과했다. 수정된 같은 watch에서 전원 재시작 후 원래 곡의 메타데이터 재조회가 확인됐다. 정상 종료(130) 뒤 재시작 전후의 임시 DB 본체·WAL·SHM 경로 6개 모두 잔존 수가 0이었다. 직접 파일을 지우지 않고 CLI 정리만으로 확인했다.

**실기 확인 뒤 정할 것**

- localdb: 긴 ASCII 문자열(0x40)을 +3부터 length만큼 읽는다(DJCrate는 +4부터 length-4).
- passive: 캡처 중 인터페이스가 사라지면 오류 없이 캡처 중 상태가 남을 수 있다(cap의 dispatch 반복과 같다).

**기능 추가·검토 필요**

- 비트 패킷(0x28): CDJ-2000nexus의 96바이트 형식과 장치 번호·마디 안 비트·곡 BPM·피치를 캡처로 확인했다. 능동·패시브 비트 이벤트와 CLI 출력을 추가했고 회귀 시험과 능동 CLI 실기를 확인했다. 실제 패시브 캡처는 #6에서 확인한다([#7](https://github.com/ImBada/DJLinkKit/issues/7)). 정밀 위치나 실제 다음 비트까지의 시간은 제공하지 않는다.
- localdb: 버튼이 있으면 알 수 없는 cue type도 hot_cue로 돌려준다. 원본 시험 주석은 cue도 loop도 아닌 항목을 뺀다고 하므로 검증 누락으로 보이지만 의도를 확정할 시험이 없다.
- Stagehand 제어(0x07)는 CDJ가 무시한다고 원본 문서(`docs/STAGEHAND.md` §6.1)에 적혀 있다.
- README는 가상 CDJ 번호로 5를 권하지만 기본값은 7이다(`src/constants.ts:9`). 우리 문서에는 7 이상만 적는다.

**Link Export 원본에서 유지하는 동작**(2026-10-15, 아직 수정하지 않음)

- rbxport `Claim`의 첫/둘째 단계 선언 길이 44/50과 실제 인코딩 길이 42/48이 다르다. 원본 패킷·시험대로 보존한다.
- 원본이 읽을 수 있는 mixer discovery subtype `0x03`도 다시 인코딩할 때는 `0x02`가 된다. 원본의 재인코딩 결과를 유지한다.
- 스마트 목록의 `dateCreated` 조건은 원본처럼 `date_added` 컬럼을 읽고, 루트 마지막 XML 닫기 이름은 검사하지 않는다. 1:1 기준선 작성 중에는 의미를 바꾸지 않는다.

## 10. 라이선스·출처

**LICENSE**

- MIT로 한다. 원본 LICENSE의 저작권 표시("Copyright (c) 2013 Evan Purkhiser")와 허가 문구를 그대로 두고, 우리 저작권 줄을 더한다.

**THIRD_PARTY_NOTICES.md**

- alphatheta-connect: 기여자는 `package.json` contributors의 Chris Le 등
- prolink-connect
- onelibrary-connect, metadata-connect: 각 LICENSE의 저작권자를 옮길 때 확인한다
- §7에서 DJCrate 리더와 함께 옮기는 항목

**옮기지 않는 것**

- `.ksy` 2개(EPL-1.0).
- 원본 `docs/` 중 Deep Symmetry DJL Analysis 문서를 그대로 인용한 부분(예: `docs/ALL_IN_ONE_UNITS.md`의 인용 블록). 링크로만 가리키고 내용은 우리 말로 적는다.

**PROVENANCE.md(출처 기록)**

- 펌웨어 분석에 근거한 원본 지식을 옮긴 곳을 적는다.
- 고정 커밋에서 확인한 곳:
  - `src/status/types.ts:5-8`: CDJ-3000 FW3.20의 `sub_d7d3c8`
  - `src/status/utils.ts:43-47`: `sub_d7d610`, 피치 네 값의 뜻
  - `docs/FULL_STARTUP.md:241-279`
- "firmware" 낱말 검색으로 걸린 후보: `src/constants.ts`, `src/virtualcdj/index.ts`, `src/virtualcdj/stagehand.ts`, `docs/STAGEHAND.md`, `docs/USB_EXPORT.md`, `docs/REMOTE.md`. 0단계에서 하나씩 열어 확인하고 표로 남긴다.
- 원칙:
  - 원본에 공개된 지식은 옮긴다.
  - 펌웨어나 rekordbox 실행 파일을 우리가 직접 분석하지 않는다(strings·디스어셈블 포함).
  - 새로 알아내는 것은 실기 패킷 캡처를 비교해서만 한다.
- 결정 기록(2026-10-10): AlphaTheta EULA §2.2(리버스 엔지니어링 금지)는 분석한 쪽에 걸리는 조항이다. 그 결과를 옮겨 배포하는 위험이 작지만 0은 아니라는 것을 알고, 옮기기로 정했다.

## 11. 안전 규칙

**시험**

- 시험은 실제 소켓을 열지 않는다(원본 시험도 0개다).
- 실제 소켓을 만드는 쪽(`SocketFactory.live`)은 시험 프로세스에서 부르면 바로 실패하게 한다. DJCrate의 `TestProcess`처럼 시험 프로세스를 알아본다.
- 루프백(127.0.0.1) 통합 시험은 `DJLINK_LOOPBACK_TESTS=1`일 때만 따로 돈다. 시험은 LAN에 아무것도 보내지 않는다.

**실기와 CLI**

- 공연이나 리허설 중인 네트워크에서 돌리지 않는다.
- 같은 Mac에서 rekordbox·rekordboxAgent가 켜져 있으면 UDP 50000~50002를 잡지 않는다. 잡으면 rekordbox LINK가 망가질 수 있다. `djlink`는 시작할 때 이것을 확인하고 거부한다. 이 확인은 CLI·앱 쪽 규칙이며 라이브러리 동작(1:1)에는 넣지 않는다.
- 가상 CDJ 번호는 7 이상만 쓴다(CLI 기본값). 1~6은 실기 확인에서 일부러 고른 경우만 쓴다. 번호가 겹쳐 다시 고를 때도 같다(허용하지 않는 번호로는 announce하기 전에 멈춘다).
- 메모(remotedb 질의 번호 예외, 바꾸지 않음): 위 7 이상 규칙은 announce 번호에 대한 것이다.
  remotedb 메시지 안의 장치 번호는 원본 `pickRemoteDbQueryId`가 1~6 중에서 고른다.
  CDJ가 1~6만 답하기 때문이며 원본 주석에 CDJ-3000 실기 확인(2026-08-30)이 있다.
  그래서 가상 CDJ가 7 이상이어도 remotedb 질의에는 같은 랙의 다른 CDJ 번호(없으면 비어 있는 1~6)가 실린다.
  1:1이라 고치지 않았고, CLI는 연결할 때 고른 번호를 한 줄 로그로 남긴다.
  실기에서 이 번호가 CDJ에 어떻게 보이는지 확인하고, 바꿀지는 사용자가 정한다.
- 소켓은 고른 인터페이스에 묶고 그 서브넷 밖의 장치와는 통신하지 않는다. `play`·`pause`는 재생 상태 패킷에 칸이 있는 1~4번 플레이어에만 보낸다(§9, 2026-10-14 실기 확인 뒤 고침).
- 제어 명령(곡 올리기, Stagehand 설정 쓰기)은 CLI에서 `--confirm <장치 이름>` 없이는 보내지 않는다.
- macOS 로컬 네트워크 권한:
  - 라이브러리는 Info.plist를 가질 수 없다.
  - 터미널에서 돌린 `djlink`는 권한을 자동으로 받는다. 그래서 앱에서는 결과가 다를 수 있고, DJCrate에 붙일 때 따로 확인한다(§13).

## 12. 원본 따라가기

- `UPSTREAM.md`에 세 저장소의 고정 커밋을 적는다.
- 새 원본 릴리스를 따라갈 때는 한 번에 한 릴리스씩 다음 순서로 한다.
  1. 두 커밋 사이의 차이를 본다.
  2. 바뀐 시험부터 옮긴다.
  3. 코드를 옮긴다.
  4. `port-status`와 시험이 통과하는지 본다.
  5. `UPSTREAM.md`를 갱신한다.
- 새 차이에 펌웨어 분석 근거가 생기면 `PROVENANCE.md`에 더한다.
- 브랜치(2026-10-10):
  - `port/one-to-one`은 원본 버그까지 그대로 둔 1:1 기준선이다. 지우지 않고 남긴다.
  - main은 기준선에 §9에서 고친 것을 더한 쪽이다.
  - 새 릴리스는 `port/one-to-one`에 먼저 옮기고, 시험과 `port-status`가 통과하면 main에 합친다.
  - 합칠 때 §9에서 고친 곳과 겹치면 고친 쪽을 남긴다. 새 원본 시험의 기대값이 고친 동작과 다르면 그 시험 위에 `// PLAN §9:` 주석을 단다.

## 13. DJCrate에 붙이기 (1:1 완료 뒤, DJCrate 저장소 이슈로)

**준비**

- DJCrate에 새 이슈를 만든다. USB 에픽 #3은 Pro DJ Link를 범위 밖으로 적어 두었다.
- DJCrate AGENTS.md에 §10의 출처 원칙을 한 줄 더한다.
- SQLCipher를 같은 패키지 의존으로 맞춘다(§7).
- Info.plist에 `NSLocalNetworkUsageDescription`을 더한다. Apple Development 인증서로 서명했을 때 권한이 빌드마다 유지되는지 확인한다. ad-hoc 서명이면 다시 물을 수 있다.

**관문**

- rekordbox·rekordboxAgent가 켜져 있으면 포트를 잡지 않는다.
- 가상 CDJ 번호는 7 이상으로 강제한다.
- `DJLinkControl`은 코드 관문(비상 스위치)과 동작마다 받는 동의 뒤에 둔다. USB 실물 쓰기와 같은 모양이다.

**데이터와 화면**

- NFS로 받은 DB·ANLZ는 Mac 사본(`DJC_HOME` 아래 캐시)에서 연다.
- `PIONEER/extracted`·`PIONEER/CDP`·`djprofile.nxs`는 NFS로도 열거·읽기·복사하지 않는다(`UsbLayout.neverRead`).
- 원격 플레이어를 그리려면 `DeckModel` 없이 값만 받는 `DrawState`·`ZoomWaveformView` init을 만든다.
- 리더가 두 벌이 된다(§7). DJCrate가 패키지 리더를 쓸지, 지금 리더를 그대로 둘지 붙일 때 정한다.
- CLI는 `djc link …`로 낸다.

## 14. 새 저장소 AGENTS.md 초안

```markdown
# AGENTS.md — DJLinkKit

alphatheta-connect(TypeScript)를 Swift로 1:1 옮기는 패키지다. 계획은 docs/PLAN.md, 원본 고정 커밋은 UPSTREAM.md, 출처 기록은 PROVENANCE.md에 있다.

- 사용자에게 하는 말·보고·질문은 한국어로 한다. 주석·커밋 메시지는 한국어, 식별자는 영어(원본 이름을 따른다)로 쓴다.
- 원본 동작을 1:1로 옮긴다. 1:1을 마치기 전에는 원본과 다르게 고치지 않는다. 원본 버그도 그대로 옮기고, 고칠 것은 docs/PLAN.md §9에 적는다.
- 원본 시험의 입력과 기대값을 바꾸지 않는다. `it('문구')`는 `@Test("문구")`로, 원본 파일 하나는 Swift 파일 하나로 옮긴다.
- 구현하는 동안에는 빌드·시험을 돌리지 않는다. 사용자가 "구현 완료"라고 하면 그 단계 시험부터 돌린다.
- 시험은 실제 소켓을 열지 않고 LAN에 아무것도 보내지 않는다.
- 실기 확인은 공연 중이 아닌 시험용 네트워크에서, 같은 Mac의 rekordbox·rekordboxAgent가 꺼져 있을 때만 한다. 가상 CDJ 번호는 7 이상을 쓴다.
- 펌웨어나 rekordbox 실행 파일을 직접 분석하지 않는다(strings·디스어셈블 포함). 원본에 공개된 지식만 옮기고, 새로 알아내는 것은 실기 패킷 캡처를 비교해서만 한다.
- 라이선스가 없는 외부 코드·문서는 쓰지 않는다. 옮기면 THIRD_PARTY_NOTICES.md에 더한다. `.ksy`(EPL-1.0)와 Deep Symmetry 문서 원문은 옮기지 않는다.
- 패킷 캡처와 픽스처에 개인 곡 정보·경로·토큰을 넣지 않는다(공개 저장소).
- 커밋 제목은 `타입: 한국어 설명`으로 쓴다. 커밋·푸시는 요청받았을 때만 한다.
```

## 15. 확인하지 못한 것

- 원본 시험을 실제로 돌려 보지 않았다. 고정 커밋에서 531개가 모두 통과하는지 모른다. 기대값은 시험 코드에 적힌 값을 따른다.
- onelibrary-connect·metadata-connect의 시험 개수. 파일 수(1개, 2개)만 셌다.
- SQLCipher.swift 패키지가 SPM product를 내주는지.
- 펌웨어 근거 표시가 없는 원본 부분(Stagehand, CDJ-3000X 등)이 어디서 왔는지.
- 시험 개수는 `grep -cE "^\s*(it|test)(\.each)?\("`로 셌다. 들여쓰기가 다르거나 동적으로 만든 시험이 있으면 숫자가 어긋날 수 있다. 0단계의 `port-status.sh`로 다시 센다.
