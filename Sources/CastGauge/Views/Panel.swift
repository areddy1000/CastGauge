import AppKit
import SwiftUI

/// The one panel that opens from the menu bar item.
struct Panel: View {
    let model: GaugeModel
    var startExpanded = false
    var startConfirming = false
    /// False for the snapshot option, because ImageRenderer does not draw a scroll view.
    var scrolls = true
    @State private var contentHeight: CGFloat = 0

    /// The panel can use the visible screen height below the menu bar, less a margin.
    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 24
    }

    private var panelHeight: CGFloat {
        min(max(contentHeight, 1), maxHeight)
    }

    var body: some View {
        if scrolls {
            // The window takes its height from the scroll view. The scroll view takes the content
            // height up to the screen limit, and scrolls the rest.
            ScrollView(.vertical) {
                content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: 340, height: panelHeight)
            .background(MaterialColor.surface)
            .background(WindowHeightSync(height: panelHeight) { model.panelVisible = $0 })
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 8) {
            if model.networkPermissionDenied {
                HeaderView(model: model)
                PermissionCard()
            } else if model.health == .notCasting {
                // No tab cast: the list of Chromecasts, with Stop for a device that casts.
                DeviceListCard(model: model)
            } else {
                HeaderView(model: model)
                ConnectionCard(model: model)
            }
            QualityCard(model: model, expanded: startExpanded, confirming: startConfirming)
            HStack {
                OpenAtLoginSwitch()
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

/// Sets the menu bar window to the panel height, with the top edge fixed under the menu bar.
/// The menu bar window does not follow a change in content height by itself. Without this,
/// the window keeps its old height, the content moves down, and empty space shows.
struct WindowHeightSync: NSViewRepresentable {
    let height: CGFloat
    /// Called with true when the panel window shows, and false when it hides.
    /// The menu bar window stays alive while closed, so the occlusion state tells.
    var onVisibilityChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let height = height
        context.coordinator.onVisibilityChange = onVisibilityChange
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.watch(window)
            let content = window.contentRect(forFrameRect: window.frame)
            guard abs(content.height - height) > 0.5 else { return }
            let target = NSRect(x: content.minX, y: content.maxY - height, width: content.width, height: height)
            window.setFrame(window.frameRect(forContentRect: target), display: true, animate: false)
        }
    }

    /// Watches the occlusion state of the panel window. A selector observer goes away with
    /// the coordinator, so it needs no remove step.
    @MainActor
    final class Coordinator: NSObject {
        var onVisibilityChange: (Bool) -> Void = { _ in }
        private weak var window: NSWindow?

        func watch(_ window: NSWindow) {
            guard self.window !== window else { return }
            if let old = self.window {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: old)
            }
            self.window = window
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged(_:)),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
            onVisibilityChange(window.occlusionState.contains(.visible))
        }

        @objc private func occlusionChanged(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            onVisibilityChange(window.occlusionState.contains(.visible))
        }
    }
}

/// The "Open at Login" switch in the panel footer, as a Material checkbox.
/// It reads the system state when it shows.
struct OpenAtLoginSwitch: View {
    @State private var enabled = LoginItem.isEnabled

    var body: some View {
        Button {
            LoginItem.setEnabled(!enabled)
            enabled = LoginItem.isEnabled
        } label: {
            HStack(spacing: 6) {
                Symbol(enabled ? "check_box" : "check_box_outline_blank", size: 18)
                    .foregroundStyle(enabled ? MaterialColor.primary : MaterialColor.onSurfaceVariant)
                Text("Open at Login")
                    .font(MaterialType.font(12, weight: .medium))
                    .foregroundStyle(MaterialColor.onSurfaceVariant)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { enabled = LoginItem.isEnabled }
        .accessibilityLabel("Open at Login")
        .accessibilityValue(enabled ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
