import DJLinkExportProtocol
import DJLinkExportSupport
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: rbxport/crates/rbl-link/src/watch.rs (90bfb53).
import DJLinkKit

@DJLinkActor public final class Watcher {
    private let socket: any UDPSocket
    private let clock: any DJLinkClock
    private let report: @DJLinkActor ([Player]) -> Void
    private var table = DeviceTable()
    private var list: [Player] = []
    private let resources: WatcherResources
    private var timer: TimerHandle? {
        get { resources.timer }
        set { resources.timer = newValue }
    }
    private let started: Double
    private var last_report: Double
    private var stopped = false
    private init(_ socket: any UDPSocket, _ clock: any DJLinkClock, _ report: @escaping @DJLinkActor ([Player]) -> Void)
    {
        self.resources = WatcherResources(socket, clock)
        self.socket = socket
        self.clock = clock
        self.report = report
        started = clock.nowMilliseconds()
        last_report = started
    }
    public static func start(
        _ announce_port: UInt16, _ report: @escaping @DJLinkActor ([Player]) -> Void,
        socketFactory: any ExportSocketFactory = LiveExportSocketFactory.shared,
        clock: any DJLinkClock = MonotonicClock.shared
    ) async throws -> Watcher {
        let socket = try socketFactory.createUDPSocket(reuseAddr: true)
        do {
            _ = try await socket.bind(port: Int(announce_port), address: "0.0.0.0")
            if let checked = socket as? any ServerUDPSocket {
                try checked.setBroadcastChecked(true)
            } else {
                socket.setBroadcast(true)
            }
        } catch {
            try? await udpClose(socket)
            throw error
        }
        let watcher = Watcher(socket, clock, report)
        socket.onMessage { [weak watcher] bytes, _ in
            guard let watcher, !watcher.stopped else { return }
            if let packet = try? KeepAlive.decode(Array(bytes.prefix(512))) {
                watcher.table.observe(packet, UInt64(max(watcher.clock.nowMilliseconds() - watcher.started, 0)))
            }
            watcher.poll()
        }
        watcher.timer = clock.setInterval(.ms(200)) { [weak watcher] in watcher?.poll() }
        return watcher
    }
    private func poll() {
        guard !stopped else { return }
        let now = clock.nowMilliseconds()
        _ = table.expire(UInt64(max(now - started, 0)))
        if now - last_report >= 500 {
            last_report = now
            list = table.peers().map {
                Player(number: $0.device_number, name: $0.name, address: $0.ip, kind: $0.device_type, last_seen: now)
            }
            report(list)
        }
    }
    public func peers() -> [Player] { list }
    public func stop() async {
        guard !stopped else { return }
        stopped = true
        clock.clearTimeout(timer)
        timer = nil
        if let server = socket as? any ServerUDPSocket {
            try? await server.shutdown()
        } else {
            try? await udpClose(socket)
        }
    }
    deinit {
        let resources = resources
        Task { @DJLinkActor in resources.close() }
    }
}

// macOS 15.0에서도 비격리 deinit이 소켓을 직접 넘기지 않고 정리를 요청한다.
@DJLinkActor private final class WatcherResources {
    let socket: any UDPSocket
    let clock: any DJLinkClock
    var timer: TimerHandle?
    init(_ socket: any UDPSocket, _ clock: any DJLinkClock) {
        self.socket = socket
        self.clock = clock
    }
    func close() {
        clock.clearTimeout(timer)
        timer = nil
        try? socket.close(nil)
    }
}
