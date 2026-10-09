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

## 3단계 (remotedb·NFS)

- NFS 경로 시험 입력의 `Users/chris/...`를 `Users/example/...`로 바꿨다(개인 이름 정리, 경로 해석 결과의 모양은 같다).

- 필드 형에 `RemoteDB` 접두사(`RemoteDBUInt32` 등)를 붙였다(표준 형과 이름이 겹친다).
- 조회 결과는 `RemoteDBQueryResult` enum으로 묶었다. 정수 `Track.year`에 담기지 않는 값은 `.trackWithRawYear`로 보존한다.

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
