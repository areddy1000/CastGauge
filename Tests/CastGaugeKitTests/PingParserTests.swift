import Foundation
import Testing
@testable import CastGaugeKit

@Suite("PingParser")
struct PingParserTests {
    @Test func parsesReply() {
        #expect(PingEvent.parse("64 bytes from 192.168.1.155: icmp_seq=3 ttl=64 time=5.616 ms") == .reply(seq: 3, ms: 5.616))
    }

    @Test func parsesTimeout() {
        #expect(PingEvent.parse("Request timeout for icmp_seq 4") == .timeout(seq: 4))
    }

    @Test func windowComputesStats() {
        var w = LinkWindow(capacity: 4)
        let t = Date()
        [PingEvent.reply(seq: 1, ms: 4), .reply(seq: 2, ms: 6), .timeout(seq: 3), .reply(seq: 4, ms: 5)]
            .forEach { w.add($0, at: t) }
        #expect(w.stats?.avgMs == 5)
        #expect(w.stats?.lossPercent == 25)
        #expect(w.stats?.lostCount == 1)
        #expect(abs((w.stats?.jitterMs ?? 0) - 0.8165) < 0.001)
    }

    @Test func windowDropsOldEvents() {
        var w = LinkWindow(capacity: 2)
        [PingEvent.timeout(seq: 1), .reply(seq: 2, ms: 5), .reply(seq: 3, ms: 5)].forEach { w.add($0, at: Date()) }
        #expect(w.stats?.lossPercent == 0)
    }

    @Test func defaultWindowHoldsTenPings() {
        var w = LinkWindow()
        w.add(.timeout(seq: 0), at: Date())
        (1...10).forEach { w.add(.reply(seq: $0, ms: 5), at: Date()) }
        #expect(w.stats?.lostCount == 0)
    }

    @Test func emptyWindowHasNoStats() {
        #expect(LinkWindow().stats == nil)
    }

    @Test func allTimeoutsIsFullLoss() {
        var w = LinkWindow(capacity: 3)
        [PingEvent.timeout(seq: 1), .timeout(seq: 2)].forEach { w.add($0, at: Date()) }
        #expect(w.stats?.lossPercent == 100)
        #expect(w.stats?.avgMs == 0)
    }
}
