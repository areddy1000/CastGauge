# CastGauge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that shows the health of a Chrome tab cast and sets the Chrome mirror quality at launch.

**Architecture:** A UI-free library, `CastGaugeKit`, holds the monitors (cast discovery, traffic, ping, Wi-Fi), a pure health classifier, and the Chrome controller. Each monitor wraps a pure parser, and tests cover the parsers. The `CastGauge` executable is a SwiftUI `MenuBarExtra` with one Material 3 panel, fed by one `@Observable` model that samples the monitors once per second.

**Tech Stack:** Swift 6, SwiftUI, Network.framework (`NWBrowser`), CoreWLAN, AppKit (`NSRunningApplication`), Swift Testing, SwiftPM with the Command Line Tools only.

**Spec:** `docs/superpowers/specs/2026-10-11-cast-gauge-design.md`

## Global Constraints

- Swift 6 language mode. `platforms: [.macOS(.v15)]`. `swift-tools-version: 6.0`.
- No Xcode. Every swift command needs `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`. The scripts set it.
- Tests use Swift Testing (`import Testing`). Run them with `scripts/test.sh`. It passes the testing plugin path, as in `/Users/Apple/Code/AppleTv/scripts/test.sh`.
- `CastGaugeKit` has no package dependencies. Its API is `public`.
- Ad-hoc signature: `codesign --force --sign - --timestamp=none`.
- Bundle ID `com.castgauge.mac`. Display name `CastGauge`. `LSUIElement` true. `LSMinimumSystemVersion` 15.0.
- Chrome bundle ID: `com.google.Chrome`.
- Chrome launch values (confirmed in the Chrome 154.0.8037.98 source):
  - feature `CastStreamingMaxVideoBitrate`, parameter `max_bitrate_mbps` (Chrome default 5)
  - feature `CastStreaming60fps` (off by default)
  - environment variable `CHROME_MIRRORING_PLAYOUT_DELAY` (milliseconds)
  - marker switch `--castgauge-playout-delay=<ms>`
- Ranges: max rate 5...20 Mbit/s (whole numbers, default 5). Buffer 100...1000 ms (default 400). Frame rate 30 or 60 (default 30).
- Quit Chrome only with `NSRunningApplication.terminate()`. Never force quit. No Apple event entitlement.
- No sound control. No Google account. No Google logo or product names in the UI.
- If macOS refuses a permission, show it in the panel and stop that feature. Do not build a workaround.
- Never show a stale or guessed value as a measurement. A value older than 3 seconds shows as "—".
- Code comments, docstrings and commit messages follow the ASD-STE100 rules in `~/.claude/CLAUDE.md`. End each commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Chrome opened from the Dock after an apply:** the flags are gone. The panel must show "Not active in Chrome", not the saved values. (Task 6 test `parsesPlainLaunchAsInactive`.)
2. **Chrome refuses to quit** (for example a "Leave site?" dialog): after 20 seconds the app stops and says so. It never force quits. (Task 6 test `restartStopsWhenChromeStaysOpen`.)
3. **A monitor process dies or stops output** (`nettop` or `ping`): the values become "—" and the monitor restarts. Old numbers must not stay on screen. (Task 5 test `staleSnapshotHasNoValues`.)
4. **Still content on a clean link:** the rate is far below the maximum. The status must stay "Good". (Task 5 test `lowRateOnCleanLinkIsGood`.)
5. **The TV is gone or a second Cast device exists:** the app follows the device with `rs=Chrome Mirroring`, and shows "Not casting" when no device mirrors. (Task 4 test `picksTheMirroringDevice`.)

---

## File Structure

```
CastGauge/
  Package.swift
  Resources/Info.plist
  Resources/Fonts/RobotoFlex.ttf                 (OFL, from google/fonts ofl/robotoflex)
  Resources/Fonts/MaterialSymbolsRounded.ttf     (Apache 2.0, from google/material-design-icons variablefont)
  scripts/build-app.sh  scripts/test.sh  scripts/run.sh
  Sources/CastGaugeKit/
    MirrorSettings.swift        settings value, ranges, Chrome argument build and parse
    ChromeController.swift      find Chrome, read its argv, restart it
    ProcessArguments.swift      KERN_PROCARGS2 parser
    LineProcess.swift           runs a tool and streams its output lines; restarts it
    TrafficParser.swift         nettop line parser
    TrafficMonitor.swift        bytes per second from Chrome to the TV
    PingParser.swift            ping line parser and rolling window
    LinkMonitor.swift           delay, variation, loss to the TV
    CastDiscovery.swift         NWBrowser for _googlecast._tcp, TXT parse, address resolve
    WiFiReader.swift            CoreWLAN snapshot
    Health.swift                health classifier and thresholds
  Sources/CastGauge/
    CastGaugeApp.swift          @main, MenuBarExtra, font registration
    GaugeModel.swift            @Observable model, 1 s sampler
    Theme/Material.swift        color roles (light, dark), shapes, motion, type
    Theme/Symbol.swift          Material Symbols view
    Views/MenuBarLabel.swift
    Views/Panel.swift  Views/HeaderView.swift  Views/ConnectionCard.swift  Views/QualityCard.swift
  Tests/CastGaugeKitTests/
    MirrorSettingsTests.swift  ProcessArgumentsTests.swift  TrafficParserTests.swift
    PingParserTests.swift  CastDiscoveryTests.swift  HealthTests.swift  ChromeControllerTests.swift
```

