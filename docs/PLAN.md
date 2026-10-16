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
- 원본 시험 532개(41개 파일)를 하나씩 옮겨 모두 통과시킨다. 원본 저장소에 기대고 있는 두 저장소의 시험도 함께 옮긴다(§2).
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
- 원본의 매개변수 시험은 두 곳이다. `tests/utils/index.spec.ts`의 jest-each(`each([...]).it(...)`)와 metadata-connect `test/label.test.ts`의 `it.each`다. 각각 `@Test(arguments:)` 하나로 옮겼고, `port-status.sh`도 한 개로 센다. `describe.each`는 없다(고정 커밋 기준).

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
        .executableTarget(name: "djlink", dependencies: ["DJLinkKit", "DJLinkControl", "DJLinkPassive"]),
        .target(name: "DJLinkTestSupport", dependencies: ["DJLinkKit"]),
        .testTarget(name: "DJLinkKitTests", dependencies: ["DJLinkKit", "DJLinkTestSupport"], resources: [.copy("Fixtures")]),
        .testTarget(name: "DJLinkControlTests", dependencies: ["DJLinkControl", "DJLinkTestSupport"]),
        .testTarget(name: "DJLinkPassiveTests", dependencies: ["DJLinkPassive", "DJLinkTestSupport"]),
    ]
)
```

위 `Package.swift`는 0단계 스케치다. 지금의 `Package.swift`는 `djlink`가 `DJLinkPassive`에도 의존하고(`passive` 명령), Link Export 타깃(`DJLinkExport*`, [LINK-EXPORT-PLAN.md](LINK-EXPORT-PLAN.md))과 `djlinkTests`가 더해졌다.

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
- 기본 실행(`swift test`)에서 실제 소켓을 연 시험이 0개다. 예외는 `DJLINK_LOOPBACK_TESTS=1`일 때만 도는 루프백 시험이다. DJLinkKit의 6개와 Link Export의 8개가 127.0.0.1에만 소켓을 열고 LAN에는 아무것도 보내지 않는다(§11).

| 단계 | 원본 | 원본 시험(파일: 개수) | 합 |
|---|---|---|---|
| 0 뼈대 | — | — | 0 |
| 1 기초·상태 | `constants`·`types`·`entities`, `utils/`, `devices/`, `status/` | `tests/utils/index` 9(jest-each 매개변수 시험 1개 포함), `tests/devices/index` 7, `tests/devices/utils` 3, `tests/status/utils` 14, `tests/status/position` 7, `tests/status/on-air` 8, `src/status/stagehand-gating` 2 | 50 |
| 2 가상 CDJ·네트워크 | `virtualcdj/`, `network.ts`, `index.ts` | `src/virtualcdj/heartbeat` 7, `tests/virtualcdj/conflict` 11, `device-id` 25, `stagehand` 8, `startup` 23, `wire-selection` 8, `tests/network/stagehand-identity` 2 | 84 |
| 3 remotedb·NFS | `remotedb/`, `nfs/` | `tests/remotedb/connection` 4, `fields` 13, `src/nfs/index` 16, `tests/nfs/path` 14 | 47 |
| 4 localdb | `localdb/`, onelibrary-connect | `tests/localdb/`: `anlz-2ex-integration` 20, `anlz-parsers-2ex` 18, `anlz-parsers-cue-nulls` 2, `anlz-parsers-cues` 3, `anlz-parsers-extended-cues` 5, `anlz-parsers-song-structure` 5, `anlz-parsing` 31, `database-fallback` 12, `database-loading` 22, `edge-cases` 44, `load-anlz-vocal-config` 10, `onelibrary-adapter` 62. 여기에 onelibrary-connect 시험 1개 파일 | 234 + α |
| 5 db·앨범아트·태그 | `db/`, `artwork/`, `metadata.ts`, metadata-connect | `tests/db/blankMetadata` 4, `getMetadata` 13, `getPlaylist` 3, `getWaveforms` 8, `tests/artwork/extraction.integration` 5, `parsers` 13. 여기에 metadata-connect 시험 2개 파일 | 46 + α |
| 6 mixstatus | `mixstatus/` | `tests/mixstatus/index` 29 | 29 |
| 7 제어 | `control/` | `tests/control/load` 2, `stagehand` 9 | 11 |
| 8 패시브 | `passive/` | `tests/passive/alphatheta` 22, `pcap-adapter` 9 | 31 |
| 9 CLI·실기 확인 | `cli/` | — | 0 |
| 합 | | 41개 파일 | 532 + α |

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

- 2026-10-16(pcap·패시브, [#6](https://github.com/ImBada/DJLinkKit/issues/6)), CDJ-2000nexus 2대(1·2번)와 DJM-900NXS2(33번), macOS 27, Mac `en8`. BPF 읽기 권한을 준 일반 사용자로 `tcpdump`와 `djlink passive --iface en8`을 함께 돌렸다. 2번 덱에는 Link Export(17번)의 시험용 합성 곡을 올리고 `djlink control`로 재생·정지했다.
  - pcap(50000~50002, 1,098개)과 `passive` 출력이 맞았다. 장치 5개(CDJ 2대, DJM, Link Export 17번, 가상 CDJ 7번), 1번 빈 덱과 2번 덱의 곡·재생 상태·on-air·master, 2번 덱의 비트가 같았다.
  - pcap에서도 on-air는 종류 0x03·45바이트·`0x20` = 0x02로 비트 포트(50001)에, keep-alive(0x06)는 54바이트, 비트(0x28)는 96바이트였다(2026-10-14 UDP 수신 결과와 같다).
  - Ctrl-C로 `passive`가 종료 코드 130으로 끝났고 남은 캡처 프로세스는 없었다.
  - MAC이 가려져 실리는 것을 이 캡처에서 찾았다(#41, §11).
  - 캡처에서 CDJ·DJM이 보낸 프레임 7개를 MAC만 가려(제조사 앞자리는 남김) `PassiveCaptureTests`의 입력으로 쓴다. 곡 정보는 합성 곡 번호뿐이다. 원시 pcap과 로그는 저장소 밖에 둔다.

- 2026-10-16(링크 로컬 remotedb TCP, [#40](https://github.com/ImBada/DJLinkKit/issues/40)), CDJ-2000nexus 2대(1·2번)와 DJM-900NXS2(33번), macOS 27, Mac `en8`(169.254/16, 라우터 없음), 가상 CDJ 7번.
  - `djlink metadata --iface en8`이 localdb를 찾지 못해 remotedb로 넘어가자 `Network interface not found: en8`로 TCP 연결을 시작하지도 못했다. `NWPathMonitor`가 기본 경로(`en0`)만 보여 주고 링크 로컬 주소만 있는 `en8`은 넣지 않기 때문이다. 이전 실기는 메타데이터를 NFS(UDP)로만 읽어 드러나지 않았다.
  - 고친 뒤(인터페이스의 IPv4 주소를 로컬 주소로 지정하고, 연결 뒤 경로가 `en8`인지 검사) 같은 명령이 1번 CDJ의 질의 포트(12523)와 remotedb 포트에 `en8`로 연결해 응답을 받았다. USB가 없는 슬롯이라 응답은 0x4003(거절)이었고, 연결 자체를 확인하는 데 그쳤다. 실제 곡의 remotedb 조회는 #9에 남는다.

- 2026-10-16(패시브 인터페이스 제거, [#8](https://github.com/ImBada/DJLinkKit/issues/8)), macOS 27, USB 랜 어댑터 `en8`, `djlink passive --iface en8`.
  - LAN 케이블만 뽑았다: 인터페이스는 남고 같은 프로세스에서 재연결 뒤 캡처가 저절로 이어졌다. 오류로 다루지 않는다.
  - USB 어댑터를 뽑았다: `en8`이 사라지고 프로세스는 오류도 종료도 없이 CPU 0%로 남았다. 어댑터를 다시 꽂아 `en8`이 살아난 뒤에도 같은 프로세스는 아무것도 받지 못하고 캡처 중으로만 남았다. 새로 띄운 `passive`는 정상이다.
  - 원인: `LibpcapBackend`가 DispatchSource 읽기 소스를 기다리는데 인터페이스가 사라지면 그 소스가 다시 읽히지 않고, 원본 cap처럼 `pcap_dispatch` 오류를 보지 않는다. 고친 내용은 §9.
  - 고친 뒤 같은 순서로 다시 확인했다. 캡처 중 어댑터를 뽑자 `패킷 캡처 오류: Capture interface "en8" is gone (index 26 -> 0). Capturing stopped.`를 내고 종료 코드 1로 끝났다. 어댑터를 다시 꽂은 뒤 새로 띄운 `passive`는 장치 3대와 on-air를 정상으로 받았다.

- 2026-10-16(remotedb 질의 번호, [#9](https://github.com/ImBada/DJLinkKit/issues/9) 일부), CDJ-2000nexus 2대(1·2번)와 DJM-900NXS2, Mac `en8`, 가상 CDJ 7번. USB가 없어 1번 CDJ의 빈 USB 슬롯에 `djlink metadata`를 보내고 TCP를 pcap으로 기록했다.
  - 순서: 질의 포트 12523에 `RemoteDBServer` → 포트 1051, 머리말 `0x11 00000001` → 같은 값, Introduce(트랜잭션 0xfffffffe, 종류 0x0000, 인자 2) → 성공(0x4000), 메타데이터 요청(0x2002, DMST 첫 바이트 2·USB·rb) → 오류(0x4003, 인자로 요청 종류 0x2002), 끝인사(0x0100).
  - CLI의 `remotedb 질의 번호 2번을 쓴다` 로그와 Introduce·DMST에 실린 번호가 같았다. 원본 `pickRemoteDbQueryId`대로 옆 CDJ의 번호(2번)를 빌렸다.
  - 같은 시간에 `passive`로 두 덱의 상태를 기록했다. 질의 동안 1·2번 덱의 상태 줄(핵심 값이 바뀔 때만 낸다)이 새로 나오지 않았다.
  - 빈 슬롯의 응답은 시간 초과가 아니라 0x4003 오류로 구분된다. 실제 곡의 remotedb 조회(분석하지 않은 곡처럼 remote로 가는 경우)는 시험용 USB가 있어야 해서 남겼다. 원시 pcap은 저장소 밖에 둔다.

- 2026-10-16(시험용 USB, [#13](https://github.com/ImBada/DJLinkKit/issues/13)·[#9](https://github.com/ImBada/DJLinkKit/issues/9)), CDJ-2000nexus 2대(1·2번)와 DJM-900NXS2, Mac `en8`, 가상 CDJ 7번. 합성 시험 곡 6개(30초, 120 BPM 킥과 사인파)를 만들었다. 4곡은 사용자의 rekordbox로 USB에 내보냈다(Device Library). 제목은 짧은 영문, 127자 영문, 200자 영문(아티스트 150자·앨범 180자), 80자 한글이다. 나머지 2곡은 rekordbox를 거치지 않고 USB 폴더에만 넣었다. USB는 1번 CDJ에 꽂았고 시험 중 rekordbox·rekordboxAgent는 꺼져 있었다.
  - #13: NFS로 받은 `export.pdb`에서 rekordbox는 127자 이상 영문을 0x40으로 썼다. 머리는 `40 83 00 00`(127자), `40 cc 00 00`(200자), `40 9a 00 00`(150자), `40 b8 00 00`(180자)였다. u16은 본문 길이 + 4이고, 다음 바이트는 0, 본문은 +4부터다. 한글 80자는 `90 a4 00 00`(UTF-16, 160 + 4)였다. 우리 리더(원본 Kaitai와 같음)는 NUL + 본문 + 다음 문자열 3바이트로 읽었다. 고친 내용은 §9다. CLI `metadata`는 기본으로 OneLibrary(`exportLibrary.db`)를 먼저 읽어 바른 제목을 냈다. 코멘트(250자)는 `export.pdb`에서 찾지 못했다.
  - #9: 폴더에서 올린 곡을 CDJ가 `Unanalyzed`로 보고했고, `djlink watch`가 remotedb로 넘어갔다. 2번 CDJ가 망에 있고 곡이 이미 올라간 상태에서는 질의 번호 2로 보낸 `0x2202`에 0x4000(항목 10개)이 왔다. 이어진 렌더로 제목 `DLK Remote 01`을 읽었다.
  - 2번 CDJ의 LAN을 빼자 같은 질의 번호 2(이제 비어 있는 번호)에 항목 0개로 답했다. 원본 렌더 경로는 `Cannot read properties of undefined`로 실패했다([#48](https://github.com/ImBada/DJLinkKit/issues/48)).
  - 곡을 올리는 순간 처음 보낸 질의에는 40초가 넘도록 답이 없었다. 원본은 연결 뒤 시간 제한이 없어 watch가 멈췄다([#47](https://github.com/ImBada/DJLinkKit/issues/47)).
  - 첫 곡을 읽은 지 약 1.7초 뒤 CDJ가 요청하지 않은 메시지(트랜잭션 0x03800122, 종류 0x4b02)를 보냈다. 원본 읽기는 트랜잭션 번호를 보지 않아 이후 응답이 한 칸씩 밀렸고, 같은 연결의 조회가 모두 실패했다([#46](https://github.com/ImBada/DJLinkKit/issues/46)).
  - 원시 pcap과 `export.pdb`는 저장소 밖에 둔다. 공개 시험에는 합성 곡의 제목·파일 이름 바이트만 쓴다.

- 2026-10-16(#46·#47 수정 뒤 실기 재확인), 같은 장비와 USB, 가상 CDJ 7번, 수정판 `djlink watch --verbose`와 TCP pcap.
  - 1번 덱에 올라가 있던 분석하지 않은 곡(207)에 이어 132, 207을 차례로 올렸고, 같은 연결에서 세 곡 모두 제목을 읽었다. 이번에는 CDJ가 끼어드는 메시지(0x4b02)를 보내지 않아, 건너뛰는 경로는 실기에서 지나가지 않았다(이슈의 54바이트로 시험한다). 캡처에서 0x4000과 메뉴 머리·항목·꼬리가 모두 요청의 트랜잭션 번호를 되돌려 보냈다.
  - 2번 CDJ의 LAN을 뽑았다가 다시 꽂은 뒤, 1번 CDJ가 질의 번호 2의 `0x2202`에 답하지 않았다(소개는 성공). 수정판은 10초마다 `RemoteDB query to … timed out`으로 연결을 닫고 다시 연결했고, 3회 뒤 포기했다. 다른 곡을 올려도 같았다. 고치기 전이라면 멈춰 있었을 상황이다(#47). 무응답의 원인은 #48에 적었다.

## 9. 1:1 이후 고칠 것

1:1이 모두 통과한 뒤에 고친다. 하나마다 실패하는 시험을 먼저 더하고, 따로 커밋한다. 1:1 기준선은 `port/one-to-one` 브랜치(PR #1)이고, 고친 것은 그 위의 `fix/upstream-bugs` 브랜치(PR #2)에 쌓아 main에 합쳤다(§12). 원본 대응 시험의 기대값을 바꿔야 했던 곳은 그 시험 위에 `// PLAN §9:` 주석을 단다. 새 시험은 영역마다 `*UpstreamFixTests.swift`에 둔다. 예외로 패시브 UDP 길이 시험(`UDP payload keeps every byte and a standard announce uses the full format`)은 `PassiveFlowTests.swift`에 있다.

