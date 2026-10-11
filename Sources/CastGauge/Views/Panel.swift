import AppKit
import SwiftUI

/// The one panel that opens from the menu bar item.
struct Panel: View {
    let model: GaugeModel
    var startExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            HeaderView(model: model)
            if model.networkPermissionDenied {
                PermissionCard()
            } else {
                ConnectionCard(model: model)
            }
            QualityCard(model: model, expanded: startExpanded)
            HStack {
                Spacer()
                Button("Quit CastGauge") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(MaterialType.font(12, weight: .medium))
                    .foregroundStyle(MaterialColor.onSurfaceVariant)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 340)
        .background(MaterialColor.surface)
        .foregroundStyle(MaterialColor.onSurface)
    }
}

/// The white (light) or dark card behind each part of the panel.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MaterialColor.card, in: RoundedRectangle(cornerRadius: MaterialShape.card, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// The small upper-case label at the top of a card.
struct CardLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(MaterialType.font(12, weight: .medium))
            .tracking(0.4)
            .foregroundStyle(MaterialColor.onSurfaceVariant)
    }
}

/// Shows that macOS refuses Local Network access. The app does not try another method.
struct PermissionCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Symbol("lan", size: 22)
                .foregroundStyle(MaterialColor.error)
            Text("CastGauge needs Local Network access. Turn it on in System Settings > Privacy & Security > Local Network.")
                .font(MaterialType.font(14))
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}
