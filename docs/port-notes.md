# 원본과 다르게 옮긴 곳·옮긴 원본 버그

1:1을 지키지 못했거나 일부러 다르게 둔 곳과, 그대로 옮긴 원본 버그(PLAN §9 후보)를 단계별로 적는다.
각 항목의 자세한 이유는 해당 Swift 파일 주석(`// 원본과 다름`)에 있다.

## 공통

- 시간 지연은 Node 규칙대로 1ms 미만·2^31-1ms 초과면 1ms로 본다(`Duration.nodeTimerDelay`).
- 원본 이벤트 처리기·타이머 콜백 안에서 잡지 않은 예외는 Node 프로세스를 죽인다. Swift에서는 그 자리에서 잡고 넘어간다(가이드 §4).
- 원본은 가상 CDJ `Device` 객체 하나를 여러 서비스가 나눠 쥐고 번호가 바뀌면 같이 바뀐다. Swift는 값 형이라 `DeviceReference`(참조 형)로 옮겼다.
- 원본 `Map`의 넣은 순서 대신 Swift 사전을 쓰는 곳이 있다. 장치별로 보내는 순서(예: announcer·heartbeat가 장치마다 보내는 순서)가 id 순이 된다. 보내는 패킷 집합은 같다.
- `DeviceManager.devices`가 돌려주는 장치는 값 형이라, 원본처럼 받은 객체를 고쳐도 관리자 안의 값은 바뀌지 않는다.

## 1·2단계 (utils·devices·status·virtualcdj)

- `buildName`: 이름이 20바이트를 넘으면 원본처럼 `RangeError`("offset is out of bounds")에 해당하는 `BufferRangeError`를 던진다. 그래서 패킷을 만드는 함수(`makeAnnouncePacket`, `makeMediaSlotRequest`, 제어 패킷 등)가 `throws`다.
- 짧은 announce 패킷(0x30–0x34바이트)의 `type`: 원본은 `undefined`, Swift는 `DeviceType(rawValue: 0)`.
- 미디어 슬롯 생성일: 원본 `new Date(str)` 중 ECMAScript 형식(`YYYY-MM-DD` 등)만 옮겼다. CDJ가 보내는 값(픽스처)은 이 형식이다. V8의 옛 형식(`2020/10/10`)은 NaN 시각이 된다.
- 원본 버그 그대로: `ready`를 다시 부르면 앞에서 기다리던 쪽이 풀리지 않는다 / `getDeviceEnsured`가 장치가 먼저 와도 타이머를 지우지 않는다 / `makeStatusPacket`이 머리말을 0x0b에 쓴다 / stage 0x06 패킷이 55바이트다.

## 2단계 network

- `network.control`: Control은 DJLinkKit에 기대는 별도 타깃(`DJLinkControl`)이라 network가 connect 때 만들 수 없다. `DJLinkControl`이 `ProlinkNetwork`를 확장해, 연결된 뒤 처음 읽을 때 그 연결의 beat·status 소켓과 가상 장치 참조로 만든다. 같은 연결에서는 같은 Control, 다음 connect에서는 새 Control이다. 연결 전에는 원본처럼 nil.
- `db`·`localdb`·`remotedb`는 시험에서 가짜를 넣을 수 있게 서비스 프로토콜(`NetworkDatabase` 등) 형으로 돌려준다. 기본은 실제 클래스다.
- `NetworkConfig`는 전체·부분 설정을 같은 형으로 받는다. nil은 생략으로 처리하므로 JS의 명시적 `undefined` 덮어쓰기는 구별하지 않는다.
- `ConnectedProlinkNetwork`는 별칭이다(TS 형 좁히기는 없다).
- `disconnect()`가 돌려주는 닫기 함수: 원본은 `return this.close`로 바인딩되지 않은 함수라 부르면 TypeError가 난다. Swift 클로저는 인스턴스에 묶여 있어 부르면 정상으로 닫힌다(바인딩 안 된 메서드 참조를 표현할 수 없다).
- `disconnect()`의 remotedb 종료(`disconnectFromDevice`)는 Task로 돌아, 원본처럼 장치마다 remotedb→localdb가 번갈아 시작하지 않고 localdb를 모두 닫은 뒤 시작한다. 결과 상태는 같다.
- 원본 버그 그대로: `bringOnline`에서 bind가 실패하면 앞서 만든 소켓을 닫지 않는다(fd가 남는다).
- CLI 안전을 위한 추가(기본값은 원본 동작): 아래 인자를 주지 않으면 동작이 원본과 같다. `djlink`만 쓴다.
  - `UDPSocket.setBoundInterface(name:)`: 소켓을 인터페이스 하나에 묶는다(macOS `IP_BOUND_IF`). 부르지 않으면 묶지 않는다. 기본 구현은 던진다(지원하지 않는 소켓이 조용히 넘어가지 않게). `BSDUDPSocket`은 `if_nametoindex`와 `setsockopt`로 구현했고, 두 호출은 `bindSocketToInterface(fd:name:nameToIndex:setsockopt:)`로 바꿔 넣어 시험한다. `FakeUDPSocket`은 호출을 기록한다.
  - `NetworkConfig.allowsDeviceId`·`Announcer(allowsDeviceId:)`: 허용하지 않는 가상 CDJ 번호로는 announce하지 않는다. 처음 번호가 허용되지 않으면 `start()`가 던지고, 충돌 뒤 다시 고른 번호가 허용되지 않으면 그 번호로 보내기 전에 announcer를 멈추고 `onDeviceIdRejected`를 한 번 부른다(번호는 바꾸지 않는다).
  - `NetworkConfig.announceTargetFilter`·`Announcer(announceTargetFilter:)`: announcer가 패킷을 보낼 장치를 고른다. 없으면 발견한 모든 장치다.

