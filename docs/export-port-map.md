# Link Export 파일·시험 대응

고정 원본: rbxport `90bfb53da59c5b2c3f0b76101601f30a6b74ab2b`. 원본 이름·순서 대조는 `python3 scripts/export-port-status.py --strict`로 한다(시험을 돌리지 않는 정적 검사). 범위와 설계는 [LINK-EXPORT-PLAN.md](LINK-EXPORT-PLAN.md), 시험 구성은 [검증 기록](LINK-EXPORT-VALIDATION.md)에 있다.

## 서버 소스

| 원본 (`crates/`) | Swift (`Sources/`) |
|---|---|
| `rbl-prolink/src/lib.rs` | `DJLinkExportProtocol/Prolink.swift` |
| `rbl-nfs/src/{xdr,rpc,vfs,lib,net}.rs` | `DJLinkExportNFS/{Xdr,Rpc,Vfs,Server,Net}.swift` |
| `rbl-dbserver/src/{lib,catalog,item,keys,filter,session,net}.rs` | `DJLinkExportDBServer/{Lib,Catalog,Item,Keys,Filter,Session,Net}.swift` |
| `rbl-link/src/{join,interface_mode,watch,beacon,catalog,files,blobs,lib}.rs` | `DJLinkExport/{Join,InterfaceMode,Watch,Beacon,Catalog,Files,Blobs,LinkExport}.swift` |
| `rbl-anlz/src/{lib,write,grid,cues,phrase,vocal,encode}.rs` | `DJLinkExportANLZ/{Anlz,Write,Grid,Cues,Phrase,Vocal,Encode}.swift` |
| `rbl-index/src/{lib,strings,view,filter,smart,key,related,category,file_time,testing}.rs` | `DJLinkExportModel/{Library,Strings,View,Filter,Smart,Key,Related,Category,FileTime,Testing}.swift` |
| `rbl-core/src/xml.rs` | `DJLinkExportModel/Xml.swift` |
| `rbl-db/src/{details,export_info}.rs 값형` | `DJLinkExportModel/{Details,ExportInfo}.swift` |
| `서버 전송 경계 (Swift 자체 구현)` | `DJLinkExportSupport/{ExportSockets,BSDTCPListener,DualStackUDPSocket,AtomicValues,MonotonicClock}.swift` |
| `루프백 전송·외부 픽스처 경계 (Swift 자체 구현)` | `DJLinkExportTestSupport/{FakeExportSockets,UpstreamFixtures}.swift` |
| `rbl-fakecdj/src/lib.rs 및 rbl-db/src/fixture.rs의 통합 시험 준비 경로` | `../Tests/DJLinkExportTests/ExportIntegrationSupport.swift` |
| `rbl-fakecdj/src/lib.rs의 실제 소켓 클라이언트 (루프백 시험용)` | `../Tests/DJLinkExportTests/FakeCdjClient.swift` |

## 시험 파일

각 원본 파일의 시험 이름·순서를 그대로 대응한다. 인라인 시험은 해당 원본 소스 파일을 기준으로 한다. `rbl-link/tests/beacon.rs`의 원본 ignore 2개도 사유를 유지한다.

