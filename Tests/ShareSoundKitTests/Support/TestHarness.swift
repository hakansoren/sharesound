import Foundation
@testable import ShareSoundKit

/// A test helper that wires a controller to a fake audio system.
///
/// Every test builds its own isolated system; no state is shared between them.
@MainActor
struct TestHarness {
    let system = FakeAudioSystem()
    let controller: ShareSessionController

    /// - Parameters:
    ///   - devices: Devices that appear connected to the system.
    ///   - defaultOutput: System output before sharing. Defaults to the first device.
    ///   - initialVolume: Starting level for devices that support volume control.
    init(
        devices: [AudioDevice],
        defaultOutput: DeviceID? = nil,
        initialVolume: Float = 0.5
    ) {
        system.installedDevices = devices
        system.defaultOutput = defaultOutput ?? devices.first?.id

        for device in devices where device.supportsVolumeControl {
            system.deviceVolumes[device.id] = initialVolume
        }

        controller = ShareSessionController(
            deviceProvider: system,
            aggregateController: system
        )
    }

    /// Ticks the given devices in order.
    func select(_ ids: DeviceID...) {
        for id in ids {
            controller.toggleSelection(id)
        }
    }

    /// Shortcut that selects devices and starts sharing.
    static func sharing(
        devices: [AudioDevice],
        selecting ids: [DeviceID],
        defaultOutput: DeviceID? = nil
    ) -> TestHarness {
        let harness = TestHarness(devices: devices, defaultOutput: defaultOutput)
        for id in ids {
            harness.controller.toggleSelection(id)
        }
        harness.controller.startSharing()
        return harness
    }
}
