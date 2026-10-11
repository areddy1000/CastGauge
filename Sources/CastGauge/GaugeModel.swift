import AppKit
import CastGaugeKit
import Foundation
import Observation

/// Collects the measurements for the menu bar and the panel.
///
/// It costs almost nothing while it idles. Bonjour and the Cast status connection call it when
/// something changes, so no timer runs with no cast and a closed panel. A 1 s tick runs only
/// during a tab cast or while the panel shows. The panel-only values update only while the
/// panel shows, so a closed panel does not draw.
@MainActor
@Observable
final class GaugeModel {
    var device: CastDevice?
    var snapshot = Snapshot(casting: false, rateBps: nil, previousRateBps: nil, link: nil)
    var health: Health = .notCasting
    var wifi: WiFiStatus?
    var chromeState: ChromeState = .notRunning
    var settings: MirrorSettings {
        didSet { saveSoon() }
    }
    var networkPermissionDenied = false
    var restartError: RestartError?
    var isRestarting = false
    /// Always nil in version 1. A later TV signal source fills it.
    var tvSignalDbm: Int?
    /// The app and title that the Cast device reports, or nil for no app, idle, or a tab mirror.
    var nowPlaying: NowPlaying?
    /// The 16 pt menu bar image of the now-playing app icon, after it loads.
    var nowPlayingIcon: NSImage?
    /// Every Chromecast on the network, for the list when no tab cast runs.
    var devices: [CastDevice] = []
    /// The devices with a Stop request in progress.
    var stopping: Set<String> = []
    /// The reason the last Stop request failed, or nil.
    var stopError: String?
    /// True while the panel shows. The panel sets it.
    var panelVisible = false {
        didSet {
            guard panelVisible != oldValue else { return }
            if panelVisible { tick() }
            updateTicker()
        }
    }

    /// The rate in Mbit/s, or nil when no fresh value exists.
    var rateMbps: Double? {
        snapshot.rateBps.map { Double($0) * 8 / 1_000_000 }
    }

    private static let settingsKey = "mirrorSettings"
    @ObservationIgnored private var discovery: CastDiscovery!
    @ObservationIgnored private let chrome = ChromeController()
    @ObservationIgnored private var traffic: InterfaceTraffic?
    @ObservationIgnored private var link: LinkMonitor?
    @ObservationIgnored private var monitoredAddress: String?
    @ObservationIgnored private var status: CastStatusMonitor?
    @ObservationIgnored private var statusAddress: String?
    @ObservationIgnored private var statusDevice: CastDevice?
    /// Devices that run a native Google TV app, keyed by ID, with the app name at that time.
    /// The answer stays valid while the Bonjour app name stays the same.
    @ObservationIgnored private var nativeApps: [String: String] = [:]
    @ObservationIgnored private var thumbnails: [URL: NSImage] = [:]
    @ObservationIgnored private var failedIcons: Set<URL> = []
    @ObservationIgnored private var loadingIcons: Set<URL> = []
    @ObservationIgnored private var lastRate: (bytesPerSecond: Int, at: Date)?
    @ObservationIgnored private var previousRate: (bytesPerSecond: Int, at: Date)?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init() {
        settings = Self.loadSettings()
        discovery = CastDiscovery(onChange: { [weak self] in
            Task { @MainActor in self?.devicesChanged() }
        })
    }

