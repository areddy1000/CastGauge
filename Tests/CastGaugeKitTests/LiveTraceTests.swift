import Foundation
import Testing
@testable import CastGaugeKit

/// Prints the monitor values once per second for 20 seconds. It runs only with CASTGAUGE_TRACE_TV.
@Suite("LiveTrace", .enabled(if: ProcessInfo.processInfo.environment["CASTGAUGE_TRACE_TV"] != nil))
struct LiveTraceTests {
    @Test func traceHealth() async throws {
        let tv = ProcessInfo.processInfo.environment["CASTGAUGE_TRACE_TV"] ?? ""
        let link = LinkMonitor(targetAddress: tv)
        let traffic = TrafficMonitor(targetAddress: tv)
        link.start(); traffic.start()
        defer { link.stop(); traffic.stop() }
        var last: (bytesPerSecond: Int, at: Date)?
        var previous: (bytesPerSecond: Int, at: Date)?
        for second in 1...20 {
            try await Task.sleep(for: .seconds(1))
            let now = Date()
            if let rate = traffic.latest, rate.at != last?.at { previous = last; last = rate }
            let snapshot = Snapshot.make(casting: true, rate: last, previous: previous, link: link.latest, now: now)
            let linkAge = link.latest.map { now.timeIntervalSince($0.at) }
            print(String(format: "t=%02d", second), "rate:", snapshot.rateBps.map { Double($0) * 8 / 1e6 } as Any,
                  "prev:", snapshot.previousRateBps.map { Double($0) * 8 / 1e6 } as Any,
                  "link:", link.latest.map { String(format: "%.1fms j%.1f loss%.0f", $0.avgMs, $0.jitterMs, $0.lossPercent) } as Any,
                  "linkAge:", linkAge.map { String(format: "%.1f", $0) } as Any,
                  "health:", Health.classify(snapshot))
        }
    }
}
