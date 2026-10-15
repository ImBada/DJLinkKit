# Link Export 서버 이식

2026-10-15. 사용자가 요청한 rbxport의 Mac → CDJ 라이브러리 공유를 별도 `DJLinkExport` 제품으로 옮긴다. 기존 TypeScript 클라이언트 포트의 범위를 확장하는 단계이며, 서버 원본은 rbxport 1.8.0, 커밋 `90bfb53da59c5b2c3f0b76101601f30a6b74ab2b`다.

## 대응 범위

- `rbl-prolink`: 패킷·장치 테이블, 원본 시험 39개.
- `rbl-nfs`: XDR·RPC·파일 트리·파일 서버, 원본 시험 73개.
- `rbl-dbserver`: 프레임·세션·메뉴·편집·TCP 서버, 원본 시험 104개.
- `rbl-link`: 참여·광고·상태·카탈로그·분석 응답·공유 파일·서버 생명주기, 원본 시험 105개.
- 핵심 서버의 원본 시험 합계는 321개다. 의존 ANLZ 78개, 메모리 모델 93개, XML 스캐너 2개, 루프백 통합 8개(`rbl-fakecdj`)는 따로 센다. 원본 대응은 모두 502개이고, 루프백을 뺀 항상 도는 쪽은 494개다.
- `rbl-anlz`: 분석 파일 파싱·재출력·grid/cue/phrase/vocal·공유 경로와 인코딩.
- `rbl-index`: 서버가 받는 메모리 라이브러리, cue/playlist/history/tag, 정렬·검색·필터·스마트 목록·관련곡·파일 생성 시간. `rbl-core`의 XML 스캐너와 `rbl-db`의 details/export-info 값형도 포함한다.

rbxport 앱 전체, 암호화 rekordbox DB 열기·쓰기, 디스크 인덱스 캐시, XML 가져오기·내보내기, 기기 내보내기, 폴더 브라우저의 느슨한 음원 태그 읽기, 오디오 재생·분석 엔진은 이번 서버 범위에 포함하지 않는다. 호출자가 `Source`로 일관된 메모리 라이브러리와 세부 정보·편집 콜백을 제공한다. `StaticSource`는 고정 스냅샷을 제공한다. 기존 CLI에는 서버를 아직 연결하지 않는다.

## 진행과 검증 관문

현재 **빌드·대응 시험·전체 회귀 검증, CDJ-2000nexus 기본 MP3/WAV 실기 확인, #20 레거시 큐 실기 확인을 마쳤다.** 지금 선언된 `DJLinkExport*` 시험은 519개다(원본 대응 502, 자체 회귀 17). 이 중 `.disabled`가 4개, `DJLINK_LOOPBACK_TESTS`에 따라 도는 것이 루프백 8개와 소켓 가드 2개다. 날짜별 실행 결과는 [검증 기록](LINK-EXPORT-VALIDATION.md)에 있고, 2026-10-16 기본 실행(`scripts/ci.sh`)에서 1,510개가 통과하고 26개를 건너뛰었다(루프백 시험은 `scripts/ci.sh --loopback`이 따로 돌린다, [#33](https://github.com/ImBada/DJLinkKit/issues/33)). 파일별 상태는 [export-port-map.md](export-port-map.md)에 기록한다.

1. 원본 시험 파일 하나를 Swift 파일 하나로 대응하고 입력·기대값을 유지한다. Rust 시험 함수 이름을 `@Test("함수 이름")`으로 유지한다.
2. 코드를 옮긴다. 원본 버그는 그대로 두고 개선 제안은 PLAN §9에 기록한다.
3. 전체 구현·정적 검토가 끝난 다음 사용자가 **“구현 완료”**라고 하면 빌드와 해당 단계 시험을 실행한다.
4. 기존 시험 회귀까지 확인한 뒤 시험용 네트워크에서 실기 확인한다. 해당 Mac의 rekordbox·rekordboxAgent는 꺼져 있어야 하고 광고 번호는 7 이상이다.
5. 커밋·푸시는 사용자가 요청했을 때만 한다.

