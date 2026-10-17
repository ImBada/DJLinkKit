// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
import DJLinkExportSupport
import DJLinkKit
// 원본: crates/rbl-nfs/src/net.rs
// 고정 커밋: 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public enum Net {
    private static let DATAGRAM = 65535
    private static let SOCKET_BUFFER = 0x10000
    private static let POLL: Duration = .milliseconds(100)
    // 원본 blocking recv의 종료·오류 경계를 이벤트와 주입한 시계로 옮긴다.
    @DJLinkActor
    private final class Serving {
        let server: Server, socket: any UDPSocket, stop: AtomicBool
        let clock: any DJLinkClock, receiver = Receiver()
        let closeOnFinish: Bool
        let program: String?
        var listeners: [SocketListener] = [], timer: TimerHandle?, completed = false
        var result: (any Error)?, waiters: [CheckedContinuation<Void, any Error>] = []
        init(
            _ server: Server, _ socket: any UDPSocket, _ stop: AtomicBool, _ clock: any DJLinkClock,
            closeOnFinish: Bool = false, program: String? = nil
        ) throws {
            self.server = server
            self.socket = socket
            self.stop = stop
            self.clock = clock
            self.closeOnFinish = closeOnFinish
            self.program = program
            if let configurable = socket as? any ServerUDPSocket {
                try configurable.setBroadcastChecked(true)
            } else {
                socket.setBroadcast(true)
            }
            try socket.setReceiveBufferSize(Net.SOCKET_BUFFER)
            try socket.setSendBufferSize(Net.SOCKET_BUFFER)
            listeners.append(
                socket.onMessage { [weak self] bytes, from in
                    guard let self, !self.completed else { return }
                    if self.stop.load() {
                        self.finish(nil)
                        return
                    }
                    self.server.logger.trace(
                        "RPC datagram received", from.address, from.port, min(bytes.count, Net.DATAGRAM))
                    let peer = Self.peer(from.address)
                    guard
                        let reply = self.server.handle_on(
                            Array(bytes.prefix(Net.DATAGRAM)), peer, UInt16(truncatingIfNeeded: from.port),
                            self.receiver)
                    else { return }
                    // 원본 send_to 실패는 해당 송신만 버리고 serving을 계속한다.
                    let started = self.clock.now()
                    self.socket.send(
                        reply, port: from.port, address: from.address,
                        callback: { [weak self] error, sent in
                            guard let self else { return }
                            if let error {
                                self.server.logger.warn(
                                    "could not send an RPC reply", from.address, from.port, String(describing: error),
                                    reply.count)
                            } else {
                                self.server.logger.trace(
                                    "RPC reply sent", from.address, from.port, sent,
                                    self.clock.now().timeIntervalSince(started) * 1000000)
                            }
                        })
                })
            listeners.append(
                socket.onError { [weak self] error in
                    guard let self else { return }
                    if Net.is_timeout(error) { return }
                    if (error as? SystemCallError)?.errno == ECONNRESET
                        || ((error as NSError).domain == NSPOSIXErrorDomain
                            && (error as NSError).code == Int(ECONNRESET))
                    {
                        self.server.logger.trace("a peer went away; ignored", String(describing: error))
                        return
                    }
                    self.finish(error)
                })
            timer = clock.setInterval(Net.POLL) { [self] in
                if stop.load() { finish(nil) }
            }
            if stop.load() { finish(nil) }
        }
        private static func peer(_ address: String) -> Address4 {
            if let v4 = try? Address4(address) { return v4 }
            var value = in6_addr()
            let valid = address.withCString { inet_pton(AF_INET6, $0, &value) } == 1
            if valid {
                let bytes = withUnsafeBytes(of: value) { Array($0) }
                if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
                    return Address4.fromInteger(Int(bytes.suffix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }))
                }
            }
            return try! Address4("0.0.0.0")
        }
        func finish(_ error: (any Error)?) {
            guard !completed else { return }
            completed = true
            result = error
            for listener in listeners { socket.off(listener) }
            listeners.removeAll()
            clock.clearInterval(timer)
            timer = nil
            if let error, let program {
                server.logger.error("RPC socket stopped; players cannot read files", program, String(describing: error))
            }
            if closeOnFinish { try? socket.close() }
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { if let error { waiter.resume(throwing: error) } else { waiter.resume() } }
        }
        func wait() async throws {
            if completed {
                if let result { throw result }
                return
            }
            try await withCheckedThrowingContinuation { waiters.append($0) }
        }
    }
    public static func is_timeout(_ error: any Error) -> Bool {
        if let call = error as? SystemCallError { return call.errno == EWOULDBLOCK || call.errno == ETIMEDOUT }
        let error = error as NSError
        return error.domain == NSPOSIXErrorDomain && (error.code == Int(EWOULDBLOCK) || error.code == Int(ETIMEDOUT))
    }
    @DJLinkActor
    public static func serve(
        _ server: Server, _ socket: any UDPSocket, _ stop: AtomicBool, clock: any DJLinkClock = SystemClock.shared
    ) async throws {
        let serving = try Serving(server, socket, stop, clock)
        try await serving.wait()
    }
    @DJLinkActor
    public final class Bound {
        private let stop: AtomicBool, server: Server
        private var loops: [Serving], sockets: [any UDPSocket]
        private let portmap: AddressInfo, mount: AddressInfo, nfs: AddressInfo
        private init(
            _ stop: AtomicBool, _ loops: [Serving], _ sockets: [any UDPSocket], _ portmap: AddressInfo,
            _ mount: AddressInfo, _ nfs: AddressInfo, _ server: Server
        ) {
            self.stop = stop
            self.loops = loops
            self.sockets = sockets
            self.portmap = portmap
            self.mount = mount
            self.nfs = nfs
            self.server = server
        }
        public static func start(
            _ exports: Exports, _ address: String, _ portmap_port: UInt16, _ mount_port: UInt16, _ nfs_port: UInt16,
            _ export_host: String?, _ up: AtomicUInt8?,
            socketFactory: any ExportSocketFactory = LiveExportSocketFactory.shared,
            clock: any DJLinkClock = SystemClock.shared,
            interfaceProvider: any InterfaceProvider = SystemInterfaceProvider(), logger: any Logger = noopLogger
        ) async throws -> Bound {
            var sockets: [any UDPSocket] = []
            do {
                var addresses: [AddressInfo] = []
                for port in [portmap_port, mount_port, nfs_port] {
                    let socket = try socketFactory.createUDPSocket(reuseAddr: false)
                    sockets.append(socket)
                    let local = try await Net.bind_rpc(
                        address, port, socket: socket, interfaceProvider: interfaceProvider)
                    addresses.append(AddressInfo(address: address, family: local.family, port: local.port))
                }
                logger.debug(
                    "file server bound", String(describing: addresses[0]), String(describing: addresses[1]),
                    String(describing: addresses[2]))
                let server = Server(
                    exports, UInt16(truncatingIfNeeded: addresses[2].port),
                    UInt16(truncatingIfNeeded: addresses[1].port), logger: logger, clock: clock)
                if let export_host { server.with_export_host(export_host) }
                if let up { server.with_gate(up) }
                let stop = AtomicBool(false)
                var loops: [Serving] = []
                // 원본 스레드별 초기 설정 실패는 그 serving만 끝낸다.
                for (name, socket) in zip(["portmap", "mount", "nfs"], sockets) {
                    do {
                        loops.append(try Serving(server, socket, stop, clock, closeOnFinish: true, program: name))
                    } catch {
                        logger.error("RPC socket stopped; players cannot read files", name, String(describing: error))
                        try? socket.close()
                    }
                }
                return Bound(stop, loops, sockets, addresses[0], addresses[1], addresses[2], server)
            } catch {
                for socket in sockets {
                    if let checked = socket as? any ServerUDPSocket {
                        try? await checked.shutdown()
                    } else {
                        try? await udpClose(socket)
                    }
                }
                throw error
            }
        }
        public func is_mounted(_ host: Address4) -> Bool { server.is_mounted(host) }
        /// 플레이어가 파일을 찾거나 처음부터 읽을 때 알린다(`Server.with_file_observer`)
        public func observe_files(_ observer: @escaping @DJLinkActor (String, Address4) -> Void) {
            server.with_file_observer(observer)
        }
        /// 그 원본 파일 대신 다른 파일을 내어 준다(`Exports.redirect`)
        public func redirect(_ host: String, to replacement: String) { server.exports().redirect(host, to: replacement) }
        public func mounted_hosts() -> [Address4] { server.mounted_hosts() }
        public func portmap_address() -> AddressInfo { portmap }
        public func mount_address() -> AddressInfo { mount }
        public func nfs_address() -> AddressInfo { nfs }
        public func shutdown() async {
            stop.store(true)
            for loop in loops { try? await loop.wait() }
            loops.removeAll()
            for socket in sockets {
                if let checked = socket as? any ServerUDPSocket {
                    try? await checked.shutdown()
                } else {
                    try? await udpClose(socket)
                }
            }
            sockets.removeAll()
            server.logger.debug("file server stopped")
        }
        deinit {
            let stop = stop
            // Drop는 원본처럼 종료 플래그만 세운다. 살아 있는 serving은 다음 poll에서 정리된다.
            Task { @DJLinkActor in stop.store(true) }
        }
    }
    @DJLinkActor
    @discardableResult
    public static func bind_rpc(
        _ address: String, _ port: UInt16, socket: any UDPSocket,
        interfaceProvider: any InterfaceProvider = SystemInterfaceProvider()
    ) async throws -> AddressInfo {
        #if canImport(Darwin)
            let ipv6 = address.contains(":")
            let unspecified = ipv6 ? "::" : "0.0.0.0"
            let local = try await udpBind(socket, Int(port), unspecified)
            if address != unspecified {
                guard
                    let interface = interfaceProvider.networkInterfaces().first(where: { entry in
                        entry.addresses.contains { $0.address == address }
                    })
                else { throw DJLinkError("no network interface has address \(address)") }
                try socket.setBoundInterface(name: interface.name)
            }
            return local
        #else
            return try await udpBind(socket, Int(port), address)
        #endif
    }
}
