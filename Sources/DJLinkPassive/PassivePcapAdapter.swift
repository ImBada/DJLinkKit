import CPcap
import DJLinkKit
import Darwin
import Dispatch
import Foundation

private func pcapString(_ chars: [CChar]) -> String {
    String(decoding: chars.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

public struct PacketInfo: Equatable, Sendable {
    public var payload: [UInt8]
    public var srcAddr: String
    public init(payload: [UInt8], srcAddr: String) {
        self.payload = payload
        self.srcAddr = srcAddr
    }
}
public struct PcapPacket: Equatable, Sendable {
    public var packet: [UInt8]
    public var info: PacketInfo
    public init(packet: [UInt8], info: PacketInfo) {
        self.packet = packet
        self.info = info
    }
}
public struct PcapAdapterConfig: Equatable, Sendable {
    public var iface: String
    public var bufferSize: Int?
    public init(iface: String, bufferSize: Int? = nil) {
        self.iface = iface
        self.bufferSize = bufferSize
    }
}
public struct CapDeviceListEntry: Equatable, Sendable {
    public var name: String
    public var description: String
    public var addresses: [String]?
    public init(name: String, description: String, addresses: [String]? = nil) {
        self.name = name
        self.description = description
        self.addresses = addresses
    }
}

@DJLinkActor
public protocol PcapBackend: AnyObject {
    var linkType: String { get }
    func deviceList() throws -> [CapDeviceListEntry]
    func open(device: String, filter: String, bufSize: Int, bufferSize: Int) throws
    func setMinBytes(_ bytes: Int)
    func onPacket(_ handler: @escaping @DJLinkActor ([UInt8], Bool) -> Void)
    func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void)
    func send(_ buffer: [UInt8], len: Int) -> Bool
    func close()
}
extension PcapBackend {
    public var linkType: String { "ETHERNET" }
    public func setMinBytes(_ bytes: Int) {}
    public func send(_ buffer: [UInt8], len: Int) -> Bool { false }
}

public let PCAP_MODULE_REQUIRED_ERROR =
    "The \"cap\" module is required for passive mode. Install it with: npm install cap\nNote: Requires libpcap-dev on Linux or Npcap/WinPcap on Windows."

/// 원본 cap.decoders의 헤더 해석과 offset을 옮긴다.
public enum PcapDecoders {
    public enum PROTOCOL {
        public enum ETHERNET { public static let IPV4 = 0x0800 }
        public enum IP { public static let UDP = 17 }
    }
    public struct EthernetResult: Equatable, Sendable {
        public var type: Int?
        public var offset: Int
    }
    public struct IPv4Result: Equatable, Sendable {
        public var `protocol`: Int
        public var srcaddr: String
        public var dstaddr: String
        public var totallen: Int
        public var offset: Int
    }
    public struct UDPResult: Equatable, Sendable {
        public var srcport: Int
        public var dstport: Int
        public var length: Int
        public var offset: Int
    }
    public static func Ethernet(_ buf: [UInt8]) throws -> EthernetResult {
        let typeOffset = buf.at(12) == 0x81 && buf.at(13) == 0x00 ? 16 : 12
        let typeLength = try buf.readUInt16BE(typeOffset)
        return EthernetResult(type: typeLength >= 1536 ? typeLength : nil, offset: typeOffset + 2)
    }
    public static func IPV4(_ buf: [UInt8], _ offset: Int) throws -> IPv4Result {
        let ihl = try buf.readUInt8(offset) & 0x0f
        return IPv4Result(
            protocol: try buf.readUInt8(offset + 9),
            srcaddr: Address4.fromInteger(try buf.readUInt32BE(offset + 12)).address,
            dstaddr: Address4.fromInteger(try buf.readUInt32BE(offset + 16)).address,
            totallen: try buf.readUInt16BE(offset + 2), offset: offset + ihl * 4)
    }
    public static func UDP(_ buf: [UInt8], _ offset: Int) throws -> UDPResult {
        UDPResult(
            srcport: try buf.readUInt16BE(offset), dstport: try buf.readUInt16BE(offset + 2),
            length: try buf.readUInt16BE(offset + 4) - 8, offset: offset + 8)
    }
}

@DJLinkActor
public final class PcapAdapter: EventEmitting {
    public let emitter = EventHub<PcapAdapter>()
    private var cap: (any PcapBackend)?
    private var buffer: [UInt8]
    private let bufferSize: Int
    private let iface: String
    private var started = false
    private let platform: String
    private let interfaceProvider: any InterfaceProvider
    private let backendFactory: @DJLinkActor () throws -> any PcapBackend
    // PLAN §9: 캡처 중 인터페이스가 사라졌는지 1초마다 인터페이스 번호로 본다(원본 cap 반복은 조용하다).
    private let clock: any DJLinkClock
    private let interfaceIndex: @DJLinkActor (String) -> UInt32
    private var startIndex: UInt32 = 0
    private var watchTimer: TimerHandle?
    public init(
        config: PcapAdapterConfig, backend: (any PcapBackend)? = nil,
        platform: String = PassivePlatform.current,
        interfaceProvider: any InterfaceProvider = SystemInterfaceProvider(),
        backendFactory: @escaping @DJLinkActor () throws -> any PcapBackend = { try LibpcapBackend() },
        clock: any DJLinkClock = SystemClock.shared,
        interfaceIndex: @escaping @DJLinkActor (String) -> UInt32 = { if_nametoindex($0) }
    ) {
        iface = config.iface
        bufferSize = config.bufferSize ?? 10 * 1024 * 1024
        // 원본과 다름: 생성자는 throws가 아니므로 범위 오류는 start에서 던진다.
        buffer = [UInt8](repeating: 0, count: max(0, bufferSize))
        self.platform = platform
        self.interfaceProvider = interfaceProvider
        self.clock = clock
        self.interfaceIndex = interfaceIndex
        self.backendFactory = {
            if let backend { return backend }
            return try backendFactory()
        }
    }
    public func start() throws {
        guard !started else { return }
        guard bufferSize > 0 else {
            // 원본과 다름: 요청한 검증에 따라 Buffer.alloc(0)이 허용하는 빈 버퍼도 거부한다.
            throw BufferRangeError("The value of \"size\" is out of range. Received \(bufferSize)")
        }
        let backend: any PcapBackend
        do { backend = try backendFactory() } catch { throw DJLinkError(PCAP_MODULE_REQUIRED_ERROR) }
        cap = backend
        var deviceName = iface
        if platform == "win32", !deviceName.hasPrefix("\\Device\\"),
            let resolved = try resolveWindowsInterface(iface, backend)
        {
            deviceName = resolved
        }
        let filter = "udp and (port \(ANNOUNCE_PORT) or port \(BEAT_PORT) or port \(STATUS_PORT))"
        do { try backend.open(device: deviceName, filter: filter, bufSize: 65535, bufferSize: buffer.count) } catch {
            throw DJLinkError(
                "Failed to open interface \"\(iface)\" (device: \(deviceName)) for packet capture. Ensure you have root/sudo privileges and the interface exists.\nOriginal error: Error: \(error)"
            )
        }
        backend.setMinBytes(0)
        backend.onPacket { [weak self] bytes, truncated in self?.handlePacket(bytes, truncated) }
        backend.onError { [weak self] error in self?.emitter.emit(.error, error) }
        started = true
        watchInterface()
    }
    deinit {
        // isolated deinit는 macOS 15.4부터다. stop 없이 해제돼도 감시 타이머를 거둔다.
        let clock = clock
        let watchTimer = watchTimer
        Task { @DJLinkActor in clock.clearInterval(watchTimer) }
    }
    public func stop() {
        clock.clearInterval(watchTimer)
        watchTimer = nil
        cap?.close()
        cap = nil
        started = false
    }
    public var isCapturing: Bool { started }
    public var interfaceName: String { iface }
    /// PLAN §9: USB 어댑터를 뽑아 인터페이스가 사라지면 BPF 읽기 소스가 다시 읽히지 않아 영영 캡처 중으로 남았다.
    /// 시작 때의 인터페이스 번호를 적어 두고 1초마다 견줘, 0이 되거나 바뀌면 오류를 내고 캡처를 멈춘다.
    /// 케이블만 뽑으면 번호는 그대로여서 오류가 아니다(재연결되면 캡처가 이어진다).
    /// 번호는 시작 때 찾을 수 있을 때만 본다: Windows는 장치 이름이 커널 인터페이스 이름과 다르고, `any` 같은 가상 이름도 번호가 없다.
    private func watchInterface() {
        guard platform != "win32" else { return }
        startIndex = interfaceIndex(iface)
        guard startIndex != 0 else { return }
        watchTimer = clock.setInterval(.seconds(1)) { [weak self] in self?.checkInterface() }
    }
    private func checkInterface() {
        guard started else { return }
        let current = interfaceIndex(iface)
        guard current != startIndex else { return }
        stop()
        emitter.emit(
            .error,
            DJLinkError(
                "Capture interface \"\(iface)\" is gone (index \(startIndex) -> \(current)). Capturing stopped."
            ))
    }
    private func resolveWindowsInterface(_ ifaceName: String, _ backend: any PcapBackend) throws -> String? {
        guard let nodeIface = interfaceProvider.networkInterfaces().first(where: { $0.name == ifaceName })?.addresses
        else { return nil }
        let nodeIpv4Addresses = Set(nodeIface.filter(passiveIsIPv4).map(\.address))
        guard !nodeIpv4Addresses.isEmpty else { return nil }
        for device in try backend.deviceList() {
            if device.addresses?.contains(where: { !$0.isEmpty && nodeIpv4Addresses.contains($0) }) == true {
                return device.name
            }
        }
        return nil
    }
    private func handlePacket(_ bytes: [UInt8], _ truncated: Bool) {
        // cap는 nbytes 밖도 같은 버퍼에 남겨 둔다. 원본은 nbytes로 해석 범위를 제한하지 않는다.
        let count = min(buffer.count, bytes.count)
        buffer.replaceSubrange(0..<count, with: bytes.prefix(count))
        guard !truncated else { return }
        do {
            let eth = try PcapDecoders.Ethernet(buffer)
            guard eth.type == PcapDecoders.PROTOCOL.ETHERNET.IPV4 else { return }
            let ip = try PcapDecoders.IPV4(buffer, eth.offset)
            guard ip.protocol == PcapDecoders.PROTOCOL.IP.UDP else { return }
            let udp = try PcapDecoders.UDP(buffer, ip.offset)
            // PLAN §9: 원본은 cap 디코더(이미 헤더 8바이트를 뺀 길이)에서 8을 한 번 더 빼 payload 끝 8바이트를 잘랐다.
            let length = udp.length
            guard length > 0 else { return }
            var payload = [UInt8](repeating: 0, count: length)
            let copied = buffer.subarray(udp.offset, udp.offset + length)
            payload.replaceSubrange(0..<copied.count, with: copied)
            let event = PcapPacket(packet: payload, info: PacketInfo(payload: payload, srcAddr: ip.srcaddr))
            switch udp.dstport {
            case ANNOUNCE_PORT: emitter.emit(.announce, event)
            case BEAT_PORT: try emitter.emitThrowing(.beat, event)
            case STATUS_PORT: emitter.emit(.status, event)
            default: break
            }
        } catch { emitter.emit(.error, error) }
    }
}
extension EventName where Owner == PcapAdapter, Payload == PcapPacket {
    public static var announce: Self { .init("announce") }
    public static var status: Self { .init("status") }
    public static var beat: Self { .init("beat") }
}
extension EventName where Owner == PcapAdapter, Payload == any Error {
    public static var error: Self { .init("error") }
}

/// 취소 핸들러는 같은 직렬 큐에서 실행되며, 캡처 포인터는 그곳에서 한 번 닫는다.
private final class PcapHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { self.pointer = pointer }
}

