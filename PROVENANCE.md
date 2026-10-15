# 출처 기록 (PROVENANCE)

원본 alphatheta-connect(고정 커밋 `7496991`, v0.28.5)에는 CDJ-3000 펌웨어를 분석한 결과에 기댄 지식이 일부 들어 있다. 이 파일은 그런 지식이 원본 어디에 있고, 우리 Swift 쪽 어디로 옮겨 오는지 적는다. 새로 옮기는 에이전트는 아래 표의 "우리 쪽 옮길 곳"을 옮기기 전에 이 파일을 먼저 본다.

작성: 2026-10-10 (0단계). 계획은 [docs/PLAN.md](docs/PLAN.md) §10, 원본 고정 커밋은 [UPSTREAM.md](UPSTREAM.md)에 있다.

## 원칙

- 원본에 공개된 지식은 옮긴다.
- 펌웨어나 rekordbox 실행 파일을 우리가 직접 분석하지 않는다. `strings`, 디스어셈블, 디컴파일, 에뮬레이터에 올려 돌려 보는 일도 포함한다.
- 새로 알아내는 것은 실기 패킷 캡처를 비교해서만 한다.
- 새 원본 릴리스를 따라갈 때 펌웨어 분석 근거가 새로 생기면 이 파일에 더한다(PLAN §12).
- Deep Symmetry의 DJL Analysis 문서는 링크로만 가리키고 원문을 옮기지 않는다. 이 파일의 문장도 원본 코드 주석을 우리 말로 요약한 것이다.

## 결정 기록 (2026-10-10)

AlphaTheta EULA §2.2(리버스 엔지니어링 금지)는 분석한 쪽에 걸리는 조항이다. 그 결과를 옮겨 배포하는 위험이 작지만 0은 아니라는 것을 알고, 옮기기로 정했다.

## 확인한 방법

고정 커밋의 세 저장소에서 다음 낱말을 `rg -n -i`로 찾았다. 범위는 `src/`, `docs/`, `tests/`, `examples/`, `README.md`, `CHANGELOG.md`이고, 걸린 곳은 전부 파일을 열어 앞뒤 문맥을 읽었다.

`firmware`, `FW 3.xx`, `sub_<16진수>`, `disassembl`, `reverse[- ]engineer`, `ghidra`, `IDA`, `decompil`, `EP122`, `emulat`, `stock firmware`, `recovered from`, `ground-truth`, `stripped`, `struct +`, `usecase`

- onelibrary-connect(`ac3edd3`)와 metadata-connect(`c2ae262`)에서는 걸린 곳이 없었다.
- alphatheta-connect의 `git log --grep`(firmware, disassembl, ghidra, decompil, reverse)로도 관련 커밋을 찾았다. `9331cac`(상태 필드, 2026-08-30), `bf74c58`(player 번호 문서, 2026-08-30), `f242bc5`(USB 문서, 2026-09-25)가 해당한다.

판정은 세 가지다.

- **분석 근거 있음**: 함수 이름·주소·구조체 오프셋처럼 펌웨어 내부를 본 흔적이 원문에 있다.
- **분석 근거 불명**: 펌웨어가 언급되지만 어떻게 알아냈는지 적혀 있지 않다.
- **분석 아님**: 실기 관찰, 패킷 캡처, 제3자 공개 문서, 단순한 버전 표기다.

## A. PLAN §10에서 확인된 곳 3개 (모두 "분석 근거 있음")

PLAN에 적힌 줄 번호는 실제와 조금 달랐다. 아래는 고정 커밋에서 다시 센 줄이다.

