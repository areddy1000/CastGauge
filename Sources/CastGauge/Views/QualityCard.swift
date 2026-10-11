import CastGaugeKit
import SwiftUI

/// The quality summary. A click expands the controls in place.
struct QualityCard: View {
    @Bindable var model: GaugeModel
    @State private var expanded: Bool
    @State private var confirming = false

    init(model: GaugeModel, expanded: Bool = false, confirming: Bool = false) {
        self.model = model
        _expanded = State(initialValue: expanded || confirming)
        _confirming = State(initialValue: confirming)
    }

    private var summary: String {
        "\(model.settings.maxRateMbps) Mbit/s · \(model.settings.bufferMs) ms buffer"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(MaterialMotion.emphasized) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Symbol("tune", size: 22)
                        .foregroundStyle(MaterialColor.onSurfaceVariant)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quality").font(MaterialType.font(14, weight: .medium))
                        Text(summary)
                            .font(MaterialType.font(13))
                            .foregroundStyle(MaterialColor.onSurfaceVariant)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer()
                    Symbol("chevron_right", size: 22)
                        .foregroundStyle(MaterialColor.onSurfaceVariant)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quality, \(summary)")
            .accessibilityHint(expanded ? "Collapses the quality settings" : "Expands the quality settings")

            if expanded {
                controls
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card()
        .clipped()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            ValueRow(title: "Max rate", value: "\(model.settings.maxRateMbps) Mbit/s")
            MaterialSlider(value: $model.settings.maxRateMbps, range: MirrorSettings.maxRateRange, step: 1)
                .accessibilityLabel("Max rate")
            ValueRow(title: "Buffer", value: "\(model.settings.bufferMs) ms")
                .padding(.top, 12)
            MaterialSlider(value: $model.settings.bufferMs, range: MirrorSettings.bufferRange, step: 50)
                .accessibilityLabel("Buffer")
            Text("The content sets its own frame rate, up to 60 fps.")
                .font(MaterialType.font(12))
                .foregroundStyle(MaterialColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            stateLine
                .padding(.top, 14)
            // The confirmation stays inside the panel. A system dialog takes the focus from the
            // menu bar window, and macOS then closes the whole panel.
            if confirming {
                confirmation
                    .padding(.top, 10)
                    .transition(.opacity)
            } else {
                applyButton
                    .padding(.top, 10)
            }
            if let error = model.restartError {
                Text(message(for: error))
                    .font(MaterialType.font(13))
                    .foregroundStyle(MaterialColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }

    private var stateLine: some View {
        let (icon, text, color): (String, String, Color) = switch model.chromeState {
        case .notRunning:
            ("public_off", "Chrome is not running", MaterialColor.onSurfaceVariant)
        case .active(let settings) where settings == model.settings:
            ("check_circle", "Active in Chrome", MaterialColor.success)
        case .active, .inactive:
            ("info", "Not active in Chrome", MaterialColor.warning)
        }
        return HStack(spacing: 6) {
            Symbol(icon, size: 16)
            Text(text).font(MaterialType.font(13, weight: .medium))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restart Chrome?")
                .font(MaterialType.font(16, weight: .medium))
            Text("The cast stops. Chrome reopens your tabs. Start the cast again after Chrome opens.")
                .font(MaterialType.font(13))
                .foregroundStyle(MaterialColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button {
                    withAnimation(MaterialMotion.emphasized) { confirming = false }
                } label: {
                    Text("Cancel")
                        .font(MaterialType.font(14, weight: .medium))
                        .foregroundStyle(MaterialColor.primary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .contentShape(Capsule())
                }
                .buttonStyle(MaterialPressStyle())
                .keyboardShortcut(.cancelAction)
                Button {
                    withAnimation(MaterialMotion.emphasized) { confirming = false }
                    Task { await model.applySettings() }
                } label: {
                    Text("Restart Chrome")
                        .font(MaterialType.font(14, weight: .medium))
                        .foregroundStyle(MaterialColor.onPrimary)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 40)
                        .background(MaterialColor.primary, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(MaterialPressStyle())
            }
        }
        .padding(16)
        .background(MaterialColor.tile, in: RoundedRectangle(cornerRadius: MaterialShape.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var applyButton: some View {
        Button {
            withAnimation(MaterialMotion.emphasized) { confirming = true }
        } label: {
            HStack(spacing: 8) {
                if model.isRestarting {
                    ProgressView().controlSize(.small).tint(MaterialColor.onPrimary)
                    Text("Restarting…")
                } else {
                    Text("Apply and restart Chrome")
                }
            }
            .font(MaterialType.font(14, weight: .medium))
            .foregroundStyle(MaterialColor.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(MaterialColor.primary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(MaterialPressStyle())
        .disabled(model.isRestarting)
    }

    private func message(for error: RestartError) -> String {
        switch error {
        case .chromeStayedOpen:
            "Chrome did not quit. Close any open dialogs in Chrome, then try again."
        case .launchFailed(let reason):
            reason.isEmpty ? "Chrome did not start." : "Chrome did not start. \(reason)"
        }
    }
}

/// A title on the left and its value on the right.
struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).font(MaterialType.font(14))
            Spacer()
            Text(value).font(MaterialType.font(14, weight: .medium)).monospacedDigit()
        }
    }
}

/// The Material 3 state layer: the control darkens a little while you press it.
struct MaterialPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.12 : 0)))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A Material 3 slider: a thick track with a gap around a bar handle. Values snap to the step.
struct MaterialSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    private let trackHeight: CGFloat = 16
    private let handleWidth: CGFloat = 4
    private let gap: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
            let x = fraction * (width - handleWidth)
            ZStack(alignment: .leading) {
                // The inactive track starts after the handle gap.
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(MaterialColor.primaryContainer)
                    .frame(width: max(width - x - handleWidth - gap, 0), height: trackHeight)
                    .offset(x: x + handleWidth + gap)
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(MaterialColor.primary)
                    .frame(width: max(x - gap, 0), height: trackHeight)
                Capsule()
                    .fill(MaterialColor.primary)
                    .frame(width: handleWidth, height: 36)
                    .offset(x: x)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let f = min(max(drag.location.x / width, 0), 1)
                    let raw = Double(range.lowerBound) + f * Double(range.upperBound - range.lowerBound)
                    let snapped = Int((raw / Double(step)).rounded()) * step
                    value = min(max(snapped, range.lowerBound), range.upperBound)
                }
            )
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

