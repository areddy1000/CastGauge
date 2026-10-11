import Testing
@testable import CastGaugeKit

/// Retries wait longer after each failure, so an unreachable TV costs almost nothing.
@Suite("Backoff")
struct BackoffTests {
    @Test func doublesUpToTheLimit() {
        var backoff = Backoff(initial: 5, limit: 300)
        let delays = (0..<8).map { _ in backoff.next() }
        #expect(delays == [5, 10, 20, 40, 80, 160, 300, 300])
    }

    @Test func resetStartsAgain() {
        var backoff = Backoff(initial: 5, limit: 300)
        _ = backoff.next()
        _ = backoff.next()
        backoff.reset()
        #expect(backoff.next() == 5)
    }
}
