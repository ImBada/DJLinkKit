import DJLinkKit
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// rbxport의 TCP listen/accept 전송을 위한 macOS 경계. 패킷·세션 코덱과 분리한다.
import Darwin
@preconcurrency import Dispatch
import Foundation

private func tcpError(_ operation: String, _ code: Int32 = Darwin.errno) -> NSError {
    NSError(
        domain: NSPOSIXErrorDomain, code: Int(code),
        userInfo: [NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(code)))"])
}

private func tcpEndpoint(_ storage: sockaddr_storage, _ length: socklen_t) -> RemoteInfo {
    var storage = storage
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    var service = [CChar](repeating: 0, count: Int(NI_MAXSERV))
    let result = withUnsafePointer(to: &storage) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getnameinfo(
                $0, length, &host, socklen_t(host.count), &service, socklen_t(service.count),
                NI_NUMERICHOST | NI_NUMERICSERV)
        }
    }
    guard result == 0 else { return RemoteInfo(address: "", port: 0, size: 0) }
    return RemoteInfo(
        address: String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
        family: storage.ss_family == AF_INET6 ? "IPv6" : "IPv4",
        port: Int(String(decoding: service.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)) ?? 0,
        size: 0)
}

@DJLinkActor
final class BSDTCPListener: TCPListener {
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var handlers: [UInt64: @DJLinkActor (any TCPConnection, RemoteInfo) -> Void] = [:]
    private var nextID: UInt64 = 0
    private var bound: AddressInfo?
    private var releasing = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init() throws {
        try ExportLiveSocketGuard.requireLiveOrLoopbackProcess()
    }

    func bind(port: Int, address: String) async throws -> AddressInfo {
        guard fd < 0, bound == nil, !releasing, let portValue = UInt16(exactly: port) else {
            throw tcpError("bind", EINVAL)
        }
        try ExportLiveSocketGuard.requireLoopbackBindInTests(address)
        let family = address.contains(":") ? AF_INET6 : AF_INET
        let socket = Darwin.socket(family, SOCK_STREAM, IPPROTO_TCP)
        guard socket >= 0 else { throw tcpError("socket") }
        var succeeded = false
        defer { if !succeeded { Darwin.close(socket) } }
        var on: Int32 = 1
        guard setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw tcpError("setsockopt")
        }
        let result: Int32
        if family == AF_INET6 {
            var target = sockaddr_in6()
            target.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            target.sin6_family = sa_family_t(AF_INET6)
            target.sin6_port = portValue.bigEndian
            guard address.withCString({ inet_pton(AF_INET6, $0, &target.sin6_addr) }) == 1 else {
                throw tcpError("address", EINVAL)
            }
            result = withUnsafePointer(to: &target) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        } else {
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            target.sin_port = portValue.bigEndian
            guard address.withCString({ inet_pton(AF_INET, $0, &target.sin_addr) }) == 1 else {
                throw tcpError("address", EINVAL)
            }
            result = withUnsafePointer(to: &target) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard result == 0 else { throw tcpError("bind") }
        guard Darwin.listen(socket, SOMAXCONN) == 0 else { throw tcpError("listen") }
        guard fcntl(socket, F_SETFL, fcntl(socket, F_GETFL) | O_NONBLOCK) == 0 else { throw tcpError("fcntl") }
        var storage = sockaddr_storage()
        var size = socklen_t(MemoryLayout<sockaddr_storage>.size)
        guard
            withUnsafeMutablePointer(
                to: &storage,
                { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &size) } }) == 0
        else { throw tcpError("getsockname") }
        let endpoint = tcpEndpoint(storage, size)
        let info = AddressInfo(address: endpoint.address, family: endpoint.family, port: endpoint.port)
        fd = socket
        bound = info
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: DJLinkActor.queue)
        source.setEventHandler { [weak self] in DJLinkActor.assumeIsolated { self?.acceptPending() } }
        releasing = true
        source.setCancelHandler { [weak self] in
            Darwin.close(socket)
            DJLinkActor.assumeIsolated {
                self?.releasing = false
                let waiters = self?.releaseWaiters ?? []
                self?.releaseWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        self.source = source
        source.resume()
        succeeded = true
        return info
    }

    @discardableResult
    func onConnection(_ handler: @escaping @DJLinkActor (any TCPConnection, RemoteInfo) -> Void) -> SocketListener {
        nextID += 1
        handlers[nextID] = handler
        return SocketListener(id: nextID)
    }

    func off(_ listener: SocketListener) { handlers.removeValue(forKey: listener.id) }
    func address() -> AddressInfo? { bound }
    func close() throws {
        guard fd >= 0 else { return }
        source?.cancel()
        source = nil
        fd = -1
        bound = nil
        handlers.removeAll()
    }

    func shutdown() async throws {
        try close()
        if releasing {
            await withCheckedContinuation { continuation in
                if releasing { releaseWaiters.append(continuation) } else { continuation.resume() }
            }
        }
    }

    deinit { source?.cancel() }

    private func acceptPending() {
        while fd >= 0 {
            var storage = sockaddr_storage()
            var size = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let accepted = withUnsafeMutablePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.accept(fd, $0, &size) }
            }
            if accepted < 0 {
                if Darwin.errno == EINTR { continue }
                return
            }
            do {
                let connection = try AcceptedTCPConnection(fd: accepted)
                let endpoint = tcpEndpoint(storage, size)
                if handlers.isEmpty {
                    connection.destroy(nil)
                } else {
                    for handler in handlers.values { handler(connection, endpoint) }
                }
            } catch { Darwin.close(accepted) }
        }
    }
}

