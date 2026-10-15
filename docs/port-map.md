# 파일 단위 대응표 (원본 → Swift)

원본 세 저장소(고정 커밋은 [UPSTREAM.md](../UPSTREAM.md))의 `src/` 파일을 실제로 옮긴 Swift 파일에 하나씩 대응시킨다. 단계 번호는 [PLAN.md](PLAN.md) §8 표를 따른다. 원본과 다르게 옮긴 곳은 [port-notes.md](port-notes.md)에 있다.

이 표는 1:1 포트를 마친 뒤의 실제 파일을 기준으로 다시 썼다. Swift 파일 이름은 각 파일 머리 주석(`// 원본 src/...`)과 내용을 열어 확인했다.

이 문서는 alphatheta-connect 계열(`DJLinkKit`·`DJLinkControl`·`DJLinkPassive`·`djlink`)만 다룬다. Link Export(`DJLinkExport*`, rbxport 원본)의 대응은 [export-port-map.md](export-port-map.md)에 따로 있다. 이 문서의 §3·§4는 main의 현재 파일을 기준으로 하고, 1:1 기준선(`port/one-to-one`)과 다른 곳은 그렇게 적었다.

## 범례와 갱신 규칙

- **상태**
  - `통과`: 옮겼고, 그 단계의 원본 시험(원본 `it` 수와 `@Test` 수가 같다)이 통과한다.
  - `옮김`: 옮겼지만 원본 시험이 없다(우리가 만든 시험만 있다).
  - `재수출(Swift에서 필요 없음)`: 다시 내보내기만 있는 파일. Swift는 모듈 안 이름이 바로 보이므로 파일이 필요 없다.
  - `빈 구현`: Sentry를 뺀 원본처럼 아무것도 하지 않는 구현만 둔다.
  - `범위 밖`: 옮기지 않는다(PLAN §1).
  - `옮기지 않음`: 라이선스나 설계 때문에 일부러 옮기지 않았다.
- **갱신 규칙**: 파일을 옮기거나 이름을 바꾸는 사람이 같은 변경에서 이 표를 고친다. 시험 파일을 바꾸면 `scripts/port-status.sh`의 대응표도 같이 고친다.
- **이름 규칙** (PLAN §5, [porting-guide.md](porting-guide.md) §2):
  - 한 모듈 안에서 파일 이름(basename)이 겹치면 안 된다. 그래서 `index.ts`는 대표 형 이름이나 `<폴더>Index`, `utils.ts`·`types.ts`는 폴더 이름을 붙인 이름이 되었다.
  - `localdb/`의 Swift 파일은 대부분 `LocalDB` 접두사, `db/`는 `DB`, `remotedb/`는 `RemoteDB`, `artwork/`는 `Artwork`, metadata-connect는 `Metadata`, onelibrary-connect는 `OneLibrary`가 앞에 붙는다.
- **하나의 원본이 여러 Swift 파일로 나뉜 곳, 여러 원본이 한 Swift 파일로 합쳐진 곳**은 해당 칸에 적었다.

## 1. 코드 파일 (`src/`)

### 단계 1 — 기초·상태: 루트, `utils/`, `devices/`, `status/`

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/constants.ts` | `Sources/DJLinkKit/Constants.swift` | 통과 |
| `alphatheta-connect/src/types.ts` | `Sources/DJLinkKit/Types.swift` | 통과 |
| `alphatheta-connect/src/entities.ts` | `Sources/DJLinkKit/Entities.swift` | 통과 |
| `alphatheta-connect/src/logger.ts` | `Sources/DJLinkKit/Logger.swift` | 통과 |
| `alphatheta-connect/src/utils/index.ts` | `Sources/DJLinkKit/Utils/UtilsIndex.swift` | 통과 |
| `alphatheta-connect/src/utils/converters.ts` | `Sources/DJLinkKit/Utils/Converters.swift` | 통과 |
| `alphatheta-connect/src/utils/udp.ts` | `Sources/DJLinkKit/Socket/UDPSocket.swift` — `UDPSocket` 프로토콜과 `udpBind`·`udpSend`·`udpRead`·`udpClose`. 소켓 구현은 §4의 `BSDUDPSocket.swift` 등 | 통과 |
| `alphatheta-connect/src/devices/index.ts` | `Sources/DJLinkKit/Devices/DeviceManager.swift` | 통과 |
| `alphatheta-connect/src/devices/utils.ts` | `Sources/DJLinkKit/Devices/DevicesUtils.swift` | 통과 |
| `alphatheta-connect/src/status/index.ts` | `Sources/DJLinkKit/Status/StatusEmitter.swift` | 통과 |
| `alphatheta-connect/src/status/media.ts` | `Sources/DJLinkKit/Status/StatusMedia.swift` | 통과 |
| `alphatheta-connect/src/status/position.ts` | `Sources/DJLinkKit/Status/PositionEmitter.swift` | 통과 |
| `alphatheta-connect/src/status/types.ts` | `Sources/DJLinkKit/Status/StatusTypes.swift` | 통과 |
| `alphatheta-connect/src/status/utils.ts` | `Sources/DJLinkKit/Status/StatusUtils.swift` | 통과 |

### 단계 2 — 가상 CDJ·네트워크: `virtualcdj/`, `network.ts`

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/virtualcdj/index.ts` | `Sources/DJLinkKit/VirtualCDJ/Announcer.swift` | 통과 |
| `alphatheta-connect/src/virtualcdj/device-id.ts` | `Sources/DJLinkKit/VirtualCDJ/DeviceId.swift` | 통과 |
| `alphatheta-connect/src/virtualcdj/heartbeat.ts` | `Sources/DJLinkKit/VirtualCDJ/StagehandHeartbeat.swift` | 통과 |
| `alphatheta-connect/src/virtualcdj/stagehand.ts` | `Sources/DJLinkKit/VirtualCDJ/StagehandAnnouncer.swift` | 통과 |
| `alphatheta-connect/src/network.ts` | `Sources/DJLinkKit/Network/ProlinkNetwork.swift`(`ProlinkNetwork`·`bringOnline`·`bringOnlineStagehand`), `Sources/DJLinkKit/Network/NetworkConfig.swift`(설정 형), `Sources/DJLinkKit/Network/NetworkDependencies.swift`(db·localdb·remotedb를 시험에서 바꿔 끼우는 서비스 프로토콜). `get control()`은 `Sources/DJLinkControl/ControlNetwork.swift`(단계 7, §4) | 통과 |

