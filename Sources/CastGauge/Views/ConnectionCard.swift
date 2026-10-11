import CastGaugeKit
import SwiftUI

/// The live rate against the maximum, the link tiles, and the TV signal row.
struct ConnectionCard: View {
    let model: GaugeModel

    /// The maximum that the running Chrome uses. Without CastGauge settings, it is the Chrome default.
    private var activeMax: Int {
        if case .active(let settings) = model.chromeState { return settings.maxRateMbps }
        return MirrorSettings.chromeDefault.maxRateMbps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: "CONNECTION")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.rateMbps.map { String(format: "%.1f", $0) } ?? "—")
                    .font(MaterialType.font(32, weight: .medium))
                    .monospacedDigit()
                Text("of \(activeMax) Mbit/s")
                    .font(MaterialType.font(14))
                    .foregroundStyle(MaterialColor.onSurfaceVariant)
            }
            .padding(.top, 6)
            LinearBar(fraction: min((model.rateMbps ?? 0) / Double(activeMax), 1))
                .padding(.top, 8)
            HStack(spacing: 8) {
                Tile(value: model.snapshot.link?.avgMs.map { String(format: "%.1f ms", $0) } ?? "—", label: "Delay")
                Tile(value: model.snapshot.link.map { String(format: "%.0f %%", $0.lossPercent) } ?? "—", label: "Loss")
                Tile(value: model.wifi.map { "\($0.rssi) dBm" } ?? "—",
                     label: model.wifi.map { "Mac · \($0.band)" } ?? "Mac Wi-Fi")
            }
            .padding(.top, 12)
            HStack(spacing: 8) {
                Symbol("wifi", size: 16)
                Text("TV Wi-Fi")
                Spacer()
                Text(model.tvSignalDbm.map { "\($0) dBm" } ?? "Not set up")
            }
            .font(MaterialType.font(13))
            .foregroundStyle(MaterialColor.onSurfaceVariant)
            .padding(.top, 12)
        }
        .card()
    }
}

/// The Material linear progress bar.
struct LinearBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(MaterialColor.primaryContainer)
                Capsule().fill(MaterialColor.primary)
                    .frame(width: max(geometry.size.width * fraction, fraction > 0 ? 6 : 0))
                    // Only the bar animates. The panel gets no writes while it is closed.
                    .animation(MaterialMotion.emphasized, value: fraction)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// One small value tile.
struct Tile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(MaterialType.font(15, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(MaterialType.font(11))
                .foregroundStyle(MaterialColor.onSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MaterialColor.tile, in: RoundedRectangle(cornerRadius: MaterialShape.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
