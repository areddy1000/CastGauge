import CoreWLAN

/// The Wi-Fi link of the Mac.
public struct WiFiStatus: Equatable, Sendable {
    /// The signal strength in dBm.
    public let rssi: Int
    /// The noise level in dBm.
    public let noise: Int
    /// The band name, for example "5 GHz".
    public let band: String
}

/// Reads the Mac Wi-Fi link with CoreWLAN.
public enum WiFiReader {
    /// Returns the Wi-Fi link, or nil when there is no interface or no signal value.
    public static func read() -> WiFiStatus? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let rssi = interface.rssiValue()
        guard rssi != 0 else { return nil }
        let band = interface.wlanChannel().map { bandName($0.channelBand) } ?? "—"
        return WiFiStatus(rssi: rssi, noise: interface.noiseMeasurement(), band: band)
    }

    static func bandName(_ band: CWChannelBand) -> String {
        switch band {
        case .band2GHz: "2.4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        default: "—"
        }
    }
}
