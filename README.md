# DJLinkKit

PRO DJ LINK 네트워크를 Swift에서 쓰는 패키지다. TypeScript 라이브러리 [alphatheta-connect](https://github.com/chrisle/alphatheta-connect)를 Swift로 1:1 옮긴 프로젝트다.

원본 동작을 그대로 옮기는 것이 목표다. 장치 발견, 가상 CDJ로 참여, CDJ·믹서 상태와 정밀 위치, remotedb·NFS로 메타데이터·파형·파일 받기, USB DB와 ANLZ 읽기, mixstatus, 제어 명령, 패시브(pcap) 모드, CLI를 다룬다. 계획은 [docs/PLAN.md](docs/PLAN.md), 파일별 대응은 [docs/port-map.md](docs/port-map.md)에 있다.

## 진행 상황

- 1:1 포트의 0~9단계 코드를 모두 옮겼다.
- 원본 시험 622개(alphatheta-connect 532, onelibrary-connect 62, metadata-connect 28)를 모두 옮겼고, 모두 통과한다. 원본 `it` 수와 옮긴 `@Test` 수가 파일마다 같다(`scripts/port-status.sh`).
- main은 1:1 기준선에, 옮기면서 찾은 원본 버그 17건을 고친 것을 더한 쪽이다(목록은 [docs/PLAN.md](docs/PLAN.md) §9). 원본 버그까지 그대로 둔 1:1 기준선은 `port/one-to-one` 브랜치에 남긴다. 고친 동작에 맞춰 원본 시험의 기대값을 바꾼 곳은 그 시험 위에 `// PLAN §9:` 주석이 있다.
- 전체 시험 966개(DJLinkKit 741, DJLinkPassive 49, DJLinkControl 13, djlink CLI 163)가 실패 없이 돈다. 이 중 13개는 조건이 맞을 때만 돈다(루프백 6개는 `DJLINK_LOOPBACK_TESTS=1`, 앨범아트 통합 5개는 실제 음원이 있을 때, SQLCipher 동시 열기 도우미 2개는 시험이 띄운 자식 프로세스 안에서만). 원본에 없는 우리 시험(기반 코드, 소켓 전송, 바이트 리더, CLI 등)이 포함되어 있다.
- **실기 확인은 아직 하지 않았다.** 모든 시험은 가짜 소켓과 합성 데이터로 돈다. 실제 CDJ·믹서와 맞춰 본 적이 없으므로 공연 장비에 쓰기 전에 시험용 네트워크에서 먼저 확인한다(아래 "안전 안내").
- 원본과 다르게 옮긴 곳, 1:1 기준선에 일부러 그대로 옮긴 원본 버그는 [docs/port-notes.md](docs/port-notes.md)에 있다.

## 구성

| 제품 | 내용 |
|---|---|
| `DJLinkKit` | 핵심 라이브러리. 장치 발견, 가상 CDJ, 상태·위치, remotedb·NFS, localdb(USB DB·ANLZ), 메타데이터·앨범아트, mixstatus |
| `DJLinkControl` | 제어 명령(곡 올리기, 재생 상태, Stagehand 설정). 공연 중인 장비를 움직인다 |
| `DJLinkPassive` | libpcap으로 듣기만 하는 패시브 모드(BPF 권한 필요) |
| `djlink` | 실기 확인용 CLI(아래 "CLI") |

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
- 제어 명령(곡 올리기, Stagehand 설정 쓰기)은 `DJLinkControl`에 따로 들어 있고, 공연 중인 장비를 움직인다. 필요한 곳에만 넣는다.

## 시험

```bash
swift test
```

- 시험은 실제 소켓을 열지 않고 LAN에 아무것도 보내지 않는다. 시험 프로세스에서 실제 소켓을 만들면 바로 실패한다.
- 실제 TCP 구현만 따로 검사하는 루프백(127.0.0.1) 시험은 `DJLINK_LOOPBACK_TESTS=1`일 때만 돈다. 켜도 LAN에는 아무것도 나가지 않는다.

  ```bash
  DJLINK_LOOPBACK_TESTS=1 swift test
  ```

- 실제 음원 파일이나 암호화 픽스처가 있어야 도는 시험은 조건이 맞지 않으면 건너뛴다(원본도 같은 조건에서 본문을 건너뛴다).
- GitHub Actions는 쓰지 않는다. 합치기 전에 로컬에서 `scripts/ci.sh`를 돌린다. `swift test`와 아래 원본 대조(`port-status.sh --strict`)를 차례로 돌리고, 하나라도 실패하면 종료 코드 1로 끝난다.

  ```bash
  UPSTREAM_DIR=~/src/upstream bash scripts/ci.sh             # 루프백 시험은 끈다
  UPSTREAM_DIR=~/src/upstream bash scripts/ci.sh --loopback  # 루프백 시험까지
  ```

## 원본 대조

원본 저장소 세 개를 같은 부모 폴더에 받아 두면(받는 법은 [UPSTREAM.md](UPSTREAM.md)) 원본 시험 수와 옮긴 시험 수를 파일별로 나란히 볼 수 있다. 읽기만 하는 스크립트다.

```bash
UPSTREAM_DIR=~/src/upstream bash scripts/port-status.sh            # 전체
UPSTREAM_DIR=~/src/upstream bash scripts/port-status.sh --stage 4  # 단계 하나(1~8)
```

하나라도 다르면 종료 코드 1로 끝난다. 원본이 고정 커밋과 다르면 경고만 낸다.

## CLI

실기 확인용 `djlink` 실행 파일이 있다.
실기 확인은 공연 중이 아닌 시험용 네트워크에서만 한다.
사용법은 `swift run djlink --help`(하위 명령별로 `--help`)에 있다.

| 명령 | 하는 일 |
|---|---|
| `devices [--seconds N]` | announce를 듣고 장치 목록을 낸다(아무것도 보내지 않는다) |
| `watch [--iface NAME] [--vcdj-id N] [--download-dir DIR]` | 원본 cli 흐름. 곡이 바뀔 때마다 제목을 낸다. 파일은 `--download-dir`를 준 경우에만 받는다 |
| `status` | 상태·정밀 위치·on-air |
| `metadata --device N --slot usb\|sd --track-id ID` | 메타데이터·그리드·파형·큐 요약 |
| `fetch --device N --slot usb\|sd --path PATH --out FILE` | NFS로 파일 하나 받기(이미 있으면 거부) |
| `mixstatus` | MixstatusProcessor 이벤트 |
| `control load ... --confirm "<장치 이름>"` | 곡 올리기. `play`·`pause`는 `--unverified-playstate` 없이는 거부 |
| `passive --iface NAME` | libpcap으로 보기만 하기(BPF 권한 필요) |

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
    이 방식을 바꿀지는 사용자가 정한다(docs/PLAN.md §11 메모).
- 제어 명령은 `--confirm`이 대상 장치 이름과 정확히 같을 때만 보낸다.
    대상을 확인하기 전에는 가상 CDJ로 참여하지 않는다.
- `control play`·`control pause`는 거부한다(종료 코드 2).
    원본 재생 상태 패킷이 칸 번호(0~3)를 장치 번호와 그대로 견주고 나머지 칸을 0(재생 시작)으로 채워 다른 덱이 움직이거나 `pause`가 `play`와 같은 패킷이 될 수 있다(docs/PLAN.md §9).
    실기로 확인하기 전에는 시험용 장비에서 위험을 알고 `--unverified-playstate`를 같이 줄 때만 보내고, 그때도 1~3번 장치(play와 pause 패킷이 서로 다른 번호)에만 보낸다.
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

종료 코드는 0 정상, 1 실행 실패(제한 시간 초과·번호 거부·캡처 오류 포함), 2 사용법·안전 규칙 거부, 130 중단(Ctrl-C)이다.
`watch`·`status`·`mixstatus`·`passive`는 Ctrl-C로만 끝나므로 늘 130이다.

## 원본과 라이선스

MIT 라이선스다. [LICENSE](LICENSE)는 원본 alphatheta-connect의 저작권 표시(Copyright (c) 2013 Evan Purkhiser)를 그대로 두고 이 프로젝트의 줄을 더했다.

- 원본 저장소와 고정 커밋: [UPSTREAM.md](UPSTREAM.md)
- 제3자 고지: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- 펌웨어 분석에 근거한 지식의 출처와 원칙: [PROVENANCE.md](PROVENANCE.md)
- 원본과 다르게 옮긴 곳: [docs/port-notes.md](docs/port-notes.md)
- 옮기는 규칙: [docs/porting-guide.md](docs/porting-guide.md)
