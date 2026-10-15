# 옮기는 규칙 (porting guide)

alphatheta-connect(TypeScript)를 Swift로 옮길 때 모든 사람·에이전트가 따르는 규칙이다. 계획은 [PLAN.md](PLAN.md), 대응표는 [port-map.md](port-map.md).
0단계에서 만든 기반 코드가 이 규칙을 구현한다. 기반 자체 시험은 `Tests/DJLinkKitTests/Infrastructure/InfrastructureTests.swift`에 있다(쓰는 예로도 본다).

## 1. 순서

1. 원본 시험 파일 하나를 Swift 시험 파일 하나로 옮긴다(경로는 `scripts/port-status.sh`의 대응표).
   - `describe('문구')` → `@Suite("문구")`, `it('문구')` → `@Test("문구")`. 문구는 원본 영어 그대로.
   - 안쪽 `describe`는 안쪽 `@Suite` 형으로 둔다.
   - 입력과 기대값을 바꾸지 않는다. 원본 버그도 그대로 둔다(PLAN §9).
   - JS에만 있는 검사(`typeof`, `instanceof Buffer` 등)는 가장 가까운 Swift 검사로 옮기고 `// 원본과 다름: 이유` 주석을 단다.
2. 원본 코드를 옮긴다.
3. 사용자가 "구현 완료"라고 하면 `swift build`와 `swift test --filter <Suite 형 이름>`로 통과시킨다. 구현하는 동안에는 빌드·시험을 돌리지 않는다(AGENTS.md).
4. `scripts/port-status.sh --stage N`에서 원본 `it(` 수와 `@Test` 수가 같은지 본다. 이 스크립트는 읽기만 하므로 구현 중에도 쓸 수 있다.

## 2. 이름과 파일

- 형·함수·속성 이름은 원본을 따른다(`DeviceManager`, `deviceFromPacket`, `getSlotName`).
- 상수는 원본 이름 그대로 둔다(`ANNOUNCE_PORT`, `PROLINK_HEADER`).
- enum 사례는 lowerCamel(`MediaSlot.USB` → `.usb`). 원본 키 이름이 필요하면 `jsName`.
- 한 모듈 안에서 파일 basename이 겹치면 안 된다. `index.ts`는 대표 형 이름(`DeviceManager.swift`)이나 `<Dir>Index.swift`, `utils.ts`·`types.ts`는 폴더 이름을 붙인다(`DevicesUtils.swift`, `StatusTypes.swift`).
- 원본 JSDoc은 영어 그대로 옮겨도 된다. 새로 쓰는 주석은 한국어로 쓴다.

## 3. 값

| 원본 | Swift |
|---|---|
| `Buffer`, `Uint8Array` | `[UInt8]`. Foundation 경계(파일·소켓 구현)에서만 `Data`(`.data`, `.bytes`) |
| `buf.readUInt16BE(o)` 등 | `try buf.readUInt16BE(o)`(`Utils/Bytes.swift`). 범위를 넘으면 Node처럼 `BufferRangeError`를 던진다. 위치는 늘 컬렉션 처음 기준(ArraySlice도) |
| `buf.toString('ascii', s, e)`, `Buffer.from(str, enc)` | `buf.toString(.ascii, s, e)`, `[UInt8](str, encoding: .ascii)` |
| `buf.slice`·`subarray` | `buf.subarray(s, e)`(새 배열) |
| `number`(정수) / (실수) | `Int` / `Double`. `bigint`는 `UInt64`·`Int64` |
| `undefined`, `null` | `nil`. 원본 시험이 둘을 가려 보면 따로 형을 만들고 이유를 적는다 |
| 선(wire)에서 읽는 숫자 enum | `RawRepresentable` 구조체(모르는 값도 담는다). 예: `DeviceType`, `MediaSlot` |
| 안에서만 쓰는 enum | Swift `enum` |
| 문자열 리터럴 합(`'high' \| 'mid'`) | `String` raw value enum, 값은 원본 문자열 |
| 판별 합(`{type: 'loop', …} \| …`) | 연관값 enum + `type` 계산 속성(`CueAndLoop` 참고) |
| `new Error(msg)` | `DJLinkError(msg)`. 문구는 원본 그대로 |
| `ip.Address4` | `Address4`(`Utils/Address4.swift`) |
| `os.networkInterfaces()` | `InterfaceProvider` 주입(`SystemInterfaceProvider`, 시험은 `FakeInterfaceProvider`) |
| `Logger`, `noopLogger` | `Logger.swift` |
| telemetry | `Telemetry`(빈 구현). 부르는 자리는 그대로 둔다 |

## 4. 동시성·시간·이벤트