| 원본 파일:줄 | 근거 | 내용 요약 | 우리 쪽 옮길 곳 | 비고 |
|---|---|---|---|---|
| `src/status/types.ts:5-17` (PLAN은 5-8) | CDJ-3000 EP122 FW3.20, `sub_d7d3c8`(0xd7d3c8), BeatSyncMaster 상태 구조체 | 상태 플래그 바이트(패킷 0x89)를 데크가 구조체의 불리언 하나씩을 비트 하나씩에 담아 만든다. 쓰이지 않는 비트 0, 이름이 남지 않은 동기화 비트 2, 초기에 켜져 있다가 내려가면 상태 변경 알림을 내는 비트 7(평소 0)을 설명한다 | `Sources/DJLinkKit/Status/StatusTypes.swift` (`StatusFlag` 주석) | **분석 근거 있음.** 코드가 쓰는 값은 비트 마스크뿐이고 근거는 주석에만 있다. 주석은 우리 말로 요약해 옮긴다. 함수 이름·주소를 남길지는 옮길 때 정한다 |
| `src/status/types.ts:20-25` | 같은 펌웨어, BeatSyncMaster 구조체 +4 | `BpmSync` 비트(1<<1)의 뜻: 마스터 템포는 따라가지만 피치 벤드·저그 이후 박 맞춤이 풀린 상태. 펌웨어가 이 비트를 구조체 +4에서 가져온다 | `Sources/DJLinkKit/Status/StatusTypes.swift` | **분석 근거 있음.** PLAN에 없던 곳이다. 동작에 쓰는 비트 값은 `status/utils.ts:39`의 `isBpmSync` |
| `src/status/types.ts:146-149`, `src/status/utils.ts:51-55` | CDJ-3000 FW3.20, `sub_d858b8`의 16비트 저장 | `deviceType`(패킷 0xcc)은 능력 비트필드다. 구형 0x05, 넥서스 0x0f, CDJ-3000·XDJ-XZ 0x1f(넥서스 값에 비트 4). 펌웨어는 0x1f를 고정으로 쓰고, 프로토콜 버전 3 미만을 알리는 상대에게는 0으로 보낸다 | `Sources/DJLinkKit/Status/StatusTypes.swift`, `StatusUtils.swift` (`0xcc`를 읽되 패킷이 짧으면 0) | **분석 근거 있음.** PLAN에 없던 곳이다. 코드 쪽 방어(길이 검사)가 시험 대상일 수 있으니 `tests/status/utils.spec.ts`와 함께 옮긴다 |
| `src/status/types.ts:155-160` | CDJ-3000 펌웨어, "상태 본문 +0xa4에 저장하는 코드가 없음"을 확인 | `packetNum`(패킷 0xc8)은 CDJ-3000에서 항상 0이다. 살아 있는 패킷 카운터는 UDP 50004의 고해상도 스트림 패킷(오프셋 0x28, 빅엔디언 u32)으로 옮겨 갔다. 그래서 이 값으로 끊김을 판단하면 안 된다 | `Sources/DJLinkKit/Status/StatusTypes.swift` (`packetNum` 주석), 읽는 코드는 `StatusUtils.swift` | **분석 근거 있음.** PLAN에 없던 곳이다. 50004 스트림은 원본 코드에 없으므로 옮길 것이 없다 |
| `src/status/utils.ts:43-48` | CDJ-3000 FW3.20, `sub_d7d610` | 상태 패킷에 피치 값이 네 개 있다. 0x8c의 Pitch1과 0xc0의 Pitch3은 실제 적용 피치(BPM 표시 기준, 페이더 또는 동기 마스터에서 온 값), 0x98의 Pitch2와 0xc4의 Pitch4는 로컬 페이더 위치다. `effectivePitch`는 Pitch1, `sliderPitch`는 Pitch2에서 읽는다 | `Sources/DJLinkKit/Status/StatusUtils.swift` (`statusFromPacket`) | **분석 근거 있음.** 읽는 오프셋은 0x8d, 0x99부터 3바이트다. 이름이 바뀐 이유(예전에는 둘이 뒤바뀌어 있었다)는 `CHANGELOG.md:87`. 시험 `tests/status/utils.spec.ts` 기대값은 그대로 옮긴다 |
| `docs/FULL_STARTUP.md:237-273` (PLAN은 241-279) | CDJ-3000 DJ 애플리케이션 EP122 FW3.20에서 복원했다고 적힘. `network::SystemManager`, `sub_1020dd0`, 설정 키 `PlayerNo`·`LastPlayerNo`, 플래시의 설정 파일 | 실제 CDJ-3000이 번호를 정하는 순서. 상태 기계는 Initialize → Discovery → SettingId → TimeServer → Connecting이고 번호 요청·방어는 모두 SettingId에서 일어난다. 번호는 전면 PLAYER No. 설정이 고정이면 그 값, Auto면 마지막에 쓴 번호다. 요청 패킷(wire 0x02)을 300ms 간격으로 3번 보내고, 상대가 "사용 중"(wire 0x03)으로 답하면 스스로 정한 번호는 1→6으로 올리며 최대 6번 다시 시도한다. 이미 4 이하이거나 모델명이 CDJ-3000이면 양보하지 않는다. 믹서가 채널별로 번호를 내려 줄 수도 있다 | 옮기지 않음(문서만). 이 내용을 쓰는 코드는 `VirtualCDJ/Announcer.swift`, `DeviceId.swift`지만 원본 코드는 이 알고리즘을 따라 하지 않는다고 문서가 밝힌다 | **분석 근거 있음.** 문서일 뿐 코드가 아니다. 우리 `docs/`에 옮길 때는 요약만 쓰고 같은 근거를 이 파일에 이어서 적는다 |

