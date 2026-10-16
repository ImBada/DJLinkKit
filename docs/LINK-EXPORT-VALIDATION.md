# Link Export 검증

`DJLinkExport*` 시험의 구성과 검증 중 고친 것을 적는다. 저장소 전체 시험 수와 실행 방법은 [testing.md](testing.md), 파일별 원본 대응은 [export-port-map.md](export-port-map.md)에 있다.

## 시험 구성

`grep -rE '^\s*@Test' Tests`로 센 선언 수다(실행 결과가 아니다).

| 시험 대상 | 선언 | 원본 대응 | 자체 시험 |
|---|---:|---:|---:|
| DJLinkExportProtocolTests | 39 | 39 | 0 |
| DJLinkExportNFSTests | 73 | 73 | 0 |
| DJLinkExportDBServerTests | 113 | 104 | 9 |
| DJLinkExportModelTests | 97 | 95 (모델 93, XML 2) | 2 |
| DJLinkExportANLZTests | 78 | 78 | 0 |
| DJLinkExportTests | 126 | 113 (rbl-link 105, 루프백 8) | 13 |
| 합계 | 526 | 502 | 24 |

원본 대응 502개는 core 321, ANLZ 78, 모델 93, XML 2, 루프백 8이다. `python3 scripts/export-port-status.py --strict`가 원본 Rust 시험 함수와 Swift `@Test` 이름·순서를 파일마다 정적으로 대조한다. 원본 Rust 시험 자체는 돌리지 않았다. 고정 원본에서 입력·기대값을 옮긴 Swift 시험만 돈다.

자체 시험 24개는 원본과 다르게 고친 곳의 회귀다.

| 파일 | 수 | 고친 것 |
|---|---:|---|
| `TrackInfoCompatibilityTests.swift` | 2 | WAV 곡 정보 형식 id ([실기 기록](LINK-EXPORT-HARDWARE.md)) |
| `LegacyCueReadTests.swift` | 7 | 레거시 큐 읽기·편집 응답 순서 (#20, #32) |
| `LegacyCueClientTests.swift` | 2 | 레거시 큐 클라이언트 왕복 (#20) |
| `FilenameSortingRegressionTests.swift`, `CatalogSortingRegressionTests.swift` | 1 + 2 | 정렬 키를 행마다 한 번만 만든다 (#24) |
| `SmartDateRegressionTests.swift` | 1 | 오늘 날짜를 그레고리력으로 계산 (#25) |
| `ExportSocketGuardTests.swift` | 2 | 시험 프로세스의 실제 소켓 가드 (#28) |
| `BeaconUpstreamFixTests.swift` | 4 | 비컨 보내기 실패 무시·경로 오류 다시 보내기·미리 들은 알림으로 참여 |
| `CatalogArtworkSizeTests.swift` | 3 | 목록 썸네일 id와 그림 크기 |

24개 모두 `export-test-map.json`의 `regressions`에 이름·순서가 적혀 있다.

## 건너뛰는 시험

- 루프백 8개(`LoopbackTests.swift`): 127.0.0.1의 실제 소켓을 열어 `DJLINK_LOOPBACK_TESTS=1`일 때만 돈다. `scripts/ci.sh --loopback`이 기본 시험 뒤에 따로 돌린다. 한 프로세스에서 다 돌리면 SQLCipher DB 열기가 `DJLinkActor`를 막아 TCP 루프백 시험이 시간 초과로 실패할 수 있다([#33](https://github.com/ImBada/DJLinkKit/issues/33)).
- 소켓 가드 2개: 하나는 루프백을 켰을 때만, 하나는 껐을 때만 돈다.
- `.disabled` 4개:
  - `rbl-link/tests/beacon.rs`의 2개. 원본이 `#[ignore]`한 시험으로, 실제 시간 창에 의존한다. 원본 사유대로 끄고 기대값은 바꾸지 않았다.
  - `a_snapshot_keeps_the_tag_categories`(디스크 캐시)와 `a_folder_sorts_its_tracks_and_loose_files_by_creation_together`(폴더 브라우저). 서버 범위 밖이라 이름만 남겼다.

## 검증 중 고친 것

첫 빌드·시험에서 원본 동작과 관계없는 Swift 쪽 문제를 고쳤다. 패킷·픽스처·기대값은 시험을 통과시키려고 바꾸지 않았다.

- macOS 15.4부터 되는 격리 소멸자를 쓰던 곳을 macOS 15.0에서도 되는 자원 정리 경계로 바꿨다. 소켓 해제 완료 대기는 그대로다.
- Darwin의 `stat`/`statfs` 가져오기 이름, 파일 mode의 C 정수 타입, 클라이언트·서버에 같이 있는 `Query`·`Message`·`MyTag` 등의 타입 참조를 명확히 했다.
- 타입 추론이 제한 시간을 넘는 컬렉션 표현에 명시 타입을 붙였다.
- Swift Testing 매크로 안에서 값형의 mutating 메서드를 부르던 곳은 결과를 지역 변수에 먼저 담아 검사한다. 입력·기대값과 상태 전이 순서는 그대로다.

원본과 다시 대조해 맞춘 것도 있다.

- `Catalog.swift`·`CatalogTests.swift`를 `catalog.rs` 전체와 원본 시험 25개에 대조했다. 동작 차이는 없었고 머리말 순서와 상수만 정리했다.
- Model 모듈에서 Rust가 거부하는 입력 세 곳(16진 실수·`nan(…)`, 결합 문자, `&#-0;`)과 `file_name`의 `.` 처리를 원본에 맞췄다. 처음에 빠뜨린 원본 시험 파일 `smartlists.rs`·`unanalysed.rs`·`filter.rs`·`file_created.rs`를 더했다.
