import AppKit
import ShareSoundKit
import SwiftUI

@main
struct ShareSoundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            ControlPanel(controller: delegate.controller)
        } label: {
            MenuBarIcon(isSharing: delegate.controller.state.isSharing)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon.
///
/// The app's own logo, used as a template image: macOS draws it black or white to
/// match the menu bar's appearance, so no separate light and dark variants are needed.
private struct MenuBarIcon: View {
    let isSharing: Bool

    var body: some View {
        Image(nsImage: Self.logo)
            // A small dot while sharing runs, so the user can tell audio is being
            // shared without opening the panel.
            .overlay(alignment: .topTrailing) {
                if isSharing {
                    Circle()
                        .fill(Design.Palette.active)
                        .frame(width: 5, height: 5)
                }
            }
            .accessibilityLabel(isSharing ? "ShareSound — sharing active" : "ShareSound")
    }

    /// The template logo, loaded once for the menu bar.
    ///
    /// Falls back to a system symbol so the app is never left without an icon.
    private static let logo: NSImage = {
        let image = Bundle.module.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)
            ?? NSImage()

        image.isTemplate = true
        // The artwork ships thicker than the source logo: at menu bar size the
        // original hairlines rendered almost invisibly next to system glyphs.
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}

/// Where the app's lifecycle and dependencies are set up.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let deviceProvider = CoreAudioDeviceProvider()
    private let aggregateController = CoreAudioAggregateController()

    let controller: ShareSessionController

    override init() {
        // A previous run may have crashed or been force-quit, leaving a ShareSound
        // device behind. Clearing it before the controller is built keeps ghost
        // devices out of the list.
        aggregateController.removeOrphanedAggregates()

        controller = ShareSessionController(
            deviceProvider: deviceProvider,
            aggregateController: aggregateController
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Absent from the Dock and the app switcher; it lives in the menu bar only.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restores the system output to wherever the user left it and removes the
        // device that was created. Skipping this would leave them on a silent output.
        controller.shutdown()
    }
}
