import Foundation
import Testing
@testable import CastGaugeKit

/// Checks against the real tools and the real TV. They run only when CASTGAUGE_LIVE_TV holds the TV address.
@Suite("Live", .enabled(if: ProcessInfo.processInfo.environment["CASTGAUGE_LIVE_TV"] != nil))
struct LiveTests {
    let tv = ProcessInfo.processInfo.environment["CASTGAUGE_LIVE_TV"] ?? ""

    @Test func measuresChromeTraffic() async throws {
        let monitor = TrafficMonitor(targetAddress: tv)
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .seconds(5))
        let latest = try #require(monitor.latest)
        print("live traffic:", latest.bytesPerSecond, "bytes/s =", Double(latest.bytesPerSecond) * 8 / 1_000_000, "Mbit/s")
        #expect(Date().timeIntervalSince(latest.at) < 3)
    }
}
