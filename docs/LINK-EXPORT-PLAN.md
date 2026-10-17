# Link Export 서버 이식

rbxport의 Mac → CDJ 라이브러리 공유(Link Export 서버)를 별도 `DJLinkExport` 제품으로 옮긴다. TypeScript 클라이언트 포트의 범위 밖이라 따로 둔 단계다. 원본은 rbxport 1.8.0, 커밋 `90bfb53da59c5b2c3f0b76101601f30a6b74ab2b`다. 원본 그대로 옮긴 기준선은 `port/rbxport-one-to-one` 브랜치(`03d3371`)에 남겨 두었다.

## 대응 범위

| 원본 crate | 내용 | 원본 시험 |
|---|---|---:|
| `rbl-prolink` | 패킷·장치 테이블 | 39 |
| `rbl-nfs` | XDR·RPC·파일 트리·파일 서버 | 73 |
| `rbl-dbserver` | 프레임·세션·메뉴·편집·TCP 서버 | 104 |
| `rbl-link` | 참여·광고·상태·카탈로그·분석 응답·공유 파일·서버 생명주기 | 105 |
| `rbl-anlz` | 분석 파일 파싱·재출력·grid/cue/phrase/vocal·공유 경로와 인코딩 | 78 |
| `rbl-index` | 메모리 라이브러리, cue/playlist/history/tag, 정렬·검색·필터·스마트 목록·관련곡·파일 생성 시간 | 93 |
| `rbl-core`·`rbl-db` 일부 | XML 스캐너, details/export-info 값형 | 2 |
| `rbl-fakecdj` | 루프백 통합 시험 | 8 |

서버 핵심 4개 crate가 321개, 전체 원본 대응은 502개다. 루프백 8개를 빼면 항상 도는 쪽은 494개다. 파일별 대응은 [export-port-map.md](export-port-map.md)에 있다.

범위 밖: rbxport 앱 전체, 암호화 rekordbox DB 열기·쓰기, 디스크 인덱스 캐시, XML 가져오기·내보내기, 기기 내보내기, 폴더 브라우저의 느슨한 음원 태그 읽기, 오디오 재생·분석 엔진. 호출자가 `Source`로 메모리 라이브러리와 세부 정보·편집 콜백을 넘긴다. `StaticSource`는 고정 스냅샷이다. `djlink` CLI에는 서버를 연결하지 않았다.

## 옮기는 규칙

1. 원본 시험 파일 하나를 Swift 파일 하나로 옮기고 입력·기대값을 유지한다. Rust 시험 함수 이름을 `@Test("함수 이름")`으로 쓴다.
2. 원본 버그는 그대로 옮기고 고칠 것은 PLAN §9에 적는다. 원본과 다르게 고친 것은 원본 대응 시험과 따로 자체 회귀를 둔다.
3. 빌드·시험은 사용자가 "구현 완료"라고 한 뒤에 돌리고, 기존 시험 회귀를 확인한 다음 실기로 넘어간다.