**고친 것**(2026-10-10, PR #2)

- status: 정밀 위치 파서가 패킷 종류 바이트(0x0a = 0x0b)를 보지 않아 같은 50001 포트의 비트 패킷도 위치로 읽었다(`src/status/utils.ts:132`). 능동·패시브 모두 고쳤다.
- devices: `getDeviceEnsured`가 장치가 먼저 와도 시간 제한 타이머를 지우지 않았다. 능동·패시브 모두 고쳤다(패시브는 #23).
- virtualcdj: announcer의 `ready`를 다시 부르면 앞서 기다리던 쪽이 풀리지 않았다 / `makeStatusPacket`이 머리말을 0x0b에 썼다(정의만 있고 쓰이지 않는 함수).
- network: `bringOnline`에서 bind가 실패하면 앞서 만든 소켓을 닫지 않았다.
- mixstatus: 같은 곡을 다시 틀면 30초 뒤 재생 중에 `setEnded`가 났다 / `isSetActive`가 돌아가지 않아 두 번째 세트에서 `setStarted`가 나지 않았다 / `setMayStop`이 두 번 불리면 앞 타이머를 지울 수 없었다 / 같은 데크에서 같은 곡으로 새 세트를 시작하면 `nowPlaying`·`setStarted`가 모두 나지 않았다(중복 억제 `lastEmittedTrackId`가 세트가 끝나도 남았다, PR #3).
- localdb: PDB 쪽 사슬이 순환하면 무한 루프에 빠졌다(이제 오류), 쪽 번호 비교로 비단조 사슬에서 일찍 끝나거나 빈 후보 뒤로 읽었다(이제 링크를 따라 마지막 쪽·빈 후보에서 종료) / 장치 제거 때 첫 DB만 닫았다 / OneLibrary 열기에 실패하면 임시 파일이 남았다. 뒤의 둘은 능동·패시브 모두 고쳤다(패시브는 #23).
- metadata-connect·artwork: mp4 문자열 atom(`©nam` 등)이 맞지 않았다 / ID3 프레임 ID 앞부분 비교로 `TCOM`·`TCOP`이 장르로 읽혔다 / 값이 모두 비어도 결과가 null이 아니었다 / APIC의 BOM 검사 위치(겉으로 드러나는 동작 변화 없음) / ID3 v2.3 확장 헤더 크기에 4바이트가 빠졌다.
- passive: UDP 길이를 두 번 빼서 payload 끝 8바이트가 잘리고 표준 announce가 short format으로 읽혔다.

**고친 것**(2026-10-14, 실기 확인 뒤)

- 제어: 재생 상태 패킷(`src/control/index.ts`)이 칸 번호(0–3)를 `device.id`와 견주고 나머지 칸을 0(시작)으로 채웠다. 대상이 한 칸 어긋나 1번에 보낸 `pause`가 1번을 계속 재생시켰고(CDJ-2000nexus 실기), 다른 플레이어 칸에는 시작을 실었다. 이제 칸 `device.id - 1`에 명령을 싣고 나머지 칸은 2(그대로)로 채운다. 칸이 없는 번호(1~4 밖)와 재생·cue 밖의 재생 상태는 보내지 않고 오류를 낸다(원본은 0, 즉 시작을 보냈다). `djlink`의 `--unverified-playstate`는 없앴고 `play`·`pause`는 1~4번에만 보낸다. CDJ 두 대에서 대상 덱만 움직이는 것을 확인했다. 패킷은 대상 IP로만 가고 CDJ는 자기 칸만 읽으므로, 원본에서도 다른 덱이 움직이지는 않았다.
- status: on-air 패킷을 상태 소켓(50002)에서만 읽었다(`src/status/index.ts:122`). DJM-900NXS2는 50001로 보낸다. 4채널 파서도 `0x20` = 0x00과 0x2e바이트 이상만 받아 실제 패킷(`0x20` = 0x02, 0x2d바이트)을 버렸다. 이제 능동·패시브 모두 50001의 종류 0x03 패킷도 읽고, 4채널은 `0x20`이 0x00·0x02이고 0x2d바이트 이상이면 받는다. 6채널 변형은 장비가 없어 그대로 두었다.
- virtualcdj: keep-alive(stage 0x06)에 원본이 0x30 한 바이트를 더 넣어 55바이트가 되고 장치 수가 0x31로 밀렸다. 실제 장비처럼 54바이트에 0x30이 장치 수가 되게 고쳤다.

**고친 것**(2026-10-15, CLI 연결 복구)

- CLI 임시 DB 정리: 장치 이탈 때 본체를 먼저 삭제하면 부속 파일이 정리 목록에서 빠졌다([#16](https://github.com/ImBada/DJLinkKit/issues/16)). 별도 소유 경로 목록을 유지해 본체 미존재·삭제 실패와 무관하게 정확한 WAL·SHM·journal을 종료 때 정리한다. 다른 파일은 정리하지 않으며, 정리 시작 뒤 새 임시 쓰기는 거부한다. 부속 파일 삭제 실패는 다음 정리 호출에서 재시도한다.
- CLI watch: 원본 `src/cli/index.ts`도 재생 덱별 곡 ID만 비교하고 조회 전에 기록해, 원본 장치·슬롯·종류 변경과 같은 곡의 재접속·일시 실패를 놓쳤다([#17](https://github.com/ImBada/DJLinkKit/issues/17)). 변경 감지 키에 원본 장치·슬롯·종류·곡 ID를 넣고 재생 덱이나 원본 장치가 이탈·재발견되면 기록을 무효화한다. 실패는 다음 상태 패킷에서 1초 이상 간격으로 최초 포함 최대 3회 조회하며 새 곡·연결 전에는 횟수를 초기화하지 않는다. 이전 조회의 늦은 결과·오류·파일 게시 안내도 버린다. 선택적 다운로드 실패는 성공한 메타데이터를 재조회하게 만들지 않는다. 곡 번호가 0(곡 없음)이면 조회하지 않고 `no track`도 내지 않는다. 원본 `cli/index.ts`는 0도 그대로 조회한다(원본과 다른 점).
- 회귀 시험 15개를 추가했다. 관련 시험 22개, 전체 로컬 CI(1,008개 선언, 조건부 시험 포함), 원본 시험 622개·44개 파일 대조가 모두 통과했다. 수정된 같은 watch에서 전원 재시작 후 원래 곡의 메타데이터 재조회가 확인됐다. 정상 종료(130) 뒤 재시작 전후의 임시 DB 본체·WAL·SHM 경로 6개 모두 잔존 수가 0이었다. 직접 파일을 지우지 않고 CLI 정리만으로 확인했다.

**고친 것**(2026-10-15, 패시브·ANLZ 점검)

- passive(#23): 능동 쪽에서만 고쳤던 세 건을 패시브에도 같은 방식으로 고쳤다. `getDeviceEnsured`가 장치가 먼저 오면 시간 제한 타이머를 지운다 / 장치 제거 때 그 장치의 모든 DB를 닫는다(원본은 첫 DB만 닫고 모두 지웠다) / OneLibrary 쓰기·열기에 실패하면 임시 파일을 지운다. 회귀 시험 6개를 `PassiveDevicesUpstreamFixTests`·`PassiveLocalDBUpstreamFixTests`에 더했다.
- localdb(#22): `loadAnlz`가 PCOB·PCO2 태그마다 결과를 덮어써(`src/localdb/rekordbox/index.ts:76-83`) 핫 큐(목록 형 1)·메모리(0) 목록 중 마지막 태그만 남았다. 같은 종류 태그를 파일 순서대로 잇는다. 태그가 하나면 결과가 같고 없으면 nil이다. 패시브도 같은 `loadAnlz`를 쓴다. 회귀 시험 1개를 `LocalDBUpstreamFixTests`에 더했다.
- localdb(#26): PSSI의 mood가 1~3 밖이면 1:1 기준선은 EXT 전체를 실패시켰다. 원본 Kaitai는 kind를 0바이트 `unknown_tag`로 읽어 항목이 2바이트 짧게 끝까지 읽는다. 원본처럼 읽고 `kind`는 nil(undefined), `phraseType`은 `Unknown`이다. 그래서 공개 형 `Phrase.kind`가 `Int?`가 되었다. 회귀 시험 2개를 더했다.

**기능 추가·검토 필요**

- 비트 패킷(0x28): CDJ-2000nexus의 96바이트 형식과 장치 번호·마디 안 비트·곡 BPM·피치를 캡처로 확인했다. 능동·패시브 비트 이벤트와 CLI 출력을 추가했고 회귀 시험과 능동 CLI 실기를 확인했다. 실제 패시브 캡처도 2026-10-16에 확인했다(#6, §8)([#7](https://github.com/ImBada/DJLinkKit/issues/7)). 정밀 위치나 실제 다음 비트까지의 시간은 제공하지 않는다.
- localdb: 버튼이 있으면 알 수 없는 cue type도 hot_cue로 돌려준다. 원본 시험 주석은 cue도 loop도 아닌 항목을 뺀다고 하므로 검증 누락으로 보이지만 의도를 확정할 시험이 없다.
- Stagehand 제어(0x07)는 CDJ가 무시한다고 원본 문서(`docs/STAGEHAND.md` §6.1)에 적혀 있다.
- README는 가상 CDJ 번호로 5를 권하지만 기본값은 7이다(`src/constants.ts:9`). 우리 문서에는 7 이상만 적는다.
- MAC(#41, §11): IOKit `IOEthernetInterface`의 부모 항목 `IOMACAddress`는 권한 없이 실제 MAC을 준다(2026-10-16 macOS 27에서 확인). 이것으로 바꾸면 원본과 다르고, OS가 일부러 가린 값을 다른 길로 읽는 것이다. CDJ가 가린 값을 받아 주는 동안은 원본대로 둔다. Mac 여러 대를 한 망에 붙이는 용도가 생기면 다시 정한다.

**Link Export 원본에서 유지하는 동작**(2026-10-15, 아직 수정하지 않음)

- rbxport `Claim`의 첫/둘째 단계 선언 길이 44/50과 실제 인코딩 길이 42/48이 다르다. 원본 패킷·시험대로 보존한다.
- 원본이 읽을 수 있는 mixer discovery subtype `0x03`도 다시 인코딩할 때는 `0x02`가 된다. 원본의 재인코딩 결과를 유지한다.
- 스마트 목록의 `dateCreated` 조건은 원본처럼 `date_added` 컬럼을 읽고, 루트 마지막 XML 닫기 이름은 검사하지 않는다. 1:1 기준선 작성 중에는 의미를 바꾸지 않는다.

**고친 것**(2026-10-15, Link Export 실기)

- rbxport `rbl-dbserver/src/session.rs::track_info_rows`가 첫 항목 id를 1로 고정했다. CDJ-2000nexus가 WAV에도 MP3 디코더를 선택해 E-8305가 났다. 동일한 합성 WAV와 송수신 비교에서 이 id만 11로 바꾸자 정상 로드·재생·CUE 복귀를 확인했다. 이제 `TrackDetails.file_type`을 보내고, 0인 기존 Source는 기본값 1을 유지한다. 원본 대응 시험의 입력·기대값은 바꾸지 않고 실기 회귀 2개를 더했다. 원본 그대로인 기준선은 `port/rbxport-one-to-one` (`03d3371`)에 남긴다. [실기 기록](LINK-EXPORT-HARDWARE.md).
- 남은 레거시 큐 목록 읽기 `0x2104`는 [#20](https://github.com/ImBada/DJLinkKit/issues/20)에 기록했다. 원본에도 핸들러가 없으며, 기본 MP3/WAV 재생 성공을 큐 목록 복원 검증으로 간주하지 않는다.

**고친 것**(2026-10-16, Link Export 경로 오류 다시 보내기)

- 한 장치에게 보내는 패킷이 `EHOSTUNREACH`·`EHOSTDOWN`·`ENETUNREACH`로 실패하면 0.25초 간격으로 최대 20번 다시 보낸다. 방송과 다른 오류는 다시 보내지 않는다.
- 실기 기록: 참여 직후 CDJ에게 보낸 인사(`0x16`)와 장치 정보 답(`0x11`)이 "No route to host"로 실패했다. 그 순간 macOS는 CDJ 주소를 확인하는 요청(ARP)도 보내지 않았다. CDJ는 약 5초 뒤 다시 물었고, 그때 답을 받은 뒤 마운트했다(`BeaconRetryTests`).

**더한 것**(2026-10-16, Link Export 빠른 참여)

- `LinkExport.start(seedAnnouncements:)`·`Beacon.hear_seed`: 앱이 띄우기 전에 들은 장치 알림을 넣으면 CDJ의 다음 알림을 기다리지 않고 바로 번호 받기를 시작한다. 원본에는 없는 입구다. 캡처에서 rekordbox도 CDJ 알림을 들은 직후 첫 번호 요청을 보냈고, 알림 간격은 약 2초였다(`BeaconSeedTests`).

**고친 것**(2026-10-16, Link Export 목록 썸네일)

- 목록 썸네일 요청(인자 둘인 `ARTWORK` 0x2003)의 id를 원본은 줄 번호+2로 읽었다. 캡처에서 CDJ-2000nexus는 목록 줄의 곡 id로 물었고 rekordbox도 같은 id에 답했다. 곡 id가 1부터 이어지는 라이브러리에서는 앞 곡의 그림이 나왔다. 이제 곡 id(없으면 앨범 id)로 찾는다.
- rekordbox 7은 그림마다 원본(500~800px)·`_m`(240px)·`_s`(80px)를 둔다. 같은 요청에 rekordbox는 `_s`(약 3KB)를 보냈다. 원본은 `_m`(약 17KB)을 먼저 보내 썸네일이 늦게 떴다. 이제 목록에는 `_s` → `_m` → 원본 순서로, 큰 그림 요청(`CONTENT_ARTWORK`·인자 셋 이상)에는 원본처럼 `_m` → 원본 순서로 보낸다(`CatalogArtworkSizeTests`).

**고친 것**(2026-10-16, Link Export 보내기 실패)

- Swift `Beacon`의 `send`는 콜백 없이 보내, 보내기가 한 번 실패하면 `DualStackUDPSocket`이 소켓 오류로 올리고 상태 소켓의 `status_running`이 꺼진다. 그 뒤로는 상태 패킷을 보내지도, CDJ의 질의에 답하지도 않는다. 2026-10-16 DJCrate 앱에서 상태 송신이 첫 패킷 뒤 멈추고 CDJ-2000nexus의 LINK 화면에 Mac이 보이지 않았다. 2026-10-15 실기 실행 도구는 송신 기록 소켓이 늘 콜백을 넘겨 이 문제가 드러나지 않았다. 이제 `send`는 빈 콜백을 넘겨 실패를 버린다(`BeaconUpstreamFixTests.swift`).

**고친 것·실기 확인**(2026-10-15, Link Export #20)

- 원본 서버가 처리하지 않던 레거시 큐 목록 조회 `0x2104`를 기존 `usb_cue_reply`/`0x4702` 응답에 연결했다. 숫자 문맥·track ID를 검사하고, 읽기에서 편집 콜백을 호출하지 않는다. 메모리·A/B/C·루프·빈 목록과 기존 클라이언트 왕복 회귀 8개를 별도로 작성했다. 원본 대응 시험은 변경하지 않았다. 실기(CDJ-2000nexus)에서 시간순으로 섞어 보낸 목록이 핫큐 A 버튼을 끄고 CALL ▶를 A로 보내 E-8302를 냈다. CDJ가 앞의 memory 개수만큼을 메모리 큐로 읽는 것으로 보여 읽기 응답을 메모리 큐 먼저, 핫큐 뒤로 정렬했고, 그 뒤 메모리 큐·루프·A/B/C 호출을 모두 확인했다. 첫 실기의 메모리 큐 소실은 수정 뒤 재현하지 못했다. [구현·검증 기록](LINK-EXPORT-LEGACY-CUES.md).

**고친 것**(2026-10-16, Link Export 원본 동작)

- 큐 편집 응답(#32): rbxport의 `0x2105` 저장·삭제 응답은 편집 뒤 큐 목록을 시간순 그대로 보냈다. CDJ-2000nexus는 `0x4702`의 앞쪽 memory 개수만큼을 메모리 큐로 읽어(#20과 같은 원인) 편집 뒤 Hot Cue A 버튼이 꺼졌다. 읽기 응답처럼 메모리 큐를 먼저, 핫큐를 뒤에 보낸다. 원본 대응 시험은 큐가 하나뿐이라 영향이 없다. 편집을 거절할 때의 상태 0x32·빈 목록 응답은 원본(rekordbox와 같다는 원본 주석, `cue_writes.rs`)대로 둔다. 실기 기록은 [LINK-EXPORT-LEGACY-CUES.md](LINK-EXPORT-LEGACY-CUES.md).

**고친 것**(2026-10-16, 시험용 USB 실기)

- localdb(#13): 긴 ASCII 문자열(0x40)을 원본 Kaitai 정의처럼 +3부터 u16 length바이트 읽었다. rekordbox가 실제로 쓴 export.pdb(§8)는 UTF-16(0x90)과 같은 배치였다. u16은 머리 4바이트를 포함한 길이이고, 0 한 바이트 뒤 +4부터 length-4바이트가 본문이다(DJCrate 리더와 같다). 그래서 127자 이상 영문 제목·아티스트·앨범이 앞에 NUL이 붙고 다음 문자열 3바이트를 먹은 채로 읽혔다. 이제 +4부터 length-4바이트를 읽고, length가 4보다 작거나 행을 넘으면 거부한다. 실제 export에서 잘라 낸 바이트(합성 곡의 제목과 파일 이름)로 회귀 시험 2개를 `LocalDBUpstreamFixTests`에 더했다. 우리 바이트 리더 시험(`LocalDBReaderIntegrationTests`의 느슨한 문자열 시험)의 0x40 입력도 이 배치로 고쳤다. CLI의 기본 경로는 OneLibrary를 먼저 읽어서 rekordbox 7 export에서는 드러나지 않았고, `export.pdb`만 있는 장치에서 드러난다.

**고친 것**(2026-10-16, 패시브 실기)

- passive(#8): 캡처 중 인터페이스가 사라지면 오류 없이 영영 캡처 중으로 남았다(실기 `en8` USB 어댑터 제거, §8). 원본 cap의 반복은 `pcap_dispatch` 오류를 무시해 조용하다. 이제 `PcapAdapter`가 시작 뒤 1초마다 인터페이스 이름의 번호(`if_nametoindex`)를 시작 때의 번호와 견주어, 0이 되거나 바뀌면 `.error`(인터페이스 이름과 번호를 적은 `DJLinkError`)를 한 번 내고 캡처를 멈춰 백엔드를 닫는다. CLI는 이 오류를 "패킷 캡처 오류"로 보고 종료 코드 1로 끝낸다. 주소가 아니라 번호로 보는 것은 케이블만 뽑아도 169.254 주소가 사라지기 때문이다. 케이블만 뽑은 경우는 번호가 그대로여서 오류가 아니며 재연결 뒤 캡처가 이어진다. win32(장치 이름이 다름)와 시작 때 번호를 찾지 못한 이름(`any` 등)은 감시하지 않는다. 시계와 번호 조회는 `PcapAdapter.init`으로 주입하고, `PassiveProlinkNetwork`는 자기 시계를 어댑터에 넘긴다. `stop` 없이 어댑터가 해제되면 감시 타이머도 거둔다. 회귀 시험 8개를 `PassivePcapUpstreamFixTests`에 더했다.

**고친 것**(2026-10-16, remotedb 실기)

- remotedb(#46): `Message.fromStream`이 응답을 순서대로 읽고 트랜잭션 번호를 보지 않았다(`src/remotedb/message/index.ts`). CDJ-2000nexus 실기(분석하지 않은 곡)에서 첫 곡 조회가 성공한 약 1.7초 뒤 CDJ가 요청하지 않은 메시지(트랜잭션 0x03800122, 종류 0x4b02, 54바이트)를 보냈고, 다음 질의가 이것을 자기 응답으로 읽어(`Expected message type 0x4000, got 0x4b02`) 그 연결의 응답이 한 칸씩 밀렸다(`got 0x4001`, `got 0x4101`). 이제 `fromStream`에 `expectedTransactionId`를 더했다(기본값 nil은 원본 동작). 번호를 주면 그 번호가 아닌 메시지(CDJ가 먼저 보낸 것, 앞선 질의에서 남은 것)를 끝까지 읽어 버리고 debug 로그 한 줄만 남긴 채 다음 메시지를 읽으며, 종류 검사는 번호가 맞는 메시지에만 한다. `RemoteDatabase`·`PassiveRemoteDatabase`가 만드는 `Connection`은 켜 두어(`matchesTransactionIds`) `readMessage`가 마지막으로 쓴 요청의 번호로 읽는다. 메뉴 질의의 머리(0x4001)·항목(0x4101)·꼬리(0x4201)는 렌더 요청(0x3000)을 쓴 번호를 따른다. 소개 응답은 소개 요청과 같은 0xfffffffe로 맞춘다. `Connection`을 직접 만들면 기본값은 원본처럼 번호를 보지 않는다(원본 대응 시험이 번호 없는 응답을 쓴다). CDJ-2000nexus는 요청의 번호를 되돌려 보낸다. 같은 날 #9 캡처에서 소개 응답(0xfffffffe), 0x4000, 메뉴 머리(0x4001)·항목(0x4101)·꼬리(0x4201)가 모두 요청의 번호였고, 끼어든 메시지만 0x03800122였다. CLI는 `--verbose`일 때 건너뛴 메시지를 debug 로그로 보인다. 다른 번호의 메시지는 응답 하나당 16개(`Message.maxSkippedMessages`)까지만 건너뛰고 더 오면 오류로 끝낸다(끼어드는 메시지가 끝없이 오면 #47의 유휴 제한이 늘어나기만 하므로). 비교는 번호가 u32로 쓰이는 것에 맞춰 하위 32비트로 한다. 회귀 시험은 `RemoteDBUpstreamFixTests`에 11개(이슈의 54바이트를 입력으로 쓴다)와 `PassiveRemoteDBUpstreamFixTests`에 1개.
- remotedb(#47): `connectToDevice`가 연결을 마치면 `setTimeout(0)`으로 시간 제한을 꺼서(`src/remotedb/index.ts`) 응답이 없는 질의가 영영 기다리고 그 장치의 잠금을 쥔 채 이후 조회도 막았다(CDJ-2000nexus 실기, 40초 넘게 무응답). 이제 `QueryInterface.query`가 응답을 기다리는 동안 소켓 제한을 10초(연결할 때와 같은 값, `Connection.queryTimeoutMilliseconds`)로 걸고, 질의가 성공하든 실패하든 끝나면 푼다. 소켓의 유휴 제한이라 응답이 오는 동안에는 늘어나고 10초 동안 바이트가 없을 때만 넘는다. 넘으면 연결을 닫고(`destroy`) 질의를 `DJLinkError("RemoteDB query to <ip> timed out")`로 끝낸다. 장치 잠금이 풀리고, 닫힌 연결은 다음 `RemoteDatabase.get`이 버리고 새로 연결한다. 놀고 있는 연결은 원본처럼 제한 없이 열려 있다. 패시브도 같은 `QueryInterface`를 쓰므로 같이 적용된다. 원본 패시브 `get`은 닫힌 연결을 그대로 돌려주어 시간 제한 뒤에도 같은 연결로 계속 실패하므로, 능동처럼 닫힌 연결은 버리고 새로 연결한다. 회귀 시험 4개를 `RemoteDBUpstreamFixTests`에 더했다(무응답 뒤 재연결, 응답이 오는 동안 늘어나는 제한, 질의가 성공·실패로 끝난 뒤 제한을 푸는 것). 패시브 재연결 시험 1개는 `PassiveRemoteDBUpstreamFixTests`에 있다. 같은 날 실기에서 무응답 조건을 다시 만나 10초마다 끊고 다시 연결하는 것을 확인했다(§8).
- remotedb(#48): CDJ-2000nexus는 질의가 빌린 번호(원본 `pickRemoteDbQueryId`)의 플레이어가 망에 없으면 분석하지 않은 곡의 메타데이터 질의(0x2202)에 항목 0개로 답한다. 원본은 필수 항목을 찾다 `Cannot read properties of undefined`로 실패했다. 이제 렌더 요청 없이 `RemoteDBNoMetadataItemsError`로 끝내고, 그 설명에 까닭을 적는다. watch는 이 오류를 실패로 세어 다시 시도하므로 그 플레이어가 돌아오면 회복된다. rekordbox 곡(0x2002)의 항목 0개는 원본처럼 빈 곡과 진단 경고로 둔다(원본 `blankMetadata.spec.ts`가 이 동작을 정한다). 질의 번호 정책과 announce 7 이상 규칙은 바꾸지 않는다(§11). 실기에서 받은 42바이트 응답으로 회귀 시험 2개를 `RemoteDBUpstreamFixTests`에 더했다.

**고친 것**(2026-10-15, Link Export Swift 쪽)

원본 rbxport의 버그가 아니라 우리 Swift 구현의 문제다. 원본 대응 시험은 바꾸지 않았고 자체 회귀 시험을 더했다.

- 정렬 키(#24): 파일명·이름·앨범 메뉴의 정렬 비교자가 비교할 때마다 문자열을 접고 복원했다. 원본의 `sort_by_cached_key`처럼 행마다 키를 한 번만 만든다. 순서는 같다(UTF-8 바이트 순서, 동률은 행·밀집 id 순서). 자체 회귀 3개.
- 스마트 목록 날짜(#25): `SmartDate.today`가 `Calendar.current`를 써서 일본력·불교력 등을 쓰는 Mac에서 연도가 달라졌다. 원본 chrono `Local`처럼 현지 시간대의 그레고리력 연월일을 쓴다. 자체 회귀 1개.
- 실제 소켓 가드(#28): Export의 가드가 `DJLINK_LOOPBACK_TESTS`와 관계없이 시험 프로세스에서 늘 소켓을 막아 루프백 시험을 돌릴 수 없었다. DJLinkKit처럼 `DJLINK_LOOPBACK_TESTS=1`일 때만 허용하고, 그때도 시험 프로세스에서는 TCP를 127.0.0.1·::1에만 묶고 그쪽으로만 연결하며, UDP는 127.0.0.1·::1로만 보낸다(UDP RPC 소켓은 원본처럼 0.0.0.0에 묶은 뒤 인터페이스를 고정하므로 보내는 주소를 검사한다). 자체 회귀 2개와 `rbl-fakecdj/tests/loopback.rs` 대응 8개를 더했다.

## 10. 라이선스·출처

**LICENSE**

- 2026-10-15 이후 **GPL-2.0-or-later**로 통일한다(`DJLinkExport`가 GPL인 rbxport의 파생물이기 때문). 원래는 MIT였고, 원본 LICENSE의 저작권 표시("Copyright (c) 2013 Evan Purkhiser")와 허가 문구는 `LICENSES/MIT.txt`에 그대로 보존한다. 저작권 범위는 `COPYRIGHT.md`에 있다.

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

- 시험은 기본적으로 실제 소켓을 열지 않는다(원본 시험도 0개다). 예외는 아래 루프백 시험뿐이다.
- 실제 소켓을 만드는 쪽(`SocketFactory.live`)은 시험 프로세스에서 부르면 바로 실패하게 한다. DJCrate의 `TestProcess`처럼 시험 프로세스를 알아본다.
- 루프백(127.0.0.1) 통합 시험은 `DJLINK_LOOPBACK_TESTS=1`일 때만 따로 돈다(DJLinkKit 8개, Link Export 8개). Link Export의 실제 소켓 가드(`LiveExportSocketFactory`)도 같은 조건에서만 열고, 그때도 시험 프로세스에서는 TCP를 127.0.0.1·::1에만 묶고 그쪽으로만 연결하며, UDP는 127.0.0.1·::1로만 보낸다(UDP RPC 소켓은 원본처럼 0.0.0.0에 묶은 뒤 인터페이스를 고정하므로 보내는 주소를 검사한다)(#28). 시험은 LAN에 아무것도 보내지 않는다.

**실기와 CLI**

- 공연이나 리허설 중인 네트워크에서 돌리지 않는다.
- 같은 Mac에서 rekordbox·rekordboxAgent가 켜져 있으면 UDP 50000~50002를 잡지 않는다. 잡으면 rekordbox LINK가 망가질 수 있다. `djlink`는 시작할 때 이것을 확인하고 거부한다. 이 확인은 CLI·앱 쪽 규칙이며 라이브러리 동작(1:1)에는 넣지 않는다.
- 가상 CDJ 번호는 7 이상만 쓴다(CLI 기본값). 1~6은 실기 확인에서 일부러 고른 경우만 쓴다. 번호가 겹쳐 다시 고를 때도 같다(허용하지 않는 번호로는 announce하기 전에 멈춘다).
- 메모(remotedb 질의 번호 예외, 바꾸지 않음): 위 7 이상 규칙은 announce 번호에 대한 것이다.
  remotedb 메시지 안의 장치 번호는 원본 `pickRemoteDbQueryId`가 1~6 중에서 고른다.
  CDJ가 1~6만 답하기 때문이며 원본 주석에 CDJ-3000 실기 확인(2026-08-30)이 있다.
  그래서 가상 CDJ가 7 이상이어도 remotedb 질의에는 같은 랙의 다른 CDJ 번호(없으면 비어 있는 1~6)가 실린다.
  1:1이라 고치지 않았고, CLI는 연결할 때 고른 번호를 한 줄 로그로 남긴다.
  CDJ-2000nexus(2026-10-16, §8)는 announce 7번 가상 CDJ가 질의 번호 2번(옆 CDJ의 번호)을 실은 Introduce를 받아 줬고, 질의하는 동안 두 덱의 상태는 바뀌지 않았다. 분석하지 않은 곡의 remotedb 조회도 이 번호로 성공했다. 다만 빌린 번호의 플레이어가 망에 없으면 항목 0개로 답하고, 그 플레이어가 망에서 빠졌다 다시 붙은 뒤에는 답하지 않았다(#48). 결정(2026-10-16, #48): 정책과 announce 7 이상 규칙은 그대로 둔다. rekordbox로 분석한 곡은 remotedb가 아니라 NFS(localdb)로 읽으므로 영향이 없다. CDJ-2000nexus에서 분석하지 않은 곡의 remotedb 조회는 될 때만 되는 것으로 문서에 적는다. 항목 0개는 까닭을 적은 오류로, 무응답은 10초 시간 제한(#47)으로 끝난다. 가상 CDJ를 1~4번으로 참여시키면 더 안정적일 수 있으나 실제 플레이어와 번호가 겹칠 위험이 있어 쓰지 않는다.
- 소켓은 고른 인터페이스에 묶고 그 서브넷 밖의 장치와는 통신하지 않는다. `play`·`pause`는 재생 상태 패킷에 칸이 있는 1~4번 플레이어에만 보낸다(§9, 2026-10-14 실기 확인 뒤 고침).
- 제어 명령(곡 올리기, Stagehand 설정 쓰기)은 CLI에서 `--confirm <장치 이름>` 없이는 보내지 않는다.
- MAC(#41): macOS 27.0.1에서 일반 프로세스가 `getifaddrs`의 AF_LINK로 읽으면 `en0`·`en8` 모두 `02:00:00:00:00:00`이 나온다(`ifconfig`는 실제 값). `SystemInterfaceProvider`가 이 값을 그대로 써서 가상 CDJ(7번)와 Link Export(17번)가 announce·keep-alive에 이 MAC을 싣는다(2026-10-16 pcap). 원본(Node `os.networkInterfaces`)도 같은 시스템 호출이다. CDJ-2000nexus는 이 값으로도 두 장치를 받아 줬다. Mac 여러 대가 같은 망에 있으면 같은 MAC을 알리고, Stagehand 모드의 MAC(OUI + 하위 3바이트)도 모두 같아진다. 바꿀지는 §9 "기능 추가·검토 필요"에 둔다.
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

- 원본 시험을 실제로 돌려 보지 않았다. 고정 커밋에서 532개가 모두 통과하는지 모른다. 기대값은 시험 코드에 적힌 값을 따른다.
- onelibrary-connect·metadata-connect의 시험 개수. 파일 수(1개, 2개)만 셌다.
- SQLCipher.swift 패키지가 SPM product를 내주는지.
- 펌웨어 근거 표시가 없는 원본 부분(Stagehand, CDJ-3000X 등)이 어디서 왔는지.
- 시험 개수는 `grep -cE "^\s*(it|test)(\.each)?\("`로 셌다. 들여쓰기가 다르거나 동적으로 만든 시험이 있으면 숫자가 어긋날 수 있다. 0단계의 `port-status.sh`로 다시 센다.
