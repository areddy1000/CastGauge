import Foundation
import Testing
@testable import CastGaugeKit

@Suite("Health")
struct HealthTests {
    let now = Date()

    func link(_ avg: Double, _ jit: Double, _ lost: Int) -> LinkStats {
        LinkStats(avgMs: avg, jitterMs: jit, lossPercent: Double(lost) * 10, lostCount: lost, at: now)
    }

    @Test func lowRateOnCleanLinkIsGood() {
        let s = Snapshot(casting: true, rateBps: 40_000, previousRateBps: 45_000, link: link(5, 1, 0))
        #expect(Health.classify(s) == .good)
    }

    @Test func twoLostPingsIsLosingData() {
        let s = Snapshot(casting: true, rateBps: 600_000, previousRateBps: 600_000, link: link(5, 1, 2))
        #expect(Health.classify(s) == .losingData)
    }

    // One lost ping at the start of a cast must not turn the dot red.
    @Test func oneLostPingIsNotLosingData() {
        let s = Snapshot(casting: true, rateBps: 600_000, previousRateBps: 600_000, link: link(5, 1, 1))
        #expect(Health.classify(s) == .good)
    }

    @Test func highJitterIsUnstable() {
        let s = Snapshot(casting: true, rateBps: 600_000, previousRateBps: 600_000, link: link(10, 25, 0))
        #expect(Health.classify(s) == .unstable)
    }

    @Test func highDelayIsUnstable() {
        let s = Snapshot(casting: true, rateBps: 600_000, previousRateBps: 600_000, link: link(80, 2, 0))
        #expect(Health.classify(s) == .unstable)
    }

    @Test func suddenDropWithDelayIsUnstable() {
        let s = Snapshot(casting: true, rateBps: 200_000, previousRateBps: 600_000, link: link(30, 5, 0))
        #expect(Health.classify(s) == .unstable)
    }

    @Test func suddenDropOnFastLinkIsGood() {
        let s = Snapshot(casting: true, rateBps: 200_000, previousRateBps: 600_000, link: link(5, 1, 0))
        #expect(Health.classify(s) == .good)
    }

    @Test func notCasting() {
        let s = Snapshot(casting: false, rateBps: nil, previousRateBps: nil, link: nil)
        #expect(Health.classify(s) == .notCasting)
    }

    @Test func staleSnapshotHasNoValues() {
        let old = now.addingTimeInterval(-4)
        let s = Snapshot.make(casting: true, rate: (600_000, old), previous: nil,
                              link: LinkStats(avgMs: 5, jitterMs: 1, lossPercent: 0, lostCount: 0, at: old), now: now)
        #expect(s.rateBps == nil && s.link == nil)
        #expect(Health.classify(s) == .unstable)
    }

    @Test func freshSnapshotKeepsValues() {
        let s = Snapshot.make(casting: true, rate: (600_000, now), previous: (500_000, now),
                              link: link(5, 1, 0), now: now)
        #expect(s.rateBps == 600_000 && s.previousRateBps == 500_000 && s.link != nil)
    }
}
