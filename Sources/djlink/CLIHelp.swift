// 도움말. 사용자에게 보이는 글이라 한국어로 쓴다.

private let commonOptionsHelp = """
      --iface NAME        쓸 네트워크 인터페이스(예: en7). 없으면 처음 보이는 장치로 정한다
      --vcdj-id N         가상 CDJ 번호(기본 7). 1~6은 --allow-player-id를 같이 줄 때만 허용
      --allow-player-id   1~6 번호를 일부러 쓸 때만 준다(실제 플레이어와 겹치면 위험하다)
      --verbose           라이브러리 debug·trace 로그도 표준 오류로 낸다
    """

private let safetyHelp = """
    안전 규칙:
      - 공연이나 리허설 중인 네트워크에서 돌리지 않는다. 시험용 스위치에 장비 한두 대만 묶는다.
      - 같은 Mac에서 rekordbox·rekordboxAgent가 돌고 있으면 UDP 50000~50002를 잡지 않고 끝낸다.
      - 가상 CDJ 번호 기본값은 7이다. 1~6은 --allow-player-id를 같이 줄 때만 쓴다.
      - 제어 명령은 --confirm "<장치 이름>"이 대상 장치 이름과 정확히 같을 때만 보낸다.
    """

func helpText(_ subcommand: CLISubcommand?) -> String {
    switch subcommand {
    case nil:
        return """
            djlink — PRO DJ LINK 네트워크 실기 확인용 CLI

            사용법: djlink <명령> [옵션]

            명령:
              devices     장치 목록(announce만 듣는다, 아무것도 보내지 않는다)
              watch       원본 cli 흐름: 참여 → 곡이 바뀔 때마다 제목 출력(--download-dir를 주면 파일도 받는다)
              status      상태·정밀 위치·on-air 출력
              metadata    remotedb/db로 메타데이터·파형·그리드·큐 요약 출력
              fetch       NFS로 파일 받기(export.pdb, exportLibrary.db, ANLZ 등)
              mixstatus   MixstatusProcessor 이벤트 출력
              control     곡 올리기·재생·정지(--confirm 필요)
              passive     libpcap으로 패시브 모니터링(아무것도 보내지 않는다)

            `djlink <명령> --help`로 명령별 도움말을 본다.
            끝나는 법: Ctrl-C. 종료 코드는 0 정상, 1 실행 실패, 2 사용법·안전 규칙 거부, 130 중단.

            \(safetyHelp)
            """
    case .devices:
        return """
            사용법: djlink devices [--seconds N] [--verbose]

            announce(UDP 50000)를 N초(기본 5) 듣고 장치 목록을 출력한다. 가상 CDJ로 참여하지 않는다.

              --seconds N   듣는 시간(1~3600, 기본 5)
              --verbose     라이브러리 debug·trace 로그도 낸다
            """
    case .watch:
        return """
            사용법: djlink watch [--iface NAME] [--vcdj-id N] [--download-dir DIR]

            원본 src/cli/index.ts와 같은 흐름이다. 가상 CDJ로 참여하고, CDJ가 곡을 바꿀 때마다 제목을 출력한다.
            원본은 파일을 현재 폴더에 무조건 쓰지만, 이 명령은 --download-dir를 준 경우에만 그 폴더에 쓴다.
            원본처럼 끝없이 돌지 않고 Ctrl-C로 끝낸다.

            옵션:
            \(commonOptionsHelp)
              --download-dir DIR  곡 파일을 받을 폴더(없으면 제목만 출력)
            """
    case .status:
        return """
            사용법: djlink status [--all] [--position-interval-ms N] [공통 옵션]

            상태, 정밀 위치(CDJ-3000 이상), on-air를 한 줄씩 출력한다. 상태는 핵심 값이 바뀔 때만 낸다.

            옵션:
            \(commonOptionsHelp)
              --all               상태 패킷을 모두 출력
              --position-interval-ms N
                                  장치마다 정밀 위치 출력 간격(0~60000, 기본 500)
            """
    case .metadata:
        return """
            사용법: djlink metadata --device N --slot usb|sd --track-id ID [공통 옵션]

            remotedb/db로 곡 메타데이터·비트 그리드·파형·큐 요약을 출력한다. 곡 종류는 rekordbox(rb)다.

            옵션:
              --device N        곡이 있는 장치 번호
              --slot usb|sd     곡이 있는 슬롯
              --track-id ID     곡 번호
            \(commonOptionsHelp)
            """
    case .fetch:
        return """
            사용법: djlink fetch --device N --slot usb|sd --path PATH --out FILE [--join] [공통 옵션]

            NFS로 장치의 파일 하나를 받아 FILE에 쓴다(예: PIONEER/rekordbox/export.pdb, exportLibrary.db, ANLZ).
            PIONEER/extracted, PIONEER/CDP, djprofile.nxs 경로는 거부한다. 이미 있는 FILE은 덮어쓰지 않는다.
            기본은 가상 CDJ로 참여하지 않고 듣기만 한다.

            옵션:
              --device N        파일이 있는 장치 번호
              --slot usb|sd     슬롯
              --path PATH       슬롯 안의 경로
              --out FILE        쓸 파일
              --join            가상 CDJ로 참여한 뒤 받는다
            \(commonOptionsHelp)
            """
    case .mixstatus:
        return """
            사용법: djlink mixstatus [공통 옵션]

            MixstatusProcessor의 nowPlaying·stopped·setStarted·setEnded 이벤트를 출력한다.

            옵션:
            \(commonOptionsHelp)
            """
    case .control:
        return """
            사용법:
              djlink control load  --device N --slot usb|sd|rb --track-id ID [--source-device M] [--track-type rb|unanalyzed] --confirm "<장치 이름>"
              djlink control play  --device N --confirm "<장치 이름>"
              djlink control pause --device N --confirm "<장치 이름>"

            공연 중인 장비를 움직이는 명령이다. --confirm이 대상 장치 이름(devices에 보이는 이름)과 정확히 같지 않으면 아무것도 보내지 않는다.
            대상 장치를 확인하기 전에는 가상 CDJ로 참여하지 않는다. play·pause는 능동 연결의 재생 상태 패킷(0x00 재생, 0x01 정지)을 보낸다.
            주의: 원본 makePlaystatePacket은 칸 번호(0~3)와 장치 번호를 그대로 견준다(칸 번호가 한 칸 어긋났을 수 있다).
            1:1을 마치기 전에는 고치지 않으므로, 보낸 뒤 출력되는 after: 줄로 실제 장치가 움직였는지 확인한다.

            옵션:
              --device N            명령을 받을 장치 번호
              --confirm NAME        대상 장치 이름(필수)
              --source-device M     load: 곡이 있는 장치 번호(기본은 --device)
              --slot usb|sd|rb      load: 곡이 있는 슬롯
              --track-id ID         load: 곡 번호
              --track-type TYPE     load: rb(기본) 또는 unanalyzed
            \(commonOptionsHelp)
            """
    case .passive:
        return """
            사용법: djlink passive --iface NAME [--position-interval-ms N]

            libpcap으로 NAME 인터페이스의 PRO DJ LINK 패킷을 보기만 한다. 아무것도 보내지 않는다.
            BPF 접근 권한(보통 root 또는 ChmodBPF)이 필요하다.

            옵션:
              --iface NAME        캡처할 인터페이스(필수)
              --position-interval-ms N
                                  정밀 위치 출력 간격(0~60000, 기본 500)
            """
    }
}
