import CastGaugeKit
import SwiftUI

/// The Chromecasts on the network, when no tab cast runs. A device that casts something
/// has a Stop button. CastGauge cannot start a Chrome tab cast, so the list has no Cast button.
struct DeviceListCard: View {
    let model: GaugeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: "CHROMECASTS")
            if model.devices.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for Chromecasts…")
                        .font(MaterialType.font(14))
                        .foregroundStyle(MaterialColor.onSurfaceVariant)
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(model.devices, id: \.id) { device in
                        DeviceRow(model: model, device: device)
                    }
                }
                .padding(.top, 10)
            }
            if let error = model.stopError {
                Text(error)
                    .font(MaterialType.font(13))
                    .foregroundStyle(MaterialColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .card()
    }
}

private struct DeviceRow: View {
    let model: GaugeModel
    let device: CastDevice

    private var stateText: String {
        switch device.activity {
        case .idle: "Idle"
        case .castingTab: "Casting a tab"
        case .app(let text): text
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(MaterialColor.primaryContainer)
                .frame(width: 36, height: 36)
                .overlay(Symbol("tv", size: 20).foregroundStyle(MaterialColor.onPrimaryContainer))
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(MaterialType.font(14, weight: .medium))
                    .lineLimit(1)
                Text(stateText)
                    .font(MaterialType.font(12))
                    .foregroundStyle(MaterialColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if device.activity != .idle {
                Button {
                    Task { await model.stop(device) }
                } label: {
                    HStack(spacing: 4) {
                        if model.stopping.contains(device.id) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Symbol("stop", size: 16)
                        }
                        Text("Stop").font(MaterialType.font(13, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .foregroundStyle(MaterialColor.primary)
                    .overlay(Capsule().stroke(MaterialColor.outline, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(MaterialPressStyle())
                .disabled(model.stopping.contains(device.id) || device.address == nil)
                .accessibilityLabel("Stop the cast on \(device.name)")
            }
        }
        .padding(10)
        .background(MaterialColor.tile, in: RoundedRectangle(cornerRadius: MaterialShape.tile, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