---

### Task 1: Package, scripts, and mirror settings

**Files:**
- Create: `Package.swift`, `Resources/Info.plist`, `scripts/build-app.sh`, `scripts/test.sh`, `scripts/run.sh`
- Create: `Sources/CastGaugeKit/MirrorSettings.swift`, `Sources/CastGauge/CastGaugeApp.swift` (empty `MenuBarExtra("CastGauge") { Text("CastGauge") }` placeholder)
- Test: `Tests/CastGaugeKitTests/MirrorSettingsTests.swift`

**Interfaces:**
- Produces:
  - `public struct MirrorSettings: Equatable, Codable, Sendable { public var maxRateMbps: Int; public var bufferMs: Int; public var frameRate: Int }`
  - `public static let chromeDefault: MirrorSettings` (5, 400, 30)
  - `public static let maxRateRange = 5...20`, `bufferRange = 100...1000`, `frameRates = [30, 60]`
  - `public func clamped() -> MirrorSettings`
  - `public func openArguments() -> [String]` (arguments for `/usr/bin/open`)
  - `public static func parse(chromeArguments: [String]) -> MirrorSettings?`

Copy the three scripts from `/Users/Apple/Code/AppleTv/scripts/` and change the names: product `CastGauge`, app `dist/CastGauge.app`, process name `CastGauge`. `build-app.sh` also copies `Resources/Fonts` into `Contents/Resources/Fonts`. Info.plist: base it on the AppleTv one. Remove the URL types. Add `LSUIElement` true. Set `NSBonjourServices` to `_googlecast._tcp`. Set `NSLocalNetworkUsageDescription` to "CastGauge finds your Cast device and measures the link to it."

- [ ] **Step 1: Write the failing tests**

```swift
@Test func buildsOpenArguments() {
    let s = MirrorSettings(maxRateMbps: 12, bufferMs: 400, frameRate: 60)
    #expect(s.openArguments() == [
        "-a", "Google Chrome",
        "--env", "CHROME_MIRRORING_PLAYOUT_DELAY=400",
        "--args", "--restore-last-session",
        "--enable-features=CastStreamingMaxVideoBitrate:max_bitrate_mbps/12,CastStreaming60fps",
        "--castgauge-playout-delay=400",
    ])
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
    let argv = ["Google Chrome", "--enable-features=Foo,CastStreamingMaxVideoBitrate:max_bitrate_mbps/9,Bar",
                "--castgauge-playout-delay=250"]
    #expect(MirrorSettings.parse(chromeArguments: argv) == MirrorSettings(maxRateMbps: 9, bufferMs: 250, frameRate: 30))
}
@Test func clampsOutOfRangeValues() {
    #expect(MirrorSettings(maxRateMbps: 50, bufferMs: 5, frameRate: 45).clamped()
            == MirrorSettings(maxRateMbps: 20, bufferMs: 100, frameRate: 30))
}
```

- [ ] **Step 2: Run the tests and make sure they fail**

Run: `scripts/test.sh` — Expected: compile error, `MirrorSettings` not found.

- [ ] **Step 3: Implement `MirrorSettings` in `Sources/CastGaugeKit/MirrorSettings.swift`**

`parse` returns nil when the marker switch is missing. The marker proves that CastGauge made this launch. A frame rate that is not 60 clamps to 30.

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `scripts/test.sh` — Expected: all tests pass.

- [ ] **Step 5: Build the bundle**