## B. "firmware" 낱말 검색으로 걸린 후보 6개 파일 (PLAN §10)

| 원본 파일:줄 | 근거 | 내용 요약 | 우리 쪽 옮길 곳 | 비고 |
|---|---|---|---|---|
| `src/constants.ts:51-54` | 없음. 상수 `VIRTUAL_CDJ_FIRMWARE = '3.20'`만 있다 | 가상 CDJ가 상태 패킷에 담아 알리는 펌웨어 버전 문자열. `CHANGELOG.md:486`에 "1.43에서 3.20으로 올림"이라고만 적혀 있다 | `Sources/DJLinkKit/Constants.swift` | **분석 아님.** 값의 출처(실제 CDJ-3000이 보고하는 값을 따랐는지)는 원본에 없다. 값은 그대로 옮긴다. 쓰는 곳은 `virtualcdj/index.ts:89`(오프셋 0x7c 4바이트) |
| `src/virtualcdj/index.ts:50-55`, `:83-89` | 없음. 장치 쪽 반응을 관찰한 설명이다 | 상태 패킷의 0x68·0x75 바이트가 1이어야 일부 mp3 메타데이터가 오고(dysentery 이슈 15번 링크), 0xb6 바이트가 1이어야 CDJ가 우리를 "구형 펌웨어"로 여기지 않는다. 오프셋 0x7c에 펌웨어 문자열을 넣는다 | `Sources/DJLinkKit/VirtualCDJ/Announcer.swift` (`makeStatusPacket`) | **분석 근거 불명.** 0x68·0x75는 제3자 공개 이슈가 출처다. 0xb6 쪽은 출처가 적혀 있지 않다. `makeStatusPacket`은 정의만 있고 쓰이지 않는다(PLAN §9). 바이트열은 원본 그대로 옮긴다 |
| `src/virtualcdj/stagehand.ts:20-32` | "에뮬레이트한 CDJ-3000 펌웨어 3.20에서 관찰"이라고만 적힘 | Stagehand 프로토콜 MAC은 AlphaTheta OUI(c8:3d:fc)에 인터페이스 MAC 하위 3바이트를 붙인 값이고, 호스트가 살아 있는 동안 바뀌면 안 된다. CDJ-3000이 IP별로 첫 요청의 신원을 기억해서, 같은 IP에서 다른 MAC·번호로 다시 요청하면 무시하기 때문이다 | `Sources/DJLinkKit/VirtualCDJ/StagehandAnnouncer.swift` (`getStagehandMac`) | **분석 근거 불명.** 동작 설명이라 옮긴다. 다만 "에뮬레이트한 펌웨어"가 펌웨어를 에뮬레이터에서 돌린 관찰이라면 우리 원칙과 같은 일을 한 것이다. 우리는 에뮬레이션을 하지 않고, 실기 캡처로만 확인한다 |
| `docs/STAGEHAND.md:191-192`, `:222`, 6.1~6.3절 | 공식 Stagehand iPad 앱과 CDJ-3000(player 4, 펌웨어 3.18)을 L2 MAC 인계로 잡은 패킷 캡처 | 실기에서 CDJ가 0x07 이송 명령을 조용히 무시한다는 관찰, 앱이 보내는 0x68·0x3c·0x55·0x6b 패킷 모양, CDJ가 보내는 0x69 토큰과 0x0b 스트림, 1116바이트 공지(118바이트 근처에 펌웨어 문자열). 바이트열을 따라 해도 CDJ가 받아 주지 않는 이유는 풀지 못했다 | 문서는 옮기지 않음. 코드는 `VirtualCDJ/StagehandAnnouncer.swift`, `VirtualCDJ/StagehandHeartbeat.swift`, `Sources/DJLinkControl/ControlStagehand.swift` | **분석 아님(패킷 캡처).** 우리 원칙이 허용하는 방법이다. 이 6.1이 PLAN §9의 마지막 항목(CDJ가 Stagehand 제어 0x07을 무시)이다 |
| `docs/USB_EXPORT.md:8-10`, `:80-82`, `:458-476`, `:954-956`, `:991` | "합성 주변장치에 올린 stock firmware", "firmware test instance", "펌웨어 3.20의 계산을 재현" | USB 내보내기 문서. 관찰한 상대를 실제 CDJ-3000과 합성 주변장치로 돌린 펌웨어로 나누고, 분석 파일 폴더(`USBANLZ/P###/########`)를 오디오 경로에서 정하는 해시 계산을 적었다(UTF-16 단위 누적 후 7비트를 골라 모으는 방식, 61곡으로 맞춰 봄) | 옮기지 않음. 이 해시는 USB 쓰기 쪽 규칙이고 이 문서가 스스로 리더의 분석 경로를 대신하지 않는다고 밝힌다(`:28`). 쓰기는 PLAN §1 범위 밖이다 | **분석 근거 불명, 가능성 높음.** 펌웨어를 합성 주변장치로 구동했다는 서술은 에뮬레이션을 뜻할 수 있다. 어떻게 계산을 재현했는지 적혀 있지 않다. 우리는 코드도 문서도 옮기지 않으므로 옮겨 오는 위험은 없다. 나중에 USB 쓰기를 맡으면 이 줄을 다시 본다 |
| `docs/REMOTE.md:64` | 없음 | `src/remote/`(범위 밖) 시험 기록의 한 줄: 2026-09-19, 펌웨어 3.20의 플레이어에서 트랙 로드를 확인했다 | 옮기지 않음 (`src/remote/` 범위 밖) | **분석 아님.** 시험한 장치의 버전 표기다. 문서 전체가 범위 밖이다 |

