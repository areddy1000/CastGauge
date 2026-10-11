import AppKit
import SwiftUI

/// A developer option: `CastGauge --snapshot <file.png> [--dark]` draws a view to a PNG file and quits.
/// It lets a build check the panel without a click on the menu bar.
@MainActor
enum PanelSnapshot {
    static func runIfRequested<V: View>(_ content: () -> V) {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return }
        let dark = args.contains("--dark")
        let renderer = ImageRenderer(content: content().environment(\.colorScheme, dark ? .dark : .light))
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
}