## 3단계 (remotedb·NFS)

- CLI 안전을 위한 추가(기본값은 원본 동작): `TCPConnection.setRequiredInterface(name:)`를 호출하면 `LiveTCPConnection`이 `NWPathMonitor.availableInterfaces`에서 이름을 찾고 `NWParameters.requiredInterface`를 설정한다. 찾지 못하면 TCP 연결을 시작하지 않는다. `djlink` 소켓 공장은 포트 조회와 DB 연결 모두에 적용한다. 미호출 시 원본처럼 라우팅한다.

- NFS 경로 시험 입력의 `Users/chris/...`를 `Users/example/...`로 바꿨다(개인 이름 정리, 경로 해석 결과의 모양은 같다).

- 필드 형에 `RemoteDB` 접두사(`RemoteDBUInt32` 등)를 붙였다(표준 형과 이름이 겹친다).
- 조회 결과는 `RemoteDBQueryResult` enum으로 묶었다. 정수 `Track.year`에 담기지 않는 값은 `.trackWithRawYear`로 보존한다.

- CLI 안전을 위한 추가(기본값은 원본 동작): `configureNFSPathGuard(_:)`는 `fetchFile`·`fetchFileRange`·`getFileInfo`가 소켓을 만들기 전에 경로를 검사하는 훅이다(던지면 아무것도 보내지 않는다). `closeAllNFSClients()`는 캐시에 있는 모든 NFS 클라이언트의 RPC 소켓을 닫고 캐시를 비운다. 부르지 않으면 원본처럼 연결을 그대로 둔다.

## 4단계 (localdb)

