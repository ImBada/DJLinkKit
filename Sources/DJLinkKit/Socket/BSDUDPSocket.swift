import Darwin
import Dispatch

/// Node 시스템 호출 오류(`Error: bind EADDRINUSE 0.0.0.0:50000`).
public struct SystemCallError: Error, Equatable, Sendable, CustomStringConvertible {
    public let syscall: String
    public let code: String
    public let errno: Int32
    public let address: String?
    public let port: Int?

    public var message: String {
        var text = "\(syscall) \(code)"
        if let address {
            text += " \(address)"
            if let port { text += ":\(port)" }
        }
        return text
    }

    public var description: String { message }

    init(syscall: String, errno: Int32, address: String? = nil, port: Int? = nil) {
        self.syscall = syscall
        self.errno = errno
        self.address = address
        self.port = port
        self.code =
            switch errno {
            case EADDRINUSE: "EADDRINUSE"
            case EADDRNOTAVAIL: "EADDRNOTAVAIL"
            case EACCES: "EACCES"
            case EPERM: "EPERM"
            case EHOSTUNREACH: "EHOSTUNREACH"
            case ENETUNREACH: "ENETUNREACH"
            case EINVAL: "EINVAL"
            case EBADF: "EBADF"
            case EMSGSIZE: "EMSGSIZE"
            default: "E\(errno)"
            }
    }
}

/// Node의 이미 닫힌 dgram 소켓 close 오류.
public struct SocketNotRunningError: Error, Equatable, Sendable, CustomStringConvertible {
    public let code = "ERR_SOCKET_DGRAM_NOT_RUNNING"
    public let message = "Not running"
    public init() {}
    public var description: String { message }
}

/// `setsockopt`와 같은 모양. 시험이 호출을 기록하는 가짜를 넣는다.
typealias SetSockOpt = (_ fd: Int32, _ level: Int32, _ name: Int32, _ value: UnsafeRawPointer?, _ length: socklen_t) ->
    Int32

/// `if_nametoindex`와 같은 모양. 없는 이름이면 0.
typealias InterfaceNameToIndex = (_ name: String) -> UInt32

/// CLI 안전을 위한 추가: 소켓 하나를 인터페이스 하나에 묶는다(`IP_BOUND_IF`).
/// 이름을 찾지 못하거나 `setsockopt`가 실패하면 던진다. 실제 호출은 인자로 바꿔 넣을 수 있다.
func bindSocketToInterface(
    fd: Int32, name: String,
    nameToIndex: InterfaceNameToIndex = { if_nametoindex($0) },
    setsockopt: SetSockOpt = { Darwin.setsockopt($0, $1, $2, $3, $4) }
) throws {
    let index = nameToIndex(name)
    guard index != 0 else { throw SystemCallError(syscall: "if_nametoindex", errno: ENXIO, address: name) }
    var value = index
    let result = setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &value, socklen_t(MemoryLayout<UInt32>.size))
    guard result == 0 else { throw SystemCallError(syscall: "setsockopt", errno: Darwin.errno, address: name) }
}

/// BSD 소켓과 DispatchSource로 만든 실제 UDP 소켓. Network.framework는 브로드캐스트를 받지 못해 쓰지 않는다.
/// `SO_REUSEADDR`·`SO_REUSEPORT`(libuv가 macOS에서 reuseAddr로 켜는 것)와 `SO_BROADCAST`를 쓴다.
@DJLinkActor
final class BSDUDPSocket: UDPSocket {
    private enum Handler {
        case message(@DJLinkActor ([UInt8], RemoteInfo) -> Void, once: Bool)
        case error(@DJLinkActor (any Error) -> Void)
        case close(@DJLinkActor () -> Void)
    }

    private let fd: Int32
    private var readSource: DispatchSourceRead?
    private var handlers: [(id: UInt64, handler: Handler)] = []
    private var nextID: UInt64 = 0
    private var isClosed = false

