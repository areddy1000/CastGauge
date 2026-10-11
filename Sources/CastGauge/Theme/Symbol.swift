import CoreText
import SwiftUI

/// A Material Symbols Rounded icon. The name is the icon ligature, for example "tv" or "tune".
struct Symbol: View {
    let name: String
    let size: CGFloat
    let filled: Bool

    init(_ name: String, size: CGFloat = 20, filled: Bool = true) {
        self.name = name
        self.size = size
        self.filled = filled
    }

    var body: some View {
        Text(name)
            .font(Font(Self.font(size: size, filled: filled)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// The fonts, made one time for each size and fill. The app uses only a few of them.
    @MainActor private static var fonts: [String: CTFont] = [:]

    /// The variable font axis "FILL" selects the filled or the outlined icon.
    @MainActor private static func font(size: CGFloat, filled: Bool) -> CTFont {
        let key = "\(size)-\(filled)"
        if let cached = fonts[key] { return cached }
        let font = makeFont(size: size, filled: filled)
        fonts[key] = font
        return font
    }

    private static func makeFont(size: CGFloat, filled: Bool) -> CTFont {
        let fillAxis = 0x4649_4C4C  // "FILL"
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "Material Symbols Rounded",
            kCTFontVariationAttribute: [fillAxis: filled ? 1 : 0],
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}
