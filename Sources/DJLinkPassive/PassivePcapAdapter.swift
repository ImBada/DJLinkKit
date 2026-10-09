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
        public var type: Int
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
        EthernetResult(type: try buf.readUInt16BE(12), offset: 14)
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
            length: try buf.readUInt16BE(offset + 4), offset: offset + 8)
    }
}

@DJLinkActor
public final class PcapAdapter: EventEmitting {
    public let emitter = EventHub<PcapAdapter>()
    private var cap: (any PcapBackend)?
    private var buffer: [UInt8]
    private let iface: String
    private var started = false
    private let platform: String
    private let interfaceProvider: any InterfaceProvider
    private let backendFactory: @DJLinkActor () throws -> any PcapBackend
    public init(
        config: PcapAdapterConfig, backend: (any PcapBackend)? = nil,
        platform: String = PassivePlatform.current,
        interfaceProvider: any InterfaceProvider = SystemInterfaceProvider(),
        backendFactory: @escaping @DJLinkActor () throws -> any PcapBackend = { try LibpcapBackend() }
    ) {
        iface = config.iface
        buffer = [UInt8](repeating: 0, count: config.bufferSize ?? 10 * 1024 * 1024)
        self.platform = platform
        self.interfaceProvider = interfaceProvider
        self.backendFactory = {
            if let backend { return backend }
            return try backendFactory()
        }
    }
    public func start() throws {
        guard !started else { return }
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
    }
    public func stop() {
        cap?.close()
        cap = nil
        started = false
    }
    public var isCapturing: Bool { started }
    public var interfaceName: String { iface }
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
            let length = udp.length - 8
            guard length > 0 else { return }
            var payload = [UInt8](repeating: 0, count: length)
            let copied = buffer.subarray(udp.offset, udp.offset + length)
            payload.replaceSubrange(0..<copied.count, with: copied)
            let event = PcapPacket(packet: payload, info: PacketInfo(payload: payload, srcAddr: ip.srcaddr))
            switch udp.dstport {
            case ANNOUNCE_PORT: emitter.emit(.announce, event)
            case BEAT_PORT: emitter.emit(.beat, event)
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
        var error = [CChar](repeating: 0, count: Int(PCAP_ERRBUF_SIZE))
        guard let pointer = pcap_create(device, &error) else { throw DJLinkError(pcapString(error)) }
        var retained = false
        defer { if !retained { pcap_close(pointer) } }
        func check(_ code: Int32) throws {
            guard code >= 0 else { throw DJLinkError(String(cString: pcap_geterr(pointer))) }
        }
        try check(pcap_set_snaplen(pointer, Int32(clamping: bufferSize)))
        try check(pcap_set_buffer_size(pointer, Int32(clamping: bufSize)))
        try check(pcap_set_promisc(pointer, 1))
        try check(pcap_set_timeout(pointer, 1000))
        try check(pcap_set_immediate_mode(pointer, 1))
        try check(pcap_activate(pointer))
        try check(pcap_setnonblock(pointer, 1, &error))
        var program = bpf_program()
        try check(pcap_compile(pointer, &program, filter, 1, PCAP_NETMASK_UNKNOWN))
        defer { pcap_freecode(&program) }
        try check(pcap_setfilter(pointer, &program))
        let fd = pcap_get_selectable_fd(pointer)
        guard fd >= 0 else { throw DJLinkError("pcap capture has no selectable file descriptor") }
        let owned = PcapHandle(pointer)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DJLinkActor.queue)
        source.setEventHandler { [weak self] in DJLinkActor.assumeIsolated { self?.drain() } }
        source.setCancelHandler { pcap_close(owned.pointer) }
        self.handle = owned
        self.source = source
        retained = true
        linkType = pcap_datalink(pointer) == DLT_EN10MB ? "ETHERNET" : String(pcap_datalink(pointer))
        source.resume()
    }
    public func setMinBytes(_ bytes: Int) {
        // libpcap의 immediate mode를 활성화 전에 설정해 cap.setMinBytes(0)에 대응한다.
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
        while self.handle != nil {
            var header: UnsafeMutablePointer<pcap_pkthdr>?
            var bytes: UnsafePointer<UInt8>?
            let result = pcap_next_ex(handle.pointer, &header, &bytes)
            if result == 0 || result == -2 { break }
            if result < 0 {
                errorHandler?(DJLinkError(String(cString: pcap_geterr(handle.pointer))))
                break
            }
            guard let header, let bytes else { break }
            packetHandler?(
                Array(UnsafeBufferPointer(start: bytes, count: Int(header.pointee.caplen))),
                header.pointee.caplen < header.pointee.len)
        }
    }
}
