import DJLinkKit
// SPDX-License-Identifier: GPL-2.0-or-later
// rbxport 서버 전송 경계: IPv4/IPv6 BSD UDP와 직렬 이벤트 전달.
import Darwin
@preconcurrency import Dispatch
import Foundation

@DJLinkActor
final class DualStackUDPSocket: ServerUDPSocket {
    private enum Handler {
        case message(@DJLinkActor ([UInt8], RemoteInfo) -> Void, once: Bool)
        case error(@DJLinkActor (any Error) -> Void)
        case close(@DJLinkActor () -> Void)
    }
    private let reuseAddr: Bool
    private var fd: Int32 = -1
    private var family: Int32 = AF_INET
    private var source: DispatchSourceRead?
    private var closed = false
    private var released = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var handlers: [(UInt64, Handler)] = []
    private var nextID: UInt64 = 0
    private var broadcast = false
    private var sendBuffer: Int32?
    private var receiveBuffer: Int32?
    private var interface: String?

    init(reuseAddr: Bool) throws {
        guard !TestProcess.isRunning else {
            throw DJLinkError("Live Link Export sockets are disabled in test processes")
        }
        self.reuseAddr = reuseAddr
    }
    deinit { source?.cancel() }
    private func failure(_ operation: String, _ code: Int32 = Darwin.errno) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain, code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(code)))"])
    }
    private func add(_ handler: Handler) -> SocketListener {
        nextID += 1
        handlers.append((nextID, handler))
        return SocketListener(id: nextID)
    }
    func onMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        add(.message(handler, once: false))
    }
    func onceMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        add(.message(handler, once: true))
    }
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) -> SocketListener { add(.error(handler)) }
    func onClose(_ handler: @escaping @DJLinkActor () -> Void) -> SocketListener { add(.close(handler)) }
    func off(_ listener: SocketListener) { handlers.removeAll { $0.0 == listener.id } }
    func removeAllListeners() { handlers.removeAll() }
    private func emitError(_ error: any Error) {
        for (_, handler) in handlers { if case let .error(callback) = handler { callback(error) } }
    }
    private func option(_ name: Int32, _ number: Int32) throws {
        guard fd >= 0 else { return }
        var number = number
        guard setsockopt(fd, SOL_SOCKET, name, &number, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw failure("setsockopt")
        }
    }
    func setBroadcast(_ enabled: Bool) { do { try setBroadcastChecked(enabled) } catch { emitError(error) } }
    func setBroadcastChecked(_ enabled: Bool) throws {
        guard !closed else { throw SocketNotRunningError() }
        try option(SO_BROADCAST, enabled ? 1 : 0)
        broadcast = enabled
    }
    func setSendBufferSize(_ bytes: Int) throws {
        guard !closed, bytes >= 0, let value = Int32(exactly: bytes) else { throw failure("setsockopt", EINVAL) }
        try option(SO_SNDBUF, value)
        sendBuffer = value
    }
    func setReceiveBufferSize(_ bytes: Int) throws {
        guard !closed, bytes >= 0, let value = Int32(exactly: bytes) else { throw failure("setsockopt", EINVAL) }
        try option(SO_RCVBUF, value)
        receiveBuffer = value
    }
    func setBoundInterface(name: String) throws {
        guard !closed else { throw SocketNotRunningError() }
        var index = if_nametoindex(name)
        guard index != 0 else { throw failure("if_nametoindex", ENXIO) }
        if fd >= 0 {
            let level = family == AF_INET6 ? IPPROTO_IPV6 : IPPROTO_IP
            let nameOption = family == AF_INET6 ? IPV6_BOUND_IF : IP_BOUND_IF
            guard setsockopt(fd, level, nameOption, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0 else {
                throw failure("setsockopt")
            }
        }
        interface = name
    }
    private func withAddress<T>(_ host: String, _ port: Int, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T)
        throws -> T
    {
        guard let port = UInt16(exactly: port) else { throw failure("address", EINVAL) }
        if family == AF_INET6 {
            var value = sockaddr_in6()
            value.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            value.sin6_family = sa_family_t(AF_INET6)
            value.sin6_port = port.bigEndian
            let host = host.contains(":") ? host : "::ffff:\(host)"
            let parts = host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
            guard let numeric = parts.first,
                String(numeric).withCString({ inet_pton(AF_INET6, $0, &value.sin6_addr) }) == 1
            else { throw failure("address", EINVAL) }
            if parts.count == 2 {
                let zone = String(parts[1])
                let index = UInt32(zone) ?? zone.withCString { if_nametoindex($0) }
                guard index != 0 else { throw failure("address", EINVAL) }
                value.sin6_scope_id = index
            }
            return try withUnsafePointer(to: &value) {
                try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    try body($0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
        var value = sockaddr_in()
        value.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        value.sin_family = sa_family_t(AF_INET)
        value.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &value.sin_addr) == 1 else { throw failure("address", EINVAL) }
        return try withUnsafePointer(to: &value) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
    func bind(port: Int?, address: String?) async throws -> AddressInfo {
        guard !closed, fd < 0 else { throw failure("bind", EINVAL) }
        let host = address ?? "0.0.0.0"
        family = host.contains(":") ? AF_INET6 : AF_INET
        let descriptor = socket(family, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw failure("socket") }
        fd = descriptor
        do {
            if reuseAddr {
                try option(SO_REUSEADDR, 1)
                try option(SO_REUSEPORT, 1)
            }
            try option(SO_BROADCAST, broadcast ? 1 : 0)
            if let sendBuffer { try option(SO_SNDBUF, sendBuffer) }
            if let receiveBuffer { try option(SO_RCVBUF, receiveBuffer) }
            if let interface { try setBoundInterface(name: interface) }
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) >= 0 else { throw failure("fcntl") }
            try withAddress(host, port ?? 0) { pointer, length in
                guard Darwin.bind(fd, pointer, length) == 0 else { throw failure("bind") }
            }
            guard let bound = self.address() else { throw failure("getsockname") }
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: DJLinkActor.queue)
            source.setEventHandler { [weak self] in DJLinkActor.assumeIsolated { self?.drain() } }
            source.setCancelHandler { [weak self] in
                Darwin.close(descriptor)
                DJLinkActor.assumeIsolated { self?.didClose() }
            }
            self.source = source
            source.resume()
            return bound
        } catch {
            Darwin.close(descriptor)
            fd = -1
            throw error
        }
    }
    private static func remote(_ storage: inout sockaddr_storage, _ length: socklen_t, _ size: Int) -> RemoteInfo? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var service = [CChar](repeating: 0, count: Int(NI_MAXSERV))
        let result = withUnsafePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo(
                    $0, length, &host, socklen_t(host.count), &service, socklen_t(service.count),
                    NI_NUMERICHOST | NI_NUMERICSERV)
            }
        }
        guard result == 0,
            let port = Int(String(decoding: service.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        else { return nil }
        return RemoteInfo(
            address: String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
            family: storage.ss_family == sa_family_t(AF_INET6) ? "IPv6" : "IPv4",
            port: port, size: size)
    }
    func address() -> AddressInfo? {
        guard !closed, fd >= 0 else { return nil }
        var value = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &value) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard result == 0, let remote = Self.remote(&value, length, 0) else { return nil }
        return AddressInfo(address: remote.address, family: remote.family, port: remote.port)
    }
    func send(_ msg: [UInt8], port: Int, address: String, callback: (@DJLinkActor ((any Error)?, Int) -> Void)?) {
        var error: (any Error)?
        var sent = 0
        do {
            guard !closed, fd >= 0 else { throw SocketNotRunningError() }
            sent = try withAddress(address, port) { pointer, length in
                let count = msg.withUnsafeBytes { sendto(fd, $0.baseAddress, $0.count, 0, pointer, length) }
                guard count >= 0 else { throw failure("sendto") }
                return count
            }
        } catch let caught { error = caught }
        let resultError = error
        let resultCount = sent
        DJLinkActor.queue.async { [weak self] in
            DJLinkActor.assumeIsolated {
                if let callback {
                    callback(resultError, resultCount)
                } else if let resultError {
                    self?.emitError(resultError)
                }
            }
        }
    }
    private func drain() {
        var bytes = [UInt8](repeating: 0, count: 65_535)
        while !closed {
            var peer = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = bytes.withUnsafeMutableBytes { buffer in
                withUnsafeMutablePointer(to: &peer) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, buffer.baseAddress, buffer.count, 0, $0, &length)
                    }
                }
            }
            if count < 0 {
                if Darwin.errno != EAGAIN && Darwin.errno != EWOULDBLOCK { emitError(failure("recvfrom")) }
                return
            }
            guard let remote = Self.remote(&peer, length, count) else { continue }
            let snapshot = handlers
            handlers.removeAll {
                if case .message(_, once: true) = $0.1 { return true }
                return false
            }
            for (_, handler) in snapshot {
                if case let .message(callback, _) = handler { callback(Array(bytes.prefix(count)), remote) }
            }
        }
    }
    private var closeCallback: (@DJLinkActor () -> Void)?
    func close(_ callback: (@DJLinkActor () -> Void)?) throws {
        guard !closed else { throw SocketNotRunningError() }
        closed = true
        closeCallback = callback
        fd = -1
        if let source {
            source.cancel()
            self.source = nil
        } else {
            didClose()
        }
    }
    func shutdown() async throws {
        if !closed { try close(nil) }
        if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
    }
    private func didClose() {
        released = true
        let pending = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in pending { waiter.resume() }
        let snapshot = handlers
        for (_, handler) in snapshot { if case let .close(callback) = handler { callback() } }
        let callback = closeCallback
        closeCallback = nil
        callback?()
    }
}