Run: `scripts/build-app.sh debug` — Expected: `Built: .../dist/CastGauge.app`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Add the package and the mirror settings"
```

---

### Task 2: Line process, traffic parser, and traffic monitor

**Files:**
- Create: `Sources/CastGaugeKit/LineProcess.swift`, `TrafficParser.swift`, `TrafficMonitor.swift`
- Test: `Tests/CastGaugeKitTests/TrafficParserTests.swift`

**Interfaces:**
- Produces:
  - `public final class LineProcess: Sendable` — `init(executable: String, arguments: [String], onLine: @Sendable @escaping (String) -> Void)`, `start()`, `stop()`. It restarts the tool 2 seconds after the tool exits, until `stop()`.
  - `public struct TrafficParser: Sendable` — `mutating func feed(_ line: String) -> Int?` returns the bytes sent to the target in the sample that the line closes, or nil.
  - `public init(targetAddress: String, processPrefix: String = "Google Chrome")`
  - `public final class TrafficMonitor: Sendable` — `init(targetAddress: String)`, `start()`, `stop()`, `var latest: (bytesPerSecond: Int, at: Date)? { get }`

Source tool: `/usr/bin/nettop -d -L 0 -s 1 -n -x -J bytes_out`. With `-d`, each value is the change since the last sample. Each sample starts with a header line `,bytes_out,`. Process lines look like `Google Chrome H.34072,631742,`. Flow lines under a process look like `udp4 192.168.1.188:50123<->192.168.1.155:38429,612000,`. Count a flow only when it belongs to a process whose name starts with `processPrefix` and its remote address equals `targetAddress`. A header line closes the previous sample.

- [ ] **Step 1: Write the failing tests**

```swift
let sample = """
,bytes_out,
Google Chrome H.34072,640000,
udp4 192.168.1.188:50123<->192.168.1.155:38429,612000,
tcp4 192.168.1.188:52112<->18.97.36.16:443,28000,
Safari.501,9000,
udp4 192.168.1.188:50999<->192.168.1.155:38429,5000,
,bytes_out,
"""
@Test func countsOnlyChromeFlowsToTheTV() {
    var p = TrafficParser(targetAddress: "192.168.1.155")
    let results = sample.split(separator: "\n").compactMap { p.feed(String($0)) }
    #expect(results == [612000])
}
@Test func emptySampleIsZero() {
    var p = TrafficParser(targetAddress: "192.168.1.155")
    _ = p.feed(",bytes_out,")
    #expect(p.feed(",bytes_out,") == 0)
}
@Test func ignoresGarbage() {
    var p = TrafficParser(targetAddress: "192.168.1.155")
    #expect(p.feed("nettop: something odd") == nil)
}
```

- [ ] **Step 2: Run the tests and make sure they fail** — `scripts/test.sh`, Expected: `TrafficParser` not found.
- [ ] **Step 3: Implement `LineProcess`, `TrafficParser`, `TrafficMonitor`.** `LineProcess` uses `Foundation.Process` and a `Pipe` with `readabilityHandler`, and splits on newlines. Keep state behind a `Mutex` (Synchronization) so the types are `Sendable`.
- [ ] **Step 4: Run the tests and make sure they pass** — `scripts/test.sh`.
- [ ] **Step 5: Check against the real tool.** Cast a tab. Run a one-off test executable or `swift repl` snippet that prints `TrafficMonitor.latest` for 5 seconds. Expected: about 600000 bytes per second (5 Mbit/s). Compare with `nettop -d -L 3 -s 1 -n -x -J bytes_out | grep 192.168.1.155`.
- [ ] **Step 6: Commit** — `git commit -m "Measure the Chrome traffic to the TV"`

---

### Task 3: Ping parser and link monitor

**Files:**
- Create: `Sources/CastGaugeKit/PingParser.swift`, `LinkMonitor.swift`
- Test: `Tests/CastGaugeKitTests/PingParserTests.swift`

**Interfaces:**
- Consumes: `LineProcess` (Task 2).
- Produces:
  - `public enum PingEvent: Equatable { case reply(seq: Int, ms: Double), timeout(seq: Int) }`
  - `public static func PingEvent.parse(_ line: String) -> PingEvent?`
  - `public struct LinkWindow: Sendable` — `init(capacity: Int = 30)`, `mutating func add(_ e: PingEvent, at: Date)`, `var stats: LinkStats? { get }` (nil when empty)
  - `public struct LinkStats: Equatable, Sendable { public let avgMs: Double; public let jitterMs: Double; public let lossPercent: Double; public let at: Date }` — `jitterMs` is the population standard deviation of the replies.
  - `public final class LinkMonitor: Sendable` — `init(targetAddress: String)`, `start()`, `stop()`, `var latest: LinkStats? { get }`

Source tool: `/sbin/ping -n -i 1 <address>`. Lines: `64 bytes from 192.168.1.155: icmp_seq=3 ttl=64 time=5.616 ms` and `Request timeout for icmp_seq 4`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func parsesReply() {
    #expect(PingEvent.parse("64 bytes from 192.168.1.155: icmp_seq=3 ttl=64 time=5.616 ms") == .reply(seq: 3, ms: 5.616))
}
@Test func parsesTimeout() {
    #expect(PingEvent.parse("Request timeout for icmp_seq 4") == .timeout(seq: 4))
}
@Test func windowComputesStats() {
    var w = LinkWindow(capacity: 4)
    let t = Date()
    [PingEvent.reply(seq: 1, ms: 4), .reply(seq: 2, ms: 6), .timeout(seq: 3), .reply(seq: 4, ms: 5)].forEach { w.add($0, at: t) }
    #expect(w.stats?.avgMs == 5)
    #expect(w.stats?.lossPercent == 25)
    #expect(abs((w.stats?.jitterMs ?? 0) - 0.8165) < 0.001)
}
@Test func windowDropsOldEvents() {
    var w = LinkWindow(capacity: 2)
    [PingEvent.timeout(seq: 1), .reply(seq: 2, ms: 5), .reply(seq: 3, ms: 5)].forEach { w.add($0, at: Date()) }
    #expect(w.stats?.lossPercent == 0)
}
```

