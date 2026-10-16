# DJLinkKit — alphatheta-connect Swift 포팅 계획

TypeScript 라이브러리 alphatheta-connect를 Swift 패키지로 1:1 옮긴다. 원본 시험은 입력과 기대값을 그대로 둔 채 옮겨 모두 통과시킨다. 1:1 포트는 끝났고, main은 그 위에 원본 버그를 고친 것(§9)을 더한 상태다. DJCrate가 이 패키지를 불러 쓴다(§13).

## 1. 목표와 범위

**대상**

- 원본의 공개 동작을 Swift로 똑같이 옮긴다.
  - 장치 발견, 가상 CDJ로 참여·번호 정하기
  - CDJ·믹서 상태, 정밀 위치, on-air
  - remotedb로 메타데이터·파형·그리드·큐·재생 목록 받기
  - NFS로 파일 받기, USB DB(`export.pdb`·`exportLibrary.db`)와 ANLZ 읽기
  - 앨범아트·태그, mixstatus, 제어 명령, 패시브(pcap) 모드, CLI
- 원본 시험과, 원본이 기대는 두 저장소(§2)의 시험을 옮긴다.
- 펌웨어 분석에 근거한 원본 지식도 옮긴다(§10).

**범위 밖**

- `src/remote/`(HTTP 서버·Hue 조명)와 `src/utils/telemetry.ts`의 Sentry 보고. 원본 시험이 없다. telemetry를 부르는 자리는 아무것도 하지 않는 함수로 둔다.
- CDJ에 라이브러리를 내주는 쪽(Link Export 서버)은 이 포트의 범위 밖이다. rbxport를 원본으로 한 [별도 서버 이식](LINK-EXPORT-PLAN.md)으로 진행한다.
- 1:1을 마치기 전에 기능을 더하거나 버그를 고치는 일(§9).

## 2. 원본 (고정 커밋)