- PDB·ANLZ는 kaitai `.ksy`(EPL) 대신 DJCrate의 MIT 리더를 고쳐 원본(kaitai 생성 코드)이 읽는 결과와 같게 만들었다. 트랙 문자열은 원본 entity-creators가 쓰는 11칸만 읽고(`dateAdded`=10, `analyzeDate`=15), 잘못된 짧은 문자열의 text는 건너뛴다(id·name 표에서는 빈 이름). 문자열 디코딩은 [kaitai-struct 0.11.0 런타임](https://github.com/kaitai-io/kaitai_struct_javascript_runtime/blob/v0.11.0/KaitaiStream.ts)의 `bytesToStr`와 같다.
- 메모리 ORM은 better-sqlite3 대신 SQLCipher C API로 같은 스키마·질의를 쓴다. undefined 바인딩은 [better-sqlite3-multiple-ciphers 12.11.1](https://github.com/m4heshd/better-sqlite3-multiple-ciphers/blob/v12.11.1/src/util/data.cpp)처럼 NULL이다(id 없는 PDB 재생 목록 항목은 SQLite가 번호를 매긴다, 무효한 날짜는 NULL → `new Date(null)`처럼 epoch).
- `LocalDBRow.int`: Int로 표현할 수 없는 NaN·무한대·범위 밖 실수는 nil(원본 JS number는 오류 없음).
- OneLibrary `dateAdded`를 읽지 못하면 원본은 Invalid Date, Swift는 nil.
- 원본 버그 후보: 긴 ASCII 문자열(0x40)을 +3부터 u16 length만큼 읽는다(DJCrate는 +4부터 length-4). 실제 형식은 실기로 확인해야 한다.
- 원본 버그 그대로: PDB 쪽 사슬이 자기 자신이나 지난 쪽을 가리키면 무한 루프에 빠진다(신뢰할 수 없는 입력에서 멈춤).
- 원본 버그 그대로: 버튼이 있으면 알 수 없는 cue type도 hot_cue로 돌려준다 / 장치 제거 때 첫 DB 항목만 닫고 같은 장치 항목을 모두 지운다 / OneLibrary 열기에 실패하면 임시 파일을 지우지 않는다.

## 5단계 (metadata-connect·artwork)

- metadata-connect의 공개 이름은 `enum MetadataConnect` 이름 공간 안에 있다(앨범아트 쪽과 이름이 겹친다).
- 통합 시험은 원본처럼 실제 음원이 있을 때만 돈다(`.enabled(if:)`, 원본은 본문에서 return). 원본 시험 입력에 있던 원작자의 개인 음악 폴더 경로·곡 이름은 공개 저장소라 견본 경로로 바꿨다(2026-10-10 사용자 결정). 파일이 없으면 건너뛰는 시험이라 동작은 같다.
- 원본 `PARSER_MAP`은 보통 객체라 `isExtensionSupported('constructor')`·`('__proto__')`가 true이고 이상한 값을 돌려준다. Swift는 이 prototype 조회를 옮기지 않았다(false).
- UTF-16 문자열의 짝 없는 서로게이트: Node는 그대로 두고 Swift `String`은 U+FFFD로 바꾼다(깨진 ID3 텍스트 프레임에서만 다르다).
- 원본 버그 그대로: APIC의 BOM 검사가 MIME 바이트를 읽는다 / v2.3 확장 헤더 크기에 크기 칸 4바이트가 빠져 태그 시작이 4바이트 어긋난다.
- 원본 버그 그대로: mp4 문자열 atom(`©nam` 등)이 `toString('ascii')` 때문에 맞지 않는다 / `Object.keys(...).length === 0` 검사 때문에 빈 값만 있어도 null이 아니다 / ID3 프레임 ID를 앞부분만 비교해 `TCOM`·`TCOP`이 장르로 읽힌다.

## 5단계 (db)

- `Track.rawYear`: RemoteDB가 정수가 아닌 연도를 주면(`.trackWithRawYear`) 원본 number 값을 여기에 보존한다.
- `Waveforms.waveformHd`는 ANLZ에 태그가 없을 때 원본처럼 비어 있을 수 있어 옵셔널이다. 높이가 없는 RemoteDB 미리보기는 `rawWaveformPreview`에 보존한다.
- `getPlaylist`의 `tracks`(`PlaylistTracks`, `AsyncSequence<Track>`)는 원본의 `null` 곡 항목을 담을 수 없어, 곡을 찾지 못하면 그 자리에서 오류를 던진다. 원본처럼 순회할 때마다 처음부터 다시 조회한다.
- 빈 메타데이터 진단 로그의 JSON은 `JSONSerialization`으로 문자열을 이스케이프한다. `JSON.stringify`와 제어 문자·U+2028/2029 이스케이프가 다를 수 있다(로그 문구에만 영향).

## 6단계 (mixstatus)

- `setMayStop`의 `await` 뒤 부분(JS 마이크로태스크)은 프로세서 안의 마이크로태스크 목록에 넣고, 가장 바깥 진입점(`handleState`, `triggerNextTrack`, 타이머 콜백)이 끝날 때 돌린다. 원본에서는 사용자가 한 처리 단위 안에서 `handleState`를 여러 번 부르면 그 뒤에 한꺼번에 돌지만, Swift는 각 호출 끝에 돈다(실제로는 패킷마다 따로 부르므로 같다).
- 원본 버그 그대로: 같은 trackId 중복을 막는 `return`이 `cancelSetEnding` 호출보다 앞에 있어, 같은 곡을 다시 틀면 30초 뒤 재생 중에 `setEnded`가 난다 / `isSetActive`가 false로 돌아가지 않아 두 번째 세트에서 `setStarted`가 나지 않는다 / `setMayStop`이 두 번 불리면 앞 취소 함수가 덮여 앞 타이머를 지울 수 없다.

## 7단계 (제어)

- `Control`에 시험용 `correlationByte` 인자를 더했다(기본값은 원본처럼 무작위).
- 원본 버그 그대로: 재생 상태 패킷이 칸 번호(0–3)를 `device.id`와 견줘 id 4 이상이면 비트가 서지 않는다.


## 8단계 (패시브)

- 장치 id가 없는 announce는 원본에서 `undefined`이며, Swift는 기반 `Device.id`의 비옵셔널 `Int`에 맞춰 0으로 둔다(`PassiveDevices.swift`).
- 원격 DB 조회는 Swift의 공용 `RemoteDBQueryResult?`를 반환한다(`PassiveRemoteDB.swift`, 3단계와 같은 결과 형).
- 로컬 DB의 `get`·`getWithMedia`·`getWithoutMedia`는 공용 `DatabaseAdapter`를 직접 반환하고, 설정·조회 결과도 `DatabasePreference`·`DatabaseType`·`PlaylistQueryResult`를 쓴다.
- preload의 미디어 캐시 조회·장치 확인·슬롯 락 생성은 Task 생성 전에 장치 순서·USB→SD 순서로 처리한다(`PassiveLocalDB.swift`의 `prepareGet` 계열).
- preload의 락 획득과 비동기 로더 실행은 Swift Task에서 시작하므로 Node의 `async-mutex` 동기 락 획득·Promise 마이크로태스크와 실행 순서까지 같지는 않다.
- 잘못된 버퍼 크기는 생성자가 `throws`가 아니므로 `start()`에서 `BufferRangeError`를 던진다(`PassivePcapAdapter.swift`).
- 요청에 따라 크기 0도 거부하지만, 원본 `Buffer.alloc(0)`은 빈 버퍼를 허용한다.
- 위치 파싱 예외는 공용 `EventHub`의 package 예외 전파 API를 통해 `emit('beat')`를 감싼 어댑터 catch로 올라가 error 이벤트가 되며, 뒤 beat 구독자는 호출하지 않는다.
- 상태·장치 방출기는 원본에도 파싱 try/catch가 있어 malformed 패킷을 무시한다.
- 캡처를 열 때 실패한 포인터는 Swift의 defer로 정리하고, selectable fd가 없으면 오류를 던진다.
- cap Open은 일부 실패 때 포인터를 남기며 selectable fd 오류는 libuv assert에 맡긴다.
- 실제 BPF 캡처는 시험 프로세스에서 금지하며, 이 수정의 시험은 가짜 백엔드만 사용한다.

그대로 옮긴 원본 버그와 동작:

- UDP 길이 이중 차감: cap 0.2.1 `lib/Decoders.js`의 UDP는 wire 길이에서 헤더 8바이트를 뺀 값을 반환하고, 원본 `src/passive/pcap-adapter.ts:213`이 다시 8을 뺀다.
- 따라서 payload의 끝 8바이트가 잘리고, payload가 8바이트 이하면 방출되지 않으며, 표준 54바이트 announce는 46바이트로 잘려 source IP와 장치 번호 휴리스틱을 쓰는 short format 경로로 읽힌다.
- `PassiveFlowTests.udpDoubleSubtraction`은 정상 wire 길이로 이 버그를 고정하며, 나중에 버그를 고칠 때 기대값을 바꿔야 한다.
- libpcap 필터의 netmask: cap 0.2.1 `src/binding.cc:308–355`는 `pcap_lookupnet`의 mask 대신 net을 `pcap_compile`의 마지막 인자로 넘긴다.
- lookupnet 실패 시 net·mask를 0으로 두고 원본과 같은 경고를 출력한다.
- 캡처 읽기 오류: 원본은 `pcap_next_ex`를 쓰지 않고 `pcap_dispatch(..., 1, ...)`를 반복한다(`src/binding.cc:159–212`).
- -1을 포함한 0 이하 반환값이면 현재 반복만 끝내고 캡처와 readable 감시는 유지하며, error 이벤트를 내거나 자동으로 닫지 않는다.
- Swift도 같은 dispatch 반복을 쓰며, 인터페이스가 사라져도 오류 없이 캡처 중 상태가 남을 수 있다(1:1 이후 개선 후보).
- truncated는 wire 길이와 caplen의 차이가 아니라 `caplen > buffer_length`일 때만 true다(`src/binding.cc:128–148`).
- Ethernet은 MAC 뒤의 단일 `81 00` VLAN 태그만 건너뛰며, type/length 값이 1536 미만이면 type은 없다(`lib/Decoders.js:1–59`).

cap 0.2.1의 동작은 npm tarball의 `lib/Decoders.js`·`src/binding.cc`를 읽어 맞췄다(코드는 옮기지 않았다). 출처와 MIT 고지는 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)에 있다.
