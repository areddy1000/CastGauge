import AppKit
import CastGaugeKit
import CoreText
import SwiftUI

/// The menu bar item. It shows the app and title that the Cast device reports.
/// Otherwise it shows the TV icon and the TV name, with a health dot during a tab mirror.
struct MenuBarLabel: View {
    let model: GaugeModel

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let playing = model.nowPlaying {
            HStack {
                Image(nsImage: Self.thumbnail(model.nowPlayingIcon) ?? Self.tvIcon(dot: nil))
                Text(Self.truncated(playing.title))
                    // The same font the system clock uses in the menu bar.
                    .font(Font(NSFont.menuBarFont(ofSize: 0)))
            }
            .accessibilityLabel("CastGauge, \(playing.appName), \(playing.title)")
        } else if let device = model.device {
            HStack {
                Image(nsImage: Self.tvIcon(dot: model.health == .notCasting ? nil : Self.color(for: model.health)))
                Text(Self.truncated(device.name))
                    .font(Font(NSFont.menuBarFont(ofSize: 0)))
            }
            .accessibilityLabel("CastGauge, \(device.name), \(Self.healthText(model.health))")
        } else {
            Image(nsImage: Self.tvIcon(dot: nil))
                .accessibilityLabel("CastGauge, no Cast device")
        }
    }

    // The status item sets its own gap between image and title and ignores view spacing,
    // so the gap lives inside the image as a clear margin on the right.
    private static let side: CGFloat = 16
    private static let margin: CGFloat = 6

    /// The Material "tv" icon in the menu bar text color, with an optional health dot.
    static func tvIcon(dot: NSColor?) -> NSImage {
        let image = NSImage(size: NSSize(width: side + margin, height: side), flipped: false) { _ in
            // The menu bar sets the drawing appearance, so labelColor matches a light or dark menu bar.
            let font = CTFontCreateWithName("Material Symbols Rounded" as CFString, side, nil)
            let glyph = NSAttributedString(string: "tv", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            let size = glyph.size()
            glyph.draw(at: NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
            if let dot {
                // A ring in the clear color cuts the dot out from the icon, so it reads at 16 points.
                let rect = NSRect(x: side - 7, y: 0, width: 7, height: 7)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: rect.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                dot.setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// A 16 point rounded app icon with the same right margin.
    static func thumbnail(_ source: NSImage?) -> NSImage? {
        guard let source else { return nil }
        let image = NSImage(size: NSSize(width: side + margin, height: side), flipped: false) { _ in
            let rect = NSRect(x: 0, y: 0, width: side, height: side)
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).addClip()
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }

    static func truncated(_ title: String) -> String {
        let limit = 26
        guard title.count > limit else { return title }
        return String(title.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func healthText(_ health: Health) -> String {
        switch health {
        case .good: "good"
        case .unstable: "unstable"
        case .losingData: "losing data"
        case .notCasting: "not casting"
        }
    }

    static func color(for health: Health) -> NSColor {
        switch health {
        case .good: NSColor(hex: 0x1E8E3E)
        case .unstable: NSColor(hex: 0xE37400)
        case .losingData: NSColor(hex: 0xD93025)
        case .notCasting: NSColor(hex: 0x747775)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