## C. 검색에서 추가로 걸려 열어 본 곳

| 원본 파일:줄 | 근거 | 내용 요약 | 우리 쪽 옮길 곳 | 비고 |
|---|---|---|---|---|
| `src/status/index.ts:62-68`, `:97-99`, `src/status/utils.ts:233`, `:285`, `src/status/stagehand-gating.test.ts:11` | "DJM-A9에서 리버스 엔지니어링"이라고만 적힘 | Stagehand 믹서 상태(0x39, 266바이트)와 VU(0x58) 패킷의 배치는 DJM-A9만으로 알아낸 것이라, Stagehand 모드에서만 읽어야 한다. 다른 믹서(XDJ-AZ 등)에는 맞지 않는다 | `Sources/DJLinkKit/Status/StatusEmitter.swift`, `StatusUtils.swift` (`mixerStateFromPacket`, `vuFromPacket`), 시험 `StatusStagehandGatingTests.swift` | **분석 근거 불명.** 방법이 적혀 있지 않다. 대상이 펌웨어가 아니라 DJM-A9가 보내는 패킷이라 패킷 분석일 가능성이 높지만 확인하지 못했다 |
| `src/virtualcdj/device-id.ts:9-15`, `:206-222` | CDJ-3000 실기 시험(2026-08-30, 플레이어 2대와 DJM-V5) | remotedb 질의 안의 장치 번호 바이트는 1~6이어야 답을 받고 7 이상은 조용히 무시된다. 공지하는 번호와는 별개다. 구형 플레이어는 더 엄격하다는 내용은 제3자 문서(dysentery)를 가리킨다 | `Sources/DJLinkKit/VirtualCDJ/DeviceId.swift` | **분석 아님(실기 관찰).** 믹서별 채널 수 표(`MIXER_PLAYER_CEILING`)의 출처는 적혀 있지 않다 |
| `CHANGELOG.md:90` | 위 A의 상태 필드 변경(`9331cac`)을 가리킴 | 상태 플래그, 피치 네 값, 패킷 카운터를 "CDJ-3000 펌웨어에서" 문서화했다는 변경 기록 | 옮기지 않음 | A의 `types.ts`·`utils.ts` 행과 같은 근거다 |
| `README.md:188-190`, `package.json`의 keywords, `src/localdb/kaitai/*.ksy` 머리말 | 제3자 공개 분석 | Pro DJ Link 프로토콜(dysentery·beat-link), rekordbox DB 형식(henrybetts·flesniak, Deep Symmetry crate-digger)을 리버스 엔지니어링한 제3자의 작업에 감사 표시를 한 것 | `THIRD_PARTY_NOTICES.md`에 감사 대상으로 밝혀 둠 | **분석 아님.** 공개된 제3자 문서이며 펌웨어 분석이 아니다. `.ksy`는 옮기지 않는다 |