### 단계 3 — remotedb·NFS

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/remotedb/index.ts` | `Sources/DJLinkKit/RemoteDB/RemoteDatabase.swift` | 통과 |
| `alphatheta-connect/src/remotedb/constants.ts` | `Sources/DJLinkKit/RemoteDB/RemoteDBConstants.swift` | 통과 |
| `alphatheta-connect/src/remotedb/fields.ts` | `Sources/DJLinkKit/RemoteDB/RemoteDBFields.swift` | 통과 |
| `alphatheta-connect/src/remotedb/queries.ts` | `Sources/DJLinkKit/RemoteDB/RemoteDBQueries.swift` | 통과 |
| `alphatheta-connect/src/remotedb/utils.ts` | `Sources/DJLinkKit/RemoteDB/RemoteDBUtils.swift` | 통과 |
| `alphatheta-connect/src/remotedb/message/index.ts` | `Sources/DJLinkKit/RemoteDB/Message/RemoteDBMessage.swift` | 통과 |
| `alphatheta-connect/src/remotedb/message/item.ts` | `Sources/DJLinkKit/RemoteDB/Message/RemoteDBItem.swift` | 통과 |
| `alphatheta-connect/src/remotedb/message/response.ts` | `Sources/DJLinkKit/RemoteDB/Message/RemoteDBResponse.swift` | 통과 |
| `alphatheta-connect/src/remotedb/message/types.ts` | `Sources/DJLinkKit/RemoteDB/Message/RemoteDBMessageTypes.swift` | 통과 |
| `alphatheta-connect/src/nfs/index.ts` | `Sources/DJLinkKit/NFS/NFSIndex.swift` | 통과 |
| `alphatheta-connect/src/nfs/programs.ts` | `Sources/DJLinkKit/NFS/NFSPrograms.swift` | 통과 |
| `alphatheta-connect/src/nfs/rpc.ts` | `Sources/DJLinkKit/NFS/NFSRPC.swift` | 통과 |
| `alphatheta-connect/src/nfs/utils.ts` | `Sources/DJLinkKit/NFS/NFSUtils.swift` | 통과 |
| `alphatheta-connect/src/nfs/xdr.ts` | `Sources/DJLinkKit/NFS/NFSXDR.swift` — 외부 `js-xdr` 대신 직접 만든 XDR 인코더·디코더 | 통과 |

### 단계 4 — localdb (alphatheta-connect)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/localdb/index.ts` | `Sources/DJLinkKit/LocalDB/LocalDatabase.swift` | 통과 |
| `alphatheta-connect/src/localdb/database-adapter.ts` | 형은 onelibrary-connect `database-adapter.ts`를 다시 내보낸다 → `Sources/DJLinkKit/LocalDB/LocalDBDatabaseAdapter.swift`(아래 onelibrary-connect 표 참고) | 재수출(Swift에서 필요 없음) |
| `alphatheta-connect/src/localdb/onelibrary.ts` | (없음) — onelibrary-connect의 `OneLibraryAdapter`·`openOneLibraryDb`·`getEncryptionKey` 등을 다시 내보낸다 | 재수출(Swift에서 필요 없음) |
| `alphatheta-connect/src/localdb/onelibrary/index.ts` | (없음) — 위와 같다 | 재수출(Swift에서 필요 없음) |
| `alphatheta-connect/src/localdb/rekordbox.ts` | (없음) — `rekordbox/index.ts`를 다시 내보낸다 | 재수출(Swift에서 필요 없음) |
| `alphatheta-connect/src/localdb/orm.ts` | `Sources/DJLinkKit/LocalDB/LocalDBMetadataORM.swift` — 메모리 SQLite 연결만 SQLCipher C API로 바꿨다 | 통과 |
| `alphatheta-connect/src/localdb/schema.ts` | `Sources/DJLinkKit/LocalDB/LocalDBSchema.swift` | 통과 |
| `alphatheta-connect/src/localdb/utils.ts` | `Sources/DJLinkKit/LocalDB/LocalDBUtils.swift` | 통과 |
| `alphatheta-connect/src/localdb/rekordbox/index.ts` | 두 함수가 두 파일로 나뉘었다. `loadAnlz` → `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBLoadAnlz.swift`, `hydrateDatabase` → `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBRekordboxHydrator.swift`(`RekordboxHydrator`와 같은 파일) | 통과 |
| `alphatheta-connect/src/localdb/rekordbox/anlz-parsers.ts` | `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBAnlzParsers.swift` — Kaitai 대신 주입 가능한 리더(§6 `LocalDBAnlzFile.swift`)의 구역을 받는다 | 통과 |
| `alphatheta-connect/src/localdb/rekordbox/entity-creators.ts` | `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBEntityCreators.swift` | 통과 |
| `alphatheta-connect/src/localdb/rekordbox/hydrator.ts` | `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBRekordboxHydrator.swift` — PDB 읽기는 §6의 리더 | 통과 |
| `alphatheta-connect/src/localdb/rekordbox/table-mappings.ts` | `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBTableMappings.swift` | 통과 |
| `alphatheta-connect/src/localdb/rekordbox/types.ts` | `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBRekordboxTypes.swift` | 통과 |

### 단계 4 — onelibrary-connect (`ac3edd3`)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `onelibrary-connect/src/adapter.ts` | `Sources/DJLinkKit/LocalDB/OneLibrary/OneLibraryAdapter.swift` | 통과 |
| `onelibrary-connect/src/connection.ts` | `Sources/DJLinkKit/LocalDB/OneLibrary/OneLibraryConnection.swift` — 연결 본체는 §6의 `LocalDBCipherDatabase.swift`(SQLCipher.swift) | 통과 |
| `onelibrary-connect/src/database-adapter.ts` | `Sources/DJLinkKit/LocalDB/LocalDBDatabaseAdapter.swift` — `DatabaseAdapter` 프로토콜, `DatabasePreference`, `DatabaseType`, `PlaylistQueryResult`. alphatheta-connect의 `localdb/database-adapter.ts`가 다시 내보내는 형이 이것이다 | 통과 |
| `onelibrary-connect/src/encryption.ts` | `Sources/DJLinkKit/LocalDB/OneLibrary/OneLibraryEncryption.swift` | 통과 |
| `onelibrary-connect/src/entities.ts`, `onelibrary-connect/src/types.ts` | 두 파일이 한 파일로 합쳐졌다 → `Sources/DJLinkKit/LocalDB/OneLibrary/OneLibraryEntities.swift` | 통과 |
| `onelibrary-connect/src/schema.ts` | `Sources/DJLinkKit/LocalDB/OneLibrary/OneLibrarySchema.swift` | 통과 |
| `onelibrary-connect/src/index.ts` | (없음) | 재수출(Swift에서 필요 없음) |