@DJLinkActor
private final class AcceptedTCPConnection: ServerTCPConnection {
    private let fd: Int32
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var bytes: [UInt8] = []
    private var ended = false
    private var readSuspended = false
    private var failure: (any Error)?
    private var readers: [(size: Int?, continuation: CheckedContinuation<[UInt8]?, any Error>)] = []
    private struct Write {
        let bytes: [UInt8]
        var offset: Int = 0
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var writers: [Write] = []
    private var closeHandler: (@DJLinkActor () -> Void)?
    private var timeout: TimerHandle?
    private var timeoutMs = 0
    private var timeoutAction: (@DJLinkActor () -> Void)?
    private(set) var isOpen = true

    init(fd: Int32) throws {
        self.fd = fd
        guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0 else { throw tcpError("fcntl") }
        var on: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw tcpError("setsockopt")
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DJLinkActor.queue)
        source.setEventHandler { [weak self] in DJLinkActor.assumeIsolated { self?.receivePending() } }
        source.setCancelHandler { Darwin.close(fd) }
        readSource = source
        readSuspended = true
    }

    func configureServer(keepaliveAfter: Int, keepaliveInterval: Int, noDelay: Bool) throws {
        guard isOpen else { throw tcpError("setsockopt", EBADF) }
        guard let after = Int32(exactly: keepaliveAfter), let interval = Int32(exactly: keepaliveInterval), after > 0,
            interval > 0
        else { throw tcpError("setsockopt", EINVAL) }
        for (level, option, number) in [
            (SOL_SOCKET, SO_KEEPALIVE, Int32(1)),
            (IPPROTO_TCP, TCP_KEEPALIVE, after),
            (IPPROTO_TCP, TCP_KEEPINTVL, interval),
            (IPPROTO_TCP, TCP_NODELAY, Int32(noDelay ? 1 : 0)),
        ] {
            var value = number
            guard setsockopt(fd, level, option, &value, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                throw tcpError("setsockopt")
            }
        }
    }