원본 통합 시험은 실제 소켓 대신 같은 TCP/UDP 바이트를 연결하는 가짜 전송을 주입한다. 단 `rbl-fakecdj/tests/loopback.rs` 대응 8개(`LoopbackTests.swift`)는 `DJLINK_LOOPBACK_TESTS=1`일 때만 127.0.0.1의 실제 소켓으로 돈다. `LiveExportSocketFactory`는 시험 프로세스에서 이 환경 변수가 없으면 실제 소켓 생성을 금지하고, 있어도 TCP는 127.0.0.1·::1에만 묶고 그쪽으로만 연결하며 UDP는 127.0.0.1·::1로만 보낸다(#28). 시험은 어느 경우에도 LAN에 아무것도 보내지 않는다. 시간은 주입한 시계를 사용하며 Rust `Instant`에 대응하는 기본 시계는 단조 시계다.

## 픽스처

원본 캡처 파일(바이너리 픽스처)과 개인 라이브러리 정보(곡·경로·토큰)는 공개 저장소에 복사하지 않는다. 캡처 파일은 `UpstreamFixtures`가 고정 원본 체크아웃에서 그대로 읽는다. 원본 시험 코드에 적힌 짧은 문자열 상수(곡 이름·경로 예시 등)는 개인 정보가 아니므로 1:1로 그대로 옮긴다. 값 대체·기대값 변경·픽스처 부재 시 성공 처리나 건너뛰기를 하지 않는다. 기본 경로는 `~/src/upstream/rbxport`, 별도 위치는 `DJLINK_EXPORT_UPSTREAM_DIR` 또는 `UPSTREAM_DIR/rbxport`다.

## 라이선스·출처

rbxport 코드는 GPL-2.0-or-later이며 새 Export 타깃과 시험에 해당 표시를 둔다. 원문은 [라이선스](../LICENSES/GPL-2.0-or-later.txt), 범위와 저작권 표시는 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)에 있다. 저장소 전체가 GPL-2.0-or-later로 통일되었다([COPYRIGHT.md](../COPYRIGHT.md)). Export는 계속 별도 제품·타깃으로 선택한다. 공개 원본 코드만 옮기며 펌웨어·rekordbox 실행 파일을 직접 분석하지 않는다. 원본에 적힌 분석 근거는 [PROVENANCE.md](../PROVENANCE.md)에 기록한다.

## 이번 단계 기록

2026-10-15: 서버 코드·원본 대응 시험 469개(core 321, ANLZ 78, 모델 68, XML 2)를 작성했다. 이 469개는 처음 등록한 개수이고, 이후 모델 시험 25개를 더해 494개, 루프백 8개를 더해 502개가 되었다. 파일별 이름·순서의 strict 정적 대조와 Swift 소스 서식 정리를 수행했다. 사용자의 이번 단계 “구현 완료” 신호 뒤 빌드·대응 시험·전체 로컬 CI를 실행해 통과했다. Export 등록 시험 469개 중 원본 ignore 2개를 제외한 467개를 실행했고 실패가 없다. 실제 소켓·장비 조작·커밋·푸시는 실행하지 않았다. 상세 결과는 [검증 기록](LINK-EXPORT-VALIDATION.md)에 있다.

공유 파일 변경: `Package.swift`의 별도 제품·타깃, 기존 `UDPSocket`/`BSDUDPSocket`의 서버용 send/receive 버퍼 옵션, `scripts/ci.sh`의 Export 정적 대응 검사를 추가했다. 기존 CLI가 서버를 실행하지는 않는다.

실기에서는 LINK 목록·두 CDJ의 NFS 마운트·2번 CDJ의 MP3 로드/재생/CUE를 확인했다. WAV E-8305는 곡 정보의 디코더 선택 id가 1로 고정된 원본 동작 때문이었다. id=11의 단일 필드 비교로 WAV 로드/재생/CUE를 확인하고 실제 서버를 수정했다. 원본 1:1 기준선은 `port/rbxport-one-to-one` (`03d3371`)에 남기고 실기 회귀는 원본 대응 개수와 분리한다. [상세 실기 기록](LINK-EXPORT-HARDWARE.md). 레거시 큐 읽기는 [#20](https://github.com/ImBada/DJLinkKit/issues/20)에서 구현하고 실기로 확인했다([#20 기록](LINK-EXPORT-LEGACY-CUES.md)).

## 호스트 안전 규칙

`djlink` CLI의 안전 규칙(PLAN §11)은 CLI·앱 쪽 규칙이라 라이브러리에는 넣지 않았다. Link Export에는 아직 CLI가 없으므로, `LinkExport.start`를 부르는 호스트가 다음을 지킨다.

- 같은 Mac에서 rekordbox·rekordboxAgent가 돌고 있으면 시작하지 않는다. 서버가 rekordbox와 같은 포트(UDP 50000~50002, TCP 12523, portmap 50111)를 잡는다. CLI의 검사(`checkRekordboxNotRunning`)는 `djlink` 타깃 안에 있어 아직 공개하지 않았다.
- NFS는 2049를 연다. macOS NFS 서버(`nfsd`)가 켜져 있으면 겹친다.
- 서버는 rekordbox 범위 번호(유선 17·18, 무선 41)로 참여하며 플레이어 번호(1~6)를 쓰지 않는다.
- 공연이나 리허설 중인 네트워크에서 띄우지 않는다. 시험용 스위치의 인터페이스를 지정해 띄운다.
- 공유할 폴더(`share_root`) 밖의 경로는 NFS가 거부한다. 개인 라이브러리를 공유할 때는 그 폴더 아래만 노출되는지 확인한다.
- 실기 확인 도구는 저장소 밖에 둔다(합성 곡·합성 큐만 쓴다).

## #20 레거시 큐 조회 추가 구현

`0x2104` 읽기 dispatch와 별도 자체 회귀 8개를 작성했다. 실기에서 시간순으로 섞은 큐 목록이 핫큐 A 버튼을 끄고 CALL ▶ 오류(E-8302)를 낸 것을 찾아 메모리 큐 먼저·핫큐 뒤로 순서를 고쳤고, 메모리 큐·루프·A/B/C 호출을 실제 CDJ에서 확인했다. [#20 구현·검증 기록](LINK-EXPORT-LEGACY-CUES.md).
