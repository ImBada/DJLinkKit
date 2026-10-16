# Link Export 실기 기록

2026-10-15에 시험용 네트워크에서 확인했다. 시작점은 원본 rbxport 1.8.0(`90bfb53da59c5b2c3f0b76101601f30a6b74ab2b`)과 같은 기준선 `03d3371`(`port/rbxport-one-to-one`)이다. 레거시 큐 실기는 [LINK-EXPORT-LEGACY-CUES.md](LINK-EXPORT-LEGACY-CUES.md)에 따로 있다.

## 환경

- 장비: CDJ-2000nexus 2대, DJM-900NXS2, 시험용 스위치, Mac USB LAN.
- 같은 Mac의 rekordbox·rekordboxAgent가 꺼진 것을 확인했고 실행 중에도 검사했다.
- Link Export 가상 번호 17, 유선 IPv4 링크 로컬 네트워크.
- 저장소 밖의 실행 도구와 합성 음원을 썼다. 기존 곡·USB 파일은 건드리지 않았다.
- 곡 로드·재생·CUE는 2번 CDJ에서 확인했다. 1번은 발견·마운트까지만 확인했다.
- 합성 신호 음원: 60초, 120 BPM, 44.1kHz 스테레오. WAV는 PCM 16비트, MP3는 320kbps. ANLZ는 이식한 author API로 만들었다.

## 결과

| 항목 | 결과 |
|---|---|
| 네트워크 참여 | 가상 번호 17로 참여, CDJ 2대와 믹서 발견 |
| NFS 공유 | 두 CDJ가 Mac 공유를 자동 마운트 |
| 브라우징 | 2번 CDJ의 LINK → Mac → PLAYLIST → DJLinkKit Test에 시험곡 표시 |
| Mac → CDJ 로드 명령 | 2번 CDJ가 합성 track ID를 받고 곡 정보·분석·NFS를 요청 |
| MP3 | 60초·120 BPM 표시, 시작 위치·재생·CUE 복귀 정상 |
| WAV (기준선) | 수동 생성 PCM WAV와 FFmpeg 생성 WAV 모두 E-8305 |
| WAV (수정 후) | 응답 보정 없이 PCM 읽기, 재생, 시작 위치 CUE 복귀 정상 |
| 종료 | 서버 종료 뒤 UDP/TCP 포트와 프로세스가 남지 않음 |

처음 쓴 완전 무음 MP3는 로드됐지만 CUE가 곡 끝에 잡혔다. 작은 신호가 든 MP3로 바꾸자 정상이었다. 무음 구간을 건너뛰는 Auto Cue 때문으로 추정한다. 이 결과는 서버 큐 목록이 맞다는 근거가 아니다.

## WAV E-8305 원인과 수정

원본 `rbl-dbserver/src/session.rs::track_info_rows`는 첫 항목의 `a`와 `id`를 모두 1로 고정한다. 기준선도 그대로 옮겼다.

CDJ 요청은 `0x2102` 다음 `0x3000`, 문맥 `0x02080401`이다. 인자 하나짜리 setup을 쓰는 이 장비에는 첫 항목이 legacy item type `0x04`로 간다. 이 항목의 `arguments[1]`이 디코더를 고르는 것으로 관측됐다.

| 같은 WAV에서 바꾼 것 | 관측 |
|---|---|
| 기준선, 첫 항목 id=1 | E-8305. NFS 경로 조회는 성공, READ 응답은 파일 바이트와 일치 |
| 별도 `0x2f` 항목만 11 또는 3 | 같은 실패. 이 항목의 의미는 단정하지 않는다 |
| 첫 항목 id만 11 | RIFF 헤더 64바이트·PCM 블록 읽기로 바뀌고 재생·CUE 복귀 정상 |
| 서버가 `TrackDetails.file_type`을 보냄 | 응답 보정 없이 같은 결과 |

첫 항목의 `a` 값 1과 나머지 항목·바이트는 그대로다. `file_type`이 0인 기존 Source와 원본 시험에는 기본값 1을 쓴다. 이 장비에서 확인한 값은 1(MP3)과 11(WAV)뿐이고, 다른 형식·장비는 확인하지 않았다. PLAN §9에도 적었다.

회귀 시험은 `TrackInfoCompatibilityTests.swift`의 2개다. setup/track-info/render 왕복을 가짜 세션으로 만들고, 인코딩된 첫 응답과 경로·track ID를 검사한다. WAV 시험은 수정 전 코드에서 실패하고 수정 뒤 통과한다. 다른 하나는 MP3와 형식 미지정 입력의 기존 응답이 그대로인지 본다. 원본 대응 시험의 입력·기대값은 바꾸지 않았다.

## 송수신 확인 방법

시스템 BPF 캡처는 권한이 없어 하지 못했다. 실행 도구가 주입한 실제 TCP/UDP 소켓의 송수신 경계에 기록을 붙여 요청·응답을 비교했다. 애플리케이션 송수신 기록이며 시스템 pcap이 아니다. 관측한 NFS READ 응답 데이터는 합성 파일의 같은 offset 바이트와 일치했다.

기록용 경계와 응답 필드 실험은 저장소 밖 임시 도구에만 두었다. 펌웨어·rekordbox 실행 파일은 분석하지 않았다. 개인 곡·경로·IP/MAC·캡처 파일은 저장소에 넣지 않았다.

## 확인하지 못한 것

- CDJ-3000 계열, MP3·WAV 밖의 음원 형식, 장시간 연속 스트리밍.
- 이 날 실기에서는 핫 큐/메모리 큐 편집을 보지 않았다. 레거시 큐 읽기와 편집 응답은 뒤에 따로 확인했다([LINK-EXPORT-LEGACY-CUES.md](LINK-EXPORT-LEGACY-CUES.md)).
- CLI에는 서버 시작 명령이 없어 실기는 임시 실행 도구로 했다.
