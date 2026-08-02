import SwiftUI

/// The panel's visual language: metrics, radii and state colours in one place.
///
/// Surfaces use the Liquid Glass material introduced in macOS 26, and the radii
/// follow the system's rounder idiom. Where one rounded shape sits inside
/// another, the inner radius is the outer radius minus the padding, so the
/// corners stay concentric.
enum Design {

    enum Metrics {
        /// Fixed width of the panel. Wider than a standard menu so device names
        /// have room to breathe alongside the larger radii and padding.
        static let panelWidth: CGFloat = 360

        /// The device list scrolls past this height instead of filling the screen.
        static let deviceListMaxHeight: CGFloat = 340

        static let panelPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 12
        static let rowSpacing: CGFloat = 8
        static let rowPadding: CGFloat = 12

        static let rowCornerRadius: CGFloat = 20
        static let bannerCornerRadius: CGFloat = 16
        static let iconCornerRadius: CGFloat = 11
        static let buttonCornerRadius: CGFloat = 16
        static let iconSize: CGFloat = 34
    }

    enum Palette {
        /// Used while sharing is running.
        static let active = Color.green

        /// Highlight for devices that are selected but not yet playing.
        static let selected = Color.accentColor

        static let criticalBanner = Color.red
        static let informationalBanner = Color.orange
    }

    enum Motion {
        /// One transition curve for every selection and state change. Liquid
        /// Glass surfaces behave like a fluid, so the spring is gentle.
        static let stateChange: Animation = .smooth(duration: 0.32, extraBounce: 0.08)
    }
}

extension View {
    /// Turns a row into a Liquid Glass card.
    ///
    /// Selected rows take a colour tint and become interactive, so the surface
    /// responds to the pointer; unselected rows stay plain glass.
    func glassCard(isHighlighted: Bool, tint: Color) -> some View {
        padding(Design.Metrics.rowPadding)
            .glassEffect(
                isHighlighted
                    ? .regular.tint(tint.opacity(0.28)).interactive()
                    : .regular.interactive(),
                in: .rect(cornerRadius: Design.Metrics.rowCornerRadius)
            )
    }
}
