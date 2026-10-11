import AppKit
import CastGaugeKit
import SwiftUI

/// The menu bar item: a colored dot and the live rate.
struct MenuBarLabel: View {
    let model: GaugeModel

    var body: some View {
        HStack(spacing: 4) {
            // The menu bar draws SwiftUI shapes in one color, so the dot is a non-template image.
            Image(nsImage: Self.dot(Self.color(for: model.health)))
            Text(text)
                .monospacedDigit()
        }
        .task { model.start() }
    }

    private var text: String {
        guard model.health != .notCasting else { return "Not casting" }
        guard let rate = model.rateMbps else { return "— Mbit/s" }
        return String(format: "%.1f Mbit/s", rate)
    }

    static func color(for health: Health) -> NSColor {
        switch health {
        case .good: NSColor(hex: 0x146C2E)
        case .unstable: NSColor(hex: 0xB26A00)
        case .losingData: NSColor(hex: 0xB3261E)
        case .notCasting: NSColor(hex: 0x747775)
        }
    }

    static func dot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
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