## D. 우리 실기 확인으로 알아낸 것

원본에 없고, 우리가 시험용 장비에서 패킷을 보내고 장치가 돌려준 상태 패킷을 비교해 알아낸 것이다. 기록은 [docs/PLAN.md](docs/PLAN.md) §8 "실기 확인 기록"에 있다.

| 날짜·장비 | 알아낸 것 | 방법 | 우리 쪽 쓴 곳 | 비고 |
|---|---|---|---|---|
| 2026-10-14, CDJ-2000nexus 1대(1번), 뒤에 2대 | 재생 상태 패킷(0x02, 50001)의 마지막 네 칸은 플레이어 1~4의 것이고 0 = 시작, 1 = 정지(cue), 2 = 그대로다. CDJ는 자기 칸만 읽는다 | 네 칸만 바꾼 패킷을 하나씩 보내고(`01 02 02 02`, `02 02 02 02`, `00 02 02 02`) CDJ 상태 패킷의 재생 상태를 읽었다. 두 대일 때 한 덱에 보낸 패킷이 다른 덱을 움직이지 않는 것을 봤다 | `Sources/DJLinkControl/Control.swift`(`makePlaystatePacket`), 시험 `ControlUpstreamFixTests.swift` | **분석 아님(실기 관찰).** 제3자 공개 프로토콜 설명(dysentery)과도 맞는다. 문서 원문은 옮기지 않았다 |
| 2026-10-14, DJM-900NXS2(33번) | 4채널 on-air 패킷은 종류 0x03, 45바이트, `0x20` = 0x02, 길이 칸 0x0009이고 비트 포트(50001)로 브로드캐스트된다 | 50000~50002를 듣기만 하는 UDP 소켓으로 받은 패킷을 비교했다. 받은 패킷 하나를 시험 픽스처로 쓴다(믹서 이름과 채널 표시뿐이다) | `Sources/DJLinkKit/Status/StatusUtils.swift`(`onAirFromPacket`), `StatusEmitter.swift`, `Sources/DJLinkPassive/PassiveStatus.swift`, 시험 `StatusUpstreamFixTests.swift`·`PassiveStatusUpstreamFixTests.swift` | **분석 아님(패킷 캡처).** 6채널 변형은 장비가 없어 원본 그대로다 |
| 2026-10-14, CDJ-2000nexus 2대, DJM-900NXS2 | keep-alive(0x06)는 54바이트, 길이 칸 0x0036, `0x30` = 장치 수, `0x31`–`0x33` = 0, `0x34` = 장치 종류로 보이는 값(CDJ 0x01, DJM 0x03) | 위와 같은 듣기 전용 소켓으로 받은 세 장비의 0x06을 비교했다 | `Sources/DJLinkKit/VirtualCDJ/Announcer.swift`(`makeStage06Packet`), 시험 `VirtualCDJKeepAliveUpstreamFixTests.swift` | **분석 아님(패킷 캡처).** 마지막 바이트(`0x35`)는 CDJ 0x00, DJM 0x31이었고 원본 값(번호 5 이상이면 0x64)을 그대로 둔다 |
| 2026-10-14, CDJ-2000nexus 2대(1·2번), DJM-900NXS2 | 비트 포트(50001)의 0x28은 96바이트, `0x20` = 0x00, `0x22`의 u16 BE = 0x003c. `0x21` = 장치 번호, `0x54`의 u32 BE = 피치 비율(0x100000이 1배), `0x5a`의 u16 BE / 100 = 곡 BPM, `0x5c` = 마디 안 비트(1~4) | UDP 수신 소켓으로 덱마다 33개씩 받았다. 상태 패킷과 비교해 1번은 BPM 166·피치 약 -2.45%, 2번은 BPM 168·약 -0.15%가 맞고 비트가 1→2→3→4로 순환하는 것을 확인했다. 두 덱 모두 cue로 돌아간 뒤 0x28이 멈췄다 | `Status/BeatTypes.swift`, `BeatUtils.swift`, `BeatEmitter.swift`, `Sources/DJLinkPassive/PassiveBeat.swift`, 시험 `BeatTests.swift`·`PassiveBeatTests.swift`·`CLIBeatTests.swift` | **분석 아님(패킷 캡처).** 지원은 관찰한 96바이트 변형에 한정한다. `effectiveBPM`은 곡 BPM × 피치 비율의 계산값이다. 앞부분 시간 필드의 의미, 양수 피치·sync·역재생·다른 기종은 실기 미확인이다 |

