# Link Export 서버 이식

2026-10-15. 사용자가 요청한 rbxport의 Mac → CDJ 라이브러리 공유를 별도 `DJLinkExport` 제품으로 옮긴다. 기존 TypeScript 클라이언트 포트의 범위를 확장하는 단계이며, 서버 원본은 rbxport 1.8.0, 커밋 `90bfb53da59c5b2c3f0b76101601f30a6b74ab2b`다.

## 대응 범위

- `rbl-prolink`: 패킷·장치 테이블, 원본 시험 39개.
- `rbl-nfs`: XDR·RPC·파일 트리·파일 서버, 원본 시험 73개.
- `rbl-dbserver`: 프레임·세션·메뉴·편집·TCP 서버, 원본 시험 104개.
- `rbl-link`: 참여·광고·상태·카탈로그·분석 응답·공유 파일·서버 생명주기, 원본 시험 105개.
- 핵심 서버의 원본 시험 합계는 321개다. 의존 ANLZ 78개와 메모리 모델 시험은 따로 센다.
- `rbl-anlz`: 분석 파일 파싱·재출력·grid/cue/phrase/vocal·공유 경로와 인코딩.
- `rbl-index`: 서버가 받는 메모리 라이브러리, cue/playlist/history/tag, 정렬·검색·필터·스마트 목록·관련곡·파일 생성 시간. `rbl-core`의 XML 스캐너와 `rbl-db`의 details/export-info 값형도 포함한다.

rbxport 앱 전체, 암호화 rekordbox DB 열기·쓰기, 디스크 인덱스 캐시, XML 가져오기·내보내기, 기기 내보내기, 폴더 브라우저의 느슨한 음원 태그 읽기, 오디오 재생·분석 엔진은 이번 서버 범위에 포함하지 않는다. 호출자가 `Source`로 일관된 메모리 라이브러리와 세부 정보·편집 콜백을 제공한다. `StaticSource`는 고정 스냅샷을 제공한다. 기존 CLI에는 서버를 아직 연결하지 않는다.

## 진행과 검증 관문

현재 **빌드·대응 시험·전체 회귀 검증 및 CDJ-2000nexus 기본 MP3/WAV 실기 확인 완료**이다. 실기 회귀 2개를 추가한 전체 1,479개 등록 시험에서 실패가 없고 15개는 조건에 따라 건너뛰었다. 상세 결과는 [검증 기록](LINK-EXPORT-VALIDATION.md)에 있다. 파일별 상태는 [export-port-map.md](export-port-map.md)에 기록한다.

1. 원본 시험 파일 하나를 Swift 파일 하나로 대응하고 입력·기대값을 유지한다. Rust 시험 함수 이름을 `@Test("함수 이름")`으로 유지한다.
2. 코드를 옮긴다. 원본 버그는 그대로 두고 개선 제안은 PLAN §9에 기록한다.
3. 전체 구현·정적 검토가 끝난 다음 사용자가 **“구현 완료”**라고 하면 빌드와 해당 단계 시험을 실행한다.
4. 기존 시험 회귀까지 확인한 뒤 시험용 네트워크에서 실기 확인한다. 해당 Mac의 rekordbox·rekordboxAgent는 꺼져 있어야 하고 광고 번호는 7 이상이다.
5. 커밋·푸시는 사용자가 요청했을 때만 한다.

원본 루프백 통합 시험은 실제 소켓 대신 같은 TCP/UDP 바이트를 연결하는 가짜 전송을 주입한다. `LiveExportSocketFactory`는 시험 프로세스에서 실제 소켓 생성을 금지한다. 시간은 주입한 시계를 사용하며 Rust `Instant`에 대응하는 기본 시계는 단조 시계다.

## 픽스처

실곡 정보·개인 경로가 들어 있는 원본 캡처와 시험 상수는 공개 저장소에 복사하지 않는다. `UpstreamFixtures`가 고정 원본 체크아웃에서 그대로 읽는다. 값 대체·기대값 변경·픽스처 부재 시 성공 처리나 건너뛰기를 하지 않는다. 기본 경로는 `~/src/upstream/rbxport`, 별도 위치는 `DJLINK_EXPORT_UPSTREAM_DIR` 또는 `UPSTREAM_DIR/rbxport`다.

## 라이선스·출처

rbxport 코드는 GPL-2.0-or-later이며 새 Export 타깃과 시험에 해당 표시를 둔다. 원문은 [라이선스](../LICENSES/GPL-2.0-or-later.txt), 범위와 저작권 표시는 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)에 있다. 기존 MIT 클라이언트 제품과 별도 제품으로 선택한다. 공개 원본 코드만 옮기며 펌웨어·rekordbox 실행 파일을 직접 분석하지 않는다. 원본에 적힌 분석 근거는 [PROVENANCE.md](../PROVENANCE.md)에 기록한다.

## 이번 단계 기록

2026-10-15: 서버 코드·원본 대응 시험 469개(core 321, ANLZ 78, 모델 68, XML 2)를 작성했다. 파일별 이름·순서의 strict 정적 대조와 Swift 소스 서식 정리를 수행했다. 사용자의 이번 단계 “구현 완료” 신호 뒤 빌드·대응 시험·전체 로컬 CI를 실행해 통과했다. Export 등록 시험 469개 중 원본 ignore 2개를 제외한 467개를 실행했고 실패가 없다. 실제 소켓·장비 조작·커밋·푸시는 실행하지 않았다. 상세 결과는 [검증 기록](LINK-EXPORT-VALIDATION.md)에 있다.

공유 파일 변경: `Package.swift`의 별도 제품·타깃, 기존 `UDPSocket`/`BSDUDPSocket`의 서버용 send/receive 버퍼 옵션, `scripts/ci.sh`의 Export 정적 대응 검사를 추가했다. 기존 CLI가 서버를 실행하지는 않는다.

실기에서는 LINK 목록·두 CDJ의 NFS 마운트·2번 CDJ의 MP3 로드/재생/CUE를 확인했다. WAV E-8305는 곡 정보의 디코더 선택 id가 1로 고정된 원본 동작 때문이었다. id=11의 단일 필드 비교로 WAV 로드/재생/CUE를 확인하고 실제 서버를 수정했다. 원본 1:1 기준선은 `port/rbxport-one-to-one` (`03d3371`)에 남기고 실기 회귀는 원본 대응 개수와 분리한다. [상세 실기 기록](LINK-EXPORT-HARDWARE.md). 레거시 큐 읽기는 [#20](https://github.com/ImBada/DJLinkKit/issues/20)에 남겼다.