- [ ] **Step 2: Run the tests and make sure they fail** — `scripts/test.sh`.
- [ ] **Step 3: Implement `PingEvent`, `LinkWindow`, `LinkMonitor`.** All timeouts in the window give `avgMs` and `jitterMs` of 0 and `lossPercent` 100.
- [ ] **Step 4: Run the tests and make sure they pass** — `scripts/test.sh`.
- [ ] **Step 5: Commit** — `git commit -m "Measure the delay and loss to the TV"`

---

### Task 4: Cast discovery and Wi-Fi reader

**Files:**
- Create: `Sources/CastGaugeKit/CastDiscovery.swift`, `WiFiReader.swift`
- Test: `Tests/CastGaugeKitTests/CastDiscoveryTests.swift`

**Interfaces:**
- Produces:
  - `public struct CastDevice: Equatable, Sendable { public let id: String; public let name: String; public let isMirroring: Bool; public var address: String? }`
  - `public static func CastDevice.from(txt: [String: String]) -> CastDevice?` — `id` from `id`, `name` from `fn`, `isMirroring` when `rs == "Chrome Mirroring"`. Nil without `id` or `fn`.
  - `public static func CastDevice.pick(_ devices: [CastDevice]) -> CastDevice?` — the first mirroring device, else nil.
  - `public final class CastDiscovery: Sendable` — `start()`, `stop()`, `var devices: [CastDevice] { get }`, `var permissionDenied: Bool { get }`. It uses `NWBrowser(for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil), using: .tcp)`. It resolves the address with a short `NWConnection` to the result endpoint and reads `currentPath?.remoteEndpoint`. It sets `permissionDenied` when the browser state is `.waiting` with a policy-denied error.
  - `public struct WiFiStatus: Equatable, Sendable { public let rssi: Int; public let noise: Int; public let band: String }` — band is "2.4 GHz", "5 GHz", or "6 GHz".
  - `public enum WiFiReader { public static func read() -> WiFiStatus?; static func bandName(_ b: CWChannelBand) -> String }` — nil when there is no interface or the RSSI is 0.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func parsesTXT() {
    let d = CastDevice.from(txt: ["id": "d6f4", "fn": "Bedroom TV", "md": "Chromecast", "rs": "Chrome Mirroring"])
    #expect(d == CastDevice(id: "d6f4", name: "Bedroom TV", isMirroring: true, address: nil))
}
@Test func idleDeviceIsNotMirroring() {
    #expect(CastDevice.from(txt: ["id": "a", "fn": "Kitchen"])?.isMirroring == false)
}
@Test func picksTheMirroringDevice() {
    let idle = CastDevice(id: "a", name: "Kitchen", isMirroring: false, address: "192.168.1.20")
    let busy = CastDevice(id: "b", name: "Bedroom TV", isMirroring: true, address: "192.168.1.155")
    #expect(CastDevice.pick([idle, busy]) == busy)
    #expect(CastDevice.pick([idle]) == nil)
}
@Test func namesBands() {
    #expect(WiFiReader.bandName(.band5GHz) == "5 GHz")
}
```

- [ ] **Step 2: Run the tests and make sure they fail** — `scripts/test.sh`.
- [ ] **Step 3: Implement `CastDevice`, `CastDiscovery`, `WiFiReader`.** Link `CoreWLAN` in `Package.swift` with `linkerSettings: [.linkedFramework("CoreWLAN")]`.
- [ ] **Step 4: Run the tests and make sure they pass** — `scripts/test.sh`.
- [ ] **Step 5: Commit** — `git commit -m "Find the Cast device and read the Mac Wi-Fi"`

---

### Task 5: Health classifier and snapshot

**Files:**
- Create: `Sources/CastGaugeKit/Health.swift`
- Test: `Tests/CastGaugeKitTests/HealthTests.swift`

**Interfaces:**
- Consumes: `LinkStats` (Task 3), `MirrorSettings` (Task 1).
- Produces:
  - `public enum Health: Equatable, Sendable { case notCasting, good, unstable, losingData }`
  - `public struct HealthThresholds: Sendable { public var lossPercent = 2.0; public var delayMs = 50.0; public var jitterMs = 20.0; public var suddenDropRatio = 0.5; public static let standard = HealthThresholds() }`
  - `public struct Snapshot: Equatable, Sendable { public let casting: Bool; public let rateBps: Int?; public let previousRateBps: Int?; public let link: LinkStats? }`
  - `public static func Snapshot.make(casting: Bool, rate: (bytesPerSecond: Int, at: Date)?, previous: (bytesPerSecond: Int, at: Date)?, link: LinkStats?, now: Date) -> Snapshot` — drops any value older than 3 seconds.
  - `public static func Health.classify(_ s: Snapshot, _ t: HealthThresholds = .standard) -> Health`

Rules, in this order:
1. Not casting → `.notCasting`.
2. `link.lossPercent >= t.lossPercent` → `.losingData`.
3. `link.avgMs >= t.delayMs` or `link.jitterMs >= t.jitterMs` → `.unstable`.
4. The rate fell below `suddenDropRatio` of the previous rate, and the delay is above half of `t.delayMs` → `.unstable`.
5. Otherwise `.good`. A rate below the maximum alone is never a warning.
6. No link stats (stale or missing) while casting → `.unstable`.

- [ ] **Step 1: Write the failing tests**

```swift
let now = Date()
func link(_ avg: Double, _ jit: Double, _ loss: Double) -> LinkStats { LinkStats(avgMs: avg, jitterMs: jit, lossPercent: loss, at: now) }
@Test func lowRateOnCleanLinkIsGood() {
    let s = Snapshot(casting: true, rateBps: 40_000, previousRateBps: 45_000, link: link(5, 1, 0))
    #expect(Health.classify(s) == .good)
}
@Test func lossIsLosingData() {
    #expect(Health.classify(Snapshot(casting: true, rateBps: 600_000, previousRateBps: 600_000, link: link(5, 1, 5))) == .losingData)
}
@Test func highJitterIsUnstable() {
    #expect(Health.classify(Snapshot(casting: true, rateBps: 600_000, previousRateBps: 600_000, link: link(10, 25, 0))) == .unstable)
}
@Test func suddenDropWithDelayIsUnstable() {
    #expect(Health.classify(Snapshot(casting: true, rateBps: 200_000, previousRateBps: 600_000, link: link(30, 5, 0))) == .unstable)
}
@Test func notCasting() {
    #expect(Health.classify(Snapshot(casting: false, rateBps: nil, previousRateBps: nil, link: nil)) == .notCasting)
}
@Test func staleSnapshotHasNoValues() {
    let old = now.addingTimeInterval(-4)
    let s = Snapshot.make(casting: true, rate: (600_000, old), previous: nil,
                          link: LinkStats(avgMs: 5, jitterMs: 1, lossPercent: 0, at: old), now: now)
    #expect(s.rateBps == nil && s.link == nil)
    #expect(Health.classify(s) == .unstable)
}
```

- [ ] **Step 2: Run the tests and make sure they fail** — `scripts/test.sh`.
- [ ] **Step 3: Implement `Health`, `HealthThresholds`, `Snapshot`.**
- [ ] **Step 4: Run the tests and make sure they pass** — `scripts/test.sh`.
- [ ] **Step 5: Commit** — `git commit -m "Classify the cast health"`

---

### Task 6: Chrome controller

**Files:**
- Create: `Sources/CastGaugeKit/ProcessArguments.swift`, `ChromeController.swift`
- Test: `Tests/CastGaugeKitTests/ProcessArgumentsTests.swift`, `ChromeControllerTests.swift`

**Interfaces:**
- Consumes: `MirrorSettings` (Task 1).
- Produces:
  - `public enum ProcessArguments { public static func parse(procargs2 data: Data) -> [String]?; public static func read(pid: pid_t) -> [String]? }` — `read` uses `sysctl([CTL_KERN, KERN_PROCARGS2, pid])`. Layout: a 4-byte `argc`, the executable path, NUL padding, then `argc` NUL-terminated strings.
  - `public protocol ChromeApp: Sendable { var pid: pid_t? { get }; func terminate() -> Bool; func isRunning() -> Bool; func launch(arguments: [String]) throws }` — the real one wraps `NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")` and `/usr/bin/open`.
  - `public enum ChromeState: Equatable, Sendable { case notRunning, inactive, active(MirrorSettings) }`
  - `public enum RestartError: Error, Equatable { case chromeStayedOpen, launchFailed(String) }`
  - `public struct ChromeController: Sendable` — `init(app: ChromeApp = SystemChrome(), quitTimeout: Duration = .seconds(20))`, `func state() -> ChromeState`, `func restart(with: MirrorSettings) async throws`
  - `public static func ChromeController.state(fromArguments: [String]?) -> ChromeState` — nil → `.notRunning`, no marker → `.inactive`.