| 구분 | 원본 (`crates/`) | Swift (`Tests/`) | 원본 개수 |
|---|---|---|---|
| core | `rbl-prolink/tests/packets.rs` | `DJLinkExportProtocolTests/PacketsTests.swift` | 39 |
| core | `rbl-nfs/tests/protocol.rs` | `DJLinkExportNFSTests/ProtocolTests.swift` | 73 |
| core | `rbl-dbserver/tests/messages.rs` | `DJLinkExportDBServerTests/MessagesTests.swift` | 24 |
| core | `rbl-dbserver/tests/session.rs` | `DJLinkExportDBServerTests/SessionTests.swift` | 52 |
| core | `rbl-dbserver/tests/my_tags.rs` | `DJLinkExportDBServerTests/MyTagsTests.swift` | 7 |
| core | `rbl-dbserver/tests/cue_writes.rs` | `DJLinkExportDBServerTests/CueWritesTests.swift` | 9 |
| core | `rbl-dbserver/tests/release.rs` | `DJLinkExportDBServerTests/ReleaseTests.swift` | 3 |
| core | `rbl-dbserver/tests/corpus.rs` | `DJLinkExportDBServerTests/CorpusTests.swift` | 3 |
| core | `rbl-dbserver/src/item.rs` | `DJLinkExportDBServerTests/ItemTests.swift` | 3 |
| core | `rbl-dbserver/src/filter.rs` | `DJLinkExportDBServerTests/FilterTests.swift` | 3 |
| core | `rbl-link/src/join.rs` | `DJLinkExportTests/JoinTests.swift` | 12 |
| core | `rbl-link/src/lib.rs` | `DJLinkExportTests/LinkSourceTests.swift` | 2 |
| core | `rbl-link/src/catalog.rs` | `DJLinkExportTests/CatalogTests.swift` | 25 |
| core | `rbl-link/src/files.rs` | `DJLinkExportTests/FilesTests.swift` | 5 |
| core | `rbl-link/src/interface_mode.rs` | `DJLinkExportTests/InterfaceModeTests.swift` | 5 |
| core | `rbl-link/src/beacon.rs` | `DJLinkExportTests/BeaconUnitTests.swift` | 33 |
| core | `rbl-link/tests/rebind.rs` | `DJLinkExportTests/RebindTests.swift` | 2 |
| core | `rbl-link/tests/link.rs` | `DJLinkExportTests/LinkTests.swift` | 3 |
| core | `rbl-link/tests/blobs.rs` | `DJLinkExportTests/BlobsTests.swift` | 10 |
| core | `rbl-link/tests/beacon.rs` | `DJLinkExportTests/BeaconTests.swift` | 8 |
| anlz | `rbl-anlz/src/lib.rs` | `DJLinkExportANLZTests/AnlzTests.swift` | 1 |
| anlz | `rbl-anlz/src/cues.rs` | `DJLinkExportANLZTests/CuesTests.swift` | 2 |
| anlz | `rbl-anlz/src/grid.rs` | `DJLinkExportANLZTests/GridTests.swift` | 8 |
| anlz | `rbl-anlz/src/phrase.rs` | `DJLinkExportANLZTests/PhraseSourceTests.swift` | 1 |
| anlz | `rbl-anlz/src/encode.rs` | `DJLinkExportANLZTests/EncodeTests.swift` | 16 |
| anlz | `rbl-anlz/tests/parse.rs` | `DJLinkExportANLZTests/ParseTests.swift` | 32 |
| anlz | `rbl-anlz/tests/phrase.rs` | `DJLinkExportANLZTests/PhraseTests.swift` | 16 |
| anlz | `rbl-anlz/tests/grid_save.rs` | `DJLinkExportANLZTests/GridSaveTests.swift` | 2 |
| model | `rbl-index/src/strings.rs` | `DJLinkExportModelTests/StringsTests.swift` | 5 |
| model | `rbl-index/src/key.rs` | `DJLinkExportModelTests/KeyTests.swift` | 2 |
| model | `rbl-index/src/filter.rs` | `DJLinkExportModelTests/FilterSourceTests.swift` | 3 |
| model | `rbl-index/src/related.rs` | `DJLinkExportModelTests/RelatedTests.swift` | 5 |
| model | `rbl-index/src/view.rs` | `DJLinkExportModelTests/ViewSourceTests.swift` | 1 |
| model | `rbl-index/src/smart.rs` | `DJLinkExportModelTests/SmartTests.swift` | 19 |
| model | `rbl-index/tests/views.rs` | `DJLinkExportModelTests/ViewsTests.swift` | 31 |
| model | `rbl-index/tests/categories.rs` | `DJLinkExportModelTests/CategoriesTests.swift` | 2 |
| model | `rbl-index/tests/smartlists.rs` | `DJLinkExportModelTests/SmartlistsTests.swift` | 5 |
| model | `rbl-index/tests/unanalysed.rs` | `DJLinkExportModelTests/UnanalysedTests.swift` | 1 |
| model | `rbl-index/tests/filter.rs` | `DJLinkExportModelTests/FilterTests.swift` | 12 (1개 `.disabled`) |
| model | `rbl-index/tests/file_created.rs` | `DJLinkExportModelTests/FileCreatedTests.swift` | 7 (1개 `.disabled`) |
| xml | `rbl-core/src/xml.rs` | `DJLinkExportModelTests/XmlTests.swift` | 2 |
| loopback | `rbl-fakecdj/tests/loopback.rs` | `DJLinkExportTests/LoopbackTests.swift` | 8 (`DJLINK_LOOPBACK_TESTS=1`일 때만 실행) |

