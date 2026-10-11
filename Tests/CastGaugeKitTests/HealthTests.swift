import Foundation
import Testing
@testable import CastGaugeKit

@Suite("Health")
struct HealthTests {
    let now = Date()

    func link(_ avg: Double, _ jit: Double, _ loss: Double) -> LinkStats {
        LinkStats(avgMs: avg, jitterMs: jit, lossPercent: loss, at: now)
    }

    @Test func lowRateOnCleanLinkIsGood() {
        let s = Snapshot(casting: true, rateBps: 40_000, previousRateBps: 45_000, link: link(5, 1, 0))
        #expect(Health.classify(s) == .good)
    }

    @Test func lossIsLosingData() {
        let s = Snapshot(casting: true, rateBps: 600_000, previousRateBps: 600_000, link: link(5, 1, 5))
        #expect(Health.classify(s) == .losingData)
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
                              link: LinkStats(avgMs: 5, jitterMs: 1, lossPercent: 0, at: old), now: now)
        #expect(s.rateBps == nil && s.link == nil)
        #expect(Health.classify(s) == .unstable)
    }

    @Test func freshSnapshotKeepsValues() {
        let s = Snapshot.make(casting: true, rate: (600_000, now), previous: (500_000, now),
                              link: link(5, 1, 0), now: now)
        #expect(s.rateBps == 600_000 && s.previousRateBps == 500_000 && s.link != nil)
    }
}