### 0x28 비트 패킷에서 확인한 범위

- 피치 원시값은 1번 `0x000f9ba5`, 2번 `0x000ff9db`였다. `(raw / 0x100000 - 1) × 100`은 각각 -2.4500846863%, -0.1500129700%이고 상태 패킷의 두 자리 표시와 일치한다.
- 곡 BPM 원시값은 `0x40d8`(16600), `0x41a0`(16800)이었다. 피치를 적용한 계산 BPM은 각각 약 161.93·167.75다. 패킷에서 별도의 실제 BPM 필드를 찾았다는 뜻은 아니다.
- 수신 간격 중앙값은 약 369.53ms·357.49ms였다. `0x24`의 u32 값은 약 361~362·357~358이어서 이 값을 그대로 실제 다음 비트까지 남은 밀리초로 해석하지 않는다. `0x24`~`0x53`의 시간값·예약 영역과 `0x5f`의 중복 장치 번호처럼 보이는 값은 API에 넣지 않았다.
- 공개 시험에는 기종 이름과 비트·템포 값뿐인 실제 패킷 두 개를 쓴다. 출발지 IP·MAC·곡 이름·경로·토큰은 포함하지 않는다. 원시 수신 기록과 기존 CLI 제어 로그는 저장소 밖에 둔다.

## 요약

판정 결과를 건수로 정리한 것이다. "곳"은 위 표의 행을 센 것이다.

- **분석 근거 있음 — 6곳**(A의 6행). 코드 주석 5곳(`types.ts` 4곳, `utils.ts` 1곳)과 문서 1곳(`FULL_STARTUP.md`)이다. 모두 CDJ-3000 EP122 FW3.20에서 가져온 것으로 적혀 있다. 단 `types.ts:155-160`은 펌웨어 버전 표기 없이 "펌웨어가 그 칸에 쓰지 않는다"는 확인만 적었다. 코드 동작에 영향을 주는 것은 상태 패킷 해석(플래그 비트, 피치 오프셋, `deviceType`, `packetNum`)이다. PLAN이 적은 3곳은 모두 맞았고, `types.ts`에서 세 곳이 더 나왔다.
- **분석 근거 불명 — 4곳**: `virtualcdj/index.ts`의 0xb6 바이트, `virtualcdj/stagehand.ts`의 MAC 고정 이유("에뮬레이트한 펌웨어"), `USB_EXPORT.md`의 해시 계산과 "펌웨어 테스트 인스턴스", DJM-A9 0x39 파서(C의 첫 행).
- **분석 아님 — 6곳**: `constants.ts`의 버전 문자열, `STAGEHAND.md`(패킷 캡처), `REMOTE.md`, `device-id.ts`(실기 관찰), `CHANGELOG.md:90`(A와 같은 근거를 가리킬 뿐), 제3자 감사 표시.
- PLAN §10의 후보 6개 파일은 모두 열어 판정했다(B). 새로 찾은 곳은 위에 쓴 `types.ts` 세 군데, `status/index.ts`·`utils.ts`의 DJM-A9 서술, `device-id.ts`, `CHANGELOG.md`, 제3자 감사 표시다(C).
- **옮길 때 지킬 점**: A의 코드 주석 5곳은 근거를 우리 말로 요약해 해당 Swift 파일의 주석에 둔다. `FULL_STARTUP.md`와 `USB_EXPORT.md`의 해당 부분은 옮기지 않는다. 불명인 곳은 원본의 바이트열과 동작만 그대로 옮기고 추측을 더하지 않는다.

## 확인하지 못한 것

- 각 지식을 원본 저작자가 어떻게 얻었는지는 원본에 적힌 만큼만 안다. 위 판정은 원문 서술에 기댄 것이고, 저작자에게 확인하지 않았다.
- `CHANGELOG.md` 전체와 `git log` 메시지는 위 낱말로만 훑었다. 낱말이 다른 서술은 놓쳤을 수 있다.
- prolink-connect 저장소 자체는 열지 않았다.

## Link Export: rbxport 1.8.0 (2026-10-15)