원본 통합 시험은 실제 소켓 대신 같은 TCP/UDP 바이트를 잇는 가짜 전송을 주입한다. `rbl-fakecdj/tests/loopback.rs` 대응 8개(`LoopbackTests.swift`)만 `DJLINK_LOOPBACK_TESTS=1`일 때 127.0.0.1의 실제 소켓으로 돈다. `LiveExportSocketFactory`는 시험 프로세스에서 이 환경 변수가 없으면 실제 소켓을 만들지 않고, 있어도 TCP는 127.0.0.1·::1에만 묶고 그쪽으로만 연결하며 UDP는 127.0.0.1·::1로만 보낸다([#28](https://github.com/ImBada/DJLinkKit/issues/28)). 시간은 주입한 시계를 쓰고, Rust `Instant`에 대응하는 기본 시계는 단조 시계다.

공유 파일 변경은 `Package.swift`의 별도 제품·타깃, 기존 `UDPSocket`/`BSDUDPSocket`의 서버용 send/receive 버퍼 옵션, `scripts/ci.sh`의 Export 정적 대응 검사다.

## 픽스처

원본 캡처 파일(바이너리 픽스처)과 개인 라이브러리 정보(곡·경로·토큰)는 공개 저장소에 복사하지 않는다. 캡처 파일은 `UpstreamFixtures`가 고정 원본 체크아웃에서 그대로 읽는다. 원본 시험 코드에 적힌 짧은 문자열 상수(곡 이름·경로 예시 등)는 그대로 옮긴다. 값을 바꿔 넣거나, 픽스처가 없을 때 성공 처리하거나 건너뛰지 않는다. 기본 경로는 `~/src/upstream/rbxport`, 다른 위치는 `DJLINK_EXPORT_UPSTREAM_DIR` 또는 `UPSTREAM_DIR/rbxport`로 준다.

## 라이선스·출처

rbxport 코드는 GPL-2.0-or-later이고 Export 타깃과 시험에 그 표시를 둔다. 원문은 [라이선스](../LICENSES/GPL-2.0-or-later.txt), 범위와 저작권 표시는 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)에 있다. 저장소 전체도 GPL-2.0-or-later다([COPYRIGHT.md](../COPYRIGHT.md)). Export는 따로 고르는 제품·타깃으로 남는다. 공개 원본 코드만 옮기고 펌웨어·rekordbox 실행 파일은 분석하지 않는다. 원본에 적힌 분석 근거와 실기 관찰은 [PROVENANCE.md](../PROVENANCE.md)에 적는다.

## 원본과 다르게 고친 곳

자세한 이유는 PLAN §9에 있다.

- WAV 곡 정보: 곡 정보 첫 항목 id가 1로 고정돼 CDJ-2000nexus가 WAV에 E-8305를 냈다. `TrackDetails.file_type`을 보낸다. [실기 기록](LINK-EXPORT-HARDWARE.md).
- 레거시 큐 목록 읽기 `0x2104`([#20](https://github.com/ImBada/DJLinkKit/issues/20)): 원본에 없던 조회를 기존 `0x4702` 응답에 연결하고, 메모리 큐를 먼저·핫큐를 뒤에 보낸다. 큐 편집 응답(`0x2105`)도 같은 순서로 보낸다(#32). [레거시 큐 기록](LINK-EXPORT-LEGACY-CUES.md).
- 정렬 키를 행마다 한 번만 만든다(#24). 스마트 목록의 오늘 날짜를 현지 그레고리력으로 계산한다(#25).
- 비컨: 보내기 한 번 실패로 상태 송신이 멈추지 않게 실패를 버린다. 한 장치로 보내다 경로 오류가 나면 잠시 뒤 다시 보낸다. 앱이 미리 들은 장치 알림으로 참여를 바로 시작하는 입구(`seedAnnouncements`)를 더했다.
- 파일 요청 알림: 플레이어가 NFS로 파일을 찾거나 처음부터 읽을 때 앱에 알리는 입구(`LinkExport.observe_files`)를 더했다.
- 파일 바꿔 내기: 원본 경로로 찾은 파일 대신 다른 호스트 파일을 내어 주는 입구(`LinkExport.redirect_file`)를 더했다.
- 목록 썸네일: 곡 id로 찾고, rekordbox처럼 `_s` 그림을 먼저 보낸다.

원본 동작을 그대로 둔 것(`Claim` 선언 길이, mixer subtype 재인코딩, 스마트 목록 `dateCreated` 등)도 PLAN §9에 있다.

## 실기 상태

CDJ-2000nexus 2대·DJM-900NXS2에서 LINK 목록, NFS 마운트, MP3·WAV 로드·재생·CUE, 레거시 큐 표시·호출을 확인했다. CDJ-3000 계열, 다른 음원 형식, 장시간 스트리밍은 확인하지 못했다. 자세한 것은 [실기 기록](LINK-EXPORT-HARDWARE.md)에, 시험 구성은 [검증 기록](LINK-EXPORT-VALIDATION.md)에 있다.

## 호스트 안전 규칙

`djlink` CLI의 안전 규칙(PLAN §11)은 CLI·앱 쪽 규칙이라 라이브러리에는 넣지 않았다. Link Export에는 CLI가 없으므로 `LinkExport.start`를 부르는 호스트가 다음을 지킨다.

- 같은 Mac에서 rekordbox·rekordboxAgent가 돌고 있으면 시작하지 않는다. 서버가 rekordbox와 같은 포트(UDP 50000~50002, TCP 12523, portmap 50111)를 잡는다. CLI의 검사(`checkRekordboxNotRunning`)는 `djlink` 타깃 안에 있어 공개하지 않았다.
- NFS는 2049를 연다. macOS NFS 서버(`nfsd`)가 켜져 있으면 겹친다.
- 서버는 rekordbox 범위 번호(유선 17·18, 무선 41)로 참여하며 플레이어 번호(1~6)를 쓰지 않는다.
- 공연이나 리허설 중인 네트워크에서 띄우지 않는다. 시험용 스위치의 인터페이스를 지정해 띄운다.
- 공유할 폴더(`share_root`) 밖의 경로는 NFS가 거부한다. 개인 라이브러리를 공유할 때는 그 폴더 아래만 노출되는지 확인한다.
- 실기 확인 도구는 저장소 밖에 둔다(합성 곡·합성 큐만 쓴다).
