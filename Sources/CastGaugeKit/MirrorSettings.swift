import Foundation

/// The Chrome mirror settings that CastGauge applies at Chrome launch.
/// Chrome reads them only at launch, so a change needs a Chrome restart.
public struct MirrorSettings: Equatable, Codable, Sendable {
    /// The maximum mirror video rate in Mbit/s.
    public var maxRateMbps: Int
    /// The receiver buffer time in milliseconds.
    public var bufferMs: Int
    /// The maximum frame rate. It is 30 or 60.
    public var frameRate: Int

    public init(maxRateMbps: Int, bufferMs: Int, frameRate: Int) {
        self.maxRateMbps = maxRateMbps
        self.bufferMs = bufferMs
        self.frameRate = frameRate
    }

    /// The Chrome default rate, with the default CastGauge buffer.
    public static let chromeDefault = MirrorSettings(maxRateMbps: 5, bufferMs: 400, frameRate: 30)

    public static let maxRateRange = 5...20
    public static let bufferRange = 100...1000
    public static let frameRates = [30, 60]

    static let rateFeature = "CastStreamingMaxVideoBitrate"
    static let rateParameter = "max_bitrate_mbps"
    static let frameRateFeature = "CastStreaming60fps"
    static let bufferVariable = "CHROME_MIRRORING_PLAYOUT_DELAY"
    /// Chrome ignores this switch. CastGauge reads it back, because macOS hides the Chrome environment.
    static let markerSwitch = "--castgauge-playout-delay="

    /// Returns a copy with each value in its allowed range.
    public func clamped() -> MirrorSettings {
        MirrorSettings(
            maxRateMbps: min(max(maxRateMbps, Self.maxRateRange.lowerBound), Self.maxRateRange.upperBound),
            bufferMs: min(max(bufferMs, Self.bufferRange.lowerBound), Self.bufferRange.upperBound),
            frameRate: frameRate == 60 ? 60 : 30
        )
    }

    /// Returns the arguments for `/usr/bin/open` that start Chrome with these settings.
    public func openArguments() -> [String] {
        var features = "\(Self.rateFeature):\(Self.rateParameter)/\(maxRateMbps)"
        if frameRate == 60 {
            features += ",\(Self.frameRateFeature)"
        }
        return [
            "-a", "Google Chrome",
            "--env", "\(Self.bufferVariable)=\(bufferMs)",
            "--args", "--restore-last-session",
            "--enable-features=\(features)",
            "\(Self.markerSwitch)\(bufferMs)",
        ]
    }

    /// Reads the settings from a Chrome command line.
    /// Returns nil when the marker switch is missing, because then CastGauge did not start this Chrome.
    public static func parse(chromeArguments: [String]) -> MirrorSettings? {
        guard let marker = chromeArguments.last(where: { $0.hasPrefix(markerSwitch) }),
              let buffer = Int(marker.dropFirst(markerSwitch.count)) else {
            return nil
        }
        let features = chromeArguments
            .filter { $0.hasPrefix("--enable-features=") }
            .flatMap { $0.dropFirst("--enable-features=".count).split(separator: ",").map(String.init) }

        var rate = chromeDefault.maxRateMbps
        let ratePrefix = "\(rateFeature):\(rateParameter)/"
        if let entry = features.last(where: { $0.hasPrefix(ratePrefix) }),
           let value = Int(entry.dropFirst(ratePrefix.count)) {
            rate = value
        }
        let frameRate = features.contains(frameRateFeature) ? 60 : 30
        return MirrorSettings(maxRateMbps: rate, bufferMs: buffer, frameRate: frameRate)
    }
}
