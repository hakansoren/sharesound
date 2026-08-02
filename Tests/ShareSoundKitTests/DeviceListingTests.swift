import Testing
@testable import ShareSoundKit

@MainActor
@Suite("Device listing and selection")
struct DeviceListingTests {

    @Test("Lists output devices")
    func listsOutputDevices() {
        let harness = TestHarness(devices: [
            .stub(id: 1, name: "AirPods"),
            .stub(id: 2, name: "Sony WH-1000XM4"),
        ])

        #expect(harness.controller.devices.map(\.name) == ["AirPods", "Sony WH-1000XM4"])
    }

    @Test("Aggregate devices stay out of the selectable list")
    func excludesAggregateDevices() {
        let harness = TestHarness(devices: [
            .stub(id: 1, name: "AirPods"),
            .stub(id: 2, name: "Multi-Output", transport: .virtual, isAggregate: true),
        ])

        #expect(harness.controller.devices.map(\.id) == [1])
    }

    @Test("The aggregate created while sharing is hidden from the list")
    func hidesOwnAggregateWhileSharing() {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2)],
            selecting: [1, 2]
        )

        // The fake system added the new device to its list, just as CoreAudio would.
        #expect(harness.system.installedDevices.count == 3)
        #expect(harness.controller.devices.map(\.id) == [1, 2])
    }

    @Test("Selection preserves the order devices were ticked")
    func selectionPreservesOrder() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2), .stub(id: 3)])

        harness.select(3, 1)

        #expect(harness.controller.selection == [3, 1])
        #expect(harness.controller.selectedDevices.map(\.id) == [3, 1])
    }

    @Test("Ticking twice deselects")
    func togglingTwiceDeselects() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)])

        harness.select(1, 1)

        #expect(harness.controller.selection.isEmpty)
        #expect(harness.controller.isSelected(1) == false)
    }

    @Test("Unknown devices cannot be selected")
    func ignoresUnknownDevice() {
        let harness = TestHarness(devices: [.stub(id: 1)])

        harness.select(99)

        #expect(harness.controller.selection.isEmpty)
    }

    @Test("Sharing requires at least two devices")
    func requiresTwoDevicesToStart() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)])

        #expect(harness.controller.canStartSharing == false)

        harness.select(1)
        #expect(harness.controller.canStartSharing == false)

        harness.select(2)
        #expect(harness.controller.canStartSharing)
    }

    @Test("A non-wireless device is chosen as master")
    func prefersWiredDeviceAsMaster() {
        let harness = TestHarness(devices: [
            .stub(id: 1, name: "AirPods", transport: .bluetooth),
            .stub(id: 2, name: "USB Headphones", transport: .usb),
        ])

        harness.select(1, 2)

        // The wired device keeps steadier time, so it should be master even though
        // it was selected second.
        #expect(harness.controller.masterDevice?.id == 2)
    }

    @Test("With everything wireless, the first selected becomes master")
    func fallsBackToFirstSelectedAsMaster() {
        let harness = TestHarness(devices: [
            .stub(id: 1, transport: .bluetooth),
            .stub(id: 2, transport: .bluetooth),
        ])

        harness.select(2, 1)

        #expect(harness.controller.masterDevice?.id == 2)
    }

    @Test("Selecting two wireless devices shows the latency hint")
    func warnsAboutWirelessLatency() {
        let harness = TestHarness(devices: [
            .stub(id: 1, transport: .bluetooth),
            .stub(id: 2, transport: .bluetooth),
            .stub(id: 3, transport: .usb),
        ])

        harness.select(1, 3)
        #expect(harness.controller.showsWirelessLatencyHint == false)

        harness.select(2)
        #expect(harness.controller.showsWirelessLatencyHint)
    }

    @Test("A newly connected device joins the list")
    func picksUpNewlyConnectedDevice() {
        let harness = TestHarness(devices: [.stub(id: 1)])

        harness.system.connect(.stub(id: 2, name: "New Headphones"))

        #expect(harness.controller.devices.map(\.id) == [1, 2])
    }
}
