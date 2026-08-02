import Testing
@testable import ShareSoundKit

@MainActor
@Suite("Volume")
struct VolumeTests {

    @Test("Volumes are read from the system")
    func readsVolumesFromSystem() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)], initialVolume: 0.42)

        #expect(harness.controller.volume(for: 1) == 0.42)
        #expect(harness.controller.volume(for: 2) == 0.42)
    }

    @Test("Volume is set and written to the device")
    func writesVolumeToDevice() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)])

        harness.controller.setVolume(0.75, for: 1)

        #expect(harness.controller.volume(for: 1) == 0.75)
        #expect(harness.system.deviceVolumes[1] == 0.75)
    }

    @Test("Out-of-range values are clamped", arguments: [
        (input: Float(1.8), expected: Float(1.0)),
        (input: Float(-0.5), expected: Float(0.0)),
        (input: Float(0.3), expected: Float(0.3)),
    ])
    func clampsVolumeToValidRange(input: Float, expected: Float) {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)])

        harness.controller.setVolume(input, for: 1)

        #expect(harness.controller.volume(for: 1) == expected)
        #expect(harness.system.deviceVolumes[1] == expected)
    }

    @Test("A device without volume support has no level")
    func omitsVolumeForUnsupportedDevice() {
        let harness = TestHarness(devices: [
            .stub(id: 1),
            .stub(id: 2, name: "HDMI", transport: .hdmi, supportsVolumeControl: false),
        ])

        #expect(harness.controller.volume(for: 2) == nil)
    }

    @Test("No level is written to an unsupported device")
    func refusesVolumeOnUnsupportedDevice() {
        let harness = TestHarness(devices: [
            .stub(id: 1),
            .stub(id: 2, name: "HDMI", transport: .hdmi, supportsVolumeControl: false),
        ])

        harness.controller.setVolume(0.9, for: 2)

        #expect(harness.controller.lastError == .volumeControlUnsupported(name: "HDMI"))
        #expect(harness.system.volumeWrites.isEmpty)
    }

    @Test("A failed write snaps the slider back to the real value")
    func revertsToActualVolumeWhenWriteFails() {
        let harness = TestHarness(devices: [.stub(id: 1, name: "AirPods"), .stub(id: 2)], initialVolume: 0.4)
        harness.system.setVolumeError = .volumeControlUnsupported(name: "AirPods")

        harness.controller.setVolume(0.9, for: 1)

        #expect(harness.controller.volume(for: 1) == 0.4, "A value that was not applied must not be shown")
        #expect(harness.controller.lastError == .volumeControlUnsupported(name: "AirPods"))
    }

    @Test("No level is written to an unknown device")
    func ignoresUnknownDevice() {
        let harness = TestHarness(devices: [.stub(id: 1)])

        harness.controller.setVolume(0.5, for: 99)

        #expect(harness.system.volumeWrites.isEmpty)
        #expect(harness.controller.lastError == nil)
    }

    @Test("A disconnected device loses its level")
    func dropsVolumeWhenDeviceDisconnects() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)])

        harness.system.disconnect(2)

        #expect(harness.controller.volume(for: 2) == nil)
        #expect(harness.controller.volume(for: 1) != nil)
    }
}
