# 시험

```bash
swift test
```

시험은 LAN에 아무것도 보내지 않는다. 시험 프로세스에서 실제 소켓을 만들면 바로 실패한다. DJLinkKit과 Link Export(`DJLinkExport`) 모두 같다. 소켓·장치는 가짜 구현과 합성 데이터로 대신한다.

## 루프백 시험

실제 소켓 구현만 따로 검사하는 루프백 시험은 `DJLINK_LOOPBACK_TESTS=1`일 때만 돈다. DJLinkKit의 8개(`LiveTCPConnectionLoopbackTests`)와 Link Export의 8개(`rbl-fakecdj/tests/loopback.rs` 대응)는 모두 127.0.0.1에만 묶는다. Link Export 소켓 가드는 루프백 시험이 아니면 소켓 생성을 막고, 시험 프로세스에서는 TCP를 127.0.0.1·::1에만 묶고 그쪽으로만 연결하며, UDP는 127.0.0.1·::1로만 보낸다(UDP RPC 소켓은 원본처럼 0.0.0.0에 묶은 뒤 인터페이스를 고정하므로 보내는 주소를 검사한다). 켜도 LAN에는 아무것도 나가지 않는다.

```bash
DJLINK_LOOPBACK_TESTS=1 swift test
```

한 번에 다 돌리면 같은 프로세스의 SQLCipher DB 열기가 `DJLinkActor`를 몇 초씩 막아 TCP 루프백 시험이 시간 초과로 실패할 수 있다([#33](https://github.com/ImBada/DJLinkKit/issues/33)). `scripts/ci.sh --loopback`은 기본 시험 뒤에 루프백 시험만 따로 돌린다.

## 조건부 시험

조건이 맞을 때만 도는 시험은 선언 기준 30개다.

- 루프백 켰을 때만 17개: DJLinkKit 8, Link Export 루프백 8, Link Export 소켓 가드 1.
- 루프백 껐을 때만 2개: Link Export 소켓 가드와 DJLinkKit의 `live sockets are refused inside the test process`(실제 소켓을 거부하는지 확인). 반대 조건의 시험이 짝으로 있어 어느 쪽으로 돌려도 일부는 건너뛴다.
- 실제 음원 파일이 있을 때만 5개: 앨범아트 통합. 원본도 같은 조건에서 본문을 건너뛴다.
- 시험이 띄운 자식 프로세스 안에서만 2개: SQLCipher 동시 열기 도우미.
- `.disabled` 4개: Link Export Beacon 2개(원본 `#[ignore]`, 실제 시간 창에 의존)와 서버 범위 밖 2개(디스크 캐시, 폴더 브라우저).

암호화 픽스처(OneLibrary)는 저장소에 들어 있어 기본 실행에 포함된다.

## 시험 수

`@Test` 선언 기준(`grep -rE '^\s*@Test' Tests`로 센 정적 수) 전체 1,570개다.

| 묶음 | 수 |
|---|---:|
| DJLinkKit | 782 |
| DJLinkControl | 18 |
| DJLinkPassive | 71 |
| djlink CLI | 180 |
| DJLinkExport 계열 | 519 |

원본 대응이 1,124개(alphatheta-connect 계열 622, rbxport 502), 우리 시험이 446개다. 원본 대응 622개는 alphatheta-connect 532, onelibrary-connect 62, metadata-connect 28이고, 원본 `it` 수와 옮긴 `@Test` 수가 파일마다 같다. 우리 시험은 기반 코드·소켓 전송·바이트 리더·CLI·PLAN §9 회귀 429개와 Link Export 자체 회귀 17개다. Link Export 쪽 실행 기록은 [LINK-EXPORT-VALIDATION.md](LINK-EXPORT-VALIDATION.md)에 있다.

## 로컬 CI

GitHub Actions는 쓰지 않는다. 합치기 전에 로컬에서 `scripts/ci.sh`를 돌린다. `swift test`, 원본 대조(`port-status.sh --strict`), Link Export 원본 대조(`export-port-status.py --strict`)를 차례로 돌리고, 하나라도 실패하면 종료 코드 1로 끝난다.

```bash
UPSTREAM_DIR=~/src/upstream bash scripts/ci.sh             # 루프백 시험은 끈다
UPSTREAM_DIR=~/src/upstream bash scripts/ci.sh --loopback  # 루프백 시험까지
```

## 원본 대조

원본 저장소 세 개를 같은 부모 폴더에 받아 두면(받는 법은 [UPSTREAM.md](../UPSTREAM.md)) 원본 시험 수와 옮긴 시험 수를 파일별로 나란히 볼 수 있다. 읽기만 하는 스크립트다.

```bash
UPSTREAM_DIR=~/src/upstream bash scripts/port-status.sh            # 전체
UPSTREAM_DIR=~/src/upstream bash scripts/port-status.sh --stage 4  # 단계 하나(1~8)
```

하나라도 다르면 종료 코드 1로 끝난다. 원본이 고정 커밋과 다르면 경고만 낸다.

Link Export는 rbxport 체크아웃(`$UPSTREAM_DIR/rbxport`, 별도 위치는 `DJLINK_EXPORT_UPSTREAM_DIR`)과 같은 방식으로 대조한다. 원본이 고정 커밋과 다르거나 이름·순서가 다르면 오류를 내고, `--strict`를 주면 종료 코드 1로 끝난다.

```bash
UPSTREAM_DIR=~/src/upstream python3 scripts/export-port-status.py --strict
```