`restart`: when Chrome runs, call `terminate()`, then poll `isRunning()` every 250 ms until `quitTimeout`. If Chrome still runs, throw `.chromeStayedOpen`. Then launch with `settings.clamped().openArguments()`. When Chrome does not run, launch at once.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func parsesProcargs2() {
    var d = Data(withUnsafeBytes(of: Int32(2).littleEndian) { Data($0) })
    d.append(contentsOf: Array("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome".utf8) + [0, 0, 0])
    d.append(contentsOf: Array("Google Chrome".utf8) + [0] + Array("--castgauge-playout-delay=400".utf8) + [0])
    d.append(contentsOf: Array("HOME=/Users/x".utf8) + [0])
    #expect(ProcessArguments.parse(procargs2: d) == ["Google Chrome", "--castgauge-playout-delay=400"])
}
@Test func parsesPlainLaunchAsInactive() {
    #expect(ChromeController.state(fromArguments: ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]) == .inactive)
    #expect(ChromeController.state(fromArguments: nil) == .notRunning)
}
@Test func restartStopsWhenChromeStaysOpen() async {
    let fake = FakeChrome(running: true, quits: false)
    let c = ChromeController(app: fake, quitTimeout: .milliseconds(300))
    await #expect(throws: RestartError.chromeStayedOpen) { try await c.restart(with: .chromeDefault) }
    #expect(fake.launches.isEmpty)
}
@Test func restartLaunchesAfterQuit() async throws {
    let fake = FakeChrome(running: true, quits: true)
    try await ChromeController(app: fake, quitTimeout: .seconds(1)).restart(with: MirrorSettings(maxRateMbps: 12, bufferMs: 400, frameRate: 30))
    #expect(fake.launches == [MirrorSettings(maxRateMbps: 12, bufferMs: 400, frameRate: 30).openArguments()])
}
```

`FakeChrome` lives in the test file. It records launches behind a `Mutex`.

- [ ] **Step 2: Run the tests and make sure they fail** — `scripts/test.sh`.
- [ ] **Step 3: Implement `ProcessArguments`, `SystemChrome`, `ChromeController`.** `SystemChrome.pid` is the pid of the main Chrome app (not a helper).
- [ ] **Step 4: Run the tests and make sure they pass** — `scripts/test.sh`.
- [ ] **Step 5: Check against the real Chrome.** Print `ChromeController().state()`. Expected with Chrome open from the Dock: `.inactive`.
- [ ] **Step 6: Commit** — `git commit -m "Read and restart Chrome with the mirror settings"`

---

### Task 7: Gauge model and menu bar label

**Files:**
- Create: `Sources/CastGauge/GaugeModel.swift`, `Sources/CastGauge/Views/MenuBarLabel.swift`
- Modify: `Sources/CastGauge/CastGaugeApp.swift`

**Interfaces:**
- Consumes: `CastDiscovery`, `TrafficMonitor`, `LinkMonitor`, `WiFiReader`, `Snapshot`, `Health`, `ChromeController`, `MirrorSettings`.
- Produces (for Tasks 8 and 9):
  - `@MainActor @Observable final class GaugeModel` with:
    - `var device: CastDevice?`, `var snapshot: Snapshot`, `var health: Health`, `var wifi: WiFiStatus?`, `var chromeState: ChromeState`
    - `var settings: MirrorSettings` (saved in `UserDefaults` under `mirrorSettings` as JSON)
    - `var networkPermissionDenied: Bool`, `var restartError: RestartError?`, `var isRestarting: Bool`
    - `func start()`, `func applySettings() async`
    - `var rateMbps: Double?` (bytes per second × 8 / 1 000 000)
    - `var tvSignalDbm: Int?` — always nil in version 1. It is the place for a later TV signal source (spec: "Later versions").

The model samples once per second. When the picked device address changes, it stops the old monitors and starts new ones for the new address. With no picked device, it stops the monitors.

Menu bar label: a dot plus text. `.notCasting` gray dot and "Not casting". Other states show "4.9 Mbit/s" with one decimal, or "— Mbit/s" when the rate is nil. Dot colors: good `#146C2E`, unstable `#B26A00`, losingData `#B3261E`, notCasting `#747775`. Use `MenuBarExtra(content:label:)` with `.menuBarExtraStyle(.window)`.

