import AppKit
import ShareSoundKit
import SwiftUI

/// The panel that opens when the menu bar icon is clicked.
///
/// Every decision lives in `ShareSessionController`; this only renders that
/// state and reports the user's intent back.
struct ControlPanel: View {
    @Bindable var controller: ShareSessionController

    /// Measured content height of the device list. Needed to give the panel a
    /// definite size — see `deviceList` for why.
    @State private var listContentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            StatusHeader(
                isSharing: controller.state.isSharing,
                activeDeviceCount: controller.state.session?.memberDeviceIDs.count ?? 0,
                onRefresh: controller.refresh
            )

            Divider().opacity(0.5)

            content
                .padding(.horizontal, Design.Metrics.panelPadding)
                .padding(.vertical, 13)

            Divider().opacity(0.5)

            footer
        }
        .frame(width: Design.Metrics.panelWidth)
        .animation(Design.Motion.stateChange, value: controller.state)
        .animation(Design.Motion.stateChange, value: controller.lastError)
        .animation(Design.Motion.stateChange, value: controller.devices)
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Design.Metrics.sectionSpacing) {
            if controller.devices.count < 2 {
                EmptyState(deviceCount: controller.devices.count)
            } else {
                sectionTitle
                deviceList
            }

            if controller.showsWirelessLatencyHint {
                NoticeBanner.wirelessLatency
                    .transition(.opacity.combined(with: .blurReplace))
            }

            if let error = controller.lastError {
                NoticeBanner(error: error, onDismiss: controller.dismissError)
                    .transition(.opacity.combined(with: .blurReplace))
            }
        }
    }

    private var sectionTitle: some View {
        HStack {
            Text("Output Devices")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text(selectionSummary)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
    }

    private var selectionSummary: String {
        switch controller.selection.count {
        case 0: "Choose two"
        case 1: "1 selected"
        default: "\(controller.selection.count) selected"
        }
    }

    private var deviceList: some View {
        ScrollView(.vertical) {
            // One container so adjacent glass surfaces blend into each other.
            GlassEffectContainer(spacing: Design.Metrics.rowSpacing) {
                VStack(spacing: Design.Metrics.rowSpacing) {
                    ForEach(controller.devices) { device in
                        DeviceRow(
                            device: device,
                            isSelected: controller.isSelected(device.id),
                            isLive: isLive(device.id),
                            volume: controller.volume(for: device.id),
                            onToggle: { controller.toggleSelection(device.id) },
                            onVolumeChange: { controller.setVolume($0, for: device.id) }
                        )
                    }
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // A ScrollView has no ideal height along its scroll axis. Because the
        // menu bar panel sizes itself from its content, an unmeasured list makes
        // the panel report a zero-height list area and the devices never appear.
        // Measuring the content and pinning a definite height fixes that while
        // keeping scrolling once the list outgrows the cap.
        .frame(height: min(max(listContentHeight, 1), Design.Metrics.deviceListMaxHeight))
        .onPreferenceChange(ContentHeightKey.self) { height in
            listContentHeight = height
        }
    }

    /// Whether the device is actually receiving audio, not merely selected.
    private func isLive(_ id: DeviceID) -> Bool {
        controller.state.session?.memberDeviceIDs.contains(id) ?? false
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            primaryAction

            Text(caption)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, Design.Metrics.panelPadding)
        .padding(.vertical, 13)
    }

    /// One plain sentence about what the button does, or about the one thing
    /// that is not obvious once sharing runs.
    private var caption: String {
        if controller.state.isSharing {
            return "Volume keys won't work while sharing — use the sliders above."
        }
        return controller.canStartSharing
            ? "Both devices will play the same audio."
            : "Select two devices to begin."
    }

    @ViewBuilder
    private var primaryAction: some View {
        if controller.state.isSharing {
            Button(action: controller.stopSharing) {
                Label("Stop Sharing", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .controlSize(.large)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: Design.Metrics.buttonCornerRadius))
            .tint(Design.Palette.criticalBanner)
            .keyboardShortcut(.defaultAction)
        } else {
            Button(action: controller.startSharing) {
                Label("Start Sharing", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .controlSize(.large)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: Design.Metrics.buttonCornerRadius))
            .disabled(!controller.canStartSharing)
            .keyboardShortcut(.defaultAction)
        }
    }
}

/// Carries the device list's real content height up the view tree.
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Shown when there are not enough devices to share between.
private struct EmptyState: View {
    let deviceCount: Int

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "headphones")
                .font(.system(size: 28, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.system(size: 12, weight: .medium))

            Text("Sharing needs two output devices. Connect your headphones and they'll show up here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        deviceCount == 0 ? "No output devices found" : "One more device needed"
    }
}