    init(reuseAddr: Bool) throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw SystemCallError(syscall: "socket", errno: Darwin.errno) }
        self.fd = fd
        if reuseAddr {
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &on, socklen_t(MemoryLayout<Int32>.size))
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DJLinkActor.queue)
        source.setEventHandler { [weak self] in
            DJLinkActor.assumeIsolated { self?.drain() }
        }
        source.setCancelHandler { Darwin.close(fd) }
        readSource = source
        source.resume()
    }

    // MARK: 이벤트

    @discardableResult
    func onMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        add(.message(handler, once: false))
    }

    @discardableResult
    func onceMessage(_ handler: @escaping @DJLinkActor ([UInt8], RemoteInfo) -> Void) -> SocketListener {
        add(.message(handler, once: true))
    }

    @discardableResult
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) -> SocketListener {
        add(.error(handler))
    }

    @discardableResult
    func onClose(_ handler: @escaping @DJLinkActor () -> Void) -> SocketListener {
        add(.close(handler))
    }

    func off(_ listener: SocketListener) {
        handlers.removeAll { $0.id == listener.id }
    }

    func removeAllListeners() {
        handlers.removeAll()
    }

    private func add(_ handler: Handler) -> SocketListener {
        nextID += 1
        handlers.append((nextID, handler))
        return SocketListener(id: nextID)
    }

    private func emitMessage(_ message: [UInt8], _ rinfo: RemoteInfo) {
        let snapshot = handlers
        handlers.removeAll {
            if case .message(_, once: true) = $0.handler { return true }
            return false
        }
        for entry in snapshot {
            if case let .message(handler, _) = entry.handler { handler(message, rinfo) }
        }
    }

    private func emitError(_ error: any Error) {
        for entry in handlers {
            if case let .error(handler) = entry.handler { handler(error) }
        }
    }

    // MARK: 동작

    func bind(port: Int?, address: String?) async throws -> AddressInfo {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port ?? 0).bigEndian)
        let host = address ?? "0.0.0.0"
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            throw SystemCallError(syscall: "bind", errno: EINVAL, address: host, port: port)
        }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            throw SystemCallError(syscall: "bind", errno: Darwin.errno, address: host, port: port ?? 0)
        }
        guard let info = self.address() else {
            throw SystemCallError(syscall: "getsockname", errno: Darwin.errno)
        }
        return info
    }

    func send(
        _ msg: [UInt8],
        port: Int,
        address: String,
        callback: (@DJLinkActor ((any Error)?, Int) -> Void)?
    ) {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(truncatingIfNeeded: port).bigEndian)
        var error: (any Error)?
        var sent = 0
        if isClosed {
            error = DJLinkError("Not running")
        } else if inet_pton(AF_INET, address, &addr.sin_addr) != 1 {
            error = SystemCallError(syscall: "send", errno: EINVAL, address: address, port: port)
        } else {
            let result = msg.withUnsafeBytes { raw in
                withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, raw.baseAddress, raw.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if result < 0 {
                error = SystemCallError(syscall: "send", errno: Darwin.errno, address: address, port: port)
            } else {
                sent = result
            }
        }
        // Node처럼 결과는 늘 다음 차례에 알린다. 콜백이 없으면 오류를 'error'로 낸다.
        let finalError = error
        let finalSent = sent
        DJLinkActor.queue.async { [weak self] in
            DJLinkActor.assumeIsolated {
                if let callback {
                    callback(finalError, finalSent)
                } else if let finalError {
                    self?.emitError(finalError)
                }
            }
        }
    }

    func setBoundInterface(name: String) throws {
        guard !isClosed else { throw SocketNotRunningError() }
        try bindSocketToInterface(fd: fd, name: name)
    }

    func setBroadcast(_ flag: Bool) {
        var value: Int32 = flag ? 1 : 0
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    func address() -> AddressInfo? {
        var addr = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard result == 0 else { return nil }
        return AddressInfo(address: Self.host(addr), port: Int(UInt16(bigEndian: addr.sin_port)))
    }

    func close(_ callback: (@DJLinkActor () -> Void)?) throws {
        guard !isClosed else { throw SocketNotRunningError() }
        isClosed = true
        readSource?.cancel()
        readSource = nil
        DJLinkActor.queue.async { [weak self] in
            DJLinkActor.assumeIsolated {
                guard let self else {
                    callback?()
                    return
                }
                let closeHandlers = self.handlers.compactMap { entry -> (@DJLinkActor () -> Void)? in
                    if case let .close(handler) = entry.handler { return handler }
                    return nil
                }
                closeHandlers.forEach { $0() }
                callback?()
            }
        }
    }

    // MARK: 받기

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while !isClosed {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, raw.baseAddress, raw.count, 0, $0, &length)
                    }
                }
            }
            if count < 0 {
                let code = Darwin.errno
                if code != EAGAIN, code != EWOULDBLOCK {
                    emitError(SystemCallError(syscall: "recvmsg", errno: code))
                }
                return
            }
            let message = Array(buffer[0..<count])
            let rinfo = RemoteInfo(address: Self.host(from), port: Int(UInt16(bigEndian: from.sin_port)), size: count)
            emitMessage(message, rinfo)
        }
    }

    private static func host(_ addr: sockaddr_in) -> String {
        var addr = addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(buffer.count))
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
