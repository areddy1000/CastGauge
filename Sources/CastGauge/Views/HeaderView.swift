import CastGaugeKit
import SwiftUI

/// The TV icon, the TV name, the cast state, and the status chip.
struct HeaderView: View {
    let model: GaugeModel

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(MaterialColor.primaryContainer)
                .frame(width: 40, height: 40)
                .overlay(Symbol("tv", size: 22).foregroundStyle(MaterialColor.onPrimaryContainer))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.device?.name ?? "No Cast device")
                    .font(MaterialType.font(16, weight: .medium))
                    .lineLimit(1)
                Text(model.health == .notCasting ? "Not casting" : "Casting a Chrome tab")
                    .font(MaterialType.font(13))
                    .foregroundStyle(MaterialColor.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            StatusChip(health: model.health)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

/// The status chip. It uses the same states as the menu bar dot.
struct StatusChip: View {
    let health: Health

    var body: some View {
        HStack(spacing: 4) {
            Symbol(icon, size: 16)
            Text(text)
                .font(MaterialType.font(12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }

    private var text: String {
        switch health {
        case .good: "Good"
        case .unstable: "Unstable"
        case .losingData: "Losing data"
        case .notCasting: "Not casting"
        }
    }

    private var icon: String {
        switch health {
        case .good: "check_circle"
        case .unstable: "warning"
        case .losingData: "error"
        case .notCasting: "cast"
        }
    }

    private var foreground: Color {
        switch health {
        case .good: MaterialColor.success
        case .unstable: MaterialColor.warning
        case .losingData: MaterialColor.error
        case .notCasting: MaterialColor.onSurfaceVariant
        }
    }

    private var background: Color {
        switch health {
        case .good: MaterialColor.successContainer
        case .unstable: MaterialColor.warningContainer
        case .losingData: MaterialColor.errorContainer
        case .notCasting: MaterialColor.surfaceContainerHigh
        }
    }
}
