import AppKit
import CoreText
import SwiftUI

/// Material 3 color roles from the seed color #0B57D0. Each color follows the system appearance.
enum MaterialColor {
    static let primary = dynamic(light: 0x0B57D0, dark: 0xA8C7FA)
    static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x062E6F)
    static let primaryContainer = dynamic(light: 0xD3E3FD, dark: 0x0842A0)
    static let onPrimaryContainer = dynamic(light: 0x041E49, dark: 0xD3E3FD)
    static let surface = dynamic(light: 0xF8FAFD, dark: 0x131314)
    static let surfaceContainer = dynamic(light: 0xF0F4F9, dark: 0x1E1F20)
    static let surfaceContainerHigh = dynamic(light: 0xE9EEF6, dark: 0x282A2C)
    /// The card fill: white in light mode, the container color in dark mode.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1E1F20)
    /// The tile fill inside a card. It must differ from the card in both modes.
    static let tile = dynamic(light: 0xF0F4F9, dark: 0x282A2C)
    static let onSurface = dynamic(light: 0x1F1F1F, dark: 0xE3E3E3)
    static let onSurfaceVariant = dynamic(light: 0x444746, dark: 0xC4C7C5)
    static let outline = dynamic(light: 0x747775, dark: 0x8E918F)
    static let success = dynamic(light: 0x146C2E, dark: 0x6DD58C)
    static let successContainer = dynamic(light: 0xC4EED0, dark: 0x0F5223)
    static let warning = dynamic(light: 0x8B5000, dark: 0xFFB870)
    static let warningContainer = dynamic(light: 0xFFDCBE, dark: 0x6A3C00)
    static let error = dynamic(light: 0xB3261E, dark: 0xF2B8B5)
    static let errorContainer = dynamic(light: 0xF9DEDC, dark: 0x8C1D18)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// Material 3 corner sizes in points.
enum MaterialShape {
    static let panel: CGFloat = 28
    static let card: CGFloat = 16
    static let tile: CGFloat = 12
}

/// Material 3 motion.
enum MaterialMotion {
    /// The emphasized curve for expand and collapse.
    static let emphasized = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.4)
}

/// Material 3 type with the bundled Roboto Flex font.
enum MaterialType {
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Roboto Flex", fixedSize: size).weight(weight)
    }
}

/// Registers the fonts in the app bundle, so the views can use them by name.
func registerBundledFonts() {
    guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
          let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
        return
    }
    for file in files where file.pathExtension == "ttf" {
        CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
    }
}
