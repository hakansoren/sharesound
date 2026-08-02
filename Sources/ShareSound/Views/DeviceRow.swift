import ShareSoundKit
import SwiftUI

/// A single output device in the list.
///
/// The whole row is the selection control; the volume slider sits below it as a
/// separate control so dragging it can never flip the selection by accident.
struct DeviceRow: View {
    let device: AudioDevice
    let isSelected: Bool
    let isLive: Bool
    let volume: Float?
    let onToggle: () -> Void
    let onVolumeChange: (Float) -> Void

    private var tint: Color {
        isLive ? Design.Palette.active : Design.Palette.selected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                header
            }
            .buttonStyle(.plain)
            .accessibilityLabel(device.name)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Adds or removes this device from sharing")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)

            if isSelected {
                volumeControl
                    .transition(.opacity.combined(with: .blurReplace))
            }
        }
        .glassCard(isHighlighted: isSelected, tint: tint)
        .animation(Design.Motion.stateChange, value: isSelected)
        .animation(Design.Motion.stateChange, value: isLive)
    }

    private var header: some View {
        HStack(spacing: 11) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(device.transport.localizedLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isLive {
                LivePulse()
                    .transition(.scale.combined(with: .opacity))
            }

            selectionIndicator
        }
        .contentShape(Rectangle())
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Design.Metrics.iconCornerRadius, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(tint.opacity(0.22)) : AnyShapeStyle(.quaternary))

            Image(systemName: device.transport.symbolName)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Color.secondary))
        }
        .frame(width: Design.Metrics.iconSize, height: Design.Metrics.iconSize)
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 17))
            .foregroundStyle(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
            .contentTransition(.symbolEffect(.replace))
    }

    /// While a shared output is in use the keyboard volume keys never reach the
    /// member devices, so every device gets its own slider here.
    @ViewBuilder
    private var volumeControl: some View {
        if let volume, device.supportsVolumeControl {
            HStack(spacing: 9) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(volume) },
                        set: { onVolumeChange(Float($0)) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .tint(tint)

                Text(volume.formattedAsPercentage)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(device.name) volume")
        } else if device.supportsVolumeControl == false {
            Label("Set the volume on the device itself", systemImage: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

/// A small pulsing dot marking a device that is currently receiving audio.
///
/// Motion carries the meaning here: a static dot reads as decoration, a breathing
/// one reads as "right now".
private struct LivePulse: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Design.Palette.active)
            .frame(width: 6, height: 6)
            .opacity(isPulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
            .accessibilityHidden(true)
    }
}

private extension Float {
    /// Renders a 0...1 level as a percentage.
    var formattedAsPercentage: String {
        "\(Int((self * 100).rounded()))%"
    }
}
