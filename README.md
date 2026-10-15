# DJLinkKit

PRO DJ LINK 네트워크를 Swift에서 쓰는 패키지다. TypeScript 라이브러리 [alphatheta-connect](https://github.com/chrisle/alphatheta-connect)를 Swift로 1:1 옮긴 프로젝트다.

원본 동작을 그대로 옮기는 것이 목표다. 장치 발견, 가상 CDJ로 참여, CDJ·믹서 상태와 정밀 위치, remotedb·NFS로 메타데이터·파형·파일 받기, USB DB와 ANLZ 읽기, mixstatus, 제어 명령, 패시브(pcap) 모드, CLI를 다룬다. 계획은 [docs/PLAN.md](docs/PLAN.md), 파일별 대응은 [docs/port-map.md](docs/port-map.md)에 있다.

## 진행 상황

- 1:1 포트의 0~9단계 코드를 모두 옮겼다.
- 원본 시험 622개(alphatheta-connect 532, onelibrary-connect 62, metadata-connect 28)를 모두 옮겼고, 모두 통과한다. 원본 `it` 수와 옮긴 `@Test` 수가 파일마다 같다(`scripts/port-status.sh`).
- main은 1:1 기준선에, 옮기면서 찾은 원본 버그를 고친 것을 더한 쪽이다(목록은 [docs/PLAN.md](docs/PLAN.md) §9). 원본 버그까지 그대로 둔 1:1 기준선은 `port/one-to-one` 브랜치에 남긴다. 고친 동작에 맞춰 원본 시험의 기대값을 바꾼 곳은 그 시험 위에 `// PLAN §9:` 주석이 있다.
- 시험은 `@Test` 선언 기준(`grep -rE '^\s*@Test' Tests`로 센 정적 수) 전체 1,568개다. DJLinkKit 780, DJLinkControl 18, DJLinkPassive 71, djlink CLI 180, DJLinkExport 계열 519다. 원본 대응이 1,124개(alphatheta-connect 계열 622, rbxport 502), 우리 시험이 444개다. 우리 시험은 DJLinkKit·Control·Passive·CLI의 기반 코드·소켓 전송·바이트 리더·CLI·PLAN §9 회귀 427개와 Link Export 자체 회귀 17개다. 이 중 30개는 조건이 맞을 때만 돈다(아래 "시험"). 2026-10-16 기본 실행(`scripts/ci.sh`)에서는 28개를 건너뛰고 1,540개가 모두 통과했다. `scripts/ci.sh --loopback`은 기본 시험 뒤에 루프백 시험 18개(DJLinkKit 8, Link Export 루프백 8과 가드 2)만 따로 돌리며 모두 통과한다. `DJLINK_LOOPBACK_TESTS=1 swift test`로 한 번에 다 돌리면 같은 프로세스의 SQLCipher DB 열기가 `DJLinkActor`를 몇 초씩 막아 TCP 루프백 시험이 시간 초과로 실패할 수 있다([#33](https://github.com/ImBada/DJLinkKit/issues/33)).
- **실기 확인은 일부만 했다.** CDJ-2000nexus 2대와 DJM-900NXS2로 장치 목록, 참여, 상태, 비트, on-air, 메타데이터, NFS, 곡 올리기, play·pause, mixstatus를 확인했다(2026-10-14, 기록은 [docs/PLAN.md](docs/PLAN.md) §8). CDJ-3000, 6채널 믹서, remotedb 질의, 번호 겹침, pcap 캡처는 아직이다. 시험은 가짜 소켓과 합성 데이터로 돈다. 공연 장비에 쓰기 전에 시험용 네트워크에서 먼저 확인한다(아래 "안전 안내").
- 현재 장비에서 CDJ LAN·Mac LAN 재연결, USB 재삽입, 덱 전원 재시작도 확인했다(2026-10-14~15). 장치·상태·메타데이터 복귀는 확인했으나, 이때 발견한 임시 DB 부속 파일 잔존([#16](https://github.com/ImBada/DJLinkKit/issues/16))과 watch의 같은 곡 ID 재조회 누락([#17](https://github.com/ImBada/DJLinkKit/issues/17))도 고쳤고 회귀 시험과 로컬 CI가 통과했다. 수정된 같은 watch에서 전원 재시작 후 같은 곡 재조회와 정상 종료 후 부속 파일 잔존 수 0을 확인했다. 상세 결과는 PLAN §8에 있다.
- 원본과 다르게 옮긴 곳, 1:1 기준선에 일부러 그대로 옮긴 원본 버그는 [docs/port-notes.md](docs/port-notes.md)에 있다.

## 구성

| 제품 | 내용 |
|---|---|
| `DJLinkKit` | 핵심 라이브러리. 장치 발견, 가상 CDJ, 상태·위치, remotedb·NFS, localdb(USB DB·ANLZ), 메타데이터·앨범아트, mixstatus |
| `DJLinkControl` | 제어 명령(곡 올리기, 재생 상태, Stagehand 설정). 공연 중인 장비를 움직인다 |
| `DJLinkPassive` | libpcap으로 듣기만 하는 패시브 모드(BPF 권한 필요) |
| `djlink` | 실기 확인용 CLI(아래 "CLI") |
| `DJLinkExport` | rbxport 기반 Link Export 서버. **빌드·시험 통과, CDJ-2000nexus 기본 실기 확인**, GPL-2.0-or-later([범위·계획](docs/LINK-EXPORT-PLAN.md)) |

## 상표 고지

이 프로젝트는 PRO DJ LINK 호환 소프트웨어이며, AlphaTheta(Pioneer DJ)와 관계없는 독립 프로젝트다. AlphaTheta, Pioneer DJ, PRO DJ LINK, CDJ, rekordbox는 각 소유자의 상표다. 이 프로젝트의 이름에는 그 상표를 쓰지 않는다.

## 요구 사항

- macOS 15 이상
- Swift 6.2 이상

Linux는 지원하지 않는다.

## 안전 안내

이 패키지는 실제 장비가 있는 네트워크에 참여한다. 다음을 지킨다.

- **가상 CDJ 번호는 7 이상만 쓴다.** 1~6은 실제 플레이어가 쓰는 번호다. 겹치면 공연 중인 플레이어가 영향을 받을 수 있다.
- 공연이나 리허설 중인 네트워크에서 돌리지 않는다. 시험용 스위치에 장비 한두 대만 묶어서 쓴다.
- 같은 Mac에서 rekordbox나 rekordboxAgent가 켜져 있으면 쓰지 않는다. UDP 50000~50002를 잡으면 rekordbox LINK가 망가질 수 있다.
- **Link Export(`DJLinkExport`)는 이 검사를 스스로 하지 않는다.** CLI(`djlink`)와 달리 서버를 띄우는 호스트 앱이 규칙을 지켜야 한다. 서버는 rekordbox처럼 17·18번(무선 41번)으로 참여하고, UDP 50000~50002, TCP 12523, portmap 50111, NFS 2049를 연다. 같은 Mac의 rekordbox·rekordboxAgent와 NFS 서버(`nfsd`)를 끄고, 시험용 네트워크에서 인터페이스를 지정해 띄운다. 자세한 규칙은 [docs/LINK-EXPORT-PLAN.md](docs/LINK-EXPORT-PLAN.md) "호스트 안전 규칙".
- 제어 명령(곡 올리기, Stagehand 설정 쓰기)은 `DJLinkControl`에 따로 들어 있고, 공연 중인 장비를 움직인다. 필요한 곳에만 넣는다.
- macOS 27에서는 일반 프로세스가 `getifaddrs`로 읽는 인터페이스 MAC이 `02:00:00:00:00:00`으로 가려진다. 가상 CDJ와 Link Export는 이 값을 announce·keep-alive에 그대로 싣는다(원본도 같은 시스템 호출을 쓴다). CDJ-2000nexus는 이 값으로도 받아 줬지만, Mac 여러 대를 같은 망에 붙이면 모두 같은 MAC을 알린다([#41](https://github.com/ImBada/DJLinkKit/issues/41)).

## 시험

```bash
swift test
```

- 시험은 LAN에 아무것도 보내지 않는다. 시험 프로세스에서 실제 소켓을 만들면 바로 실패한다. DJLinkKit과 Link Export(`DJLinkExport`) 모두 같다.
- 실제 소켓 구현만 따로 검사하는 루프백 시험은 `DJLINK_LOOPBACK_TESTS=1`일 때만 돈다. DJLinkKit의 8개(`LiveTCPConnectionLoopbackTests`)와 Link Export의 8개(`rbl-fakecdj/tests/loopback.rs` 대응)는 모두 127.0.0.1에만 묶는다. Link Export 소켓 가드는 루프백 시험이 아니면 소켓 생성을 막고, 시험 프로세스에서는 TCP를 127.0.0.1·::1에만 묶고 그쪽으로만 연결하며, UDP는 127.0.0.1·::1로만 보낸다(UDP RPC 소켓은 원본처럼 0.0.0.0에 묶은 뒤 인터페이스를 고정하므로 보내는 주소를 검사한다). 켜도 LAN에는 아무것도 나가지 않는다.

  ```bash
  DJLINK_LOOPBACK_TESTS=1 swift test
  ```

- 조건이 맞을 때만 도는 시험은 선언 기준 30개다.
  - 루프백 켰을 때만 17개: DJLinkKit 8, Link Export 루프백 8, Link Export 소켓 가드 1.
  - 루프백 껐을 때만 2개: Link Export 소켓 가드와 DJLinkKit의 `live sockets are refused inside the test process`(실제 소켓을 거부하는지 확인). 반대 조건의 시험이 짝으로 있어 어느 쪽으로 돌려도 일부는 건너뛴다.
  - 실제 음원 파일이 있을 때만 5개: 앨범아트 통합.
  - 시험이 띄운 자식 프로세스 안에서만 2개: SQLCipher 동시 열기 도우미.
  - `.disabled` 4개: Link Export Beacon 2개(원본 `#[ignore]`, 실제 시간 창에 의존)와 서버 범위 밖 2개(디스크 캐시, 폴더 브라우저).
- 암호화 픽스처(OneLibrary)는 저장소에 들어 있어 기본 실행에 포함된다. 실제 음원 파일이 있어야 도는 시험은 조건이 맞지 않으면 건너뛴다(원본도 같은 조건에서 본문을 건너뛴다).
- GitHub Actions는 쓰지 않는다. 합치기 전에 로컬에서 `scripts/ci.sh`를 돌린다. `swift test`, 아래 원본 대조(`port-status.sh --strict`), Link Export 원본 대조(`export-port-status.py --strict`)를 차례로 돌리고, 하나라도 실패하면 종료 코드 1로 끝난다.

  ```bash
  UPSTREAM_DIR=~/src/upstream bash scripts/ci.sh             # 루프백 시험은 끈다
  UPSTREAM_DIR=~/src/upstream bash scripts/ci.sh --loopback  # 루프백 시험까지(DJLinkKit 8개와 Link Export 8개 포함)
  ```

## 원본 대조

원본 저장소 세 개를 같은 부모 폴더에 받아 두면(받는 법은 [UPSTREAM.md](UPSTREAM.md)) 원본 시험 수와 옮긴 시험 수를 파일별로 나란히 볼 수 있다. 읽기만 하는 스크립트다.

```bash
UPSTREAM_DIR=~/src/upstream bash scripts/port-status.sh            # 전체
UPSTREAM_DIR=~/src/upstream bash scripts/port-status.sh --stage 4  # 단계 하나(1~8)
```

하나라도 다르면 종료 코드 1로 끝난다. 원본이 고정 커밋과 다르면 경고만 낸다.

Link Export는 rbxport 체크아웃(`$UPSTREAM_DIR/rbxport`, 별도 위치는 `DJLINK_EXPORT_UPSTREAM_DIR`)과 같은 방식으로 대조한다. 이 스크립트도 읽기만 한다. 원본이 고정 커밋과 다르거나 이름·순서가 다르면 오류를 내고, `--strict`를 주면 종료 코드 1로 끝난다.

```bash
UPSTREAM_DIR=~/src/upstream python3 scripts/export-port-status.py --strict
```

## CLI

실기 확인용 `djlink` 실행 파일이 있다.
실기 확인은 공연 중이 아닌 시험용 네트워크에서만 한다.
사용법은 `swift run djlink --help`(하위 명령별로 `--help`)에 있다. 아래 표는 주요 옵션만 적었으니, 전체 옵션은 `--help`를 본다.

| 명령 | 하는 일 |
|---|---|
| `devices [--seconds N]` | announce를 듣고 장치 목록을 낸다(아무것도 보내지 않는다) |
| `watch [--iface NAME] [--vcdj-id N] [--download-dir DIR]` | 원본 cli 흐름. 곡이 바뀔 때마다 제목을 낸다. 파일은 `--download-dir`를 준 경우에만 받는다 |
| `status` | 상태·비트·정밀 위치·on-air |
| `metadata --device N --slot usb\|sd --track-id ID` | 메타데이터·그리드·파형·큐 요약 |
| `fetch --device N --slot usb\|sd --path PATH --out FILE` | NFS로 파일 하나 받기(이미 있으면 거부) |
| `mixstatus` | MixstatusProcessor 이벤트 |
| `control load\|play\|pause ... --confirm "<장치 이름>"` | 곡 올리기·재생·정지. `play`·`pause`는 1~4번 플레이어에만 |
| `passive --iface NAME` | libpcap으로 보기만 하기(BPF 권한 필요) |

비트 수신은 CDJ-2000nexus에서 확인한 96바이트 0x28 형식을 지원한다. `network.beatEmitter`와 패시브 네트워크의 `beatEmitter`에서 `.beat`를 구독하면 장치 번호·마디 안 비트·곡 BPM·피치를 받는다. `effectiveBPM`은 곡 BPM에 피치 비율을 적용한 계산값이다. CLI `status`와 `passive`는 비트마다 `beat device=… beat=… bpm=… pitch=… effective-bpm=…`를 출력한다. 정밀 위치와 비트 예측 시간은 별개다. 능동 수신은 두 CDJ에서 CLI 실기로 확인했고, 패시브 수신 경로는 가짜 pcap 백엔드로 시험했다. 실제 pcap 확인은 [#6](https://github.com/ImBada/DJLinkKit/issues/6)에 남긴다. 앞부분 시간 필드와 다른 기종은 해석·검증 범위에 포함하지 않는다([#7](https://github.com/ImBada/DJLinkKit/issues/7)).

watch는 곡 ID뿐 아니라 원본 장치·슬롯·곡 종류의 변경과 장치 재접속을 구분해 제목을 다시 조회한다. 메타데이터 조회 실패는 다음 상태 패킷에서 1초 이상 간격으로 최대 두 번 재시도한다. 최초 포함 3회가 모두 실패하면 새 곡이나 새 연결이 될 때까지 멈춘다. 성공한 조회와 진행 중인 조회는 반복 상태 패킷 때문에 중복 실행하지 않는다. 곡 번호가 0(곡 없음)이면 조회하지 않고 `no track`도 내지 않는다(원본 cli는 곡 번호 0도 조회하고 결과가 없으면 `no track`을 낸다).

CLI가 지키는 안전 규칙(docs/PLAN.md §11):

- 시작할 때 같은 Mac에서 rekordbox·rekordboxAgent가 돌고 있으면 UDP 50000~50002를 잡지 않고 끝낸다.
    확인하지 못해도 끝낸다.
- UDP는 macOS `IP_BOUND_IF`, TCP는 `NWParameters.requiredInterface`로 고른 인터페이스에만 묶고 그 인터페이스 서브넷 밖의 장치에는 announce도 연결도 질의도 하지 않는다.
    `--iface`를 주면 소켓을 만들 때부터 묶고, 주지 않으면 처음 보이는 장치(이미 본 장치가 있으면 그것)의 인터페이스를 고른 뒤 같은 제한을 건다.
    TCP 인터페이스 이름을 찾지 못하면 연결하지 않는다.
    UDP 송신·TCP 연결 직전에 목적지 범위를 검사하며 범위 미확정·서브넷 밖 주소·호스트 이름은 거부한다.
    NFS 경로 검사에서도 장치 IP를 검사한다.
    다른 LAN에 같이 연결된 Mac에서는 `--iface`를 주는 편이 안전하다.
- 가상 CDJ 번호 기본값은 7이다.
    1~6은 `--allow-player-id`를 같이 줄 때만 쓴다.
    번호가 겹쳐 다시 골라야 하는데 허용하지 않는 번호(1~6)가 나오면 그 번호로 announce하기 전에 멈추고 오류를 낸 뒤 종료 코드 1로 끝난다.
- **remotedb 질의 번호는 announce 번호와 별개이며 1~6 중에서 고른다(원본 동작).**
    CDJ는 remotedb 메시지 안의 장치 번호가 1~6일 때만 답한다(원본 `pickRemoteDbQueryId`의 주석에 CDJ-3000 실기 확인이 적혀 있다).
    그래서 가상 CDJ가 7 이상이어도 메타데이터·파형 같은 remotedb 조회 메시지에는 원본이 고른 다른 CDJ의 번호(없으면 비어 있는 1~6)가 실린다.
    announce·heartbeat에는 쓰이지 않고 `--allow-player-id` 규칙과도 무관하다.
    동작은 바꾸지 않았고, CLI는 remotedb에 연결할 때 고른 번호를 `remotedb 질의 번호 N번을 쓴다 …` 한 줄로 출력한다(announce 번호가 1~6이면 같은 번호를 쓰므로 그 줄이 없다).
    CDJ-2000nexus는 announce 7번인 가상 CDJ가 2번(옆 CDJ의 번호)을 실은 Introduce를 받아 줬고, 질의하는 동안 두 덱의 상태는 바뀌지 않았다. 분석하지 않은 곡의 메타데이터도 이 번호로 읽었다(2026-10-16, [#9](https://github.com/ImBada/DJLinkKit/issues/9)).
    빌린 번호의 플레이어가 망에 없으면 CDJ-2000nexus가 항목 0개로 답해 조회가 실패한다. 그래서 CDJ-2000nexus 한 대만 있는 망에서는 remotedb 메타데이터를 얻지 못할 수 있다([#48](https://github.com/ImBada/DJLinkKit/issues/48)).
    이 방식을 바꿀지는 사용자가 정한다(docs/PLAN.md §11 메모).
- 제어 명령은 `--confirm`이 대상 장치 이름과 정확히 같을 때만 보낸다.
    대상을 확인하기 전에는 가상 CDJ로 참여하지 않는다.
- `control play`·`control pause`는 1~4번 플레이어에만 보낸다. 5번 이상은 거부한다(종료 코드 2).
    재생 상태 패킷에는 1~4번 플레이어 칸만 있고, 대상 칸에만 명령을 싣고 다른 칸은 "그대로"로 채운다.
    원본은 칸이 한 칸 어긋나고 나머지를 "재생 시작"으로 채워, `pause`가 대상을 멈추지 못하고 다른 플레이어 칸에 시작을 실었다. CDJ-2000nexus 실기로 확인하고 고쳤다(docs/PLAN.md §9).
- `PIONEER/extracted`·`PIONEER/CDP`·`djprofile.nxs`는 `fetch`뿐 아니라 메타데이터·파형·분석·앨범아트 조회 안의 모든 NFS 읽기에서 거부한다.
    경로 구성 요소 끝의 `.`·공백은 걷어낸 뒤 비교하고(`PIONEER.`는 `PIONEER`), FAT 8.3 짧은 이름 별칭 꼴(`EXTRAC~1`, `DJPROF~1.NXS`처럼 이름 8자 이하가 `~숫자`로 끝나는 것)은 긴 이름을 알 수 없으므로 거부한다. 그 꼴이 아닌 `~`(예: `a~b.mp3`)는 막지 않는다.
    그래서 이름에 `~`가 든 곡 파일도 받지 않는다.
- Ctrl-C(SIGINT)·SIGTERM·SIGHUP(터미널이 닫힘)은 같은 정리 경로로 간다.
    SIGPIPE는 무시하며, 닫힌 파이프로 나가는 출력은 오류로 돌려받아 그 줄만 버린다(프로세스가 죽지 않는다).
- 중단된 뒤에는 참여(announce)·제어 송신·파일 쓰기·NFS 요청을 새로 만들지 않고, 시작한 작업과 소켓(NFS RPC 소켓 포함)을 모두 닫고 끝낸다.
    신호와 제한 시간 감시는 `DJLinkActor`와 독립되어 동기 PDB 해석이 멈춰도 동작한다.
    두 번째 신호는 즉시 `_exit(130)`으로 끝내고, 첫 중단 뒤 3초 안에 정리가 끝나지 않으면 강제 종료한다.
    정리 단계는 진행 중인 파일 게시가 끝나거나 취소되길 최대 3초 기다리고, 쓰는 도중에 취소되면 임시 파일(`.djlink-*.tmp`)을 지운다.
    두 번째 신호·3초 초과 강제 종료·SIGKILL처럼 프로세스가 갑자기 끝나면 임시 파일이 남을 수 있다.
- `metadata`·`fetch`·`control`은 전체 제한 시간이 있다(`--timeout SEC`, 기본 15·300·15초).
    넘으면 남은 작업과 소켓을 정리하고 종료 코드 1로 끝난다.
- `watch --download-dir`는 파일을 `<장치>-<슬롯>-<곡 번호>-<원래 이름>`으로 쓰고, `fetch`와 `watch` 모두 이미 있는 파일은 덮어쓰지 않는다(임시 파일에 쓴 뒤 `link`로 게시한다).
    `link`를 못 쓰는 파일 시스템(FAT·exFAT 등)에서는 덮어쓰지 않는 이름 바꾸기(`renamex_np`의 `RENAME_EXCL`)로 게시하고, 그것도 안 될 때만 `O_EXCL`로 만든 최종 이름에 직접 쓴다.
    **직접 쓰는 경로는 원자적이지 않다.**
    그 상태에서 강제 종료하면 반쯤 쓴 파일이 최종 이름으로 남을 수 있으니, 그런 볼륨에는 `--download-dir`·`--out`을 두지 않는 편이 안전하다.
    쓰기·fsync·게시를 별도 큐에서 1MiB씩 수행하며 조각 사이와 게시 직전에 중단을 확인한다.
- 로컬 DB(OneLibrary)를 읽을 때 라이브러리가 임시 폴더에 푸는 `prolink-onelibrary-*.db`에는 장치 USB의 곡 정보가 들어 있을 수 있다.
    CLI는 이 파일을 추적하고 정리 단계에서 남은 것(`-journal`·`-wal`·`-shm` 포함)을 지운다.
    두 번째 신호·3초 초과 강제 종료·SIGKILL처럼 정리가 돌지 못한 경우에는 남을 수 있으니, 그때는 `$TMPDIR`(`getconf DARWIN_USER_TEMP_DIR`)에서 직접 지운다.
- `metadata`는 미디어 슬롯 조회 실패도 오류로 보고하며, 요청한 파형·분석 조회가 실패하면(데이터가 없는 것과 다르다) 나머지를 출력한 뒤 종료 코드 1로 끝낸다.
    `passive`는 캡처 오류를 출력하고 정리한 뒤 종료 코드 1로 끝낸다.

NFS 읽기·재시도는 소켓 닫기와 취소 때 대기자·구독·타이머를 정리한다.
TCP 포트 조회 연결은 응답 직후 닫고, 닫힌 TCP는 장부에서 제거한다.
안전 정책이 있는 Stagehand 연결은 송신 전에 거부한다.
번호 거부 뒤 startupReady 대기도 끝나며 `startupRejectedDeviceId`·`waitUntilReady()`로 거부 상태를 확인할 수 있다.

종료 코드는 0 정상, 1 실행 실패(제한 시간 초과·번호 거부·장치 미발견·캡처 오류 포함), 2 사용법·안전 규칙 거부, 130 중단(Ctrl-C)이다.
`watch`·`status`·`mixstatus`·`passive`는 스스로 끝나지 않으므로 Ctrl-C로 끝나면 130이다. 번호 거부, 장치를 찾지 못한 제한 시간 초과(`watch`·`status`·`mixstatus`), 캡처 오류(`passive`)로 먼저 끝나면 1이다.

## 원본과 라이선스

이 저장소는 **GPL-2.0-or-later**다([LICENSE](LICENSE)). `DJLinkExport`가 GPL인 rbxport의 파생물이라 저장소 전체를 GPL로 통일했다. 원본 alphatheta-connect 등 MIT 코드의 원문과 저작권 표시(Copyright (c) 2013 Evan Purkhiser 등)는 [LICENSES/MIT.txt](LICENSES/MIT.txt)와 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 그대로 두었고, 범위별 저작권은 [COPYRIGHT.md](COPYRIGHT.md)에 있다. 2026-10-15 이전에 공개된 커밋의 MIT 사본은 그때의 조건이 유지된다. 이 패키지를 링크해 배포하는 프로그램은 GPL 조건을 따라야 한다.

- 원본 저장소와 고정 커밋: [UPSTREAM.md](UPSTREAM.md)
- 제3자 고지: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- 펌웨어 분석에 근거한 지식의 출처와 원칙: [PROVENANCE.md](PROVENANCE.md)
- 원본과 다르게 옮긴 곳: [docs/port-notes.md](docs/port-notes.md)
- 옮기는 규칙: [docs/porting-guide.md](docs/porting-guide.md)

## Link Export

Mac 라이브러리의 곡·메타데이터·분석을 CDJ에 내주는 `DJLinkExport`를 별도 제품으로 작성했다. 원본 rbxport 1.8.0 고정 커밋과 시험을 따른다. 원본 시험 502개(core 321, ANLZ 78, 서버 메모리 모델 93, XML 2, 루프백 8)를 모두 옮겼다. 이 중 4개는 `.disabled`다(원본 `#[ignore]` 2개, 서버 범위 밖 2개). 원본에 없는 자체 회귀 17개(실기 회귀 2, 레거시 큐 9, 정렬 키 3, 날짜 1, 소켓 가드 2)가 따로 있다. `DJLinkExport*` 시험은 선언 기준 519개다. 날짜별 실행 기록과 범위, 건너뛴 시험은 [검증 기록](docs/LINK-EXPORT-VALIDATION.md)에 있고, 2026-10-16 기본 실행(`scripts/ci.sh`)에서는 28개를 건너뛰고 1,540개가 모두 통과했다. `scripts/ci.sh --loopback`은 기본 시험 뒤에 루프백 시험 18개(DJLinkKit 8, Link Export 루프백 8과 가드 2)만 따로 돌리며 모두 통과한다. `DJLINK_LOOPBACK_TESTS=1 swift test`로 한 번에 다 돌리면 같은 프로세스의 SQLCipher DB 열기가 `DJLinkActor`를 몇 초씩 막아 TCP 루프백 시험이 시간 초과로 실패할 수 있다([#33](https://github.com/ImBada/DJLinkKit/issues/33)). CDJ-2000nexus에서 목록·마운트·Mac 음원의 MP3/WAV 로드·재생·CUE 복귀를 확인했다. 현재 CLI에서는 서버를 실행하지 않으며 별도 임시 실행 도구로 실기 확인했다. 서버 코드의 GPL-2.0-or-later 고지는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), 세부 상태는 [서버 계획](docs/LINK-EXPORT-PLAN.md)과 [대응표](docs/export-port-map.md)에 있다.

원본과 동일한 Link Export 기준선은 `port/rbxport-one-to-one` (`03d3371`)에 남긴다. 실기에서 찾은 WAV 형식 선택 오류는 PLAN §9에 따라 수정했다. [실기 기록](docs/LINK-EXPORT-HARDWARE.md)에 확인 범위와 한계를, [#20 기록](docs/LINK-EXPORT-LEGACY-CUES.md)에 레거시 큐 조회의 확인 결과를 적었다.

레거시 큐 조회 [#20](https://github.com/ImBada/DJLinkKit/issues/20)는 추가 회귀 9개(`LegacyCueReadTests` 7, `LegacyCueClientTests` 2)로 시험하고, 2026-10-15 검증에서 통과했다. 실기(CDJ-2000nexus)에서 찾은 큐 순서 문제를 고쳐 메모리 큐·루프·Hot Cue A/B/C 호출을 확인했다. 확인한 것과 못 한 것은 [#20 기록](docs/LINK-EXPORT-LEGACY-CUES.md)에 있다.
