import AppKit
import CastGaugeKit
import SwiftUI

/// A developer option: `CastGauge --snapshot <file.png> [--dark] [--expanded]` draws the panel
/// with sample values to a PNG file and quits.
/// It lets a build check the panel without a click on the menu bar.
@MainActor
enum PanelSnapshot {
    static func runIfRequested<V: View>(_ content: (_ expanded: Bool) -> V) {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return }
        let dark = args.contains("--dark")
        let renderer = ImageRenderer(content: content(args.contains("--expanded")).environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        // The dynamic colors read the app appearance, so set it to match the scheme.
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: args[index + 1]))
        exit(0)
    }

    /// Sample values that match the measurements of 2026-10-11. The settings stay untouched,
    /// because a change would overwrite the saved settings.
    static func sampleModel() -> GaugeModel {
        let model = GaugeModel()
        let now = Date()
        model.device = CastDevice(id: "sample", name: "Bedroom TV", isMirroring: true, address: "192.168.1.155")
        model.snapshot = Snapshot(casting: true, rateBps: 612_500, previousRateBps: 600_000,
                                  link: LinkStats(avgMs: 5.6, jitterMs: 0.8, lossPercent: 0, at: now))
        model.health = .good
        model.wifi = WiFiStatus(rssi: -51, noise: -95, band: "5 GHz")
        model.chromeState = .inactive
        return model
    }
}