### 단계 5 — `db/`, `artwork/`, `metadata.ts`

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/db/index.ts` | `Sources/DJLinkKit/DB/Database.swift` | 통과 |
| `alphatheta-connect/src/db/getArtworkFromFile.ts` | `Sources/DJLinkKit/DB/DBGetArtworkFromFile.swift` | 통과 |
| `alphatheta-connect/src/db/getArtworkThumbnail.ts` | `Sources/DJLinkKit/DB/DBGetArtworkThumbnail.swift` | 통과 |
| `alphatheta-connect/src/db/getFile.ts` | `Sources/DJLinkKit/DB/DBGetFile.swift` | 통과 |
| `alphatheta-connect/src/db/getMetadata.ts` | `Sources/DJLinkKit/DB/DBGetMetadata.swift` | 통과 |
| `alphatheta-connect/src/db/getPlaylist.ts` | `Sources/DJLinkKit/DB/DBGetPlaylist.swift` | 통과 |
| `alphatheta-connect/src/db/getTrackAnalysis.ts` | `Sources/DJLinkKit/DB/DBGetTrackAnalysis.swift` | 통과 |
| `alphatheta-connect/src/db/getWaveforms.ts` | `Sources/DJLinkKit/DB/DBGetWaveforms.swift` | 통과 |
| `alphatheta-connect/src/db/utils.ts` | `Sources/DJLinkKit/DB/DBUtils.swift` | 통과 |
| `alphatheta-connect/src/artwork/index.ts` | `Sources/DJLinkKit/Artwork/ArtworkIndex.swift` | 통과 |
| `alphatheta-connect/src/artwork/reader.ts` | `Sources/DJLinkKit/Artwork/ArtworkReader.swift` | 통과 |
| `alphatheta-connect/src/artwork/types.ts` | `Sources/DJLinkKit/Artwork/ArtworkTypes.swift` | 통과 |
| `alphatheta-connect/src/artwork/parsers/index.ts` | (없음) | 재수출(Swift에서 필요 없음) |
| `alphatheta-connect/src/artwork/parsers/aiff.ts` | `Sources/DJLinkKit/Artwork/Parsers/ArtworkAiff.swift` | 통과 |
| `alphatheta-connect/src/artwork/parsers/flac.ts` | `Sources/DJLinkKit/Artwork/Parsers/ArtworkFlac.swift` | 통과 |
| `alphatheta-connect/src/artwork/parsers/id3.ts` | `Sources/DJLinkKit/Artwork/Parsers/ArtworkId3.swift` | 통과 |
| `alphatheta-connect/src/artwork/parsers/mp4.ts` | `Sources/DJLinkKit/Artwork/Parsers/ArtworkMp4.swift` | 통과 |
| `alphatheta-connect/src/artwork/parsers/utils.ts` | `Sources/DJLinkKit/Artwork/Parsers/ArtworkParsersUtils.swift` | 통과 |
| `alphatheta-connect/src/metadata.ts` | `Sources/DJLinkKit/Metadata/Metadata.swift` | 통과 |

### 단계 5 — metadata-connect (`c2ae262`)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `metadata-connect/src/extract.ts` | `Sources/DJLinkKit/Metadata/MetadataExtract.swift` | 통과 |
| `metadata-connect/src/index.ts` | `Sources/DJLinkKit/Metadata/MetadataConnectIndex.swift` — 이름 공간 `enum MetadataConnect {}`만 선언한다(앨범아트 쪽과 이름이 겹쳐서 metadata-connect의 공개 이름을 이 안에 둔다) | 재수출(Swift에서 필요 없음) |
| `metadata-connect/src/reader.ts` | `Sources/DJLinkKit/Metadata/MetadataReader.swift` | 통과 |
| `metadata-connect/src/types.ts` | `Sources/DJLinkKit/Metadata/MetadataTypes.swift` | 통과 |
| `metadata-connect/src/types/logger.ts` | `Sources/DJLinkKit/Metadata/MetadataLogger.swift` — 별도 형 없이 `Logger.swift`의 `Logger`를 그대로 쓴다 | 통과 |
| `metadata-connect/src/parsers/index.ts` | (없음) | 재수출(Swift에서 필요 없음) |
| `metadata-connect/src/parsers/aiff.ts` | `Sources/DJLinkKit/Metadata/Parsers/MetadataAiff.swift` | 통과 |
| `metadata-connect/src/parsers/flac.ts` | `Sources/DJLinkKit/Metadata/Parsers/MetadataFlac.swift` | 통과 |
| `metadata-connect/src/parsers/id3.ts` | `Sources/DJLinkKit/Metadata/Parsers/MetadataId3.swift` | 통과 |
| `metadata-connect/src/parsers/mp4.ts` | `Sources/DJLinkKit/Metadata/Parsers/MetadataMp4.swift` | 통과 |
| `metadata-connect/src/parsers/utils.ts` | `Sources/DJLinkKit/Metadata/Parsers/MetadataParsersUtils.swift` | 통과 |

`ArtworkReader.swift`·`ArtworkIndex.swift`·`Metadata.swift`가 `nfs/`를 부르는 자리는 `Sources/DJLinkKit/Artwork/ArtworkNFSSeam.swift`(우리가 더한 주입점, §4)로 바꿔 끼울 수 있다.

### 단계 6 — `mixstatus/`

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/mixstatus/index.ts` | `Sources/DJLinkKit/MixStatus/MixstatusProcessor.swift` | 통과 |
| `alphatheta-connect/src/mixstatus/utils.ts` | `Sources/DJLinkKit/MixStatus/MixStatusUtils.swift` | 통과 |

### 단계 7 — `control/` (`DJLinkControl`)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/control/index.ts` | `Sources/DJLinkControl/Control.swift` | 통과 |
| `alphatheta-connect/src/control/load.ts` | `Sources/DJLinkControl/ControlLoad.swift` | 통과 |
| `alphatheta-connect/src/control/stagehand.ts` | `Sources/DJLinkControl/ControlStagehand.swift` | 통과 |

### 단계 8 — `passive/` (`DJLinkPassive`)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/passive/index.ts` | `Sources/DJLinkPassive/PassiveProlinkNetwork.swift` — `PassiveProlinkNetwork`·`bringOnlinePassive`·`listInterfaces` | 통과 |
| `alphatheta-connect/src/passive/alphatheta.ts` | `Sources/DJLinkPassive/PassiveAlphatheta.swift` | 통과 |
| `alphatheta-connect/src/passive/devices.ts` | `Sources/DJLinkPassive/PassiveDevices.swift` | 통과 |
| `alphatheta-connect/src/passive/localdb.ts` | `Sources/DJLinkPassive/PassiveLocalDB.swift` — 서비스 형과 `PassiveLocalDatabase`. DJLinkKit의 localdb에 잇는 실제 구현은 `PassiveLocalDBBackend.swift`(우리가 더한 파일, §4) | 통과 |
| `alphatheta-connect/src/passive/pcap-adapter.ts` | `Sources/DJLinkPassive/PassivePcapAdapter.swift` — libpcap은 `Sources/CPcap` 시스템 라이브러리로 부른다 | 통과 |
| `alphatheta-connect/src/passive/position.ts` | `Sources/DJLinkPassive/PassivePosition.swift` | 통과 |
| `alphatheta-connect/src/passive/remotedb.ts` | `Sources/DJLinkPassive/PassiveRemoteDB.swift` | 통과 |
| `alphatheta-connect/src/passive/status.ts` | `Sources/DJLinkPassive/PassiveStatus.swift` | 통과 |

### 단계 9 — `cli/` (`djlink`)

원본 `cli/index.ts`는 인자가 없는 스크립트 하나다. Swift는 하위 명령과 안전 규칙(PLAN §11)을 더해 여러 파일로 나눴다.

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/cli/index.ts` | `Sources/djlink/` 아래 14개 파일로 나뉘었다(1:1 기준선은 13개, `CLIWatchTracks.swift`는 main에서 더했다). 진입점 `DJLinkCLI.swift`, 인자 해석 `CLIArguments.swift`, 명령 실행(`watch`가 원본 흐름) `CLICommands.swift`, 한 번의 실행이 가진 네트워크·소켓·작업과 정리 `CLISession.swift`, 주입하는 바깥 세계(소켓·인터페이스·시계·파일·NFS) `CLIRuntime.swift`, 소켓 소유권·인터페이스 묶기·중단 뒤 송신 차단 `CLISocketGuard.swift`, 중단 토큰·신호 `CLIAbort.swift`, 액터와 독립된 제한 시간·강제 종료 감시 `CLIWatchdog.swift`, 덮어쓰지 않는 파일 쓰기 `CLIFileWriter.swift`, 안전 검사 `CLISafety.swift`, 출력 `CLIConsole.swift`·`CLIFormat.swift`, 도움말 `CLIHelp.swift`, watch의 곡별 조회 중복·재시도·늦은 결과 관리 `CLIWatchTracks.swift`(#17) | 옮김 (원본 시험 없음. 우리 시험 180개, §3) |

### 빈 구현

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/utils/telemetry.ts` | `Sources/DJLinkKit/Utils/Telemetry.swift` — 부르는 자리(`init`·`captureException`·span 등)만 남기고 아무것도 하지 않는다(PLAN §1). 원본도 이미 Sentry를 뺀 빈 구현이다 | 빈 구현 |

