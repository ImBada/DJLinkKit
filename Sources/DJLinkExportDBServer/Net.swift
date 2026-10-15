import DJLinkExportSupport
import DJLinkKit
import Darwin
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-dbserver/src/net.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Foundation

@DJLinkActor public protocol Handler: AnyObject {
    func open() -> any Session
    func open_ready() -> (any Session)?
    func serving() -> Bool
}
extension Handler {
    public func serving() -> Bool { true }
    public func open_ready() -> (any Session)? { serving() ? open() : nil }
}
@DJLinkActor public protocol Session: AnyObject { func handle(_ message: Message) -> [Message] }
public enum Net {
    public static let KEEPALIVE_AFTER: Duration = .seconds(10)
    public static let KEEPALIVE_INTERVAL: Duration = .seconds(5)
    public static let READ_TIMEOUT: Duration = .milliseconds(200)
    public static let MAX_PENDING = 64 * 1024
    public static let ACCEPT_POLL: Duration = .milliseconds(25)

    @DJLinkActor public static func serve_session(
        _ handler: any Handler, _ stream: any TCPConnection, _ stop: AtomicBool,
        clock: any DJLinkClock = SystemClock.shared
    ) async throws {
        // 원본의 read timeout으로 shutdown을 확인하는 흐름은 주입 시계의 점검으로 옮긴다.
        if let connection = stream as? any ServerTCPConnection {
            try connection.configureServer(keepaliveAfter: 10, keepaliveInterval: 5, noDelay: true)
        }
        let poll = clock.setInterval(READ_TIMEOUT) { if stop.load() { stream.destroy(nil) } }
        defer {
            clock.clearTimer(poll)
            stream.destroy(nil)
        }
        guard let session = handler.open_ready() else { return }
        var pending: [UInt8] = []
        var greeted = false
        while !stop.load() {
            let received: [UInt8]
            do {
                guard let chunk = try await stream.read(nil), !chunk.isEmpty else { return }
                received = chunk
            } catch {
                if is_timeout(error) {
                    // SDK에서 이미 닫힌 연결은 다음 read의 EOF에 대응한다.
                    if !stream.isOpen { return }
                    continue
                }
                throw error
            }
            // 원본 Read의 최대 4096바이트 경계를 유지한다.
            for start in stride(from: 0, to: received.count, by: 4096) {
                if stop.load() { return }
                let chunk = Array(received[start..<min(start + 4096, received.count)])
                pending += chunk
                if pending.count > MAX_PENDING { return }
                if !greeted {
                    if pending.count < GREETING.count { continue }
                    guard pending.starts(with: GREETING) else { return }
                    pending.removeFirst(GREETING.count)
                    try await stream.write(GREETING)
                    greeted = true
                }
                let (messages, used) = Message.decode_all(pending)
                pending.removeFirst(used)
                for message in messages {
                    for reply in session.handle(message) { try await stream.write(reply.encode()) }
                }
            }
        }
    }
    private static func is_timeout(_ error: any Error) -> Bool {
        if let call = error as? SystemCallError { return call.errno == EWOULDBLOCK || call.errno == ETIMEDOUT }
        let call = error as NSError
        return call.domain == NSPOSIXErrorDomain && (call.code == Int(EWOULDBLOCK) || call.code == Int(ETIMEDOUT))
    }
    @DJLinkActor public static func answer_port_query(
        _ stream: any TCPConnection, _ port: UInt16, clock: any DJLinkClock = SystemClock.shared
    ) async throws {
        let timer = clock.setTimeout(.seconds(5)) { stream.destroy(nil) }
        defer { clock.clearTimer(timer) }
        guard let request = try await stream.read(PORT_QUERY_REQUEST.count), request.count == PORT_QUERY_REQUEST.count
        else { throw DJLinkError("unexpected end of file") }
        guard request == PORT_QUERY_REQUEST else { return }
        try await stream.write(dbBE(port))
    }
    @DJLinkActor public final class Bound {
        private final class Lifetime: @unchecked Sendable {
            let stop: AtomicBool
            let queryListener: any TCPListener
            let databaseListener: any TCPListener
            var streams: [ObjectIdentifier: any TCPConnection] = [:]
            var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
            @DJLinkActor init(_ stop: AtomicBool, _ query: any TCPListener, _ database: any TCPListener) {
                self.stop = stop
                queryListener = query
                databaseListener = database
            }
            @DJLinkActor func close() {
                stop.store(true)
                try? queryListener.close()
                try? databaseListener.close()
                // 원본 accept loop 종료는 열린 세션을 join하지 않는다.
                // DB 세션은 stop read poll, 포트 query는 기존 timeout에서 끝난다.
            }
        }
        private let lifetime: Lifetime
        private let query: AddressInfo
        private let database: AddressInfo
        private init(_ lifetime: Lifetime, _ query: AddressInfo, _ database: AddressInfo) {
            self.lifetime = lifetime
            self.query = query
            self.database = database
        }
        public static func start(
            _ handler: any Handler, _ address: String, _ query_port: UInt16, _ database_port: UInt16,
            socketFactory: any ExportSocketFactory = LiveExportSocketFactory.shared,
            clock: any DJLinkClock = SystemClock.shared
        ) async throws -> Bound {
            let queryListener = try socketFactory.createTCPListener()
            let databaseListener: any TCPListener
            do { databaseListener = try socketFactory.createTCPListener() } catch {
                try? await queryListener.shutdown()
                throw error
            }
            let query: AddressInfo
            let database: AddressInfo
            do {
                query = try await queryListener.bind(port: Int(query_port), address: address)
                database = try await databaseListener.bind(port: Int(database_port), address: address)
            } catch {
                try? await queryListener.shutdown()
                try? await databaseListener.shutdown()
                throw error
            }
            let lifetime = Lifetime(AtomicBool(), queryListener, databaseListener)
            let bound = Bound(lifetime, query, database)
            queryListener.onConnection { [weak lifetime] stream, _ in
                guard let lifetime, !lifetime.stop.load() else {
                    stream.destroy(nil)
                    return
                }
                let id = ObjectIdentifier(stream)
                lifetime.streams[id] = stream
                lifetime.tasks[id] = Task { @DJLinkActor [weak lifetime] in
                    defer {
                        stream.destroy(nil)
                        lifetime?.streams.removeValue(forKey: id)
                        lifetime?.tasks.removeValue(forKey: id)
                    }
                    guard handler.serving() else { return }
                    try? await answer_port_query(stream, UInt16(database.port), clock: clock)
                }
            }
            databaseListener.onConnection { [weak lifetime] stream, _ in
                guard let lifetime, !lifetime.stop.load() else {
                    stream.destroy(nil)
                    return
                }
                let id = ObjectIdentifier(stream)
                lifetime.streams[id] = stream
                let stop = lifetime.stop
                lifetime.tasks[id] = Task { @DJLinkActor [weak lifetime] in
                    defer {
                        stream.destroy(nil)
                        lifetime?.streams.removeValue(forKey: id)
                        lifetime?.tasks.removeValue(forKey: id)
                    }
                    try? await serve_session(handler, stream, stop, clock: clock)
                }
            }
            return bound
        }
        public func query_address() -> AddressInfo { query }
        public func database_address() -> AddressInfo { database }
        public func shutdown() async {
            lifetime.close()
            try? await lifetime.queryListener.shutdown()
            try? await lifetime.databaseListener.shutdown()
            // 이미 열린 세션의 원본 스레드는 분리되어 계속 정리된다.
        }
        deinit {
            let lifetime = lifetime
            Task { @DJLinkActor in lifetime.close() }
        }
    }
}
public typealias Bound = Net.Bound
