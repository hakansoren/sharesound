import AppKit
import SwiftUI

/// The panel's top strip: app name, a one-line status, and the overflow menu.
struct StatusHeader: View {
    let isSharing: Bool
    let activeDeviceCount: Int
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ShareSound")
                    .font(.system(size: 14, weight: .semibold))

                Text(statusDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 0)

            statusBadge
            overflowMenu
        }
        .padding(.horizontal, Design.Metrics.panelPadding)
        .padding(.vertical, 13)
        .animation(Design.Motion.stateChange, value: isSharing)
    }

    private var statusDescription: String {
        guard isSharing else { return "Sharing is off" }
        return activeDeviceCount == 1
            ? "Playing to 1 device"
            : "Playing to \(activeDeviceCount) devices"
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isSharing ? Design.Palette.active : Color.secondary.opacity(0.6))
                .frame(width: 6, height: 6)

            Text(isSharing ? "Active" : "Ready")
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassEffect(
            isSharing ? .regular.tint(Design.Palette.active.opacity(0.3)) : .regular,
            in: .capsule
        )
        .foregroundStyle(isSharing ? AnyShapeStyle(Design.Palette.active) : AnyShapeStyle(Color.secondary))
        .accessibilityLabel(isSharing ? "Sharing active" : "Sharing off")
    }

    /// Secondary actions live behind one button rather than as links along the
    /// bottom edge, so the panel has a single obvious primary action.
    private var overflowMenu: some View {
        Menu {
            Button("Refresh Devices", action: onRefresh)

            Divider()

            Button("Sound Settings…", action: openSoundSettings)

            Divider()

            Button("Quit ShareSound") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26)
        .foregroundStyle(.secondary)
        .help("More options")
        .accessibilityLabel("More options")
    }

    private func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