- 상태를 가진 형은 `@DJLinkActor final class`로 만든다. 순수 함수(패킷 읽기·만들기)는 격리 없이 둔다.
  Node 이벤트 루프 하나를 `DJLinkActor`(직렬 큐) 하나로 옮긴 것이다. 소켓 수신·타이머 콜백도 이 위에서 동기로 돈다.
- 시간: `setTimeout`·`setInterval`·`clearTimeout`·`Date.now()`는 주입한 `clock: any DJLinkClock`로 부른다
  (`clock.setTimeout(.ms(1500)) { … }`, `clock.now()`, `clock.nowMilliseconds()`). 기본값은 `SystemClock.shared`.
- 이벤트: `EventEmitter`는 `EventEmitting` + `let emitter = EventHub<Self>()`로 옮기고, 이벤트 이름은 제약 걸린 확장으로 선언한다.

  ```swift
  extension EventName where Owner == DeviceManager, Payload == Device {
      public static var connected: Self { .init("connected") }
  }
  emitter.emit(.connected, device)      // 안에서
  deviceManager.on(.connected) { … }    // 밖에서. once/off/events(.connected)(AsyncStream)도 있다
  ```
  인자가 여럿인 이벤트는 작은 구조체나 튜플 대신 구조체로 묶는다. 인자가 없으면 `Payload == Void`.
- `async-mutex` → `AsyncMutex`(`runExclusive`). `promise-timeout` → `withTimeout(clock:_:_:)`, `TimeoutError`("Timeout").
- `Promise.race([p, timeout])` 같은 것은 `withCheckedContinuation` + `clock.setTimeout`으로 옮긴다(InfrastructureTests의 `waitForPing` 예).
- 원본 이벤트 핸들러 안에서 잡지 않은 예외는 Node 프로세스를 죽인다. Swift에서는 그 경계에서 잡고 넘어가며 주석을 단다.

## 5. 소켓

- UDP: `UDPSocket` 프로토콜(`Socket/UDPSocket.swift`). `udpBind`·`udpSend`·`udpRead`·`udpClose`도 같은 파일에 있다.
- TCP: `TCPConnection` 프로토콜(`Socket/TCPConnection.swift`).
- 소켓을 만드는 형은 `SocketFactory`를 주입받는다(`LiveSocketFactory.shared`가 기본). 시험은 `FakeSocketFactory`·`FakeUDPSocket`.
- 실제 소켓은 시험 프로세스에서 만들 수 없다(`TestProcess`). 시험은 LAN에 아무것도 보내지 않는다.
  예외는 `DJLINK_LOOPBACK_TESTS=1`일 때만 도는 루프백 시험(DJLinkKit 6개, `DJLinkExport` 8개)이다. 이 시험은 127.0.0.1에만 묶는다. Export는 소켓 가드가 시험 프로세스에서는 TCP를 127.0.0.1·::1에만 묶고 그쪽으로만 연결하며, UDP는 127.0.0.1·::1로만 보낸다(UDP RPC 소켓은 원본처럼 0.0.0.0에 묶은 뒤 인터페이스를 고정하므로 보내는 주소를 검사한다).

## 6. 시험

- swift-testing(`import Testing`)만 쓴다. 액터 형을 만지는 Suite는 `@DJLinkActor`를 붙인다.
- `jest.fn()` → 지역 변수나 `CallRecorder`. `jest.useFakeTimers()` → `TestClock`을 주입하고 `advance(ms:)`·`runAllTimers()`.
- `jest.mock('모듈')` → 그 모듈 함수·형을 init 인자(기본값은 실제 구현)나 프로토콜로 주입받게 만들고 시험에서 가짜를 넣는다.
- 비동기 함수를 시작한 뒤 시간을 밀 때는 `await clock.waitForTimers(atLeast:)`나 `await clock.settle()`로 타이머가 걸릴 때까지 기다린다
  (JS async 함수는 첫 await까지 동기로 돈다).
- 진짜 시간을 기다리는 원본 시험(`done` + 실제 `setTimeout`)도 가능하면 `TestClock`으로 옮긴다.
- 픽스처는 `Tests/DJLinkKitTests/Fixtures/`. `readMock("status-simple.dat")`(`Support/TestHelpers.swift`).
- `mockDevice(...)`는 DJLinkTestSupport에 있다.
- `#expect(a == b)`, `#expect(throws: DJLinkError("msg")) { … }`, `try #require(x)`.

## 7. 공유 파일

여러 단계가 같이 쓰는 기반 파일(`Package.swift`, `Sources/DJLinkKit/{Concurrency,Socket,Utils}/`, `Types.swift`, `Entities.swift`, `Constants.swift`, `Logger.swift`, `LocalDB/OneLibrary/OneLibraryEntities.swift`, `Sources/DJLinkTestSupport/`)는
꼭 필요할 때만 더하는 쪽으로 고친다. 고쳤으면 보고에 "공유 파일 변경"으로 적는다.