### 범위 밖·옮기지 않음

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/remote/hue.ts`, `remote/index.ts`, `remote/server.ts` | (없음) | 범위 밖 (원본 시험 0개라 시험 수는 줄지 않는다. PLAN §1) |
| `alphatheta-connect/src/localdb/kaitai/rekordbox_pdb.ksy`, `rekordbox_anlz.ksy` | (없음) — §6의 DJCrate 리더(`LocalDBPdb*.swift`, `LocalDBAnlzFile.swift`)가 같은 형식을 읽는다 | 옮기지 않음(EPL, DJCrate 리더로 대신) |
| `alphatheta-connect/src/global.d.ts` | (없음) — `kaitai-struct`·`js-xdr`·`.ksy` 모듈 선언뿐이다 | 범위 밖 |
| `alphatheta-connect/src/index.ts` | (없음) — 공개 이름을 모아 내보내기만 한다(`Control`, `PositionEmitter`, `loadAnlz`, `fetchFile`, `OneLibraryAdapter` 등). Swift는 모듈 안 공개 이름이 바로 보인다 | 재수출(Swift에서 필요 없음) |
| `alphatheta-connect/src/tsconfig.json`, `alphatheta-connect/src/passive/README.md` | (없음) — 빌드 설정, 문서 | 범위 밖 |

### 합계

- `src/` 코드 파일(시험 파일·`.d.ts` 제외): alphatheta-connect 85개, onelibrary-connect 8개, metadata-connect 11개 = 104개. 위 표에 모두 있다.
- 대응하는 Swift 파일을 찾지 못한 원본 `src/` 코드 파일은 없다. Swift 파일이 없는 것은 모두 `재수출`·`범위 밖`·`옮기지 않음`으로 적은 파일이다.

## 2. 시험 파일 (`scripts/port-status.sh`의 대응표와 같다)

`UPSTREAM_DIR=~/src/upstream bash scripts/port-status.sh`의 결과다. 모든 파일에서 원본 `it` 수와 Swift `@Test` 수가 같다. 상태 칸의 숫자는 그 수다.

| 구분 | 원본 시험 | Swift 시험 |
|---|---|---|
| alphatheta-connect | 532 | 532 |
| onelibrary-connect | 62 | 62 |
| metadata-connect | 28 | 28 |
| **합계 (44개 파일)** | **622** | **622** |

### 단계 1 — 기초·상태 (원본 50)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/tests/utils/index.spec.ts` | `Tests/DJLinkKitTests/Utils/UtilsIndexTests.swift` | 통과 (9) |
| `alphatheta-connect/tests/devices/index.spec.ts` | `Tests/DJLinkKitTests/Devices/DevicesIndexTests.swift` | 통과 (7) |
| `alphatheta-connect/tests/devices/utils.spec.ts` | `Tests/DJLinkKitTests/Devices/DevicesUtilsTests.swift` | 통과 (3) |
| `alphatheta-connect/tests/status/utils.spec.ts` | `Tests/DJLinkKitTests/Status/StatusUtilsTests.swift` | 통과 (14) |
| `alphatheta-connect/tests/status/position.spec.ts` | `Tests/DJLinkKitTests/Status/StatusPositionTests.swift` | 통과 (7) |
| `alphatheta-connect/tests/status/on-air.test.ts` | `Tests/DJLinkKitTests/Status/StatusOnAirTests.swift` | 통과 (8) |
| `alphatheta-connect/src/status/stagehand-gating.test.ts` | `Tests/DJLinkKitTests/Status/StatusStagehandGatingTests.swift` | 통과 (2) |

### 단계 2 — 가상 CDJ·네트워크 (원본 84)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/src/virtualcdj/heartbeat.test.ts` | `Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJHeartbeatTests.swift` | 통과 (7) |
| `alphatheta-connect/tests/virtualcdj/conflict.test.ts` | `Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJConflictTests.swift` | 통과 (11) |
| `alphatheta-connect/tests/virtualcdj/device-id.test.ts` | `Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJDeviceIdTests.swift` | 통과 (25) |
| `alphatheta-connect/tests/virtualcdj/stagehand.test.ts` | `Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJStagehandTests.swift` | 통과 (8) |
| `alphatheta-connect/tests/virtualcdj/startup.test.ts` | `Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJStartupTests.swift` | 통과 (23) |
| `alphatheta-connect/tests/virtualcdj/wire-selection.test.ts` | `Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJWireSelectionTests.swift` | 통과 (8) |
| `alphatheta-connect/tests/network/stagehand-identity.test.ts` | `Tests/DJLinkKitTests/Network/NetworkStagehandIdentityTests.swift` | 통과 (2) |

### 단계 3 — remotedb·NFS (원본 47)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/tests/remotedb/connection.spec.ts` | `Tests/DJLinkKitTests/RemoteDB/RemoteDBConnectionTests.swift` | 통과 (4) |
| `alphatheta-connect/tests/remotedb/fields.spec.ts` | `Tests/DJLinkKitTests/RemoteDB/RemoteDBFieldsTests.swift` | 통과 (13) |
| `alphatheta-connect/src/nfs/index.test.ts` | `Tests/DJLinkKitTests/NFS/NFSIndexTests.swift` | 통과 (16) |
| `alphatheta-connect/tests/nfs/path.spec.ts` | `Tests/DJLinkKitTests/NFS/NFSPathTests.swift` | 통과 (14) |

### 단계 4 — localdb (원본 296: alphatheta-connect 234 + onelibrary-connect 62)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/tests/localdb/anlz-2ex-integration.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBAnlz2exIntegrationTests.swift` | 통과 (20) |
| `alphatheta-connect/tests/localdb/anlz-parsers-2ex.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsers2exTests.swift` | 통과 (18) |
| `alphatheta-connect/tests/localdb/anlz-parsers-cue-nulls.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsersCueNullsTests.swift` | 통과 (2) |
| `alphatheta-connect/tests/localdb/anlz-parsers-cues.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsersCuesTests.swift` | 통과 (3) |
| `alphatheta-connect/tests/localdb/anlz-parsers-extended-cues.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsersExtendedCuesTests.swift` | 통과 (5) |
| `alphatheta-connect/tests/localdb/anlz-parsers-song-structure.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsersSongStructureTests.swift` | 통과 (5) |
| `alphatheta-connect/tests/localdb/anlz-parsing.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBAnlzParsingTests.swift` | 통과 (31) |
| `alphatheta-connect/tests/localdb/database-fallback.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBDatabaseFallbackTests.swift` | 통과 (12) |
| `alphatheta-connect/tests/localdb/database-loading.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBDatabaseLoadingTests.swift` | 통과 (22) |
| `alphatheta-connect/tests/localdb/edge-cases.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBEdgeCasesTests.swift` | 통과 (44) |
| `alphatheta-connect/tests/localdb/load-anlz-vocal-config.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBLoadAnlzVocalConfigTests.swift` | 통과 (10) |
| `alphatheta-connect/tests/localdb/onelibrary-adapter.spec.ts` | `Tests/DJLinkKitTests/LocalDB/LocalDBOnelibraryAdapterTests.swift` | 통과 (62) |
| `onelibrary-connect/tests/adapter.spec.ts` | `Tests/DJLinkKitTests/OneLibraryConnect/OneLibraryConnectAdapterTests.swift` | 통과 (62) |