- [ ] **Step 1: Implement `GaugeModel` and `MenuBarLabel`, and wire them into `CastGaugeApp`.**
- [ ] **Step 2: Build and run** — `scripts/run.sh`. Expected: the menu bar shows "● 4.9 Mbit/s" (green) during a cast. macOS asks for the Local Network permission at first launch.
- [ ] **Step 3: Check the gray state.** Stop the cast. Expected: within about 5 seconds the label shows a gray dot and "Not casting".
- [ ] **Step 4: Commit** — `git commit -m "Show the cast rate in the menu bar"`

---

### Task 8: Material theme and fonts

**Files:**
- Create: `Resources/Fonts/RobotoFlex.ttf`, `Resources/Fonts/MaterialSymbolsRounded.ttf`, `Sources/CastGauge/Theme/Material.swift`, `Sources/CastGauge/Theme/Symbol.swift`
- Modify: `Sources/CastGauge/CastGaugeApp.swift` (register fonts at launch), `scripts/build-app.sh` (already copies `Resources/Fonts`)

**Interfaces:**
- Produces:
  - `enum MaterialColor` with `static func primary(_ scheme: ColorScheme) -> Color`, and the same for `onPrimary`, `primaryContainer`, `onPrimaryContainer`, `surface`, `surfaceContainer`, `surfaceContainerHigh`, `onSurface`, `onSurfaceVariant`, `outline`, `success`, `successContainer`, `warning`, `warningContainer`, `error`, `errorContainer`.
  - `enum MaterialShape { static let panel: CGFloat = 28; static let card: CGFloat = 16; static let tile: CGFloat = 12 }`
  - `enum MaterialMotion { static let emphasized: Animation }` — `.timingCurve(0.2, 0, 0, 1, duration: 0.4)`.
  - `enum MaterialType { static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font }` — Roboto Flex.
  - `struct Symbol: View { init(_ name: String, size: CGFloat = 20, filled: Bool = true) }` — draws a Material Symbols ligature (for example "tv", "tune", "check_circle", "chevron_right", "network_check", "wifi").
  - `func registerBundledFonts()` — `CTFontManagerRegisterFontsForURL` for each file in `Bundle.main.resourceURL/Fonts`.

