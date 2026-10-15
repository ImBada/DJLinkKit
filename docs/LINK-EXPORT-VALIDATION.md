# Link Export 검증 기록

2026-10-15, `port/rbxport-link-export` 작업 트리에서 사용자의 “구현 완료 — 검증까지 진행” 신호를 받은 뒤 검증했다. 원본은 rbxport 1.8.0, 커밋 `90bfb53da59c5b2c3f0b76101601f30a6b74ab2b`다. 커밋·푸시는 하지 않았다.

## 현재 선언 수 (정적)

아래 숫자는 `@Test` 선언을 `grep -rE '^\s*@Test' Tests`로 센 정적 수다. 시험을 실행한 결과가 아니다. 이 문서의 날짜별 기록에 있는 "등록"·"건너뜀" 숫자는 그날 실행 결과이므로 아래 현재 수와 다를 수 있다. 2026-10-15 기본 실행(`scripts/ci.sh`)에서는 26개를 건너뛰고 1,509개가 모두 통과했다. `--loopback`에서는 Link Export 루프백 8개와 가드 시험이 통과하지만, DJLinkKit TCP 루프백 5개가 전체 실행에서만 시간 초과로 실패한다(따로 돌리면 통과, [#33](https://github.com/ImBada/DJLinkKit/issues/33)).

| 시험 대상 | 선언 | 원본 대응 | 자체 시험 |
|---|---:|---:|---:|
| DJLinkKitTests | 760 | 580 | 180 |
| DJLinkControlTests | 18 | 11 | 7 |
| DJLinkPassiveTests | 59 | 31 | 28 |
| djlinkTests (CLI) | 180 | 0 | 180 |
| DJLinkExportProtocolTests | 39 | 39 | 0 |
| DJLinkExportNFSTests | 73 | 73 | 0 |
| DJLinkExportDBServerTests | 112 | 104 | 8 |
| DJLinkExportModelTests | 97 | 95 (모델 93, XML 2) | 2 |
| DJLinkExportANLZTests | 78 | 78 | 0 |
| DJLinkExportTests | 119 | 113 (rbl-link 105, 루프백 8) | 6 |
| **합계** | **1,535** | **1,124** | **411** |

- 원본 대응 1,124개는 TypeScript 계열 622개(alphatheta-connect 532, onelibrary-connect 62, metadata-connect 28)와 rbxport 502개(core 321, ANLZ 78, 모델 93, XML 2, 루프백 8)다. 루프백을 뺀 rbxport는 494개다.
- 자체 시험 411개 중 Link Export 자체 회귀는 16개다(`export-test-map.json`의 `regressions`). 소켓 가드 2, WAV 곡 정보 2, 레거시 큐 8, 정렬 키 3, 날짜 1이다. 나머지 395개는 기반 코드·소켓 전송·바이트 리더·CLI·PLAN §9 회귀 같은 DJLinkKit 계열 시험이다.
- 조건부는 28개다. `DJLINK_LOOPBACK_TESTS=1`에서만 15개(DJLinkKit 6, Export 루프백 8, 소켓 가드 1), 꺼졌을 때만 2개(Export 소켓 가드, DJLinkKit 실제 소켓 거부), 실제 음원이 있을 때만 5개(앨범아트), 자식 프로세스 안에서만 2개(SQLCipher 도우미), `.disabled` 4개(Beacon 2개는 원본 `#[ignore]`, 나머지 2개는 서버 범위 밖)다.

## 결과 (2026-10-15 초기 검증)

| 검사 | 등록 시험 | 건너뜀 | 실패 |
|---|---:|---:|---:|
| 기존 DJLinkKit·Control·Passive·CLI 회귀 | 1,008 | 13 | 0 |
| 새 Link Export 및 ANLZ·모델/XML 대응 시험 | 469 | 2 | 0 |
| 전체 | **1,477** | **15** | **0** |

실행한 명령:

```sh
swift build
swift test --filter DJLinkExport
bash scripts/ci.sh
python3 scripts/export-port-status.py --strict
git diff --check
```

- 프로덕션 빌드 통과. macOS 최소 지원 버전 15.0을 유지했다.
- Export 시험: Link 105, Protocol 39, NFS 73, DBServer 104, ANLZ 78, 모델/XML 70개. 등록 469개 중 467개를 실행했고 실패가 없다.
- 원본이 ignore한 Beacon 시험 2개는 원본 사유 그대로 비활성화했다. 실제 시간 창에 대한 환경 의존 검사를 임의로 활성화하거나 기대값을 바꾸지 않았다.
- 기존 13개 조건부 시험은 기존과 같이 건너뛰었다. 루프백 6개, 실제 음원 앨범아트 5개, 별도 프로세스용 SQLCipher 도우미 2개다.
- 로컬 CI의 기존 원본 대응: TypeScript 원본 622개와 Swift 622개, 파일 44개 일치.
- Export 정적 대응: 서버 321, ANLZ 78, 모델 68, XML 2개가 파일별 이름·순서까지 일치.
- 경고 정리 뒤 Export 시험을 다시 실행해 실패 0을 확인했다. 새 Export 코드의 컴파일 경고도 남지 않았다.

원본 Rust 시험 자체는 실행하지 않았다. 이 기록은 고정 원본에서 입력·기대값을 옮긴 Swift 시험의 결과다. 파일별 대응과 의존 범위는 [export-port-map.md](export-port-map.md)에 있다.

## 검증 중 수정

- macOS 15.4부터 지원되는 격리 소멸자를 사용하던 부분을 macOS 15.0에서도 동작하는 자원 정리 경계로 바꿨다. 소켓 해제 완료 대기는 유지한다.
- Darwin의 `stat`/`statfs` 가져오기 이름, 파일 mode의 C 정수 타입, 클라이언트·서버에 공존하는 `Query`·`Message`·`MyTag` 등 타입 참조를 명확히 했다.
- Swift 타입 추론이 제한 시간을 넘는 컬렉션 표현에 명시 타입을 붙였다.
- Swift Testing 매크로 안에서 값형의 mutating 메서드를 직접 호출한 곳은 먼저 결과를 지역 변수에 담아 검사했다. 원본 입력·기대값과 상태 전이 순서는 유지했다.

패킷·픽스처·기대값을 통과시키기 위해 바꾸지 않았다. 민감한 원본 캡처는 고정 원본 체크아웃에서 읽고 공개 저장소에 복사하지 않았다.

## 실제 장비 확인

초기 검증에서는 실제 소켓을 열거나 LAN에 패킷을 보내지 않았다. 원본의 통합 시험은 가짜 TCP/UDP 버스로 실행했다(`rbl-fakecdj/tests/loopback.rs` 대응 8개는 이때 옮기지 않았고 #28에서 루프백 조건부 시험으로 더했다). 이 시점에는 CDJ의 실제 브라우징·Mac 음원 로드·재생·분석 표시와 macOS의 실제 서버 소켓 동작을 실기로 확인하지 않았다. 이 항목은 같은 날 뒤이어 CDJ-2000nexus에서 확인했다(아래 "실기 수정 후 회귀", [실기 기록](LINK-EXPORT-HARDWARE.md)).

서버는 `Source`로 메모리 라이브러리를 받는 별도 `DJLinkExport` 제품이며, 현재 `djlink` CLI에는 서버 시작 명령을 연결하지 않았다. 실기 단계에서는 실행 도구와 시험 라이브러리를 준비하고, 시험용 네트워크·rekordbox/rekordboxAgent 종료·광고 번호 7 이상을 확인해야 한다. 장비 케이블·전원·USB 조작은 이번 검증에 필요하지 않았다.

## 실기 수정 후 회귀 (2026-10-15)

이후 CDJ-2000nexus 실기에서 WAV 형식 선택 id 문제를 확인해 수정하고 별도 회귀 2개를 추가했다. 전체 로컬 CI를 다시 실행해 등록 1,479개(기존 1,008 + 원본 대응 469 + 실기 회귀 2), 건너뜀 15개, 실패 0을 확인했다. 원본 대응 469개의 이름·순서·입력·기대값은 유지한다. 위 초기 검증의 실제 소켓 미사용 기록과 달리, 후속 실기는 시험용 LAN에서 실제 소켓을 사용했다. [실기 기록](LINK-EXPORT-HARDWARE.md)에 구분해 적었다.

## 레거시 큐 읽기 회귀 (2026-10-15, #20)

사용자의 구현 완료·검증 진행 신호 뒤 `swift test --filter 'LegacyCue(Read|Client)Tests'`로 추가 회귀 7개를 실행해 모두 통과했다. 실기에서 찾은 큐 순서 문제를 고치며 회귀 1개를 더해 8개가 되었고, 이 시험은 수정 전 코드에서 실패하고 수정 후 통과한다. 이어 `bash scripts/ci.sh`가 종료 코드 0으로 통과했다. 등록 시험은 1,487개(기존 1,008 + 원본 대응 469 + WAV 회귀 2 + 레거시 큐 회귀 8), 조건부 건너뜀 15개, 실패 0이다. 이 기록의 앞선 판은 회귀를 7개로 세어 1,486개로 적었으나, 그 커밋(`1d5124f`)의 `@Test` 선언 수는 1,487개다. TypeScript 원본 622개·44개 파일과 Rust 원본 469개의 정적 대응도 유지했다. 실제 소켓 없이 자동 시험을 마친 뒤 별도 도구로 실기를 진행했다. [#20 기록](LINK-EXPORT-LEGACY-CUES.md).

## 모델 시험 보강과 Catalog 대조 (2026-10-15)

병렬 작업자 둘이 컴파일 없이 정적으로 한 대조를 이후 `bash scripts/ci.sh`로 검증했다. 종료 코드 0, 실패 0이다.

- `Catalog.swift`·`CatalogTests.swift`: `catalog.rs` 전체와 원본 시험 25개를 대조했고 동작 차이는 없었다. 머리말 순서와 상수 정리만 있다.
- Model 모듈: 정렬 키를 행마다 한 번만 계산하게 했고, Rust가 거부하는 입력 세 곳(16진 실수·`nan(…)`, 결합 문자, `&#-0;`)과 `file_name`의 `.` 처리를 원본에 맞췄다.
- 원본 시험 파일 3개를 더했다: `smartlists.rs` 5, `unanalysed.rs` 1, `filter.rs` 12(디스크 캐시를 거치는 1개는 `.disabled`). 모델 대응이 68개에서 86개가 되었다. `export-port-status.py --strict`가 통과한다.

## 이후 변경 (2026-10-15, #22~#28)

선언 수 기준의 변화만 적는다. 이 변경들의 시험을 실행한 결과는 이 문서에 적지 않았다.

- #27: `rbl-index/tests/file_created.rs` 원본 시험 7개를 `FileCreatedTests.swift`로 옮겼다(1개 `.disabled`). 모델 대응이 86개에서 93개가 되어 원본 대응은 494개다.
- #24: 파일명·이름·앨범 정렬 키를 행마다 한 번만 만든다. 순서는 같다. 자체 회귀 3개를 더했다.
- #25: `SmartDate.today`가 현지 시간대의 그레고리력으로 계산한다(원본 chrono Local과 같다). 자체 회귀 1개를 더했다.
- #28: Link Export 실제 소켓 가드가 `DJLINK_LOOPBACK_TESTS=1`일 때만 소켓을 허용하고, 시험 프로세스에서는 TCP를 127.0.0.1·::1에만 묶고 그쪽으로만 연결하며, UDP는 127.0.0.1·::1로만 보낸다(UDP RPC 소켓은 원본처럼 0.0.0.0에 묶은 뒤 인터페이스를 고정하므로 보내는 주소를 검사한다). 가드 회귀 2개와 `rbl-fakecdj/tests/loopback.rs` 대응 8개(`LoopbackTests.swift`)를 더했다. 원본 대응은 502개가 된다.
- `DJLinkExport*` 선언 수는 레거시 큐 회귀 시점의 479개에서 모델 시험 보강(+18, 497개), #27(+7), #24·#25 회귀(+4), #28 가드·루프백(+10)을 거쳐 518개가 되었다. `python3 scripts/export-port-status.py --strict`가 보는 대응(core 321, ANLZ 78, 모델 93, XML 2, 루프백 8)과 자체 회귀 16개의 이름·순서는 정적으로 일치한다.
