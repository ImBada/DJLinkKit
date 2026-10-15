import DJLinkExportTestSupport
import DJLinkKit
import DJLinkTestSupport
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Chris Le (원본 rbxport). Swift 이식: Copyright (c) 2026 Bada
// 원본: crates/rbl-dbserver/tests/release.rs @ 90bfb53da59c5b2c3f0b76101601f30a6b74ab2b
import Testing

@testable import DJLinkExportDBServer

private typealias Message = DJLinkExportDBServer.Message
private typealias Query = DJLinkExportDBServer.Query
private typealias Item = DJLinkExportDBServer.Item

@DJLinkActor private final class Silent: DJLinkExportDBServer.Handler, Session {
    func open() -> any Session { Silent() }
    func handle(_ message: Message) -> [Message] { [] }
}
@Suite @DJLinkActor struct ReleaseTests {
    @Test("dropping_the_server_without_shutdown_releases_both_ports")
    func dropping_the_server_without_shutdown_releases_both_ports() async throws {
        let clock = TestClock()
        let factory = FakeExportSocketFactory(clock: clock)
        var bound: Bound? = try await .start(Silent(), "127.0.0.1", 0, 0, socketFactory: factory, clock: clock)
        let query = try #require(bound).query_address()
        let database = try #require(bound).database_address()
        clock.advance(ms: 200)
        bound = nil
        await clock.settle()
        let queryListener = try factory.createTCPListener()
        let databaseListener = try factory.createTCPListener()
        #expect(try await queryListener.bind(port: query.port, address: query.address) == query)
        #expect(try await databaseListener.bind(port: database.port, address: database.address) == database)
        try queryListener.close()
        try databaseListener.close()
    }
    @Test("shutdown_releases_both_ports_and_the_same_ports_serve_again")
    func shutdown_releases_both_ports_and_the_same_ports_serve_again() async throws {
        let clock = TestClock()
        let factory = FakeExportSocketFactory(clock: clock)
        let bound = try await Bound.start(Silent(), "127.0.0.1", 0, 0, socketFactory: factory, clock: clock)
        let query = bound.query_address()
        let database = bound.database_address()
        let started = clock.nowMilliseconds()
        await bound.shutdown()
        #expect(clock.nowMilliseconds() - started < 2000)
        for _ in 0..<2 {
            let again = try await Bound.start(
                Silent(), "127.0.0.1", UInt16(query.port), UInt16(database.port), socketFactory: factory, clock: clock)
            #expect(again.query_address() == query)
            let stream = try factory.createTCPConnection()
            try await stream.connect(port: database.port, host: database.address)
            await again.shutdown()
        }
    }
    @Test("a_player_is_still_accepted_promptly") func a_player_is_still_accepted_promptly() async throws {
        let clock = TestClock()
        let factory = FakeExportSocketFactory(clock: clock)
        let bound = try await Bound.start(Silent(), "127.0.0.1", 0, 0, socketFactory: factory, clock: clock)
        let stream = try factory.createTCPConnection()
        let database = bound.database_address()
        try await stream.connect(port: database.port, host: database.address)
        try await stream.write(GREETING)
        let started = clock.nowMilliseconds()
        let greeting = try await stream.read(5)
        #expect(greeting == GREETING)
        #expect(clock.nowMilliseconds() - started < 1000)
        await bound.shutdown()
    }
}
