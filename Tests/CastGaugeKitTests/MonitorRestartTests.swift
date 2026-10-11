import Foundation
import Synchronization
import Testing
@testable import CastGaugeKit

@Suite("MonitorRestart")
struct MonitorRestartTests {
    let sample = [",bytes_out,", "Google Chrome H.1,700,", "udp4 *:5000<->*:*,700000,"]

    // After a nettop restart, the first full sample holds the totals since the flow opened.
    @Test func restartSkipsTheCumulativeSample() {
        var traffic = TrafficAccumulator(targetAddress: "192.168.1.155")
        traffic.launched()
        (sample + sample + [",bytes_out,"]).forEach { traffic.feed($0, at: Date()) }
        #expect(traffic.latest?.bytesPerSecond == 700_000)

        traffic.launched()
        // The old process left a partial sample. The new process starts with a cumulative sample.
        traffic.feed("udp4 *:5000<->*:*,999,", at: Date())
        [",bytes_out,", "Google Chrome H.1,9,", "udp4 *:5000<->*:*,1075000000,", ",bytes_out,"]
            .forEach { traffic.feed($0, at: Date()) }
        #expect(traffic.latest?.bytesPerSecond == 700_000)
        ["Google Chrome H.1,9,", "udp4 *:5000<->*:*,650000,", ",bytes_out,"]
            .forEach { traffic.feed($0, at: Date()) }
        #expect(traffic.latest?.bytesPerSecond == 650_000)
    }

    // A tool that writes nothing for the silence limit gets stopped, and LineProcess starts it again.
    @Test func restartsASilentTool() async throws {
        let launches = Mutex(0)
        let process = LineProcess(executable: "/bin/sleep", arguments: ["30"], silenceLimit: .milliseconds(500),
                                  restartDelay: .milliseconds(200), onLaunch: { launches.withLock { $0 += 1 } },
                                  onLine: { _ in })
        process.start()
        defer { process.stop() }
        try await Task.sleep(for: .seconds(2.5))
        #expect(launches.withLock { $0 } >= 2)
    }

    @Test func allTimeoutsHaveNoDelay() {
        var w = LinkWindow(capacity: 3)
        [PingEvent.timeout(seq: 1), .timeout(seq: 2)].forEach { w.add($0, at: Date()) }
        #expect(w.stats?.avgMs == nil)
        #expect(w.stats?.jitterMs == nil)
        #expect(w.stats?.lostCount == 2)
    }
}
