import DJLinkExportTestSupport
import DJLinkKit
import DJLinkTestSupport
// SPDX-License-Identifier: GPL-2.0-or-later
// 원본: rbl-link/tests/rebind.rs. 루프백 bind는 가짜 전송으로 옮긴다.
import Foundation
import Testing

@testable import DJLinkExport

@Suite @DJLinkActor struct RebindTests {
    func source() -> StaticSource {
        StaticSource(
            library: fixture_library(tracks: 2, playlists: 1, tracks_per_playlist: 1, histories: 0), share_root: "")
    }
    func fixed_ports(_ factory: FakeExportSocketFactory) -> Ports {
        Ports(
            announce: UInt16(factory.allocatePort()), status: UInt16(factory.allocatePort()),
            query: UInt16(factory.allocatePort()), database: UInt16(factory.allocatePort()),
            portmap: UInt16(factory.allocatePort()), mount: UInt16(factory.allocatePort()),
            nfs: UInt16(factory.allocatePort()))
    }
    @Test("link_starts_again_on_the_same_ports_after_stopping") func restart() async throws {
        let clock = TestClock()
        let factory = FakeExportSocketFactory(clock: clock)
        let source = source()
        let ports = fixed_ports(factory)
        for _ in 0..<3 {
            let link = try await LinkExport.start(
                source, .loopback(), ports, socketFactory: factory, clock: clock, connectionMode: .wired)
            #expect(link.query_address().port == Int(ports.query))
            #expect(link.database_address().port == Int(ports.database))
            #expect(link.portmap_address().port == Int(ports.portmap))
            await stop_link(link, clock)
        }
        for port in [ports.query, ports.database] {
            let listener = try factory.createTCPListener()
            _ = try await listener.bind(port: Int(port), address: "127.0.0.1")
            try await listener.shutdown()
        }
        for port in [ports.portmap, ports.nfs] {
            let socket = try factory.createUDPSocket(reuseAddr: false)
            _ = try await socket.bind(port: Int(port), address: "0.0.0.0")
            try await udpClose(socket)
        }
    }
    @Test("a_start_that_fails_part_way_leaves_no_port_bound") func rollback() async throws {
        let clock = TestClock()
        let factory = FakeExportSocketFactory(clock: clock)
        let source = source()
        let ports = fixed_ports(factory)
        let holder = try factory.createUDPSocket(reuseAddr: false)
        _ = try await holder.bind(port: Int(ports.portmap), address: "0.0.0.0")
        do {
            _ = try await LinkExport.start(
                source, .loopback(), ports, socketFactory: factory, clock: clock, connectionMode: .wired)
            Issue.record("started with the portmap port taken")
        } catch let error as LinkError {
            if case let .bind(why) = error {
                #expect(why.contains(String(ports.portmap)))
            } else {
                Issue.record("expected a bind error, got \(error)")
            }
        }
        try await udpClose(holder)
        let link = try await LinkExport.start(
            source, .loopback(), ports, socketFactory: factory, clock: clock, connectionMode: .wired)
        #expect(link.query_address().port == Int(ports.query))
        await stop_link(link, clock)
    }
}