### 단계 5 — db·앨범아트·태그 (원본 74: alphatheta-connect 46 + metadata-connect 28)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/tests/db/blankMetadata.spec.ts` | `Tests/DJLinkKitTests/DB/DBBlankMetadataTests.swift` | 통과 (4) |
| `alphatheta-connect/tests/db/getMetadata.spec.ts` | `Tests/DJLinkKitTests/DB/DBGetMetadataTests.swift` | 통과 (13) |
| `alphatheta-connect/tests/db/getPlaylist.spec.ts` | `Tests/DJLinkKitTests/DB/DBGetPlaylistTests.swift` | 통과 (3) |
| `alphatheta-connect/tests/db/getWaveforms.spec.ts` | `Tests/DJLinkKitTests/DB/DBGetWaveformsTests.swift` | 통과 (8) |
| `alphatheta-connect/tests/artwork/extraction.integration.test.ts` | `Tests/DJLinkKitTests/Artwork/ArtworkExtractionIntegrationTests.swift` | 통과 (5) |
| `alphatheta-connect/tests/artwork/parsers.spec.ts` | `Tests/DJLinkKitTests/Artwork/ArtworkParsersTests.swift` | 통과 (13) |
| `metadata-connect/test/extract.test.ts` | `Tests/DJLinkKitTests/MetadataConnect/MetadataConnectExtractTests.swift` | 통과 (15) |
| `metadata-connect/test/label.test.ts` | `Tests/DJLinkKitTests/MetadataConnect/MetadataConnectLabelTests.swift` | 통과 (13) |

### 단계 6 — mixstatus (원본 29)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/tests/mixstatus/index.spec.ts` | `Tests/DJLinkKitTests/MixStatus/MixStatusIndexTests.swift` | 통과 (29) |

### 단계 7 — 제어 (원본 11)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/tests/control/load.spec.ts` | `Tests/DJLinkControlTests/ControlLoadTests.swift` | 통과 (2) |
| `alphatheta-connect/tests/control/stagehand.spec.ts` | `Tests/DJLinkControlTests/ControlStagehandTests.swift` | 통과 (9) |

### 단계 8 — 패시브 (원본 31)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/tests/passive/alphatheta.spec.ts` | `Tests/DJLinkPassiveTests/PassiveAlphathetaTests.swift` | 통과 (22) |
| `alphatheta-connect/tests/passive/pcap-adapter.spec.ts` | `Tests/DJLinkPassiveTests/PassivePcapAdapterTests.swift` | 통과 (9) |

일부 시험은 원본처럼 조건이 맞을 때만 돈다(`.enabled(if:)`). 실제 음원 파일이 있어야 하는 앨범아트·태그 통합 시험, 암호화 픽스처가 있어야 하는 OneLibrary 시험이 그렇다. `@Test` 개수는 조건과 관계없이 같다.

### 시험 도우미 (원본, 시험 수에 들지 않음)

| 원본 파일 | Swift 파일 | 상태 |
|---|---|---|
| `alphatheta-connect/tests/utils.ts` | `Sources/DJLinkTestSupport/Mocks.swift`(`mockDevice`), `Tests/DJLinkKitTests/Support/TestHelpers.swift`(`readMock`) — 두 파일로 나뉘었다 | 통과 |
| `alphatheta-connect/tests/_data/*.dat` (3개) | `Tests/DJLinkKitTests/Fixtures/`의 `announce-cdj-2.dat`, `media-slot-usb.dat`, `status-simple.dat` — `Package.swift`의 `resources: [.copy("Fixtures")]`로 포함 | 통과 |
| `alphatheta-connect/tests/artwork/fixtures.ts` | `Tests/DJLinkKitTests/Artwork/ArtworkFixtures.swift` | 통과 |
| `alphatheta-connect/tests/localdb/fixtures/anlz-fixtures.ts` | `Tests/DJLinkKitTests/LocalDB/Support/LocalDBAnlzFixtures.swift` | 통과 |
| `alphatheta-connect/tests/localdb/fixtures/create-test-db.ts` | `Tests/DJLinkKitTests/LocalDB/Support/LocalDBCreateTestDB.swift` | 통과 |
| `alphatheta-connect/tests/localdb/fixtures/test-onelibrary.db` | `Tests/DJLinkKitTests/Fixtures/localdb/test-onelibrary.db` | 통과 |
| `onelibrary-connect/tests/fixtures/test-onelibrary.db` | `Tests/DJLinkKitTests/Fixtures/localdb/onelibrary-connect-test.db` — 파일 이름이 겹치지 않게 바꿨다 | 통과 |
| `alphatheta-connect/tests/localdb/native-sqlite.ts` | `Tests/DJLinkKitTests/LocalDB/Support/LocalDBNativeSQLite.swift` — SQLCipher는 패키지 의존이라 Node ABI에 따른 건너뛰기 조건이 없다 | 통과 |
| `alphatheta-connect/tests/__mocks__/ksyFileMock.js` | (없음) — `.ksy` 모듈 mock | 범위 밖 |
| `alphatheta-connect/tests/tsconfig.json` | (없음) — 빌드 설정 | 범위 밖 |

## 3. 원본 대응이 아닌 우리 시험

원본 시험에는 없고 이 패키지에서 더한 시험이다. 원본 시험의 입력·기대값은 건드리지 않고, 소켓·SQLCipher·CLI처럼 Swift 쪽에서 새로 생긴 경계와 PLAN §9의 고친 동작을 따로 검사한다. 시험은 LAN에 아무것도 보내지 않는다(PLAN §11). `@Test` 개수는 선언 기준이며 main의 현재 값이다. "기준선"은 1:1 기준선(`port/one-to-one`)에도 있는 파일, "main"은 main에서 더한 파일이다.