| 저장소 | 커밋 | 라이선스 | 쓰는 부분 |
|---|---|---|---|
| [chrisle/alphatheta-connect](https://github.com/chrisle/alphatheta-connect) | `7496991` (v0.28.5, 2026-10-04) | MIT, Copyright (c) 2013 Evan Purkhiser | 범위 밖을 뺀 전부 |
| [chrisle/onelibrary-connect](https://github.com/chrisle/onelibrary-connect) | `ac3edd3` (2026-09-26) | MIT | `getEncryptionKey`, `OneLibraryAdapter`, `openOneLibraryDb`과 형들. 시험 1개 파일 |
| [chrisle/metadata-connect](https://github.com/chrisle/metadata-connect) | `c2ae262` (2026-09-08) | MIT | `extractMetadata`, `isExtensionSupported`, `FileReader`(부분 읽기). 시험 2개 파일 |

- alphatheta-connect는 두 저장소를 `file:../`로 불러온다. 그래서 세 저장소를 같은 부모 폴더 아래에 나란히 받는다(예: `~/src/upstream/`).
- 받은 원본은 읽기만 한다. 그 안에서 npm이나 스크립트를 돌리지 않는다.

## 3. 결정 사항

| 항목 | 결정 | 이유 |
|---|---|---|
| 패키지 이름 | `DJLinkKit` | AlphaTheta·PRO DJ LINK는 상표라서 이름에 넣지 않는다. README에 "PRO DJ LINK 호환, AlphaTheta와 관계없는 독립 프로젝트"라고 고지한다 |
| 플랫폼 | macOS 15 이상, swift-tools 6.2, Swift 6 언어 모드(엄격 동시성) | macOS 15부터 로컬 네트워크 권한이 생겼다. Linux는 지원하지 않는다 |
| localdb | 1:1로 옮긴다 | kaitai `.ksy`(EPL-1.0)는 옮기지 않는다. 파서는 같은 저작자의 MIT 코드인 DJCrate 리더를 출발점으로 쓴다(§7) |
| control | 별도 product `DJLinkControl` | 공연 중인 장비를 움직이는 기능이다. 쓰는 쪽이 골라서 넣게 한다 |
| passive | 별도 product `DJLinkPassive` | libpcap과 BPF 권한이 필요하다 |
| CLI | `djlink` 실행 파일 | 실기 확인에 쓴다 |
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
- 매개변수 시험(`tests/utils/index.spec.ts`의 jest-each, metadata-connect `test/label.test.ts`의 `it.each`)은 각각 `@Test(arguments:)` 하나로 옮기고, `port-status.sh`도 한 개로 센다.

## 5. 구조

제품은 `DJLinkKit`, `DJLinkControl`, `DJLinkPassive`(시스템 라이브러리 `CPcap`에 의존), `djlink` 실행 파일이다. 시험 지원 타깃 `DJLinkTestSupport`가 가짜 소켓·시계를 내준다. 그 뒤 Link Export 타깃(`DJLinkExport*`, [LINK-EXPORT-PLAN.md](LINK-EXPORT-PLAN.md))과 `djlinkTests`가 더해졌다. 실제 구성은 `Package.swift`에 있다.

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

파일 단위 대응표는 [port-map.md](port-map.md)에 있다.

## 6. Node → Swift 바꿈표

| 원본 | Swift | 시험에서 |
|---|---|---|
| `dgram`(UDP) | `UDPSocket` 프로토콜. 실제 구현은 BSD 소켓과 DispatchSource로, `SO_REUSEADDR`·`SO_BROADCAST`를 켜고 `0.0.0.0`에 바인드한다. Network.framework는 브로드캐스트를 지원하지 않아 쓰지 않는다 | `FakeUDPSocket`: 보낸 바이트를 기록하고, 받은 패킷을 주입한다 |
| `net`·`promise-socket`(TCP) | `TCPConnection` 프로토콜. 실제 구현은 `NWConnection` | `FakeTCPConnection`: 정해 둔 순서대로 주고받는다 |
| `setTimeout`·`setInterval`, jest 가짜 타이머 | `any Clock<Duration>`을 주입한다 | 직접 만든 `TestClock`(`advance(by:)`) |
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
| `jest.mock`(모듈 바꿔치기) | 위에서 프로토콜로 주입한 자리에 가짜를 넣는다 | |

## 7. localdb와 DJCrate 리더

**원본 구조**

- kaitai로 `export.pdb`와 ANLZ를 읽어 메모리 SQLite(`MetadataORM`)에 채우고, 그 위에서 질의한다.
- OneLibrary는 onelibrary-connect로 SQLCipher DB를 연다.

**옮기는 방법**

- kaitai `.ksy` 2개(Deep Symmetry crate-digger 출신, EPL-1.0)는 쓰지 않는다.
- 대신 DJCrate(MIT, 같은 저작자)의 PDB·OneLibrary·ANLZ 리더와 `CipherDatabase`를 옮겨 출발점으로 삼는다. 이 리더들에 해당하는 DJCrate THIRD_PARTY_NOTICES 항목(pyrekordbox·baken·rekordbox_converter, 칸 위치만 참고한 rekordcrate·Crate Digger 문서)도 같이 옮긴다. 파일별 출처는 [port-map.md](port-map.md) §6.
- 이 리더 위에 원본 localdb의 바깥 모양(형, 필드 이름, 빈 값 처리, 2EX, 노래 구조, 보컬 설정)을 그대로 만든다.
- DJCrate 리더와 원본 시험의 결과가 다르면 원본 시험이 정답이다(1:1).
- `CipherDatabase`와 함께 DJCrate의 cold-open 경쟁 시험도 옮긴다. SQLCipher 초기화 경쟁은 DJCrate에서 실제로 겪은 문제다.

**SQLCipher**

- DJCrate가 `SQLCipher.xcframework`를 `binaryTarget`으로 직접 선언하면, 이 패키지가 같은 이름의 타깃을 선언할 때 서로 부딪친다.
- 그래서 이 패키지는 [SQLCipher.swift](https://github.com/sqlcipher/SQLCipher.swift) 패키지(4.19.0)의 `SQLCipher` product에 의존한다. DJCrate도 같은 패키지 의존으로 맞춘다.

**픽스처**

- 원본의 `tests/localdb/fixtures/test-onelibrary.db`는 공개 저장소에 들이기 전에 개인 데이터와 토큰이 없는지 확인한다.

## 8. 단계

각 단계는 원본 시험 옮기기 → 원본 코드 옮기기 → 사용자가 "구현 완료"라고 하면 그 단계와 앞 단계의 시험 돌리기 → 끝 조건 확인 순서로 진행했다. 모든 단계를 마쳤다.

**끝 조건**(모든 단계 공통)

- `scripts/port-status.sh`에서 원본 `it(` 수와 옮긴 `@Test` 수가 파일마다 같다.
- 그 단계와 앞 단계의 시험이 모두 통과한다.
- 기본 실행(`swift test`)에서 실제 소켓을 연 시험이 0개다. 예외는 `DJLINK_LOOPBACK_TESTS=1`일 때만 도는 루프백 시험이다(§11).

| 단계 | 원본 | 원본 시험 파일 | 시험 수 |
|---|---|---|---|
| 0 뼈대 | — | — | 0 |
| 1 기초·상태 | `constants`·`types`·`entities`, `utils/`, `devices/`, `status/` | `tests/utils/index`, `tests/devices/index`·`utils`, `tests/status/utils`·`position`·`on-air`, `src/status/stagehand-gating` | 50 |
| 2 가상 CDJ·네트워크 | `virtualcdj/`, `network.ts`, `index.ts` | `src/virtualcdj/heartbeat`, `tests/virtualcdj/conflict`·`device-id`·`stagehand`·`startup`·`wire-selection`, `tests/network/stagehand-identity` | 84 |
| 3 remotedb·NFS | `remotedb/`, `nfs/` | `tests/remotedb/connection`·`fields`, `src/nfs/index`, `tests/nfs/path` | 47 |
| 4 localdb | `localdb/`, onelibrary-connect | `tests/localdb/` 12개 파일, onelibrary-connect 1개 파일 | 234 + 62 |
| 5 db·앨범아트·태그 | `db/`, `artwork/`, `metadata.ts`, metadata-connect | `tests/db/` 4개 파일, `tests/artwork/` 2개 파일, metadata-connect 2개 파일 | 46 + 28 |
| 6 mixstatus | `mixstatus/` | `tests/mixstatus/index` | 29 |
| 7 제어 | `control/` | `tests/control/load`·`stagehand` | 11 |
| 8 패시브 | `passive/` | `tests/passive/alphatheta`·`pcap-adapter` | 31 |
| 9 CLI·실기 확인 | `cli/` | — | 0 |
| 합 | | 44개 파일 | 622 |

파일별 개수는 [port-map.md](port-map.md)에 있다.

**실기 확인 방법**

- 시험용 스위치에 CDJ와 믹서만 묶는다. 공연이나 리허설 중인 네트워크는 쓰지 않는다. 같은 Mac의 rekordbox·rekordboxAgent는 꺼 둔다. 가상 CDJ는 7번.
- 순서: 장치 목록 → 참여·번호 겹침 → 상태·정밀 위치·on-air → remotedb → NFS → mixstatus → 마지막에 따로 제어 명령.
- 확인하면서 받은 패킷을 pcap으로 남겨 회귀 시험 입력으로 쓴다. 개인 곡이 없는 시험용 USB와 합성 곡으로만 캡처하고, 원시 pcap·로그는 저장소 밖에 둔다.

**실기 확인 기록**

장비는 CDJ-2000nexus 2대(1·2번), DJM-900NXS2(33번), Mac의 USB 랜 어댑터(169.254/16, 라우터 없음), 가상 CDJ 7번이다(2026-10-14~16). Link Export 쪽 실기는 [LINK-EXPORT-HARDWARE.md](LINK-EXPORT-HARDWARE.md)에 있다.

- 확인한 기능: 장치 목록, 7번으로 참여, 상태(재생 상태·곡·BPM·피치·master·마디 안 비트), `watch`, 메타데이터·비트 그리드·파형·큐, NFS로 `export.pdb`·`exportLibrary.db` 받기, `djprofile.nxs` 거부, 곡 올리기, play·pause, on-air, mixstatus, 비트 패킷, pcap과 `passive`, remotedb(분석하지 않은 곡), Ctrl-C 정리(종료 코드 130, 남은 소켓 없음).
- rekordbox로 분석한 곡의 메타데이터는 remotedb가 아니라 NFS로 받은 USB DB에서 온다. 원본도 localdb로 읽는다(`getTrackLookupStrategy`). remotedb는 USB 폴더에만 넣은 분석하지 않은 곡으로 확인했다.
- 재생 상태 패킷: 칸 i가 플레이어 i+1이고 0 = 시작, 1 = 정지(cue), 2 = 그대로다. 원본 패킷으로는 `pause`가 대상을 멈추지 못했다. CDJ는 자기 칸만 읽어 다른 덱은 움직이지 않았다(§9 제어).
- on-air: DJM-900NXS2는 종류 0x03, 45바이트, `0x20` = 0x02인 패킷을 50001로 보낸다. 원본은 하나도 읽지 못했다(§9 status).
- keep-alive(0x06)는 CDJ·DJM 모두 54바이트이고 `0x30`이 장치 수다. 원본은 55바이트였다(§9 virtualcdj).
- 비트 패킷(0x28)은 96바이트다. 장치 번호·마디 안 비트(1~4 순환)·곡 BPM·피치가 CDJ 상태와 맞고, 정지하면 멈춘다. 앞부분 시간 필드, 양수 피치·sync·역재생과 다른 기종은 확인하지 못했다. 근거는 PROVENANCE §D.
- mixstatus: 믹서가 없으면 on-air가 꺼져 있어 기본 설정(`useOnAirStatus`)에서는 `stopped`만 난다(원본과 같다). 믹서가 있으면 on-air 덱만 `set started`·`now playing`을 내고, 정지 30초 뒤 `set ended`, 같은 덱·같은 곡을 다시 틀면 새 세트로 보고한다.
- 연결 끊김: CDJ LAN을 빼면 약 10초 뒤 이탈하고 다시 꽂으면 같은 프로세스가 재발견한다. Mac LAN 케이블을 빼도 CLI는 살아 있고, 같은 IPv4 주소를 다시 받으면 수신이 이어진다. 다른 주소로 바뀌는 경우는 확인하지 않았다. 이때 드러난 임시 DB 부속 파일 잔존([#16](https://github.com/ImBada/DJLinkKit/issues/16))과 watch 재조회 누락([#17](https://github.com/ImBada/DJLinkKit/issues/17))은 고쳤다(§9 CLI).
- 링크 로컬 인터페이스: `NWPathMonitor`가 기본 경로만 보여 주어, 링크 로컬 주소만 있는 인터페이스로 remotedb TCP를 열지 못했다([#40](https://github.com/ImBada/DJLinkKit/issues/40)). 인터페이스의 IPv4 주소를 로컬 주소로 지정하고 연결 뒤 경로를 검사하게 고쳤다.
- 패시브 인터페이스 제거([#8](https://github.com/ImBada/DJLinkKit/issues/8)): 케이블만 빼면 인터페이스가 남아 재연결 뒤 캡처가 이어진다. USB 어댑터를 빼면 원본은 오류 없이 영영 캡처 중으로 남았다(§9 passive).
- MAC: 일반 프로세스가 읽은 MAC이 가려져 실린다(#41, §11).
- remotedb 질의 번호([#9](https://github.com/ImBada/DJLinkKit/issues/9)): 원본 `pickRemoteDbQueryId`대로 옆 CDJ의 번호(2번)를 빌린 Introduce를 CDJ가 받아 주고, 질의 동안 두 덱의 상태는 바뀌지 않는다. 빈 USB 슬롯에는 시간 초과가 아니라 0x4003 오류로 답한다. 빌린 번호의 플레이어가 망에 없으면 항목 0개로 답하고, 빠졌다 다시 붙은 뒤에는 답하지 않을 수 있다(#48, §11 메모).
- remotedb 실기에서 찾은 원본 결함: 곡을 올리는 순간의 질의가 40초 넘게 무응답이면 영영 기다렸다(#47). 곡을 읽은 뒤 CDJ가 요청하지 않은 메시지(트랜잭션 0x03800122, 종류 0x4b02)를 보내 이후 응답이 한 칸씩 밀렸다(#46). 고친 뒤 같은 연결에서 여러 곡을 읽고, 무응답이면 10초마다 끊고 다시 연결하는 것을 확인했다(§9 remotedb).
- 긴 문자열([#13](https://github.com/ImBada/DJLinkKit/issues/13)): rekordbox는 127자 이상 영문을 0x40 형식으로 쓴다. 머리 `40 LL LL 00`의 u16은 본문 길이 + 4이고 본문은 +4부터다(UTF-16 0x90과 같은 배치). 코멘트는 `export.pdb`에서 찾지 못했다(§9 localdb).
- 확인하지 못한 것: 가상 CDJ 하나 더(번호 겹침), CDJ-3000(정밀 위치), 6채널 믹서(on-air 6채널 변형).

## 9. 1:1 이후 고칠 것

1:1이 모두 통과한 뒤에 고친다. 하나마다 실패하는 시험을 먼저 더하고 따로 커밋한다. 1:1 기준선은 `port/one-to-one` 브랜치이고, 고친 것은 main에 있다(§12). 원본 대응 시험의 기대값을 바꿔야 했던 곳은 그 시험 위에 `// PLAN §9:` 주석을 단다. 새 시험은 영역마다 `*UpstreamFixTests.swift`에 둔다. 예외로 패시브 UDP 길이 시험(`UDP payload keeps every byte and a standard announce uses the full format`)은 `PassiveFlowTests.swift`에 있다.

**고친 것: alphatheta-connect 계열**

- status
  - 정밀 위치 파서가 패킷 종류 바이트(0x0a = 0x0b)를 보지 않아 같은 50001 포트의 비트 패킷도 위치로 읽었다(`src/status/utils.ts:132`). 능동·패시브 모두 고쳤다.
  - on-air 패킷을 상태 소켓(50002)에서만 읽었다(`src/status/index.ts:122`). DJM-900NXS2는 50001로 보낸다. 4채널 파서도 `0x20` = 0x00과 0x2e바이트 이상만 받아 실제 패킷(`0x20` = 0x02, 0x2d바이트)을 버렸다. 이제 능동·패시브 모두 50001의 종류 0x03 패킷도 읽고, 4채널은 `0x20`이 0x00·0x02이고 0x2d바이트 이상이면 받는다. 6채널 변형은 장비가 없어 그대로 두었다.
- devices: `getDeviceEnsured`가 장치가 먼저 와도 시간 제한 타이머를 지우지 않았다. 능동·패시브(#23) 모두 고쳤다.
- virtualcdj
  - announcer의 `ready`를 다시 부르면 앞서 기다리던 쪽이 풀리지 않았다.
  - `makeStatusPacket`이 머리말을 0x0b에 썼다(정의만 있고 쓰이지 않는 함수).
  - keep-alive(stage 0x06)에 원본이 0x30 한 바이트를 더 넣어 55바이트가 되고 장치 수가 0x31로 밀렸다. 실제 장비처럼 54바이트, 0x30이 장치 수가 되게 고쳤다.
- network: `bringOnline`에서 bind가 실패하면 앞서 만든 소켓을 닫지 않았다.
- 제어: 재생 상태 패킷(`src/control/index.ts`)이 칸 번호(0–3)를 `device.id`와 견주고 나머지 칸을 0(시작)으로 채웠다. 대상이 한 칸 어긋나 1번에 보낸 `pause`가 1번을 계속 재생시켰다. 이제 칸 `device.id - 1`에 명령을 싣고 나머지 칸은 2(그대로)로 채운다. 칸이 없는 번호(1~4 밖)와 재생·cue 밖의 재생 상태는 보내지 않고 오류를 낸다(원본은 0, 즉 시작을 보냈다). `djlink`의 `play`·`pause`는 1~4번에만 보낸다.
- mixstatus
  - 같은 곡을 다시 틀면 30초 뒤 재생 중에 `setEnded`가 났다.
  - `isSetActive`가 돌아가지 않아 두 번째 세트에서 `setStarted`가 나지 않았다.
  - `setMayStop`이 두 번 불리면 앞 타이머를 지울 수 없었다.
  - 같은 데크에서 같은 곡으로 새 세트를 시작하면 `nowPlaying`·`setStarted`가 모두 나지 않았다(중복 억제 `lastEmittedTrackId`가 세트가 끝나도 남았다).
- localdb
  - PDB 쪽 사슬이 순환하면 무한 루프에 빠졌다(이제 오류). 쪽 번호 비교로 비단조 사슬에서 일찍 끝나거나 빈 후보 뒤로 읽었다(이제 링크를 따라 마지막 쪽·빈 후보에서 끝낸다).
  - 장치 제거 때 첫 DB만 닫았다. OneLibrary 쓰기·열기에 실패하면 임시 파일이 남았다. 둘 다 능동·패시브(#23) 모두 고쳤다.
  - `loadAnlz`가 PCOB·PCO2 태그마다 결과를 덮어써(`src/localdb/rekordbox/index.ts:76-83`) 핫 큐·메모리 목록 중 마지막 태그만 남았다(#22). 같은 종류 태그를 파일 순서대로 잇는다. 패시브도 같은 `loadAnlz`를 쓴다.
  - PSSI의 mood가 1~3 밖이면 1:1 기준선은 EXT 전체를 실패시켰다(#26). 원본 Kaitai처럼 kind를 0바이트 `unknown_tag`로 읽어, `kind`는 nil, `phraseType`은 `Unknown`이다. 그래서 공개 형 `Phrase.kind`가 `Int?`가 되었다.
  - 긴 ASCII 문자열(0x40)을 원본 Kaitai 정의처럼 +3부터 u16 length바이트 읽었다(#13). rekordbox가 실제로 쓴 `export.pdb`는 UTF-16(0x90)과 같은 배치다(§8). 그래서 127자 이상 영문 제목·아티스트·앨범이 앞에 NUL이 붙고 다음 문자열 3바이트를 먹은 채로 읽혔다. 이제 +4부터 length-4바이트를 읽고, length가 4보다 작거나 행을 넘으면 거부한다(DJCrate 리더와 같다). 회귀 시험은 실제 export에서 잘라 낸 합성 곡 바이트를 쓴다. CLI 기본 경로는 OneLibrary를 먼저 읽어 rekordbox 7 export에서는 드러나지 않고, `export.pdb`만 있는 장치에서 드러난다.
- metadata-connect·artwork: mp4 문자열 atom(`©nam` 등)이 맞지 않았다 / ID3 프레임 ID 앞부분 비교로 `TCOM`·`TCOP`이 장르로 읽혔다 / 값이 모두 비어도 결과가 null이 아니었다 / APIC의 BOM 검사 위치(겉으로 드러나는 동작 변화 없음) / ID3 v2.3 확장 헤더 크기에 4바이트가 빠졌다.
- passive
  - UDP 길이를 두 번 빼서 payload 끝 8바이트가 잘리고 표준 announce가 short format으로 읽혔다.
  - 캡처 중 인터페이스가 사라지면 오류 없이 영영 캡처 중으로 남았다(#8). 원본 cap의 반복은 `pcap_dispatch` 오류를 무시한다. 이제 `PcapAdapter`가 1초마다 인터페이스 번호(`if_nametoindex`)를 시작 때 번호와 견주어, 0이 되거나 바뀌면 `.error`를 한 번 내고 캡처를 멈춘다. CLI는 이것을 "패킷 캡처 오류"로 보고 종료 코드 1로 끝낸다. 주소가 아니라 번호로 보는 것은 케이블만 뽑아도 169.254 주소가 사라지기 때문이다. win32와 시작 때 번호를 찾지 못한 이름(`any` 등)은 감시하지 않는다. 시계와 번호 조회는 `PcapAdapter.init`으로 주입한다.
- remotedb
  - 트랜잭션 번호(#46): `Message.fromStream`이 응답을 순서대로 읽고 트랜잭션 번호를 보지 않았다(`src/remotedb/message/index.ts`). CDJ가 요청하지 않은 메시지(0x4b02)를 끼워 보내면 그 연결의 응답이 한 칸씩 밀렸다. 이제 `fromStream`에 `expectedTransactionId`를 더했다(기본값 nil은 원본 동작). 번호를 주면 다른 번호의 메시지를 읽어 버리고 debug 로그를 남기며, 종류 검사는 번호가 맞는 메시지에만 한다. 응답 하나당 16개(`Message.maxSkippedMessages`)까지만 건너뛰고 더 오면 오류로 끝낸다. 비교는 하위 32비트로 한다. `RemoteDatabase`·`PassiveRemoteDatabase`가 만드는 `Connection`은 이것을 켜고(`matchesTransactionIds`), `Connection`을 직접 만들면 원본처럼 번호를 보지 않는다(원본 대응 시험이 번호 없는 응답을 쓴다). 메뉴의 머리·항목·꼬리는 렌더 요청의 번호를, 소개 응답은 0xfffffffe를 따른다. CDJ-2000nexus는 요청의 번호를 되돌려 보낸다.
  - 질의 시간 제한(#47): `connectToDevice`가 연결 뒤 `setTimeout(0)`으로 시간 제한을 꺼서(`src/remotedb/index.ts`) 응답이 없는 질의가 영영 기다리고 그 장치의 잠금을 쥔 채 이후 조회도 막았다. 이제 `QueryInterface.query`가 응답을 기다리는 동안 소켓 유휴 제한을 10초(`Connection.queryTimeoutMilliseconds`)로 걸고, 끝나면 푼다. 넘으면 연결을 닫고 `DJLinkError("RemoteDB query to <ip> timed out")`로 끝낸다. 닫힌 연결은 다음 `RemoteDatabase.get`이 버리고 새로 연결한다. 원본 패시브 `get`은 닫힌 연결을 그대로 돌려주므로 패시브도 능동처럼 새로 연결하게 했다. 놀고 있는 연결은 원본처럼 제한 없이 열려 있다.
  - 항목 0개(#48): 빌린 질의 번호의 플레이어가 망에 없으면 CDJ-2000nexus는 분석하지 않은 곡의 메타데이터 질의(0x2202)에 항목 0개로 답한다. 원본은 `Cannot read properties of undefined`로 실패했다. 이제 렌더 요청 없이 까닭을 적은 `RemoteDBNoMetadataItemsError`로 끝낸다. watch는 이것을 실패로 세어 다시 시도한다. rekordbox 곡(0x2002)의 항목 0개는 원본처럼 빈 곡과 진단 경고로 둔다(원본 `blankMetadata.spec.ts`가 정한다). 질의 번호 정책은 바꾸지 않는다(§11).
- CLI
  - 임시 DB 정리(#16): 장치 이탈 때 본체를 먼저 삭제하면 부속 파일이 정리 목록에서 빠졌다. 소유한 경로 목록을 따로 두어 종료 때 정확한 WAL·SHM·journal을 지운다. 다른 파일은 지우지 않고, 정리 시작 뒤 새 임시 쓰기는 거부하며, 삭제 실패는 다음 정리에서 다시 시도한다.
  - watch(#17): 원본 `src/cli/index.ts`는 재생 덱별 곡 ID만 비교하고 조회 전에 기록해, 원본 장치·슬롯·종류 변경과 같은 곡의 재접속·일시 실패를 놓쳤다. 변경 감지 키에 원본 장치·슬롯·종류·곡 ID를 넣고, 재생 덱이나 원본 장치가 이탈·재발견되면 기록을 무효화한다. 실패하면 1초 이상 간격으로 처음 포함 최대 3회 조회하고, 이전 조회의 늦은 결과는 버린다. 곡 번호 0(곡 없음)은 조회하지 않는다(원본은 0도 조회한다).

**기능 추가·검토 필요**

- 비트 패킷(0x28)([#7](https://github.com/ImBada/DJLinkKit/issues/7)): 캡처로 확인한 96바이트 형식(§8)으로 `CDJStatus.BeatState`·`beatFromPacket`, 능동·패시브 비트 이벤트와 CLI 출력을 더했다. 원본에 없는 기능이다. 정밀 위치나 다음 비트까지의 시간은 제공하지 않는다.
- localdb: 버튼이 있으면 알 수 없는 cue type도 hot_cue로 돌려준다. 원본 시험 주석은 cue도 loop도 아닌 항목을 뺀다고 하므로 검증 누락으로 보이지만 의도를 확정할 시험이 없다.
- Stagehand 제어(0x07)는 CDJ가 무시한다고 원본 문서(`docs/STAGEHAND.md` §6.1)에 적혀 있다.
- README는 가상 CDJ 번호로 5를 권하지만 기본값은 7이다(`src/constants.ts:9`). 우리 문서에는 7 이상만 적는다.
- MAC(#41, §11): IOKit `IOEthernetInterface`의 부모 항목 `IOMACAddress`는 권한 없이 실제 MAC을 준다(macOS 27). 이것으로 바꾸면 원본과 다르고, OS가 일부러 가린 값을 다른 길로 읽는 것이다. CDJ가 가린 값을 받아 주는 동안은 원본대로 둔다. Mac 여러 대를 한 망에 붙이는 용도가 생기면 다시 정한다.

**Link Export: 원본에서 유지하는 동작**

- rbxport `Claim`의 첫/둘째 단계 선언 길이 44/50과 실제 인코딩 길이 42/48이 다르다. 원본 패킷·시험대로 둔다.
- 원본이 읽을 수 있는 mixer discovery subtype `0x03`도 다시 인코딩하면 `0x02`가 된다. 원본대로 둔다.
- 스마트 목록의 `dateCreated` 조건은 원본처럼 `date_added` 컬럼을 읽고, 루트 마지막 XML 닫기 이름은 검사하지 않는다.
- 큐 편집을 거절할 때의 상태 0x32·빈 목록 응답은 원본(rekordbox와 같다는 원본 주석, `cue_writes.rs`)대로 둔다.

**Link Export: 고친 것(원본 rbxport)**

원본 그대로인 기준선은 `port/rbxport-one-to-one` 브랜치에 있다. 원본 대응 시험의 입력·기대값은 바꾸지 않고 자체 회귀 시험을 더했다. 실기 기록은 [LINK-EXPORT-HARDWARE.md](LINK-EXPORT-HARDWARE.md).

- 파일 형식: `rbl-dbserver/src/session.rs::track_info_rows`가 첫 항목 id를 1로 고정해, CDJ-2000nexus가 WAV에도 MP3 디코더를 골라 E-8305가 났다. 이제 `TrackDetails.file_type`을 보내고, 0인 기존 Source는 기본값 1을 유지한다.
- 레거시 큐 목록(#20): 원본에 핸들러가 없던 `0x2104` 조회를 기존 `usb_cue_reply`/`0x4702` 응답에 연결했다. 숫자 문맥·track ID를 검사하고, 읽기에서 편집 콜백을 부르지 않는다. CDJ-2000nexus는 앞쪽 memory 개수만큼을 메모리 큐로 읽어, 시간순 목록은 핫큐 A를 끄고 E-8302를 냈다. 그래서 메모리 큐를 먼저, 핫큐를 뒤에 보낸다. [구현·검증 기록](LINK-EXPORT-LEGACY-CUES.md).
- 큐 편집 응답(#32): `0x2105` 저장·삭제 응답도 같은 원인으로 편집 뒤 Hot Cue A가 꺼졌다. 읽기 응답처럼 메모리 큐를 먼저 보낸다.
- 경로 오류 다시 보내기: 참여 직후 CDJ에게 보낸 패킷이 "No route to host"로 실패했고, 그 순간 macOS는 ARP도 보내지 않았다. 한 장치에게 보내는 패킷이 `EHOSTUNREACH`·`EHOSTDOWN`·`ENETUNREACH`로 실패하면 0.25초 간격으로 최대 20번 다시 보낸다. 방송과 다른 오류는 다시 보내지 않는다(`BeaconRetryTests`).
- 빠른 참여(추가): `LinkExport.start(seedAnnouncements:)`·`Beacon.hear_seed`로, 앱이 미리 들은 장치 알림을 넣으면 CDJ의 다음 알림(약 2초 간격)을 기다리지 않고 번호 받기를 시작한다. 원본에는 없는 입구다. rekordbox도 CDJ 알림을 들은 직후 번호를 요청한다(`BeaconSeedTests`).
- 목록 썸네일: 인자 둘인 `ARTWORK`(0x2003)의 id를 원본은 줄 번호+2로 읽어, 곡 id가 1부터 이어지는 라이브러리에서 앞 곡의 그림이 나왔다. CDJ는 목록 줄의 곡 id로 묻는다. 이제 곡 id(없으면 앨범 id)로 찾는다. 크기도 rekordbox처럼 목록에는 `_s`(80px) → `_m` → 원본 순서로, 큰 그림 요청(`CONTENT_ARTWORK`·인자 셋 이상)에는 원본처럼 `_m` → 원본 순서로 보낸다(`CatalogArtworkSizeTests`).

**Link Export: 고친 것(Swift 구현)**

원본 rbxport의 버그가 아니라 우리 구현의 문제다.

- 보내기 실패: `Beacon`의 `send`가 콜백 없이 보내, 한 번 실패하면 `DualStackUDPSocket`이 소켓 오류로 올리고 `status_running`이 꺼져 상태 송신과 질의 응답이 모두 멈췄다(DJCrate 앱에서 CDJ의 LINK 화면에 Mac이 보이지 않았다). 이제 빈 콜백을 넘겨 실패를 버린다(`BeaconUpstreamFixTests.swift`).
- 정렬 키(#24): 파일명·이름·앨범 메뉴의 비교자가 비교할 때마다 문자열을 접고 복원했다. 원본의 `sort_by_cached_key`처럼 행마다 키를 한 번만 만든다. 순서는 같다.
- 스마트 목록 날짜(#25): `SmartDate.today`가 `Calendar.current`를 써서 일본력·불교력 등을 쓰는 Mac에서 연도가 달라졌다. 원본 chrono `Local`처럼 현지 시간대의 그레고리력을 쓴다.
- 실제 소켓 가드(#28): Export의 가드가 `DJLINK_LOOPBACK_TESTS`와 관계없이 소켓을 막아 루프백 시험을 돌릴 수 없었다. DJLinkKit과 같은 조건으로 맞췄다(§11).

## 10. 라이선스·출처

**LICENSE**

- 저장소 전체가 GPL-2.0-or-later다(`DJLinkExport`가 GPL인 rbxport의 파생물이기 때문). 원래는 MIT였고, 원본 LICENSE의 저작권 표시("Copyright (c) 2013 Evan Purkhiser")와 허가 문구는 `LICENSES/MIT.txt`에 그대로 둔다. 저작권 범위는 `COPYRIGHT.md`에 있다.

**THIRD_PARTY_NOTICES.md**

- alphatheta-connect(기여자는 `package.json` contributors의 Chris Le 등), prolink-connect, onelibrary-connect, metadata-connect, §7에서 DJCrate 리더와 함께 옮긴 항목.

**옮기지 않는 것**

- `.ksy` 2개(EPL-1.0).
- 원본 `docs/` 중 Deep Symmetry DJL Analysis 문서를 그대로 인용한 부분(예: `docs/ALL_IN_ONE_UNITS.md`의 인용 블록). 링크로만 가리키고 내용은 우리 말로 적는다.

**PROVENANCE.md(출처 기록)**

- 펌웨어 분석에 근거한 원본 지식을 옮긴 곳과, 실기 캡처로 새로 알아낸 것을 적는다.
- 원칙:
  - 원본에 공개된 지식은 옮긴다.
  - 펌웨어나 rekordbox 실행 파일을 우리가 직접 분석하지 않는다(strings·디스어셈블 포함).
  - 새로 알아내는 것은 실기 패킷 캡처를 비교해서만 한다.
- 결정: AlphaTheta EULA §2.2(리버스 엔지니어링 금지)는 분석한 쪽에 걸리는 조항이다. 그 결과를 옮겨 배포하는 위험이 작지만 0은 아니라는 것을 알고, 옮기기로 정했다.

## 11. 안전 규칙

**시험**

- 시험은 기본적으로 실제 소켓을 열지 않는다(원본 시험도 0개다). 예외는 아래 루프백 시험뿐이다.
- 실제 소켓을 만드는 쪽(`SocketFactory.live`)은 시험 프로세스에서 부르면 바로 실패한다. DJCrate의 `TestProcess`처럼 시험 프로세스를 알아본다.
- 루프백(127.0.0.1) 통합 시험은 `DJLINK_LOOPBACK_TESTS=1`일 때만 따로 돈다. Link Export의 실제 소켓 가드(`LiveExportSocketFactory`)도 같은 조건에서만 열고, 그때도 시험 프로세스에서는 TCP를 127.0.0.1·::1에만 묶고 그쪽으로만 연결하며 UDP는 127.0.0.1·::1로만 보낸다. UDP RPC 소켓은 원본처럼 0.0.0.0에 묶은 뒤 인터페이스를 고정하므로 보내는 주소를 검사한다(#28). 시험은 LAN에 아무것도 보내지 않는다.

**실기와 CLI**

- 공연이나 리허설 중인 네트워크에서 돌리지 않는다.
- 같은 Mac에서 rekordbox·rekordboxAgent가 켜져 있으면 UDP 50000~50002를 잡지 않는다. 잡으면 rekordbox LINK가 망가질 수 있다. `djlink`는 시작할 때 이것을 확인하고 거부한다. 이 확인은 CLI·앱 쪽 규칙이며 라이브러리 동작(1:1)에는 넣지 않는다.
- 가상 CDJ 번호는 7 이상만 쓴다(CLI 기본값). 1~6은 실기 확인에서 일부러 고른 경우만 쓴다. 번호가 겹쳐 다시 고를 때도 같다(허용하지 않는 번호로는 announce하기 전에 멈춘다).
- 메모(remotedb 질의 번호 예외, 바꾸지 않음):
  - 위 7 이상 규칙은 announce 번호에 대한 것이다. remotedb 메시지 안의 장치 번호는 원본 `pickRemoteDbQueryId`가 1~6 중에서 고른다. CDJ가 1~6만 답하기 때문이며 원본 주석에 CDJ-3000 실기 확인이 있다. 그래서 가상 CDJ가 7 이상이어도 remotedb 질의에는 같은 랙의 다른 CDJ 번호(없으면 비어 있는 1~6)가 실린다. CLI는 연결할 때 고른 번호를 한 줄 로그로 남긴다.
  - CDJ-2000nexus는 이 번호로 질의를 받아 주고 덱 상태도 바뀌지 않는다. 다만 빌린 번호의 플레이어가 망에 없으면 항목 0개로 답하고, 빠졌다 다시 붙은 뒤에는 답하지 않을 수 있다(#48, §8).
  - 결정(#48): 정책과 announce 7 이상 규칙은 그대로 둔다. rekordbox로 분석한 곡은 NFS(localdb)로 읽으므로 영향이 없다. CDJ-2000nexus에서 분석하지 않은 곡의 remotedb 조회는 될 때만 되는 것으로 문서에 적는다. 항목 0개는 까닭을 적은 오류로, 무응답은 10초 시간 제한(#47)으로 끝난다. 가상 CDJ를 1~4번으로 참여시키면 더 안정적일 수 있으나 실제 플레이어와 번호가 겹칠 위험이 있어 쓰지 않는다.
- 소켓은 고른 인터페이스에 묶고 그 서브넷 밖의 장치와는 통신하지 않는다. `play`·`pause`는 재생 상태 패킷에 칸이 있는 1~4번 플레이어에만 보낸다(§9).
- 제어 명령(곡 올리기, Stagehand 설정 쓰기)은 CLI에서 `--confirm <장치 이름>` 없이는 보내지 않는다.
- MAC(#41): macOS 27에서 일반 프로세스가 `getifaddrs`의 AF_LINK로 읽으면 `02:00:00:00:00:00`이 나온다(`ifconfig`는 실제 값). `SystemInterfaceProvider`가 이 값을 그대로 써서 가상 CDJ와 Link Export가 announce·keep-alive에 이 MAC을 싣는다. 원본(Node `os.networkInterfaces`)도 같은 시스템 호출이다. CDJ-2000nexus는 이 값으로도 장치를 받아 줬다. Mac 여러 대가 같은 망에 있으면 같은 MAC을 알리고, Stagehand 모드의 MAC(OUI + 하위 3바이트)도 모두 같아진다. 바꿀지는 §9 "기능 추가·검토 필요"에 둔다.
- macOS 로컬 네트워크 권한: 라이브러리는 Info.plist를 가질 수 없다. 터미널에서 돌린 `djlink`는 권한을 자동으로 받으므로, 앱에서는 결과가 다를 수 있다(§13).

## 12. 원본 따라가기

- `UPSTREAM.md`에 세 저장소의 고정 커밋을 적는다.
- 새 원본 릴리스는 한 번에 하나씩 따라간다: 두 커밋 사이의 차이를 보고 → 바뀐 시험부터 옮기고 → 코드를 옮기고 → `port-status`와 시험이 통과하면 → `UPSTREAM.md`를 갱신한다.
- 새 차이에 펌웨어 분석 근거가 생기면 `PROVENANCE.md`에 더한다.
- 브랜치:
  - `port/one-to-one`은 원본 버그까지 그대로 둔 1:1 기준선이다. 지우지 않는다.
  - main은 기준선에 §9에서 고친 것을 더한 쪽이다.
  - 새 릴리스는 `port/one-to-one`에 먼저 옮기고, 시험과 `port-status`가 통과하면 main에 합친다.
  - 합칠 때 §9에서 고친 곳과 겹치면 고친 쪽을 남긴다. 새 원본 시험의 기대값이 고친 동작과 다르면 그 시험 위에 `// PLAN §9:` 주석을 단다.

## 13. DJCrate에 붙이기

DJCrate 저장소 이슈로 진행한다.

**준비**

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

## 14. 저장소 AGENTS.md

작업 규칙은 저장소 맨 위의 [AGENTS.md](../AGENTS.md)에 있다. 이 계획의 1:1 원칙(§4, §9), 출처 원칙(§10), 안전 규칙(§11)을 줄여 적은 것이다.

## 15. 확인하지 못한 것

- 원본 시험을 Node로 실제로 돌려 보지 않았다. 기대값은 시험 코드에 적힌 값을 따른다.
- 펌웨어 근거 표시가 없는 원본 부분(Stagehand, CDJ-3000X 등)이 어디서 왔는지.
- 실기: CDJ-3000(정밀 위치), 6채널 믹서(on-air 6채널 변형), 가상 CDJ 둘의 번호 겹침, Mac 주소가 바뀌는 재연결(§8).
