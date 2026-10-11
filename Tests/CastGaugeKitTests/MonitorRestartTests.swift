import Foundation
import Synchronization
import Testing
@testable import CastGaugeKit

@Suite("MonitorRestart")
struct MonitorRestartTests {
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