@DJLinkActor
public final class LibpcapBackend: PcapBackend {
    private var handle: PcapHandle?
    private var source: DispatchSourceRead?
    private var packetHandler: (@DJLinkActor ([UInt8], Bool) -> Void)?
    private var errorHandler: (@DJLinkActor (any Error) -> Void)?
    private var bufferLength = 0
    public private(set) var linkType = "ETHERNET"
    public init() throws {
        // SwiftPM의 CPcap 링크 외에도, 원본 require 실패에 해당하는 오류 주입 경계를 둔다.
        guard let library = dlopen("/usr/lib/libpcap.A.dylib", RTLD_LAZY) else {
            throw DJLinkError(PCAP_MODULE_REQUIRED_ERROR)
        }
        dlclose(library)
    }
    public func deviceList() throws -> [CapDeviceListEntry] {
        var list: UnsafeMutablePointer<pcap_if_t>?
        var error = [CChar](repeating: 0, count: Int(PCAP_ERRBUF_SIZE))
        guard pcap_findalldevs(&list, &error) == 0 else { throw DJLinkError(pcapString(error)) }
        defer { pcap_freealldevs(list) }
        var result: [CapDeviceListEntry] = []
        var next = list
        while let device = next {
            defer { next = device.pointee.next }
            var addresses: [String] = []
            var address = device.pointee.addresses
            while let item = address {
                defer { address = item.pointee.next }
                guard let addr = item.pointee.addr else { continue }
                let family = Int32(addr.pointee.sa_family)
                guard family == AF_INET || family == AF_INET6 else { continue }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length = socklen_t(
                    family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
                if getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    addresses.append(pcapString(host))
                }
            }
            result.append(
                .init(
                    name: String(cString: device.pointee.name),
                    description: device.pointee.description.map { String(cString: $0) } ?? "", addresses: addresses))
        }
        return result
    }
    public func open(device: String, filter: String, bufSize: Int, bufferSize: Int) throws {
        // 루프백 허용 환경변수와 관계없이 실제 BPF 캡처는 시험 프로세스에서 금지한다.
        guard !TestProcess.isRunning else { throw DJLinkError("Live pcap capture is disabled in test processes") }
        close()
        var error = [CChar](repeating: 0, count: Int(PCAP_ERRBUF_SIZE))
        var net: bpf_u_int32 = 0
        var mask: bpf_u_int32 = 0
        if pcap_lookupnet(device, &net, &mask, &error) == -1 {
            net = 0
            mask = 0
            fputs("Warning: \(pcapString(error)) - This may not actually work\n", stderr)
        }
        guard let pointer = pcap_create(device, &error) else { throw DJLinkError(pcapString(error)) }
        var retained = false
        defer { if !retained { pcap_close(pointer) } }
        guard pcap_set_snaplen(pointer, 65535) == 0 else { throw DJLinkError("Unable to set snaplen") }
        guard pcap_set_promisc(pointer, 1) == 0 else { throw DJLinkError("Unable to set promiscuous mode") }
        guard pcap_set_buffer_size(pointer, Int32(truncatingIfNeeded: bufSize)) == 0 else {
            throw DJLinkError("Unable to set buffer size")
        }
        guard pcap_set_timeout(pointer, 1000) == 0 else { throw DJLinkError("Unable to set read timeout") }
        guard pcap_activate(pointer) == 0 else { throw DJLinkError(String(cString: pcap_geterr(pointer))) }
        guard pcap_setnonblock(pointer, 1, &error) != -1 else { throw DJLinkError(pcapString(error)) }
        if !filter.isEmpty {
            var program = bpf_program()
            // 원본 버그 그대로: cap Open은 lookupnet의 mask 대신 net을 compile의 netmask 인자로 쓴다.
            guard pcap_compile(pointer, &program, filter, 1, net) != -1 else {
                throw DJLinkError(String(cString: pcap_geterr(pointer)))
            }
            defer { pcap_freecode(&program) }
            guard pcap_setfilter(pointer, &program) != -1 else {
                throw DJLinkError(String(cString: pcap_geterr(pointer)))
            }
        }
        let fd = pcap_get_selectable_fd(pointer)
        var immediate: UInt32 = 1
        // 원본 macOS Open과 같이 BIOCIMMEDIATE의 반환값은 검사하지 않는다.
        _ = ioctl(fd, UInt(DJLINK_BIOCIMMEDIATE), &immediate)
        guard fd >= 0 else { throw DJLinkError("pcap capture has no selectable file descriptor") }
        bufferLength = bufferSize
        let owned = PcapHandle(pointer)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DJLinkActor.queue)
        source.setEventHandler { [weak self] in DJLinkActor.assumeIsolated { self?.drain() } }
        source.setCancelHandler { pcap_close(owned.pointer) }
        self.handle = owned
        self.source = source
        retained = true
        switch pcap_datalink(pointer) {
        case DLT_NULL: linkType = "NULL"
        case DLT_EN10MB: linkType = "ETHERNET"
        case DLT_IEEE802_11_RADIO: linkType = "IEEE802_11_RADIO"
        case DLT_LINUX_SLL: linkType = "LINKTYPE_LINUX_SLL"
        case DLT_RAW: linkType = "RAW"
        case let type: linkType = "Unknown linktype \(type)"
        }
        source.resume()
    }
    public func setMinBytes(_ bytes: Int) {
        // 원본 cap의 macOS 구현에는 setMinBytes가 없으며 Open의 BIOCIMMEDIATE로 대응한다.
    }
    public func onPacket(_ handler: @escaping @DJLinkActor ([UInt8], Bool) -> Void) { packetHandler = handler }
    public func onError(_ handler: @escaping @DJLinkActor (any Error) -> Void) { errorHandler = handler }
    public func send(_ buffer: [UInt8], len: Int) -> Bool {
        guard let handle else { return false }
        return buffer.withUnsafeBytes {
            pcap_sendpacket(
                handle.pointer, $0.bindMemory(to: UInt8.self).baseAddress, Int32(clamping: min(len, buffer.count))) == 0
        }
    }
    public func close() {
        source?.cancel()
        source = nil
        handle = nil
        packetHandler = nil
        errorHandler = nil
    }
    private func drain() {
        guard let handle else { return }
        let context = Unmanaged.passUnretained(self).toOpaque().assumingMemoryBound(to: UInt8.self)
        while self.handle != nil {
            let result = pcap_dispatch(
                handle.pointer, 1,
                { context, header, bytes in
                    guard let context, let header, let bytes else { return }
                    let backend = Unmanaged<LibpcapBackend>.fromOpaque(UnsafeRawPointer(context)).takeUnretainedValue()
                    DJLinkActor.assumeIsolated { backend.handleCapturedPacket(header.pointee, bytes) }
                }, context)
            // 원본 cap는 -1도 오류 이벤트 없이 반복만 끝내고 다음 readable 콜백을 기다린다.
            if result <= 0 { break }
        }
    }
    private func handleCapturedPacket(_ header: pcap_pkthdr, _ bytes: UnsafePointer<UInt8>) {
        let capturedLength = Int(header.caplen)
        let count = min(capturedLength, bufferLength)
        packetHandler?(
            Array(UnsafeBufferPointer(start: bytes, count: count)), capturedLength > bufferLength)
    }
}
