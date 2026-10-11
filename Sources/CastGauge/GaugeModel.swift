import CastGaugeKit
import Foundation
import Observation

/// Collects the measurements once per second for the menu bar and the panel.
@MainActor
@Observable
final class GaugeModel {
    var device: CastDevice?
    var snapshot = Snapshot(casting: false, rateBps: nil, previousRateBps: nil, link: nil)
    var health: Health = .notCasting
    var wifi: WiFiStatus?
    var chromeState: ChromeState = .notRunning
    var settings: MirrorSettings {
        didSet { save(settings) }
    }
    var networkPermissionDenied = false
    var restartError: RestartError?
    var isRestarting = false
    /// Always nil in version 1. A later TV signal source fills it.
    var tvSignalDbm: Int?

    /// The rate in Mbit/s, or nil when no fresh value exists.
    var rateMbps: Double? {
        snapshot.rateBps.map { Double($0) * 8 / 1_000_000 }
    }

    private static let settingsKey = "mirrorSettings"
    private let discovery = CastDiscovery()
    private let chrome = ChromeController()
    private var traffic: TrafficMonitor?
    private var link: LinkMonitor?
    private var monitoredAddress: String?
    private var lastRate: (bytesPerSecond: Int, at: Date)?
    private var previousRate: (bytesPerSecond: Int, at: Date)?
    private var sampler: Task<Void, Never>?

    init() {
        settings = Self.loadSettings()
    }

    func start() {
        guard sampler == nil else { return }
        discovery.start()
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
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

    private func sample() {
        networkPermissionDenied = discovery.permissionDenied
        let devices = discovery.devices
        // Show the mirroring device. With no mirror, show an idle device so the header has a name.
        device = CastDevice.pick(devices) ?? devices.first
        let casting = device?.isMirroring ?? false
        follow(casting ? device?.address : nil)

        if let rate = traffic?.latest, rate.at != lastRate?.at {
            previousRate = lastRate
            lastRate = rate
        }
        snapshot = Snapshot.make(casting: casting, rate: lastRate, previous: previousRate,
                                 link: link?.latest, now: Date())
        health = Health.classify(snapshot)
        wifi = WiFiReader.read()
        chromeState = chrome.state()
    }

    /// Starts the monitors for a new address and stops the old ones.
    private func follow(_ address: String?) {
        guard address != monitoredAddress else { return }
        traffic?.stop()
        link?.stop()
        traffic = nil
        link = nil
        lastRate = nil
        previousRate = nil
        monitoredAddress = address
        guard let address else { return }
        let traffic = TrafficMonitor(targetAddress: address)
        let link = LinkMonitor(targetAddress: address)
        traffic.start()
        link.start()
        self.traffic = traffic
        self.link = link
    }

    private static func loadSettings() -> MirrorSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(MirrorSettings.self, from: data) else {
            return .chromeDefault
        }
        return settings.clamped()
    }

    private func save(_ settings: MirrorSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }
}