Light values follow the mockup `docs/superpowers/specs/2026-10-11-material-panel-mockup.html`: primary `#0B57D0`, onPrimary `#FFFFFF`, primaryContainer `#D3E3FD`, onPrimaryContainer `#041E49`, surface `#F8FAFD`, surfaceContainer `#F0F4F9`, surfaceContainerHigh `#E9EEF6`, onSurface `#1F1F1F`, onSurfaceVariant `#444746`, outline `#747775`, success `#146C2E` on `#C4EED0`. Dark values: primary `#A8C7FA`, onPrimary `#062E6F`, primaryContainer `#0842A0`, onPrimaryContainer `#D3E3FD`, surface `#131314`, surfaceContainer `#1E1F20`, surfaceContainerHigh `#282A2C`, onSurface `#E3E3E3`, onSurfaceVariant `#C4C7C5`, outline `#8E918F`, success `#6DD58C` on `#0F5223`. The builder picks the warning and error pairs from the Material 3 baseline.

Font sources: `https://github.com/google/fonts/raw/main/ofl/robotoflex/RobotoFlex%5BGRAD,XOPQ,XTRA,YOPQ,YTAS,YTDE,YTFI,YTLC,YTUC,opsz,slnt,wdth,wght%5D.ttf` and `https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf`. Add the license files next to them (`OFL.txt`, `LICENSE-Apache-2.0.txt`).

- [ ] **Step 1: Add the fonts and licenses, and implement the theme files and `registerBundledFonts()`.**
- [ ] **Step 2: Build and run** — `scripts/run.sh`. Put a temporary `Symbol("tv")` and a Roboto Flex `Text` in the panel. Expected: a TV icon, not the letters "tv". Remove the temporary views.
- [ ] **Step 3: Commit** — `git commit -m "Add the Material theme and the fonts"`

---

### Task 9: The panel

**Files:**
- Create: `Sources/CastGauge/Views/Panel.swift`, `HeaderView.swift`, `ConnectionCard.swift`, `QualityCard.swift`
- Modify: `Sources/CastGauge/CastGaugeApp.swift`

**Interfaces:**
- Consumes: `GaugeModel` (Task 7), theme (Task 8).

