# 원본과 다르게 옮긴 곳·옮긴 원본 버그

1:1을 지키지 못했거나 일부러 다르게 둔 곳과, 그대로 옮긴 원본 버그를 단계별로 적는다. 자세한 이유는 해당 Swift 파일의 `// 원본과 다름` 주석에 있다.

- "원본 버그 그대로"는 1:1 기준선(`port/one-to-one`)의 동작이다. main에서 고친 것은 "main에서 고침"으로 표시했고, 고친 내용은 [PLAN.md](PLAN.md) §9에 있다.
- "CLI opt-in"은 `djlink`의 안전 규칙([cli.md](cli.md#안전-규칙))을 위해 라이브러리에 더한 선택 인자다. 주지 않으면 원본과 같다.

## 공통

- 시간 지연은 Node 규칙대로 1ms 미만·2^31-1ms 초과면 1ms로 본다(`Duration.nodeTimerDelay`).
- 원본 이벤트 처리기·타이머 콜백에서 잡지 않은 예외는 Node 프로세스를 죽인다. Swift는 그 자리에서 잡고 넘어간다(가이드 §4).
- 원본은 가상 CDJ `Device` 객체 하나를 여러 서비스가 나눠 쥐고 번호가 바뀌면 같이 바뀐다. Swift는 값 형이라 `DeviceReference`(참조 형)로 옮겼다.
- 원본 `Map`의 넣은 순서 대신 Swift 사전을 쓰는 곳이 있다. 장치마다 보내는 순서(announcer·heartbeat 등)가 id 순이 된다. 보내는 패킷 집합은 같다.
- `DeviceManager.devices`가 돌려주는 장치는 값 형이라, 받은 값을 고쳐도 관리자 안의 값은 바뀌지 않는다.
- `djlink`의 중단 상태는 액터 밖의 잠금으로 보호하고, 신호 큐와 독립 제한 시간 감시가 세운다. 두 번째 신호는 `_exit(130)`, 중단 뒤 3초 안에 정리가 끝나지 않으면 강제 종료한다. 파일 쓰기·fsync·게시는 별도 큐에서 하고 쓰는 도중과 게시 직전에 중단을 확인한다. OneLibrary 임시 DB는 CLI가 주입한 `LocalDBFileSystem` 래퍼로 추적해 종료 때 지운다.

## 1·2단계 (utils·devices·status·virtualcdj)

- `buildName`: 이름이 20바이트를 넘으면 원본 `RangeError`("offset is out of bounds")에 해당하는 `BufferRangeError`를 던진다. 그래서 패킷을 만드는 함수(`makeAnnouncePacket`, `makeMediaSlotRequest`, 제어 패킷 등)가 `throws`다.
- 짧은 announce 패킷(0x30–0x34바이트)의 `type`: 원본은 `undefined`, Swift는 `DeviceType(rawValue: 0)`.
- 미디어 슬롯 생성일: 원본 `new Date(str)` 중 ECMAScript 형식(`YYYY-MM-DD` 등)만 옮겼다. CDJ가 보내는 값은 이 형식이다. V8의 옛 형식(`2020/10/10`)은 NaN 시각이 된다.
- 원본 버그 그대로: `ready`를 다시 부르면 앞에서 기다리던 쪽이 풀리지 않는다 / `getDeviceEnsured`가 장치가 먼저 와도 타이머를 지우지 않는다 / `makeStatusPacket`이 머리말을 0x0b에 쓴다 / stage 0x06 패킷이 55바이트다. 모두 main에서 고침. `getDeviceEnsured`는 패시브도 고쳤다(#23).

## 2단계 network

- `network.control`: Control은 DJLinkKit에 기대는 별도 타깃(`DJLinkControl`)이라 network가 connect 때 만들 수 없다. `DJLinkControl`이 `ProlinkNetwork`를 확장해, 연결 뒤 처음 읽을 때 그 연결의 beat·status 소켓과 가상 장치 참조로 만든다. 같은 연결에서는 같은 Control, 다음 connect에서는 새 Control이다. 연결 전에는 원본처럼 nil.
- `db`·`localdb`·`remotedb`는 시험에서 가짜를 넣을 수 있게 서비스 프로토콜(`NetworkDatabase` 등) 형으로 돌려준다. 기본은 실제 클래스다.
- `NetworkConfig`는 전체·부분 설정을 같은 형으로 받는다. nil은 생략으로 보므로 JS의 명시적 `undefined` 덮어쓰기는 구별하지 않는다.
- `ConnectedProlinkNetwork`는 별칭이다(TS 형 좁히기는 없다).
- `disconnect()`가 돌려주는 닫기 함수: 원본은 `return this.close`라 바인딩되지 않아 부르면 TypeError가 난다. Swift 클로저는 인스턴스에 묶여 있어 정상으로 닫힌다.
- `disconnect()`의 remotedb 종료(`disconnectFromDevice`)는 Task로 돌아, 장치마다 remotedb→localdb가 번갈아 시작하지 않고 localdb를 모두 닫은 뒤 시작한다. 결과 상태는 같다.
- 원본 버그 그대로: `bringOnline`에서 bind가 실패하면 앞서 만든 소켓을 닫지 않는다(fd가 남는다). main에서 고침.
- CLI opt-in:
  - `UDPSocket.setBoundInterface(name:)`: 소켓을 인터페이스 하나에 묶는다(macOS `IP_BOUND_IF`). 기본 구현은 던진다(지원하지 않는 소켓이 조용히 넘어가지 않게). `BSDUDPSocket`은 `if_nametoindex`와 `setsockopt`로 구현했고, 시험은 `bindSocketToInterface(fd:name:nameToIndex:setsockopt:)`에 두 호출을 바꿔 넣는다.
  - `NetworkConfig.allowsDeviceId`·`Announcer(allowsDeviceId:)`: 허용하지 않는 가상 CDJ 번호로는 announce하지 않는다. 처음 번호가 허용되지 않으면 `start()`가 던진다. 충돌 뒤 다시 고른 번호가 허용되지 않으면 보내기 전에 announcer를 멈추고 `onDeviceIdRejected`를 한 번 부른다(번호는 바꾸지 않는다). 거부는 `rejectedDeviceId`에 남고 모든 ready 대기자가 풀리며 이후 ready도 바로 끝난다. 네트워크는 `startupRejectedDeviceId`·`waitUntilReady()`(거부를 던진다)로 알린다. 정책이 없으면 원본의 ready 재호출 동작 그대로다.
  - `NetworkConfig.announceTargetFilter`·`Announcer(announceTargetFilter:)`: announcer가 패킷을 보낼 장치를 고른다. 없으면 발견한 모든 장치다.
  - Stagehand 연결에 `allowsDeviceId`·`announceTargetFilter`·`onDeviceIdRejected`가 있으면 시작 전에 거부한다. Stagehand 브로드캐스트와 heartbeat에 정책을 온전히 적용할 수 없기 때문이다.
  - CLI 소켓 경계는 고른 서브넷 안의 IPv4 목적지(서브넷 브로드캐스트 포함)만 허용한다. 범위 미확정·호스트 이름·범위 밖 주소는 UDP 송신과 TCP 연결 전에 거부한다. NFS 경로 훅도 장치 IP를 검사하므로 watch 중 나중에 발견된 범위 밖 장치에는 질의하지 않는다.

## 3단계 (remotedb·NFS)

- 필드 형에 `RemoteDB` 접두사(`RemoteDBUInt32` 등)를 붙였다(표준 형과 이름이 겹친다).
- 조회 결과는 `RemoteDBQueryResult` enum으로 묶었다. 정수 `Track.year`에 담기지 않는 값은 `.trackWithRawYear`로 보존한다.
- NFS 경로 시험 입력의 `Users/chris/...`를 `Users/example/...`로 바꿨다(개인 이름 정리, 결과의 모양은 같다).
- CLI opt-in:
  - `RemoteDatabase(closesPortQueryConnection: true)`: 포트 응답을 받으면 조회 TCP를 바로 닫고, 실패 경로에서도 닫는다. 기본은 연결을 유지한다.
  - `TCPConnection.setCloseHandler`: 원격 FIN·destroy·연결 실패를 알린다. CLI는 이것으로 닫힌 연결을 장부에서 바로 지운다.
  - `UDPSocket.cancelsPendingReads`(CLI 래퍼만 true): RPC가 `udpReadCancellable`을 써서 닫기·취소·시간 초과 때 대기자를 실패시키고 구독·타이머를 거둔다. 재시도 대기도 닫기로 풀린다. `withRetry(sleep:)`의 기본 nil은 원본 시계 sleep이다. 원본 `udpRead`는 바꾸지 않았다.
  - `TCPConnection.setRequiredInterface(name:)`: `LiveTCPConnection`이 그 인터페이스의 IPv4 주소를 `NWParameters.requiredLocalEndpoint`로 지정해 연결한다. 연결할 곳과 같은 서브넷의 주소를 먼저 고르고, 없으면 첫 IPv4 주소를 쓴다. 인터페이스나 IPv4 주소가 없으면 연결을 시작하지 않는다. 연결 뒤 `currentPath.availableInterfaces`에 그 이름이 없으면 끊고 실패시킨다. 그래서 Mac 자신의 주소로 연결하면 경로가 `lo0`이라 거부되고, IPv6 목적지도 연결되지 않는다(CDJ는 IPv4만 쓴다). `djlink`는 포트 조회와 DB 연결 모두에 쓴다.
    - 예전에는 `NWPathMonitor.availableInterfaces`에서 찾은 이름으로 `requiredInterface`를 묶었다. macOS는 기본 경로만 보여 주므로 라우터 없는 링크 로컬망(169.254/16)의 인터페이스를 찾지 못해 remotedb 연결이 늘 실패했다(실기, #40).
  - `setConnectGuard`: 인터페이스 주소를 찾은 뒤 `NWConnection`을 만들기 직전에 CLI 중단 플래그를 검사한다. `interfaceProvider`는 시험이 인터페이스 목록을 바꿔 끼우는 이음매이고 기본은 `getifaddrs`다.
  - `configureNFSPathGuard(_:)`: `fetchFile`·`fetchFileRange`·`getFileInfo`가 소켓을 만들기 전에 경로를 검사한다(던지면 아무것도 보내지 않는다). `closeAllNFSClients()`는 캐시의 모든 NFS 클라이언트 RPC 소켓을 닫고 캐시를 비운다.

## 4단계 (localdb)

- PDB·ANLZ는 kaitai `.ksy`(EPL) 대신 DJCrate의 MIT 리더를 고쳐 원본(kaitai 생성 코드)과 같은 결과를 내게 했다. 트랙 문자열은 원본 entity-creators가 쓰는 11칸만 읽고(`dateAdded`=10, `analyzeDate`=15), 잘못된 짧은 문자열의 text는 건너뛴다(id·name 표에서는 빈 이름). 문자열 디코딩은 [kaitai-struct 0.11.0 런타임](https://github.com/kaitai-io/kaitai_struct_javascript_runtime/blob/v0.11.0/KaitaiStream.ts)의 `bytesToStr`와 같다.
- 메모리 ORM은 better-sqlite3 대신 SQLCipher C API로 같은 스키마·질의를 쓴다. undefined 바인딩은 [better-sqlite3-multiple-ciphers 12.11.1](https://github.com/m4heshd/better-sqlite3-multiple-ciphers/blob/v12.11.1/src/util/data.cpp)처럼 NULL이다(id 없는 PDB 재생 목록 항목은 SQLite가 번호를 매긴다, 무효한 날짜는 NULL → `new Date(null)`처럼 epoch).
- `LocalDBRow.int`: Int로 표현할 수 없는 NaN·무한대·범위 밖 실수는 nil(원본 JS number는 오류 없음).
- OneLibrary `dateAdded`를 읽지 못하면 원본은 Invalid Date, Swift는 nil.
- 긴 ASCII 문자열(0x40): 원본 Kaitai 정의는 +3부터 u16 length만큼 읽고, 1:1 기준선도 그렇다. rekordbox가 쓴 실제 export는 length가 머리 4바이트를 포함하고 +4부터 본문이라, main은 +4부터 length-4바이트를 읽는다(#13, DJCrate와 같다).
- PSSI: 원본 Kaitai song_structure_entry처럼 mood가 1~3 밖이면 kind를 0바이트 unknown_tag로 읽는다. 항목이 len_entry_bytes보다 2바이트 짧아 뒤 항목이 어긋나지만 실패하지 않는다. 결과는 원본처럼 mood high, kind nil(undefined), phraseType Unknown이고, 그래서 `Phrase.kind`는 `Int?`다. 1:1 기준선은 이 경우 EXT 전체를 실패시킨다(#26).
- 원본 버그 그대로: PDB 쪽 사슬이 자기 자신이나 지난 쪽을 가리키면 무한 루프에 빠진다. main에서 고침(오류를 낸다).
- 원본 버그 그대로: `loadAnlz`가 PCOB·PCO2 태그마다 결과를 덮어써(`src/localdb/rekordbox/index.ts:76-83`) 핫 큐(1)·메모리(0) 목록 중 마지막 태그만 남는다. main에서 고침: 같은 종류 태그를 파일 순서대로 잇는다(#22). 패시브도 같은 `loadAnlz`를 쓴다.
- 원본 버그 그대로: 장치 제거 때 첫 DB 항목만 닫고 같은 장치 항목을 모두 지운다 / OneLibrary 열기에 실패하면 임시 파일을 지우지 않는다. 둘 다 main에서 고침, 패시브도 같다(#23).
- 원본 버그 그대로: 버튼이 있으면 알 수 없는 cue type도 hot_cue로 돌려준다. main도 그대로다(PLAN §9 검토 필요).
- CLI opt-in: `LocalDatabase(throwsOnMediaQueryFailure: true)`는 미디어 슬롯 질의 실패를 nil 대신 원래 오류로 전달한다. CLI `metadata`는 이것으로 조회 실패를 종료 코드 1로 알린다.

## 5단계 (metadata-connect·artwork)

- metadata-connect의 공개 이름은 `enum MetadataConnect` 이름 공간 안에 있다(앨범아트 쪽과 이름이 겹친다).
- 통합 시험은 원본처럼 실제 음원이 있을 때만 돈다(`.enabled(if:)`, 원본은 본문에서 return). 원본 시험 입력의 원작자 개인 음악 폴더 경로·곡 이름은 공개 저장소라 견본 경로로 바꿨다. 파일이 없으면 건너뛰는 시험이라 동작은 같다.
- 원본 `PARSER_MAP`은 보통 객체라 `isExtensionSupported('constructor')`·`('__proto__')`가 true다. Swift는 이 prototype 조회를 옮기지 않았다(false).
- UTF-16 문자열의 짝 없는 서로게이트: Node는 그대로 두고 Swift `String`은 U+FFFD로 바꾼다(깨진 ID3 텍스트 프레임에서만 다르다).
- 원본 버그 그대로: APIC의 BOM 검사가 MIME 바이트를 읽는다 / v2.3 확장 헤더 크기에 크기 칸 4바이트가 빠져 태그 시작이 4바이트 어긋난다 / mp4 문자열 atom(`©nam` 등)이 `toString('ascii')` 때문에 맞지 않는다 / `Object.keys(...).length === 0` 검사 때문에 빈 값만 있어도 null이 아니다 / ID3 프레임 ID를 앞부분만 비교해 `TCOM`·`TCOP`이 장르로 읽힌다. 모두 main에서 고침.

## 5단계 (db)

- `Track.rawYear`: RemoteDB가 정수가 아닌 연도를 주면(`.trackWithRawYear`) 원본 number 값을 여기에 보존한다.
- `Waveforms.waveformHd`는 ANLZ에 태그가 없으면 원본처럼 비어 있을 수 있어 옵셔널이다. 높이가 없는 RemoteDB 미리보기는 `rawWaveformPreview`에 보존한다.
- `getPlaylist`의 `tracks`(`PlaylistTracks`, `AsyncSequence<Track>`)는 원본의 `null` 곡 항목을 담을 수 없어, 곡을 찾지 못하면 그 자리에서 오류를 던진다. 원본처럼 순회할 때마다 처음부터 다시 조회한다.
- 빈 메타데이터 진단 로그의 JSON은 `JSONSerialization`으로 이스케이프한다. `JSON.stringify`와 제어 문자·U+2028/2029 이스케이프가 다를 수 있다(로그 문구에만 영향).

## 6단계 (mixstatus)

- `setMayStop`의 `await` 뒤 부분(JS 마이크로태스크)은 프로세서 안의 목록에 넣고, 가장 바깥 진입점(`handleState`, `triggerNextTrack`, 타이머 콜백)이 끝날 때 돌린다. 원본은 한 처리 단위 안에서 `handleState`를 여러 번 부르면 그 뒤에 한꺼번에 돌고, Swift는 호출마다 끝에 돈다(실제로는 패킷마다 따로 부르므로 같다).
- 원본 버그 그대로: 같은 trackId 중복을 막는 `return`이 `cancelSetEnding`보다 앞에 있어, 같은 곡을 다시 틀면 30초 뒤 재생 중에 `setEnded`가 난다 / `isSetActive`가 false로 돌아가지 않아 두 번째 세트에서 `setStarted`가 나지 않는다 / `setMayStop`이 두 번 불리면 앞 취소 함수가 덮여 앞 타이머를 지울 수 없다. 모두 main에서 고침.

## 7단계 (제어)

- `Control`에 시험용 `correlationByte` 인자를 더했다(기본값은 원본처럼 무작위).
- 원본 버그 그대로: 재생 상태 패킷이 칸 번호(0–3)를 `device.id`와 견줘 한 칸 어긋난다(칸 i는 플레이어 i+1의 것이다). 명령은 플레이어 id+1의 칸에 실리고 나머지 칸은 0(시작)이 된다. 그래서 `pause`는 대상을 멈추지 못하고 대상 칸에는 시작이 간다. id가 4 이상이면 모든 칸이 시작이다. main에서 고침: 칸 `device.id - 1`에 명령을 싣고 나머지는 2(그대로)로 채우며, 1~4 밖 번호와 재생·cue 밖의 상태는 보내지 않고 오류를 낸다.

## 8단계 (패시브)

- 장치 id가 없는 announce는 원본에서 `undefined`이고, Swift는 `Device.id`(비옵셔널 `Int`)에 맞춰 0으로 둔다(`PassiveDevices.swift`).
- 원격 DB 조회는 3단계와 같은 `RemoteDBQueryResult?`를 돌려준다(`PassiveRemoteDB.swift`).
- 로컬 DB의 `get`·`getWithMedia`·`getWithoutMedia`는 공용 `DatabaseAdapter`를 돌려주고, 설정·결과도 `DatabasePreference`·`DatabaseType`·`PlaylistQueryResult`를 쓴다.
- preload의 미디어 캐시 조회·장치 확인·슬롯 락 생성은 Task를 만들기 전에 장치 순서·USB→SD 순서로 한다(`PassiveLocalDB.swift`의 `prepareGet` 계열). 락 획득과 로더 실행은 Swift Task에서 시작하므로 Node `async-mutex`의 동기 락 획득·Promise 마이크로태스크와 실행 순서까지 같지는 않다.
- 잘못된 버퍼 크기는 생성자가 `throws`가 아니라 `start()`에서 `BufferRangeError`를 던진다(`PassivePcapAdapter.swift`). 크기 0도 거부한다(원본 `Buffer.alloc(0)`은 빈 버퍼를 허용한다).
- 위치 파싱 예외는 `EventHub`의 package 예외 전파 API로 `emit('beat')`를 감싼 어댑터 catch까지 올라가 error 이벤트가 되고, 뒤 beat 구독자는 불리지 않는다. 상태·장치 방출기는 원본에도 파싱 try/catch가 있어 잘못된 패킷을 무시한다.
- 캡처를 열다 실패하면 Swift는 포인터를 defer로 정리하고, selectable fd가 없으면 오류를 던진다. 원본(cap)은 일부 실패에서 포인터를 남기고 selectable fd 오류는 libuv assert에 맡긴다.
- 실제 BPF 캡처는 시험 프로세스에서 금지하며, 시험은 가짜 백엔드만 쓴다.

그대로 옮긴 cap 0.2.1의 동작:

- UDP 길이 이중 차감: cap `lib/Decoders.js`가 wire 길이에서 헤더 8바이트를 뺀 값을 주고, 원본 `src/passive/pcap-adapter.ts:213`이 다시 8을 뺀다. 그래서 1:1 기준선에서는 payload 끝 8바이트가 잘리고, 8바이트 이하면 방출되지 않으며, 표준 54바이트 announce는 46바이트로 잘려 short format 경로(source IP와 장치 번호 휴리스틱)로 읽힌다. main에서 고침. `PassiveFlowTests`의 `UDP payload keeps every byte and a standard announce uses the full format`이 고친 동작을 확인한다.
- libpcap 필터의 netmask: cap `src/binding.cc:308–355`는 `pcap_lookupnet`의 mask 대신 net을 `pcap_compile`의 마지막 인자로 넘긴다. lookupnet이 실패하면 net·mask를 0으로 두고 원본과 같은 경고를 낸다.
- 캡처 읽기 오류: 원본은 `pcap_next_ex` 대신 `pcap_dispatch(..., 1, ...)`를 반복한다(`src/binding.cc:159–212`). -1을 포함한 0 이하 반환값이면 그 반복만 끝내고 캡처와 readable 감시는 유지하며, error 이벤트를 내거나 닫지 않는다. Swift도 같은 반복을 쓴다. 그래서 1:1 기준선에서는 인터페이스가 사라져도 캡처 중으로 남는다. main에서 고침: 인터페이스 번호를 감시해 사라지면 오류를 내고 멈춘다(#8).
- truncated는 wire 길이와 caplen의 차이가 아니라 `caplen > buffer_length`일 때만 true다(`src/binding.cc:128–148`).
- Ethernet은 MAC 뒤의 단일 `81 00` VLAN 태그만 건너뛰며, type/length 값이 1536 미만이면 type은 없다(`lib/Decoders.js:1–59`).

cap 0.2.1의 동작은 npm tarball의 `lib/Decoders.js`·`src/binding.cc`를 읽어 맞췄다(코드는 옮기지 않았다). 출처와 MIT 고지는 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)에 있다.

## 1:1 완료 뒤 더한 기능

- 비트 0x28([#7](https://github.com/ImBada/DJLinkKit/issues/7)): 원본에 수신 기능이 없다. CDJ-2000nexus 실기 캡처로 확인한 96바이트 형식에서 장치 번호·마디 안 비트·곡 BPM·피치를 읽는 `beatFromPacket`과 `CDJStatus.BeatState`를 더했다. `ProlinkNetwork.beatEmitter`·패시브 `beatEmitter`의 `.beat` 이벤트와 CLI `status`·`passive`로 제공한다. 피치를 적용한 BPM은 계산값이고, 정밀 위치나 비트 예측 시간은 없다. 1:1 기준선 브랜치에는 넣지 않았다.
- CLI 임시 DB([#16](https://github.com/ImBada/DJLinkKit/issues/16)): CLI가 가진 경로 목록을 본체 파일의 존재와 분리해, 본체가 먼저 지워져도 부속 파일을 종료 때 정리한다. 라이브러리 API는 바꾸지 않았다.
- CLI watch([#17](https://github.com/ImBada/DJLinkKit/issues/17)): 원본 cli는 곡 ID만 비교해 중복을 막는다. Swift는 원본 장치·슬롯·종류·곡 ID와 연결 수명으로 구분하고, 실패는 정해진 간격·횟수로 다시 조회하며, 이전 상태의 늦은 응답과 파일 게시 안내는 버린다. 곡 번호가 0(곡 없음)이면 조회하지 않고 `no track`도 내지 않는다(원본 cli는 0도 조회한다).