    func start() {
        guard !started else { return }
        started = true
        discovery.start()
        devicesChanged()
        // Stop the ping tool at quit, so no child process can stay behind.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.link?.stop() }
        }
    }

    /// Ends what the device casts, the same as Stop in the Google Home app.
    func stop(_ device: CastDevice) async {
        guard let address = device.address, !stopping.contains(device.id) else { return }
        stopping.insert(device.id)
        stopError = nil
        do {
            try await CastStopper.stop(address: address)
        } catch CastStopError.noSession {
            // The cast already ended. Nothing is left to stop.
        } catch {
            stopError = "\(device.name) did not stop. Try again."
        }
        stopping.remove(device.id)
    }

    func applySettings() async {
        isRestarting = true
        restartError = nil
        do {
            try await chrome.restart(with: settings)
        } catch let error as RestartError {
            restartError = error
        } catch {
            restartError = .launchFailed(error.localizedDescription)
        }
        isRestarting = false
        chromeState = chrome.state()
    }

    /// Runs when Bonjour reports a change. It picks the device and starts or stops the monitors.
    private func devicesChanged() {
        let denied = discovery.permissionDenied
        if denied != networkPermissionDenied { networkPermissionDenied = denied }
        var devices = discovery.devices
        // A remembered native app counts only while the device still shows the same app name.
        nativeApps = nativeApps.filter { id, name in devices.first { $0.id == id }?.statusText == name }
        for index in devices.indices where nativeApps[devices[index].id] == devices[index].statusText {
            devices[index].runsNativeApp = true
        }
        if devices != self.devices { self.devices = devices }
        // Show the mirroring device. With no mirror, show an idle device so the header has a name.
        let picked = CastDevice.pick(devices) ?? devices.first
        if picked != device { device = picked }
        let casting = picked?.isMirroring ?? false
        follow(casting ? picked?.address : nil)
        // The status connection is open only while a device runs an app other than a tab mirror.
        // The Bonjour record already shows the idle state, so idle needs no connection.
        let appDevice = devices.first { if case .app = $0.activity { true } else { false } }
        followStatus(appDevice)
        updateNowPlaying(status?.nowPlaying)
        if !casting, health != .notCasting {
            health = .notCasting
            snapshot = Snapshot(casting: false, rateBps: nil, previousRateBps: nil, link: nil)
        }
        updateTicker()
    }

    /// The 1 s tick runs only during a tab cast or while the panel shows.
    private func updateTicker() {
        let needed = monitoredAddress != nil || panelVisible
        if needed, ticker == nil {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.tick()
                    // The tolerance lets macOS group this wakeup with others.
                    try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(250))
                }
            }
        } else if !needed, let ticker {
            ticker.cancel()
            self.ticker = nil
        }
    }

    private func tick() {
        let now = Date()
        traffic?.sample(at: now)
        if let rate = traffic?.latest, rate.at != lastRate?.at {
            previousRate = lastRate
            lastRate = rate
        }
        let casting = monitoredAddress != nil
        let fresh = Snapshot.make(casting: casting, rate: lastRate, previous: previousRate,
                                  link: link?.latest, now: now)
        let newHealth = Health.classify(fresh)
        if newHealth != health { health = newHealth }
        // These values show only in the panel. A closed panel gets no writes, so it does not draw.
        guard panelVisible else { return }
        if fresh != snapshot { snapshot = fresh }
        let newWifi = WiFiReader.read()
        if newWifi != wifi { wifi = newWifi }
        let newChrome = chrome.state()
        if newChrome != chromeState { chromeState = newChrome }
    }

    /// Starts the monitors for a new address and stops the old ones.
    private func follow(_ address: String?) {
        guard address != monitoredAddress else { return }
        link?.stop()
        traffic = nil
        link = nil
        lastRate = nil
        previousRate = nil
        monitoredAddress = address
        guard let address else { return }
        let traffic = InterfaceTraffic(targetAddress: address)
        traffic.sample()
        let link = LinkMonitor(targetAddress: address)
        link.start()
        self.traffic = traffic
        self.link = link
    }

    /// Opens the status connection to a device that runs an app, and closes it when none does.
    private func followStatus(_ device: CastDevice?) {
        statusDevice = device
        let address = device?.address
        guard address != statusAddress else { return }
        status?.stop()
        status = nil
        statusAddress = address
        guard let address else { return }
        let status = CastStatusMonitor(address: address, onChange: { [weak self] in
            Task { @MainActor in self?.statusChanged() }
        })
        status.start()
        self.status = status
    }

    /// A native Google TV app, such as the Apple TV app, is not a cast. Remember it, and let
    /// devicesChanged close the connection, so it does not stay open while the app runs.
    private func statusChanged() {
        if let app = status?.app, app.isNativeApp, let device = statusDevice, let name = device.statusText {
            nativeApps[device.id] = name
            devicesChanged()
            return
        }
        updateNowPlaying(status?.nowPlaying)
    }

    private func updateNowPlaying(_ playing: NowPlaying?) {
        guard playing != nowPlaying else { return }
        nowPlaying = playing
        nowPlayingIcon = playing?.iconURL.flatMap { thumbnails[$0] }
        guard let url = playing?.iconURL, thumbnails[url] == nil,
              !failedIcons.contains(url), !loadingIcons.contains(url) else { return }
        loadingIcons.insert(url)
        Task { [weak self] in
            // Some devices report the icon over http. macOS blocks plain http, so use https.
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            let image: NSImage? = if let secure = components?.url,
                                     let (data, _) = try? await URLSession.shared.data(from: secure) {
                NSImage(data: data)
            } else {
                nil
            }
            guard let self else { return }
            self.loadingIcons.remove(url)
            // Keep only the small menu bar image, made one time. The full icon is not kept.
            guard let image, let thumbnail = MenuBarLabel.thumbnail(image) else {
                self.failedIcons.insert(url)
                return
            }
            if self.thumbnails.count >= 8 { self.thumbnails.removeAll() }
            self.thumbnails[url] = thumbnail
            if self.nowPlaying?.iconURL == url { self.nowPlayingIcon = thumbnail }
        }
    }

    /// Saves the settings 0.5 s after the last change, not on each slider step.
    private func saveSoon() {
        saveTask?.cancel()
        let settings = settings
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.settingsKey)
            }
        }
    }

    private static func loadSettings() -> MirrorSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(MirrorSettings.self, from: data) else {
            return .chromeDefault
        }
        return settings.clamped()
    }
}
