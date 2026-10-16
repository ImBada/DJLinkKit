# djlink CLI

실기 확인용 실행 파일이다. 공연 중이 아닌 시험용 네트워크에서만 쓴다.

```bash
swift run djlink --help
swift run djlink <명령> --help
```

## 명령

주요 옵션만 적었다. 전체 옵션은 `--help` 참고.

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

## 비트

CDJ-2000nexus에서 확인한 96바이트 0x28 형식을 받는다. `network.beatEmitter`와 패시브 네트워크의 `beatEmitter`에서 `.beat`를 구독하면 장치 번호·마디 안 비트·곡 BPM·피치가 온다. `effectiveBPM`은 곡 BPM에 피치를 적용한 계산값이다. `status`와 `passive`는 비트마다 `beat device=… beat=… bpm=… pitch=… effective-bpm=…`를 출력한다.

능동·패시브 수신 모두 CDJ 두 대에서 실기로 확인했다([#6](https://github.com/ImBada/DJLinkKit/issues/6)). 앞부분 시간 필드와 다른 기종은 범위 밖이다([#7](https://github.com/ImBada/DJLinkKit/issues/7)). 정밀 위치와 비트 예측 시간은 비트와 별개다.

## watch

곡 ID뿐 아니라 원본 장치·슬롯·곡 종류의 변경과 장치 재접속을 구분해 제목을 다시 조회한다. 조회가 실패하면 다음 상태 패킷에서 1초 이상 간격으로 두 번까지 다시 시도하고, 세 번 모두 실패하면 새 곡이나 새 연결 때까지 멈춘다. 성공했거나 진행 중인 조회는 반복되는 상태 패킷으로 다시 돌리지 않는다. 곡 번호가 0(곡 없음)이면 조회하지 않고 `no track`도 내지 않는다(원본 cli는 0도 조회하고 결과가 없으면 `no track`을 낸다).

## 안전 규칙

[PLAN §11](PLAN.md)을 따른다.

- rekordbox 확인: 같은 Mac에서 rekordbox·rekordboxAgent가 돌고 있거나 확인하지 못하면 UDP 50000~50002를 잡지 않고 끝낸다.
- 인터페이스 제한: 소켓을 고른 인터페이스 하나에만 묶는다(UDP는 `IP_BOUND_IF`, TCP는 그 인터페이스의 IPv4 주소). 그 서브넷 밖의 장치에는 announce·연결·질의를 하지 않는다.
  - `--iface`를 주면 소켓을 만들 때부터 묶는다. 주지 않으면 처음 보이는 장치의 인터페이스를 고른 뒤 같은 제한을 건다. 다른 LAN에도 연결된 Mac에서는 `--iface`를 주는 편이 안전하다.
  - UDP 송신·TCP 연결 직전에 목적지를 검사해 범위 미확정·서브넷 밖 주소·호스트 이름을 거부한다. NFS 경로 검사에서도 장치 IP를 본다. TCP 인터페이스를 찾지 못하면 연결하지 않는다.
- 가상 CDJ 번호: 기본 7이다. 1~6은 `--allow-player-id`를 같이 줄 때만 쓴다. 번호가 겹쳐 다시 고른 번호가 허용되지 않으면(1~6) 그 번호로 announce하기 전에 멈추고 종료 코드 1로 끝난다.
- remotedb 질의 번호: announce 번호와 별개로 1~6 중에서 고른다(원본 동작). CDJ는 remotedb 메시지의 장치 번호가 1~6일 때만 답하기 때문이다(원본 `pickRemoteDbQueryId` 주석, CDJ-3000 실기).
  - 그래서 가상 CDJ가 7 이상이어도 remotedb 조회에는 원본이 고른 다른 CDJ의 번호(없으면 비어 있는 1~6)가 실린다. announce·heartbeat에는 쓰지 않고 `--allow-player-id`와도 관계없다.
  - CLI는 고른 번호를 `remotedb 질의 번호 N번을 쓴다 …`로 출력한다(announce 번호가 1~6이면 같은 번호라 출력하지 않는다).
  - CDJ-2000nexus는 7번 가상 CDJ가 옆 CDJ의 번호(2번)로 보낸 Introduce를 받았고, 질의 중 두 덱의 상태는 바뀌지 않았다. 분석하지 않은 곡의 메타데이터도 이 번호로 읽었다([#9](https://github.com/ImBada/DJLinkKit/issues/9)).
  - 다만 CDJ-2000nexus에서 분석하지 않은 곡의 조회는 될 때만 된다([#48](https://github.com/ImBada/DJLinkKit/issues/48)). 번호를 빌린 플레이어가 망에 없으면 항목 0개로 답해 오류로 끝나고, 그 플레이어가 빠졌다 다시 붙은 뒤에는 답하지 않아 10초 제한 시간으로 끝난다. 그래서 CDJ-2000nexus 한 대만 있는 망에서는 분석하지 않은 곡의 메타데이터를 얻지 못한다. rekordbox로 분석한 곡은 NFS로 읽으므로 상관없다.
  - 이 방식을 바꿀지는 사용자가 정한다([PLAN §11](PLAN.md) 메모).
- 제어 확인: 제어 명령은 `--confirm`이 대상 장치 이름과 정확히 같을 때만 보낸다. 대상을 확인하기 전에는 가상 CDJ로 참여하지 않는다.
- `control play`·`pause`: 1~4번 플레이어에만 보내고 5번 이상은 거부한다(종료 코드 2). 재생 상태 패킷에는 1~4번 칸만 있고, 대상 칸에만 명령을 싣고 나머지는 "그대로"로 채운다. 원본은 칸이 한 칸 어긋나고 나머지를 "재생 시작"으로 채워 `pause`가 대상을 멈추지 못했다. CDJ-2000nexus 실기로 확인하고 고쳤다([PLAN §9](PLAN.md)).
- 금지 경로: `PIONEER/extracted`·`PIONEER/CDP`·`djprofile.nxs`는 `fetch`뿐 아니라 메타데이터·파형·분석·앨범아트 조회 안의 모든 NFS 읽기에서 거부한다.
  - 경로 구성 요소 끝의 `.`·공백은 걷어내고 비교한다(`PIONEER.`는 `PIONEER`).
  - FAT 8.3 짧은 이름 꼴(`EXTRAC~1`, `DJPROF~1.NXS`처럼 8자 이하 이름이 `~숫자`로 끝나는 것)은 긴 이름을 알 수 없어 거부한다. 그래서 이 꼴인 곡 파일도 받지 않는다. `a~b.mp3`처럼 그 꼴이 아닌 `~`는 막지 않는다.
- 신호: SIGINT(Ctrl-C)·SIGTERM·SIGHUP은 같은 정리 경로로 간다. SIGPIPE는 무시하고, 닫힌 파이프로 나가는 출력은 그 줄만 버린다.
- 중단: 중단 뒤에는 announce·제어 송신·파일 쓰기·NFS 요청을 새로 만들지 않고, 시작한 작업과 소켓(NFS RPC 포함)을 모두 닫고 끝낸다.
  - 신호와 제한 시간 감시는 `DJLinkActor`와 독립이라 동기 PDB 해석이 멈춰도 동작한다.
  - 두 번째 신호는 바로 `_exit(130)`으로 끝낸다. 첫 중단 뒤 3초 안에 정리가 끝나지 않으면 강제 종료한다.
  - 정리는 진행 중인 파일 게시를 3초까지 기다리고, 쓰는 도중 취소되면 임시 파일(`.djlink-*.tmp`)을 지운다. 두 번째 신호·강제 종료·SIGKILL로 끝나면 임시 파일이 남을 수 있다.
- 제한 시간: `metadata`·`fetch`·`control`은 전체 제한 시간이 있다(`--timeout SEC`, 기본 15·300·15초). 넘으면 정리하고 종료 코드 1로 끝난다.
- 파일 쓰기: `fetch`와 `watch --download-dir`는 이미 있는 파일을 덮어쓰지 않는다. `watch`는 `<장치>-<슬롯>-<곡 번호>-<원래 이름>`으로 쓴다.
  - 임시 파일에 쓴 뒤 `link`로 게시한다. `link`가 안 되는 파일 시스템(FAT·exFAT 등)에서는 `renamex_np`의 `RENAME_EXCL`, 그것도 안 되면 `O_EXCL`로 만든 최종 이름에 직접 쓴다.
  - 직접 쓰는 경로는 원자적이지 않아, 강제 종료하면 반쯤 쓴 파일이 남을 수 있다. 그런 볼륨에는 `--download-dir`·`--out`을 두지 않는 편이 안전하다.
  - 쓰기·fsync·게시는 별도 큐에서 1MiB씩 하고, 조각 사이와 게시 직전에 중단을 확인한다.
- 임시 DB: OneLibrary를 읽을 때 임시 폴더에 푸는 `prolink-onelibrary-*.db`에는 USB의 곡 정보가 들어 있을 수 있다. CLI는 이 파일과 `-journal`·`-wal`·`-shm`을 정리 때 지운다. 정리가 돌지 못하고 끝났으면 `$TMPDIR`(`getconf DARWIN_USER_TEMP_DIR`)에서 직접 지운다.
- 오류 보고: `metadata`는 미디어 슬롯 조회 실패도 오류로 알리고, 요청한 파형·분석 조회가 실패하면(데이터가 없는 것과 다르다) 나머지를 출력한 뒤 종료 코드 1로 끝낸다. `passive`는 캡처 오류를 출력하고 정리한 뒤 종료 코드 1로 끝낸다.
- 연결 정리: NFS 읽기·재시도는 소켓 닫기와 취소 때 대기자·구독·타이머를 정리한다. TCP 포트 조회 연결은 응답 직후 닫고, 닫힌 TCP는 장부에서 지운다. 안전 정책이 있는 Stagehand 연결은 보내기 전에 거부한다. 번호가 거부되면 ready 대기도 끝나고, `startupRejectedDeviceId`·`waitUntilReady()`로 확인할 수 있다.

## 종료 코드

| 코드 | 뜻 |
|---|---|
| 0 | 정상 |
| 1 | 실행 실패(제한 시간 초과·번호 거부·장치 미발견·캡처 오류 포함) |
| 2 | 사용법 오류, 안전 규칙 거부 |
| 130 | 중단(Ctrl-C) |

`watch`·`status`·`mixstatus`·`passive`는 스스로 끝나지 않아 Ctrl-C로 끝내면 130이다. 번호 거부, 장치를 찾지 못한 제한 시간 초과(`watch`·`status`·`mixstatus`), 캡처 오류(`passive`)로 먼저 끝나면 1이다.
