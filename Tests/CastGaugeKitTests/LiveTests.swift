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

extension LiveTests {
    @Test func measuresTheLink() async throws {
        let monitor = LinkMonitor(targetAddress: tv)
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .seconds(4))
        let stats = try #require(monitor.latest)
        print("live link:", stats.avgMs, "ms avg,", stats.jitterMs, "ms jitter,", stats.lossPercent, "% loss")
        #expect(stats.avgMs > 0)
    }
}

extension LiveTests {
    @Test func findsTheMirroringTV() async throws {
        let discovery = CastDiscovery()
        discovery.start()
        defer { discovery.stop() }
        try await Task.sleep(for: .seconds(4))
        print("live devices:", discovery.devices, "denied:", discovery.permissionDenied)
        let picked = try #require(CastDevice.pick(discovery.devices))
        #expect(picked.address == tv)
    }

    @Test func readsTheMacWiFi() throws {
        let wifi = try #require(WiFiReader.read())
        print("live wifi:", wifi)
        #expect(wifi.rssi < 0)
    }
}

extension LiveTests {
    @Test func readsTheRealChromeState() {
        let state = ChromeController().state()
        print("live chrome state:", state)
        #expect(state != .notRunning)
    }
}
