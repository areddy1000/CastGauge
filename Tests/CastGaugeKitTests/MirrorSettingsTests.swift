import Testing
@testable import CastGaugeKit

@Suite("MirrorSettings")
struct MirrorSettingsTests {
    @Test func buildsOpenArguments() {
        let s = MirrorSettings(maxRateMbps: 12, bufferMs: 400, frameRate: 60)
        #expect(s.openArguments() == [
            "-a", "Google Chrome",
            "--env", "CHROME_MIRRORING_PLAYOUT_DELAY=400",
            "--args", "--restore-last-session",
            "--enable-features=CastStreamingMaxVideoBitrate:max_bitrate_mbps/12,CastStreaming60fps",
            "--disable-features=MediaRemoting",
            "--castgauge-playout-delay=400",
        ])
    }

    // At 60 fps the TV ignores the "remoting" offer, and Chrome stops the cast. Test of 2026-10-11.
    @Test func keepsRemotingAt30() {
        let args = MirrorSettings(maxRateMbps: 20, bufferMs: 600, frameRate: 30).openArguments()
        #expect(!args.contains { $0.hasPrefix("--disable-features") })
    }

    @Test func leaves60fpsOutAt30() {
        let args = MirrorSettings(maxRateMbps: 8, bufferMs: 200, frameRate: 30).openArguments()
        #expect(args.contains("--enable-features=CastStreamingMaxVideoBitrate:max_bitrate_mbps/8"))
    }

    @Test func parsesItsOwnArguments() {
        let s = MirrorSettings(maxRateMbps: 12, bufferMs: 400, frameRate: 60)
        let chromeArgv = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]
            + s.openArguments().drop(while: { $0 != "--args" }).dropFirst()
        #expect(MirrorSettings.parse(chromeArguments: Array(chromeArgv)) == s)
    }

    @Test func parsesFeaturesAmongOthers() {
        let argv = [
            "Google Chrome",
            "--enable-features=Foo,CastStreamingMaxVideoBitrate:max_bitrate_mbps/9,Bar",
            "--castgauge-playout-delay=250",
        ]
        #expect(MirrorSettings.parse(chromeArguments: argv)
                == MirrorSettings(maxRateMbps: 9, bufferMs: 250, frameRate: 30))
    }

    @Test func clampsOutOfRangeValues() {
        #expect(MirrorSettings(maxRateMbps: 50, bufferMs: 5, frameRate: 45).clamped()
                == MirrorSettings(maxRateMbps: 20, bufferMs: 100, frameRate: 30))
    }
}
