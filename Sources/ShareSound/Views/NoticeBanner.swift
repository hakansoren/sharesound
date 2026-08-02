import ShareSoundKit
import SwiftUI

/// The error and information strip.
///
/// Presented inline in the panel rather than as a modal, so the user can read it
/// at a glance and carry on without the flow being interrupted.
struct NoticeBanner: View {
    let title: String
    let message: String?
    let symbol: String
    let tint: Color
    let onDismiss: (() -> Void)?

    var body: some View {
        // Centred vertically: the icon and dismiss button stay aligned with the
        // middle of the card whether the text runs to one line or two.
        HStack(alignment: .center, spacing: 11) {
            badge

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onDismiss {
                DismissButton(action: onDismiss)
            } else {
                // Without a dismiss button the text would hug the right edge; this
                // keeps every strip on the same visual rhythm.
                Spacer(minLength: 0).frame(width: 6)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Colour hints rather than fills: the stripe and badge carry it while the
        // glass stays calm. A saturated fill would drown out the rest of the panel.
        .glassEffect(
            .regular.tint(tint.opacity(0.1)),
            in: .rect(cornerRadius: Design.Metrics.bannerCornerRadius)
        )
        .overlay(alignment: .leading) {
            // A thin colour stripe, so the kind of notice reads before the text does.
            Capsule()
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 4)
        }
        .accessibilityElement(children: .combine)
    }

    /// Sets the symbol in a tinted circle so the notice type reads at a distance.
    private var badge: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.22))

            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 26, height: 26)
        .padding(.leading, 4)
    }
}

/// The button that dismisses a notice.
///
/// The visible circle is 22pt but the click target is 28pt: as Apple recommends
/// for small glyphs, the target is kept larger than the artwork.
private struct DismissButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 22)
                .background {
                    Circle().fill(.primary.opacity(isHovering ? 0.12 : 0.06))
                }
                .contentShape(Circle().size(width: 28, height: 28).offset(x: -3, y: -3))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Dismiss")
        .accessibilityLabel("Dismiss")
    }
}

extension NoticeBanner {
    /// Turns a `ShareSoundError` into a strip. Severity picks the colour and icon.
    init(error: ShareSoundError, onDismiss: @escaping () -> Void) {
        self.init(
            title: error.errorDescription ?? "Something went wrong",
            message: error.recoverySuggestion,
            symbol: error.severity == .critical ? "exclamationmark.triangle.fill" : "info.circle.fill",
            tint: error.severity == .critical ? Design.Palette.criticalBanner : Design.Palette.informationalBanner,
            onDismiss: onDismiss
        )
    }

    /// The latency note shown when two wireless devices are selected.
    static var wirelessLatency: NoticeBanner {
        NoticeBanner(
            title: "Two wireless devices selected",
            message: "You may hear a small delay between Bluetooth headphones.",
            symbol: "wave.3.right",
            tint: Design.Palette.informationalBanner,
            onDismiss: nil
        )
    }
}
