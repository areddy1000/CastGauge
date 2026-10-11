import Foundation

/// The Chrome mirror settings that CastGauge applies at Chrome launch.
/// Chrome reads them only at launch, so a change needs a Chrome restart.
///
/// The user sets the rate and the buffer. Two launch switches stay fixed:
/// - The frame rate limit is 60, so the content sets its own frame rate. Chrome's default is 30.
/// - Remoting is off. The test TV never answers a remoting offer, and Chrome then loses time,
///   or stops the cast together with the 60 limit.
public struct MirrorSettings: Equatable, Codable, Sendable {
    /// The maximum mirror video rate in Mbit/s.
    public var maxRateMbps: Int
    /// The receiver buffer time in milliseconds.
    public var bufferMs: Int

    public init(maxRateMbps: Int, bufferMs: Int) {
        self.maxRateMbps = maxRateMbps
        self.bufferMs = bufferMs
    }

    private enum CodingKeys: String, CodingKey {
        case maxRateMbps, bufferMs
    }

    /// The Chrome default rate, with the default CastGauge buffer.
    public static let chromeDefault = MirrorSettings(maxRateMbps: 5, bufferMs: 400)

    public static let maxRateRange = 5...20
    public static let bufferRange = 100...1000

    static let rateFeature = "CastStreamingMaxVideoBitrate"
    static let rateParameter = "max_bitrate_mbps"
    static let frameRateFeature = "CastStreaming60fps"
    static let remotingFeature = "MediaRemoting"
    static let bufferVariable = "CHROME_MIRRORING_PLAYOUT_DELAY"
    /// Chrome ignores this switch. CastGauge reads it back, because macOS hides the Chrome environment.
    static let markerSwitch = "--castgauge-playout-delay="

    /// Returns a copy with each value in its allowed range.
    public func clamped() -> MirrorSettings {
        MirrorSettings(
            maxRateMbps: min(max(maxRateMbps, Self.maxRateRange.lowerBound), Self.maxRateRange.upperBound),
            bufferMs: min(max(bufferMs, Self.bufferRange.lowerBound), Self.bufferRange.upperBound)
        )
    }

    /// Returns the arguments for `/usr/bin/open` that start Chrome with these settings.
    public func openArguments() -> [String] {
        [
            "-a", "Google Chrome",
            "--env", "\(Self.bufferVariable)=\(bufferMs)",
            "--args", "--restore-last-session",
            "--enable-features=\(Self.rateFeature):\(Self.rateParameter)/\(maxRateMbps),\(Self.frameRateFeature)",
            "--disable-features=\(Self.remotingFeature)",
            "\(Self.markerSwitch)\(bufferMs)",
        ]
    }

    /// Reads the settings from a Chrome command line.
    /// Returns nil when CastGauge did not start this Chrome with the current fixed switches:
    /// the marker, the 60 limit, and remoting off.
    public static func parse(chromeArguments: [String]) -> MirrorSettings? {
        guard let marker = chromeArguments.last(where: { $0.hasPrefix(markerSwitch) }),
              let buffer = Int(marker.dropFirst(markerSwitch.count)) else {
            return nil
        }
        let enabled = list("--enable-features=", in: chromeArguments)
        let disabled = list("--disable-features=", in: chromeArguments)
        guard enabled.contains(frameRateFeature), disabled.contains(remotingFeature) else { return nil }

        var rate = chromeDefault.maxRateMbps
        let ratePrefix = "\(rateFeature):\(rateParameter)/"
        if let entry = enabled.last(where: { $0.hasPrefix(ratePrefix) }),
           let value = Int(entry.dropFirst(ratePrefix.count)) {
            rate = value
        }
        return MirrorSettings(maxRateMbps: rate, bufferMs: buffer)
    }

    /// The items of every switch with this prefix, for example all `--enable-features=` lists.
    private static func list(_ prefix: String, in arguments: [String]) -> [String] {
        arguments
            .filter { $0.hasPrefix(prefix) }
            .flatMap { $0.dropFirst(prefix.count).split(separator: ",").map(String.init) }
    }
}