| Swift 시험 파일 | `@Test` | 하는 일 |
|---|---|---|
| `Tests/DJLinkKitTests/Infrastructure/InfrastructureTests.swift` | 9 | 기반 코드(`EventHub`, `TestClock`, 가짜 소켓 등)의 동작 |
| `Tests/DJLinkKitTests/Network/NetworkFlowTests.swift` | 8 | `ProlinkNetwork`의 connect·disconnect 흐름(가짜 소켓) |
| `Tests/DJLinkKitTests/RemoteDB/RemoteDBTransportTests.swift` | 12 | remotedb 연결을 가짜 TCP로 검사 |
| `Tests/DJLinkKitTests/RemoteDB/LiveTCPConnectionLoopbackTests.swift` | 8 | 실제 TCP 구현을 127.0.0.1에서만 검사. `DJLINK_LOOPBACK_TESTS=1`일 때만 돈다 |
| `Tests/DJLinkKitTests/RemoteDB/LiveTCPConnectionInterfaceTests.swift` | 4 | TCP를 인터페이스 주소로 묶을 때 주소 고르기와 연결 전 거부(소켓 없이, #40) |
| `Tests/DJLinkKitTests/NFS/NFSTransportTests.swift` | 14 | NFS RPC 전송을 가짜 UDP로 검사. CLI 안전을 위한 경로 검사 훅과 모든 클라이언트 닫기 포함 |
| `Tests/DJLinkKitTests/Network/CLISafetyOptInTests.swift` | 12 | CLI 안전을 위한 opt-in(번호 정책, announce 대상 필터, `IP_BOUND_IF` 묶기)이 기본값에서는 원본과 같고 켜면 막는 것 |
| `Tests/DJLinkKitTests/LocalDB/LocalDBReaderIntegrationTests.swift` | 29 | Kaitai를 대신한 PDB·ANLZ 바이트 리더의 실제 바이트 경계 |
| `Tests/DJLinkKitTests/LocalDB/CipherDatabaseColdOpenTests.swift` | 7 | SQLCipher 처음 열기 경쟁(DJCrate의 `CipherColdOpenTests`·`CipherLab`에서 옮김, §6). 별도 시험 프로세스를 띄우는 워커 시험(2개)이 포함된다 |
| `Tests/DJLinkKitTests/LocalDB/LocalDBMediaFailureSafetyTests.swift` | 1 | `throwsOnMediaQueryFailure` opt-in이 미디어 질의 실패를 오류로 전달하는 것 |
| `Tests/DJLinkControlTests/ControlNetworkTests.swift` | 2 | `ProlinkNetwork.control`이 연결 뒤에 만들어지는 것 |
| `Tests/DJLinkPassiveTests/PassiveFlowTests.swift` | 17 | 패시브 네트워크 전체 흐름(가짜 pcap). PLAN §9의 UDP 길이 시험(`UDP payload keeps every byte and a standard announce uses the full format`)도 이 파일에 있다 |
| `Tests/djlinkTests/CLIApplicationTests.swift` | 6 | CLI 실행 흐름과 종료 코드(가짜 실행기) |
| `Tests/djlinkTests/CLIArgumentsTests.swift` | 22 | 인자 해석(옵션 값 삼킴 방지, `play`·`pause` 거부, `--timeout`)(기준선은 23) |
| `Tests/djlinkTests/CLIFormatTests.swift` | 14 | 출력 형식 |
| `Tests/djlinkTests/CLISafetyTests.swift` | 11 | 안전 규칙(rekordbox 실행 확인, 가상 CDJ 번호, `--confirm`, 재생 상태 패킷, 경로 거부) |
| `Tests/djlinkTests/CLIFileWriterTests.swift` | 17 | 덮어쓰지 않는 파일 게시(임시 폴더만 쓴다): `link`·`RENAME_EXCL`·`O_EXCL` 순서, 1MiB 조각 쓰기, 쓰기 도중 취소 |
| `Tests/djlinkTests/CLIPublishCleanupTests.swift` | 4 | 막힌 파일 큐를 `cleanup()`·`run`이 3초까지 기다리는 것 |
| `Tests/djlinkTests/CLISignalHandlingTests.swift` | 5 | SIGHUP 정리 경로, SIGPIPE 무시, 닫힌 파이프 출력 |
| `Tests/djlinkTests/CLILocalTempCleanupTests.swift` | 13 | OneLibrary 임시 DB 추적·정리(부속 파일 포함, #16)(기준선은 7) |
| `Tests/djlinkTests/CLIRealSchedulerTests.swift` | 3 | 실제 `DispatchCLIScheduler`가 막힌 `DJLinkActor.queue`와 독립으로 도는 것(약 3초) |
| `Tests/djlinkTests/CLINFSGlobalsTests.swift` | 1 | 전역 NFS 경로 검사 훅의 설치·해제(`.serialized`) |
| `Tests/djlinkTests/CLIRuntimeTests.swift` | 47 | 가짜 소켓·시계·파일·NFS로 돌린 실행 경로: 인터페이스 묶기·서브넷 제한, 번호 정책, 중단 뒤 송신·쓰기 0회, 제한 시간, 정리, 종료 코드, NFS 경로 검사 |
| `Tests/djlinkTests/CLIDestinationSafetyTests.swift` | 5 | CLI 소켓 경계: 서브넷 밖 UDP는 0바이트, TCP는 연결하지 않고, NFS도 밖 장치를 거부하는 것 |
| `Tests/djlinkTests/CLIIndependentAbortTests.swift` | 6 | `DJLinkActor` 큐가 막혀도 신호·제한 시간이 즉시 중단·강제 종료를 일으키는 것 |
| `Tests/djlinkTests/CLIMediaFailureTests.swift` | 1 | 미디어 슬롯 조회 실패가 `metadata`의 종료 코드 1이 되는 것 |
| `Tests/djlinkTests/CLINFSWaitingSafetyTests.swift` | 3 | NFS RPC 읽기·재시도 대기를 닫기·취소가 구독·타이머까지 정리하는 것 |
| `Tests/djlinkTests/CLIReadySafetyTests.swift` | 2 | 시작 번호 거부가 ready 대기자를 모두 풀고 거부 번호를 노출하는 것 |
| `Tests/djlinkTests/CLIStagehandSafetyTests.swift` | 1 | 지원하지 않는 안전 정책이 있으면 Stagehand를 바이트를 보내기 전에 거부하는 것 |
| `Tests/djlinkTests/CLITCPRegistrySafetyTests.swift` | 5 | 닫힌 TCP를 장부에서 바로 지우고, 포트 조회 연결을 응답 직후 닫는 것. remotedb 질의 번호 로그 포함 |
| `Tests/djlinkTests/CLITCPSafetyTests.swift` | 2 | 포트 조회와 DB 연결이 고른 인터페이스를 요구하고, 해석 못 하면 연결하지 않는 것 |
| `Tests/DJLinkKitTests/Artwork/ArtworkUpstreamFixTests.swift` | 7 | **main.** PLAN §9 앨범아트 고침(mp4 atom 이름, APIC BOM, ID3 v2.3 확장 헤더) |
| `Tests/DJLinkKitTests/MetadataConnect/MetadataConnectUpstreamFixTests.swift` | 25 | **main.** PLAN §9 metadata-connect 고침(mp4 문자열 atom, ID3 프레임 ID, 빈 값, APIC BOM, 확장 헤더) |
| `Tests/DJLinkKitTests/Devices/DevicesUpstreamFixTests.swift` | 3 | **main.** PLAN §9 `getDeviceEnsured` 타이머·구독 정리 |
| `Tests/DJLinkKitTests/LocalDB/LocalDBUpstreamFixTests.swift` | 13 | **main.** PLAN §9 localdb 고침(PDB 사슬, 장치 제거 때 모든 DB 닫기, OneLibrary 임시 파일, ANLZ 큐 태그 잇기 #22, 알 수 없는 PSSI mood #26, 긴 ASCII 0x40 #13) |
| `Tests/DJLinkKitTests/MixStatus/MixStatusUpstreamFixTests.swift` | 7 | **main.** PLAN §9 mixstatus 고침 |
| `Tests/DJLinkKitTests/Network/NetworkUpstreamFixTests.swift` | 3 | **main.** PLAN §9 `bringOnline` bind 실패 때 만든 소켓 닫기 |
| `Tests/DJLinkKitTests/RemoteDB/RemoteDBUpstreamFixTests.swift` | 15 | **main.** PLAN §9 remotedb 응답이 CDJ가 먼저 보낸 메시지에 밀리지 않는 것(#46)과 질의 응답 시간 제한(#47) |
| `Tests/DJLinkKitTests/Status/StatusUpstreamFixTests.swift` | 8 | **main.** PLAN §9 위치 파서의 종류 바이트 검사와 비트 포트(50001) on-air |
| `Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJKeepAliveUpstreamFixTests.swift` | 1 | **main.** PLAN §9 keep-alive 54바이트 |
| `Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJReadyUpstreamFixTests.swift` | 3 | **main.** PLAN §9 `ready` 재호출과 번호 거부 때 대기자 풀기 |
| `Tests/DJLinkKitTests/VirtualCDJ/VirtualCDJStatusUpstreamFixTests.swift` | 2 | **main.** PLAN §9 `makeStatusPacket` 머리말 |
| `Tests/DJLinkControlTests/ControlUpstreamFixTests.swift` | 5 | **main.** PLAN §9 제어 재생 상태 패킷의 칸 배치 |
| `Tests/DJLinkPassiveTests/PassiveDevicesUpstreamFixTests.swift` | 3 | **main.** PLAN §9 패시브 `getDeviceEnsured` 타이머 정리(#23) |
| `Tests/DJLinkPassiveTests/PassiveLocalDBUpstreamFixTests.swift` | 3 | **main.** PLAN §9 패시브 localdb 고침(장치 제거 때 모든 DB 닫기, OneLibrary 임시 파일)(#23) |
| `Tests/DJLinkPassiveTests/PassivePcapUpstreamFixTests.swift` | 8 | **main.** PLAN §9 패시브 캡처 중 인터페이스가 사라지면 오류로 멈춤(#8) |
| `Tests/DJLinkPassiveTests/PassivePositionUpstreamFixTests.swift` | 1 | **main.** PLAN §9 패시브 위치 파서의 종류 바이트 검사 |
| `Tests/DJLinkPassiveTests/PassiveStatusUpstreamFixTests.swift` | 1 | **main.** PLAN §9 패시브 on-air(비트 포트 50001) |
| `Tests/DJLinkPassiveTests/PassiveRemoteDBUpstreamFixTests.swift` | 2 | **main.** PLAN §9 패시브 remotedb가 CDJ가 먼저 보낸 메시지를 건너뜀(#46), 닫힌 연결을 버리고 다시 연결(#47) |
| `Tests/DJLinkPassiveTests/PassiveCaptureTests.swift` | 2 | **main.** 실기 pcap 프레임(MAC 가림)이 패시브 경로를 지나는 것(#6) |
| `Tests/DJLinkKitTests/Status/BeatTests.swift` | 9 | **main.** 비트 0x28 해석과 능동 `BeatEmitter` 연결(#7, PROVENANCE §D) |
| `Tests/DJLinkPassiveTests/PassiveBeatTests.swift` | 3 | **main.** 패시브 비트 이벤트 연결과 종료(#7) |
| `Tests/djlinkTests/CLIBeatTests.swift` | 3 | **main.** CLI `status`·`passive`의 비트 출력(#7) |
| `Tests/djlinkTests/CLIWatchRecoveryTests.swift` | 9 | **main.** `watch`의 재접속·재시도·늦은 결과 버리기(#17) |

시험 수 합계(`@Test` 선언 기준, main의 현재 값):

| 시험 대상 | 원본 대응 | 우리 시험 | 합 | 1:1 기준선 합 |
|---|---|---|---|---|
| `DJLinkKitTests` | 580 | 200 | 780 | 683 |
| `DJLinkControlTests` | 11 | 7 | 18 | 13 |
| `DJLinkPassiveTests` | 31 | 40 | 71 | 48 |
| `djlinkTests` | 0 | 180 | 180 | 163 |
| 합 | 622 | 427 | 1,049 | 907 |

1:1 기준선(`port/one-to-one`)의 선언 수는 907개다(위 표의 마지막 칸, #26의 PSSI 시험 2개를 2026-10-16 기준선에도 더해 905개에서 늘었다). main은 PLAN §9 고치기 시험(`*UpstreamFixTests.swift`), 비트 0x28 시험(`BeatTests`·`PassiveBeatTests`·`CLIBeatTests`), CLI 복구 시험(`CLIWatchRecoveryTests` 등)이 더해져 수가 다르다. 기준선에서는 907개 중 조건이 맞을 때만 도는 13개(루프백 6개, 실제 음원이 필요한 앨범아트 통합 시험 5개, 자식 프로세스 안에서만 도는 SQLCipher 동시 열기 도우미 2개)를 건너뜀으로 셌다. 이 13개는 main에도 그대로 있다. Link Export 시험 519개까지 합친 전체 선언 수 1,568개와 조건부 30개의 분류는 [LINK-EXPORT-VALIDATION.md](LINK-EXPORT-VALIDATION.md)와 README "시험"에 있다. CLI 시험은 파일 21개에 180개다(기준선은 19개 파일에 163개). 시험 도우미 `Tests/djlinkTests/CLITestHarness.swift`는 `@Test`가 없다.

## 4. 우리가 더한 Swift 파일 (원본에 대응하는 파일이 없다)

원본이 Node·npm 패키지에 맡기던 일을 Swift에서 직접 해야 하는 곳과, 시험·안전 때문에 주입점을 만든 곳이다.

| Swift 파일 | 원본에서 이것이 맡던 일 |
|---|---|
| `Sources/DJLinkKit/Concurrency/DJLinkActor.swift` | Node 이벤트 루프 하나(직렬 실행) |
| `Sources/DJLinkKit/Concurrency/DJLinkClock.swift` | `setTimeout`·`setInterval`·`Date.now()`(시험은 `TestClock`) |
| `Sources/DJLinkKit/Concurrency/EventHub.swift` | `EventEmitter` |
| `Sources/DJLinkKit/Concurrency/AsyncMutex.swift` | `async-mutex` 패키지 |
| `Sources/DJLinkKit/Socket/BSDUDPSocket.swift` | `dgram` 소켓의 실제 구현 |
| `Sources/DJLinkKit/Socket/LiveTCPConnection.swift`, `Sources/DJLinkKit/Socket/TCPConnection.swift` | `net.Socket`과 `promise-socket`(remotedb가 쓰는 부분) |
| `Sources/DJLinkKit/Socket/SocketFactory.swift` | `dgram.createSocket`·`new net.Socket()`. 시험 프로세스에서 실제 소켓을 만들면 바로 실패하게 한다. `DJLINK_LOOPBACK_TESTS=1`일 때만 루프백 시험이 연다(PLAN §11) |
| `Sources/DJLinkKit/Socket/InterfaceProvider.swift` | `os.networkInterfaces()` |
| `Sources/DJLinkKit/Socket/CancellableUDPRead.swift` | 원본 `udpRead`의 취소 가능한 변형. 닫기·취소·시간 초과 때 대기자와 구독·타이머를 거둔다. 원본 `udpRead`는 그대로 두고 CLI의 RPC opt-in에서만 쓴다(CLI 안전을 위한 추가, [port-notes.md](port-notes.md) 3단계) |
| `Sources/DJLinkKit/Utils/Address4.swift` | `ip-address` 패키지의 `Address4` |
| `Sources/DJLinkKit/Utils/Bytes.swift` | Node `Buffer`의 읽기·쓰기(범위를 넘으면 `BufferRangeError`) |
| `Sources/DJLinkKit/Utils/DJLinkError.swift` | `new Error(message)` |
| `Sources/DJLinkKit/Utils/JSString.swift` | JS의 숫자·문자열 규칙(`String(number)`, `trim()` 등) |
| `Sources/DJLinkKit/Utils/Retry.swift` | `retry`·`promise-retry` 패키지 |
| `Sources/DJLinkKit/VirtualCDJ/DeviceReference.swift` | 여러 서비스가 나눠 쥐는 가상 CDJ `Device` 객체(참조 의미) |
| `Sources/DJLinkKit/Artwork/ArtworkNFSSeam.swift` | `artwork/`·`metadata.ts`가 `src/nfs`를 부르는 자리의 주입점 |
| `Sources/DJLinkKit/DB/DBSeams.swift` | `db/`가 localdb·remotedb·장치 관리자를 부르는 자리의 주입점 |
| `Sources/DJLinkKit/LocalDB/LocalDBSeams.swift`, `Sources/DJLinkKit/LocalDB/LocalDBSeamConformances.swift` | `localdb/`가 장치 관리자·상태·NFS를 부르는 자리의 주입점과, 1단계 형을 거기에 잇는 확장 |
| `Sources/DJLinkControl/ControlNetwork.swift` | `network.ts`의 `get control()` (`DJLinkControl`이 `ProlinkNetwork`를 확장한다) |
| `Sources/DJLinkPassive/PassiveLocalDBBackend.swift` | `passive/localdb.ts`가 쓰는 `MetadataORM`·`hydrateDatabase`·`OneLibraryAdapter`를 DJLinkKit에 잇는 실제 구현 |
| `Sources/CPcap/` (`module.modulemap`, `shim.h`) | libpcap을 부르는 시스템 라이브러리 선언 |
| `Sources/DJLinkTestSupport/` (`FakeInterfaceProvider`, `FakeTCPConnection`, `FakeUDPSocket`, `TestClock`) | 원본 시험의 `jest.mock('os')`, 가짜 소켓, `jest.useFakeTimers()`. `Mocks.swift`는 원본 `tests/utils.ts`(§2) |
| `Sources/djlink/*.swift` | 원본 `cli/index.ts`를 나눈 것(§1 단계 9) |
| `Sources/djlink/CLIWatchTracks.swift` | main에서 더한 파일. `watch`의 곡별 조회 중복 억제·재시도·늦은 결과 버리기(#17). 원본 `cli/index.ts`의 곡 ID만 비교하는 `lastTid` 자리 |
| `Sources/DJLinkKit/Status/BeatTypes.swift`, `BeatUtils.swift`, `BeatEmitter.swift` | main에서 더한 파일. 원본에 없는 비트 포트(50001) 0x28 패킷 수신: `CDJStatus.BeatState`, `beatFromPacket`, `BeatEmitter`(#7, [PROVENANCE.md](../PROVENANCE.md) §D) |
| `Sources/DJLinkPassive/PassiveBeat.swift` | main에서 더한 파일. 패시브 어댑터의 비트 포트에서 0x28만 읽는 `PassiveBeatEmitter`(#7) |

시험 쪽 도우미 중 원본 대응이 없는 것: `Tests/DJLinkKitTests/DB/DBTestHelpers.swift`, `Tests/DJLinkKitTests/Network/NetworkTestHelpers.swift`, `Tests/DJLinkKitTests/LocalDB/Support/LocalDBTestDependencies.swift`(원본 시험의 `jest.mock` 자리를 주입으로 바꾼 가짜들), `Tests/DJLinkKitTests/LocalDB/Support/LocalDBPdbBuilder.swift`(§6), `Tests/djlinkTests/CLITestHarness.swift`(CLI 시험이 쓰는 가짜 소켓·시계·파일 시스템 모음).

## 5. 이름·주입점 요약

- 원본 `jest.mock('모듈')`은 그 모듈을 init 인자나 프로토콜로 주입받게 하고 시험에서 가짜를 넣는 방식으로 바꿨다([porting-guide.md](porting-guide.md) §6). 위 §4의 `*Seam*`·`NetworkDependencies.swift`·`DBSeams.swift`가 그 자리다.
- 대표 형 이름은 원본 파일의 `export`를 열어 정했다.

## 6. DJCrate에서 옮긴 리더 파일

localdb의 `.ksy`(Kaitai, EPL-1.0)는 쓰지 않고, 같은 저작자의 MIT 저장소 DJCrate(`6b2954892257f7d96aee1328c9f654e267921333`)의 리더를 읽기에 필요한 부분만 옮겨 출발점으로 삼았다(PLAN §7). 그 위에 원본 localdb의 바깥 모양을 그대로 만들었다. 출처 고지는 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)에 있다.

| Swift 파일 | DJCrate 출처 | 옮긴 범위 |
|---|---|---|
| `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBPdbFile.swift` | `PdbFile.swift` | 파일 머리, 표 포인터, 표별 훑기 결과, 읽기 문제 목록(`PdbIssue`) |
| `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBPdbPage.swift` | `PdbPage.swift` | 쪽 머리, 행 슬롯, 쪽 |
| `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBPdbReader.swift` | `PdbReader` | 쪽·산 행 순회. `exportExt`와 쓰기 모델은 옮기지 않았다 |
| `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBPdbRows.swift` | `PdbRows.swift` | localdb가 읽는 표의 칸(원본 칸 이름으로 내보낸다). `exportExt`의 My Tag 행(`PdbRows.tag`)은 옮기지 않았다 |
| `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBPdbString.swift` | `PdbString.swift` | 문자열 디코더만(인코더는 옮기지 않았다) |
| `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBPdbTable.swift` | `PdbTable.swift` | 표 종류(`export.pdb`·`exportExt.pdb`)와 파일 종류 |
| `Sources/DJLinkKit/LocalDB/Rekordbox/LocalDBAnlzFile.swift` | `AnlzFile`·`AnlzColorWaveform`·`AnlzCueTags`·`AnlzMasks` | ANLZ 구역 읽기, 큐·색 파형 칸, 프레이즈(PSSI) 마스크 풀기. 원본 localdb 단위(ms)와 12바이트 픽스처 머리에 맞췄다 |
| `Sources/DJLinkKit/LocalDB/OneLibrary/LocalDBCipherDatabase.swift` | `CipherDatabase.swift` | SQLCipher 연결·초기화·질의. 처음 열기 경쟁을 막는 `sqlite3_initialize` 선호출이 들어 있다 |
| `Tests/DJLinkKitTests/LocalDB/Support/LocalDBPdbBuilder.swift` | `PdbBuilder` | 시험용 합성 PDB 조립기(읽기 시험에 필요한 부분만) |
| `Tests/DJLinkKitTests/LocalDB/CipherDatabaseColdOpenTests.swift` | `Tests/djcTests/CipherColdOpenTests.swift`, `Sources/djc/Lab/CipherLab.swift` | SQLCipher 처음 열기 경쟁 시험 |

PLAN §7이 후보로 적은 DJCrate의 `OneLibraryReader`는 옮기지 않았다. OneLibrary는 원본 onelibrary-connect를 옮긴 `OneLibraryAdapter`가 읽는다.