루프백을 뺀 합계는 494개다(서버 core 321, ANLZ 78, 서버 메모리 모델 93, XML 스캐너 2). 루프백 8개를 더하면 원본 대응은 502개다. `.disabled`는 4개다. Beacon 2개는 원본 ignore 사유를 따르고, 디스크 캐시를 거치는 `a_snapshot_keeps_the_tag_categories`와 폴더 브라우저의 `a_folder_sorts_its_tracks_and_loose_files_by_creation_together`는 서버 범위 밖이라 이름만 남겼다.

`loopback` 8개는 실제 127.0.0.1 소켓을 열어 `DJLINK_LOOPBACK_TESTS=1`(`scripts/ci.sh --loopback`)일 때만 돌고 기본 실행에서는 건너뛴다. 그래서 494개와 따로 센다. Export 소켓 가드는 루프백 시험이 아니면 실제 소켓을 막고, 루프백 시험에서도 TCP는 127.0.0.1·::1에만 묶고 그쪽으로만 연결하며 UDP는 127.0.0.1·::1로만 보낸다. UDP RPC 소켓은 원본처럼 0.0.0.0에 묶은 뒤 인터페이스를 고정하므로 보내는 주소를 검사한다(#28). 실제 소켓을 쓰는 가짜 CDJ 클라이언트는 가짜 소켓 버스용 `ExportIntegrationSupport.swift`와 따로 `FakeCdjClient.swift`에 둔다.

## 의존 범위의 제한

`rbl-index` 시험 149개를 다 옮기지는 않았다. 서버가 쓰는 메모리 알고리즘·파일 생성 시각의 원본 시험 93개와 `rbl-core` XML 2개만 대응했다. DB 적재·쓰기, cloud/drive 매핑 적재, 디스크 캐시, XML export, device export, 느슨한 음원 폴더 브라우저 등 앱 의존 시험은 서버 범위 밖이다. `Source` 입력 스냅샷은 호출자가 제공한다. 통합 시험의 SQL fixture 구축/적재는 동일한 합성 행을 메모리에 준비하는 코드로 바꾸었고 해당 위치에 이유를 표시했다.

픽스처 규칙은 [LINK-EXPORT-PLAN.md](LINK-EXPORT-PLAN.md)의 "픽스처"에 있다.

## Swift 전송·동시성 대응

Rust의 `Arc`/원자값·잠금/스레드는 직렬 `DJLinkActor`, 참조형 공유 셀·잠금, 주입 소켓/시계로 옮긴다. `Instant`의 경과 시간은 단조 시계로 유지한다. OS UDP 옵션·TCP keepalive·즉시 재바인딩을 위한 해제 대기는 실제 전송 경계에서 처리한다. 시험은 실제 TCP/UDP listen/connect를 하지 않는다(위 `loopback` 8개만 `DJLINK_LOOPBACK_TESTS=1`일 때 127.0.0.1에서 연다).

원본의 병렬 색인/파일 메타데이터 구축은 Swift에서 같은 행 순서와 결과로 직렬 수행한다. 실제 처리량·지연은 실기 확인 전이다. 기존 MIT 클라이언트의 수신 상태 파서와 Rust 파서의 다른 길이·반올림 경계는 Export 어댑터에서 처리한다.

## 원본 기준선 뒤에 더한 시험

`port/rbxport-one-to-one` (`03d3371`)이 원본과 같은 기준선이다. 그 뒤 원본과 다르게 고친 곳의 자체 회귀를 원본 대응과 따로 더했다. 원본 대응 시험의 입력·기대값은 바꾸지 않았다. 파일 목록과 고친 내용은 [검증 기록](LINK-EXPORT-VALIDATION.md#시험-구성), 실기 근거는 [실기 기록](LINK-EXPORT-HARDWARE.md)과 [레거시 큐 기록](LINK-EXPORT-LEGACY-CUES.md)에 있다.
