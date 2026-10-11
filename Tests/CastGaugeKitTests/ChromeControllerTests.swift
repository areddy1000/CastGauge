import Foundation
import Synchronization
import Testing
@testable import CastGaugeKit

/// A Chrome stand-in. It records launches and can refuse to quit.
final class FakeChrome: ChromeApp {
    private let state: Mutex<(running: Bool, launches: [[String]])>
    private let quits: Bool

    init(running: Bool, quits: Bool) {
        state = Mutex((running, []))
        self.quits = quits
    }

    var pid: pid_t? { state.withLock { $0.running ? 1 : nil } }
    var launches: [[String]] { state.withLock { $0.launches } }

    func terminate() -> Bool {
        if quits { state.withLock { $0.running = false } }
        return true
    }

    func isRunning() -> Bool { state.withLock { $0.running } }

    func launch(arguments: [String]) throws {
        state.withLock {
            $0.launches.append(arguments)
            $0.running = true
        }
    }
}

@Suite("ChromeController")
struct ChromeControllerTests {
    @Test func parsesPlainLaunchAsInactive() {
        #expect(ChromeController.state(fromArguments: ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]) == .inactive)
        #expect(ChromeController.state(fromArguments: nil) == .notRunning)
    }

    @Test func parsesOwnLaunchAsActive() {
        let s = MirrorSettings(maxRateMbps: 12, bufferMs: 400)
        let argv = ["Google Chrome", "--enable-features=CastStreamingMaxVideoBitrate:max_bitrate_mbps/12,CastStreaming60fps",
                    "--disable-features=MediaRemoting", "--castgauge-playout-delay=400"]
        #expect(ChromeController.state(fromArguments: argv) == .active(s))
    }

    @Test func restartStopsWhenChromeStaysOpen() async {
        let fake = FakeChrome(running: true, quits: false)
        let c = ChromeController(app: fake, quitTimeout: .milliseconds(300))
        await #expect(throws: RestartError.chromeStayedOpen) { try await c.restart(with: .chromeDefault) }
        #expect(fake.launches.isEmpty)
    }

    @Test func restartLaunchesAfterQuit() async throws {
        let fake = FakeChrome(running: true, quits: true)
        let s = MirrorSettings(maxRateMbps: 12, bufferMs: 400)
        try await ChromeController(app: fake, quitTimeout: .seconds(1)).restart(with: s)
        #expect(fake.launches == [s.openArguments()])
    }

    @Test func restartLaunchesAtOnceWhenChromeIsClosed() async throws {
        let fake = FakeChrome(running: false, quits: true)
        try await ChromeController(app: fake, quitTimeout: .seconds(1)).restart(with: .chromeDefault)
        #expect(fake.launches == [MirrorSettings.chromeDefault.openArguments()])
    }

    @Test func restartClampsSettings() async throws {
        let fake = FakeChrome(running: false, quits: true)
        try await ChromeController(app: fake).restart(with: MirrorSettings(maxRateMbps: 99, bufferMs: 400))
        #expect(fake.launches.first?.contains("--enable-features=CastStreamingMaxVideoBitrate:max_bitrate_mbps/20,CastStreaming60fps") == true)
    }
}