고정 커밋 `90bfb53da59c5b2c3f0b76101601f30a6b74ab2b`의 GPL 공개 Rust 코드와 시험을 옮긴다. 직접 실행 파일 분석은 하지 않았다. 아래의 근거는 원본 저작자가 코드에 밝힌 출처이며, 우리가 새로 실측한 결과가 아니다. 원본의 관찰·추정·미확인 구분을 바꾸지 않는다.

| 원본 코드 | 공개된 근거와 제한 | Swift 대응 |
|---|---|---|
| `rbl-link/src/join.rs`, `interface_mode.rs`, `beacon.rs`; `rbl-prolink/src/lib.rs` | 원본이 공개한 rekordbox 7.2.11 시스템 관리자 분석·캡처 기반 참여 순서, 유선/무선 후보 번호·점유 응답, 호환성 거절·장치 멤버십·identity/settings·master/load 응답. 무선 선택 타이밍 등 미확인 내용은 추측해 보완하지 않는다 | `DJLinkExport/Join`, `InterfaceMode`, `Beacon`; `DJLinkExportProtocol/Prolink` |
| `rbl-nfs/src/lib.rs`, `vfs.rs`; `rbl-link/src/files.rs` | 원본이 공개한 libFilSiNE 분석과 CDJ-3000·XDJ 패킷 비교: 파일 핸들·read 상한·상대 경로·symlink/stat 의미. Windows drive mount 규칙은 원본에서도 추정이다 | `DJLinkExportNFS/Server`, `Vfs`; `DJLinkExport/Files` |
| `rbl-dbserver`의 session/item/filter, `rbl-link/src/catalog.rs`, `blobs.rs` | 메뉴·정렬·My Tag·cue·VBR·분석 응답의 공개 원본 및 캡처. VBR의 1604 zero-byte 호환 값은 원본의 임시값으로 유지한다 | `DJLinkExportDBServer/*`, `DJLinkExport/Catalog`, `Blobs` |
| `rbl-anlz/*`, `rbl-index`의 정렬·스마트 목록·관련곡 | 공개 ANLZ 관찰·인코딩과 원본의 comparator/RelatedTrackCriteria 분석 지식. 미확인 padding·빈 필드는 원본 값대로 보존한다 | `DJLinkExportANLZ/*`, `DJLinkExportModel/*` |
| `rbl-core/src/xml.rs`, `rbl-db/src/details.rs`, `export_info.rs`, `fixture.rs`, `rbl-fakecdj/src/lib.rs` | 서버 입력 값형·스마트 목록 XML 스캐너·합성 시험 준비·클라이언트 요청 절차. 실제 사용자 DB·경로·곡 정보를 새 fixture로 넣지 않는다 | `DJLinkExportModel/Xml`, `Details`, `ExportInfo`; Export 통합 시험 준비 코드 |
| `alphatheta-connect-rs/src/status/utils.rs` @ `b54d9e9c53059f11e04f4de9898f4abae3b46480` | MIT 공개 클라이언트 상태 파서의 패킷 길이 및 반올림 규칙 | `DJLinkExport/Beacon`의 기존 Swift 클라이언트 파서 어댑터 |

Deep Symmetry 문서·`.ksy` 원문은 복사하지 않는다. 원본 캡처는 외부 고정 체크아웃에서 읽어 시험하고 공개 저장소에 복사하지 않는다. 이번 서버 실기 결과는 아직 없다.

### Link Export 실기 추가 관측 (2026-10-15)

CDJ-2000nexus와 합성 신호 WAV의 애플리케이션 TCP/UDP 송수신을 비교했다. `0x2102`/`0x3000` 곡 정보 첫 항목의 `arguments[1]`만 1에서 11로 바꾸자 E-8305가 사라지고 RIFF/PCM 읽기·재생·시작 위치 CUE 복귀가 됐다. 이 값을 `TrackDetails.file_type`에서 전달하는 수정과 별도 회귀 2개를 추가했다. `0x2f` 항목의 비교는 실패했으므로 그 항목의 의미는 새로 단정하지 않는다. 시스템 pcap·펌웨어·rekordbox 실행 파일 분석은 하지 않았다. 원본과 같은 기준선 `03d3371`은 별도 브랜치에 남긴다. 상세 증거·범위·한계는 [실기 기록](docs/LINK-EXPORT-HARDWARE.md)에 있다.