Layout follows mockup A (leave out its Sound card). Panel width 340 pt, padding 16, background `surface`, corner `MaterialShape.panel`. Cards are `#FFFFFF` in light mode and `surfaceContainer` in dark mode, 8 pt apart.

- **HeaderView:** a 40 pt round `primaryContainer` circle with `Symbol("tv")`. The device name (16 pt, medium), or "No Cast device" with no device. The subtitle "Casting a Chrome tab" or "Not casting". A status chip on the right: "Good" (success colors, `check_circle`), "Unstable" (warning, `warning`), "Losing data" (error, `error`), "Not casting" (surfaceContainerHigh, `cast`).
- **ConnectionCard:** label "CONNECTION". The large number `rateMbps` with one decimal, 32 pt, then "of N Mbit/s" where N is the active maximum (`chromeState` `.active` value, else 5). A linear bar, `primary` on `primaryContainer`, rate ÷ maximum, capped at 1. Three tiles: "Delay" (`avgMs`, one decimal, " ms"), "Loss" (whole percent), "Mac Wi-Fi" (`rssi` " dBm" and band below). Every nil value shows "—". A fourth row: "TV Wi-Fi · Not set up" in `onSurfaceVariant` while `tvSignalDbm` is nil.
- **QualityCard:** collapsed, it shows `Symbol("tune")`, "Quality", the summary "12 Mbit/s · 400 ms · 30 fps", and `chevron_right`. A click expands it in place with `MaterialMotion.emphasized`, and the chevron turns 90°. Expanded, it shows:
  - "Max rate" slider, step 1, `MirrorSettings.maxRateRange`.
  - "Buffer" slider, step 50, `bufferRange`.
  - "Frame rate" segmented control, 30 fps / 60 fps.
  - A state line: "Active in Chrome" (success) when `chromeState == .active(settings)`. "Not active in Chrome" (warning) when inactive, or when the active values differ from the edited ones. "Chrome is not running" when not running.
  - A filled `primary` button "Apply and restart Chrome". It opens a confirmation (`.confirmationDialog`) with the title "Restart Chrome?" and the message "The cast stops. Chrome reopens your tabs. Start the cast again after Chrome opens." and the buttons "Restart Chrome" and "Cancel".
  - While `isRestarting`, the button shows a small progress view and "Restarting…".
  - On `.chromeStayedOpen`, show "Chrome did not quit. Close any open dialogs in Chrome, then try again." On `.launchFailed`, show "Chrome did not start." and the reason.
- When `networkPermissionDenied`, the panel shows one card in place of the connection card: "CastGauge needs Local Network access. Turn it on in System Settings > Privacy & Security > Local Network." It does not try another method.
- A small footer row: "Quit CastGauge" text button in `onSurfaceVariant`.

- [ ] **Step 1: Implement the four views and put `Panel` in the `MenuBarExtra`.**
- [ ] **Step 2: Build and run** — `scripts/run.sh`. Open the panel during a cast. Compare with mockup A in light and dark mode (System Settings > Appearance). Expected: the same structure, colors, and corners. No Sound card.
- [ ] **Step 3: Check the stale values.** Turn off the Mac Wi-Fi for 5 seconds. Expected: the rate, delay and loss show "—", and the chip shows "Unstable" or "Not casting". Turn the Wi-Fi on again. Expected: the values return.
- [ ] **Step 4: Commit** — `git commit -m "Add the Material panel"`

---

### Task 10: End-to-end check on the real TV

**Files:**
- Modify: `README.md` (create it): what the app does, how to build (`scripts/build-app.sh`), how to test (`scripts/test.sh`), and the Chrome launch values.

- [ ] **Step 1: Apply 12 Mbit/s.** In the panel, set Max rate 12, Buffer 400, 30 fps. Select "Apply and restart Chrome", and confirm. Expected: Chrome quits, reopens with the tabs, and the panel shows "Active in Chrome".
- [ ] **Step 2: Confirm the Chrome command line.** Open `chrome://version`. Expected: the command line contains `--enable-features=CastStreamingMaxVideoBitrate:max_bitrate_mbps/12` and `--castgauge-playout-delay=400`.
- [ ] **Step 3: Measure the higher rate.** Cast the tab with a video that has a lot of motion. Expected: the panel shows a rate above 5 Mbit/s at some moments. If it never goes above 5, record that in the README and report it. Do not change the plan.
- [ ] **Step 4: Check the Dock case.** Quit Chrome, and open it from the Dock. Expected: the panel shows "Not active in Chrome".
- [ ] **Step 5: Run all tests** — `scripts/test.sh`. Expected: all pass.
- [ ] **Step 6: Commit** — `git commit -m "Add the README and record the device check"`