    func connect(port: Int, host: String) async throws {
        throw DJLinkError("Accepted TCP connection is already connected")
    }
    func setRequiredInterface(name: String) throws {
        guard isOpen else { throw tcpError("setsockopt", EBADF) }
        var index = name.withCString { if_nametoindex($0) }
        guard index != 0 else { throw tcpError("interface", ENODEV) }
        var address = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        guard
            withUnsafeMutablePointer(
                to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } })
                == 0
        else { throw tcpError("getsockname") }
        let ipv6 = address.ss_family == sa_family_t(AF_INET6)
        guard
            setsockopt(
                fd, ipv6 ? IPPROTO_IPV6 : IPPROTO_IP, ipv6 ? IPV6_BOUND_IF : IP_BOUND_IF, &index,
                socklen_t(MemoryLayout<UInt32>.size)) == 0
        else { throw tcpError("setsockopt") }
    }
    func setConnectGuard(_ check: @escaping @DJLinkActor () throws -> Void) throws { try check() }
    func setCloseHandler(_ handler: @escaping @DJLinkActor () -> Void) throws { closeHandler = handler }
    func setTimeout(_ milliseconds: Int, onTimeout: (@DJLinkActor () -> Void)?) {
        timeoutMs = milliseconds
        timeoutAction = onTimeout
        refreshTimeout()
    }
    private func refreshTimeout() {
        SystemClock.shared.clearTimerIfPresent(timeout)
        timeout = nil
        if timeoutMs > 0, isOpen {
            timeout = SystemClock.shared.setTimeout(.ms(Double(timeoutMs))) { [weak self] in self?.timeoutAction?() }
        }
    }

    func read(_ size: Int?) async throws -> [UInt8]? {
        try await withCheckedThrowingContinuation { continuation in
            readers.append((size, continuation))
            drainReaders()
        }
    }
    func write(_ data: [UInt8]) async throws {
        guard isOpen else { throw failure ?? tcpError("write", EPIPE) }
        try await withCheckedThrowingContinuation { continuation in
            writers.append(Write(bytes: data, continuation: continuation))
            flushWrites()
        }
    }
    func destroy(_ error: (any Error)?) {
        guard isOpen else { return }
        isOpen = false
        ended = true
        failure = error
        bytes.removeAll()
        SystemClock.shared.clearTimerIfPresent(timeout)
        timeout = nil
        writeSource?.cancel()
        writeSource = nil
        if readSuspended {
            readSource?.resume()
            readSuspended = false
        }
        readSource?.cancel()
        readSource = nil
        drainReaders()
        let pending = writers
        writers.removeAll()
        for writer in pending { writer.continuation.resume(throwing: error ?? tcpError("write", EPIPE)) }
        let handler = closeHandler
        closeHandler = nil
        handler?()
    }
    private func receivePending() {
        var buffer = [UInt8](repeating: 0, count: 16384)
        while isOpen, !ended, !readers.isEmpty {
            let count = buffer.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress, $0.count, 0) }
            if count > 0 {
                bytes += buffer.prefix(count)
                refreshTimeout()
                drainReaders()
            } else if count == 0 {
                ended = true
                drainReaders()
                return
            } else if Darwin.errno == EINTR {
                continue
            } else if Darwin.errno == EAGAIN || Darwin.errno == EWOULDBLOCK {
                return
            } else {
                destroy(tcpError("read"))
                return
            }
        }
    }
    private func updateReadInterest() {
        guard let readSource else { return }
        let shouldRead = isOpen && !ended && !readers.isEmpty
        if shouldRead && readSuspended {
            readSource.resume()
            readSuspended = false
        } else if !shouldRead && !readSuspended {
            readSource.suspend()
            readSuspended = true
        }
    }
    private func drainReaders() {
        // 원본 blocking read처럼 다음 read가 올 때까지 커널에 데이터를 남긴다.
        defer { updateReadInterest() }
        while let first = readers.first {
            if let failure {
                readers.removeFirst().continuation.resume(throwing: failure)
                continue
            }
            let wanted = first.size ?? bytes.count
            guard ended || (first.size == nil ? !bytes.isEmpty : bytes.count >= wanted) else { return }
            readers.removeFirst()
            if bytes.isEmpty, ended {
                first.continuation.resume(returning: nil)
                continue
            }
            let count = min(max(0, wanted), bytes.count)
            let result = Array(bytes.prefix(count))
            bytes.removeFirst(count)
            first.continuation.resume(returning: result)
        }
    }
    private func flushWrites() {
        while isOpen, !writers.isEmpty {
            let entry = writers[0]
            if entry.offset == entry.bytes.count {
                writers.removeFirst().continuation.resume()
                continue
            }
            let count = entry.bytes.withUnsafeBytes {
                Darwin.send(fd, $0.baseAddress!.advanced(by: entry.offset), $0.count - entry.offset, 0)
            }
            if count > 0 {
                writers[0].offset += count
                refreshTimeout()
            } else if count < 0, Darwin.errno == EINTR {
                continue
            } else if count < 0, Darwin.errno == EAGAIN || Darwin.errno == EWOULDBLOCK {
                if writeSource == nil {
                    let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: DJLinkActor.queue)
                    source.setEventHandler { [weak self] in DJLinkActor.assumeIsolated { self?.flushWrites() } }
                    writeSource = source
                    source.resume()
                }
                return
            } else {
                destroy(tcpError("write"))
                return
            }
        }
        if writers.isEmpty {
            writeSource?.cancel()
            writeSource = nil
        }
    }

    deinit {
        writeSource?.cancel()
        if readSuspended { readSource?.resume() }
        readSource?.cancel()
        let timer = timeout
        Task { @DJLinkActor in SystemClock.shared.clearTimerIfPresent(timer) }
    }
}

extension DJLinkClock {
    @DJLinkActor fileprivate func clearTimerIfPresent(_ timer: TimerHandle?) { if let timer { clearTimer(timer) } }
}
