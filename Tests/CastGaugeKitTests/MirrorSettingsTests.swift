import Foundation
import Testing
@testable import CastGaugeKit

@Suite("MirrorSettings")
struct MirrorSettingsTests {
    // The user sets only the rate and the buffer. The content sets the frame rate, up to 60,
    // and remoting stays off, because the test TV never answers a remoting offer.
    @Test func buildsOpenArguments() {
        let s = MirrorSettings(maxRateMbps: 12, bufferMs: 400)
        #expect(s.openArguments() == [
            "-a", "Google Chrome",
            "--env", "CHROME_MIRRORING_PLAYOUT_DELAY=400",
            "--args", "--restore-last-session",
            "--enable-features=CastStreamingMaxVideoBitrate:max_bitrate_mbps/12,CastStreaming60fps",
            "--disable-features=MediaRemoting",
            "--castgauge-playout-delay=400",
        ])
    }

    @Test func parsesItsOwnArguments() {
        let s = MirrorSettings(maxRateMbps: 12, bufferMs: 400)
        let chromeArgv = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]
            + s.openArguments().drop(while: { $0 != "--args" }).dropFirst()
        #expect(MirrorSettings.parse(chromeArguments: Array(chromeArgv)) == s)
    }

    @Test func parsesFeaturesAmongOthers() {
        let argv = [
            "Google Chrome",
            "--enable-features=Foo,CastStreamingMaxVideoBitrate:max_bitrate_mbps/9,CastStreaming60fps,Bar",
            "--disable-features=Baz,MediaRemoting",
            "--castgauge-playout-delay=250",
        ]
        #expect(MirrorSettings.parse(chromeArguments: argv) == MirrorSettings(maxRateMbps: 9, bufferMs: 250))
    }

    // A Chrome from an older CastGauge launch has other fixed switches, so it is not active.
    @Test func olderLaunchIsNotActive() {
        let argv = ["Google Chrome", "--enable-features=CastStreamingMaxVideoBitrate:max_bitrate_mbps/9",
                    "--castgauge-playout-delay=250"]
        #expect(MirrorSettings.parse(chromeArguments: argv) == nil)
    }

    @Test func clampsOutOfRangeValues() {
        #expect(MirrorSettings(maxRateMbps: 50, bufferMs: 5).clamped() == MirrorSettings(maxRateMbps: 20, bufferMs: 100))
    }

    // Settings saved with a frame rate and a remoting choice still load. Those values are ignored.
    @Test func oldSavedSettingsLoad() throws {
        let json = #"{"maxRateMbps":20,"bufferMs":600,"frameRate":60,"remoting":false}"#
        let settings = try JSONDecoder().decode(MirrorSettings.self, from: Data(json.utf8))
        #expect(settings == MirrorSettings(maxRateMbps: 20, bufferMs: 600))
    }
}
