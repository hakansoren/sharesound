import Testing
@testable import ShareSoundKit

@MainActor
@Suite("Losing a device while sharing")
struct DeviceLossTests {

    @Test("Losing one of three members continues with the rest")
    func continuesWithRemainingMembers() throws {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2), .stub(id: 3)],
            selecting: [1, 2, 3],
            defaultOutput: 1
        )
        let firstAggregateID = try #require(harness.controller.state.session?.aggregateDeviceID)

        harness.system.disconnect(2)

        let session = try #require(harness.controller.state.session)
        #expect(session.memberDeviceIDs == [1, 3])
        #expect(session.previousDefaultDeviceID == 1)
        #expect(harness.system.destroyedAggregateIDs == [firstAggregateID])
        #expect(harness.controller.selection == [1, 3])
    }

    @Test("Losing one of two members stops sharing and restores the output")
    func stopsWhenTooFewMembersRemain() throws {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2)],
            selecting: [1, 2],
            defaultOutput: 1
        )
        let aggregateID = try #require(harness.controller.state.session?.aggregateDeviceID)

        harness.system.disconnect(2)

        #expect(harness.controller.state == .idle)
        #expect(harness.system.defaultOutput == 1)
        #expect(harness.system.destroyedAggregateIDs == [aggregateID])
        #expect(harness.system.liveAggregateIDs.isEmpty)
    }

    @Test("The disconnected device is reported by name")
    func namesTheDisconnectedDevice() {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1, name: "AirPods"), .stub(id: 2, name: "Sony WH-1000XM4")],
            selecting: [1, 2]
        )

        harness.system.disconnect(2)

        #expect(harness.controller.lastError == .memberDeviceDisappeared(name: "Sony WH-1000XM4"))
    }

    @Test("Losing a selected non-member device leaves sharing alone")
    func ignoresLossOfNonMemberDevice() throws {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2), .stub(id: 3)],
            selecting: [1, 2],
            defaultOutput: 1
        )
        let aggregateID = try #require(harness.controller.state.session?.aggregateDeviceID)

        harness.system.disconnect(3)

        #expect(harness.controller.state.session?.aggregateDeviceID == aggregateID)
        #expect(harness.system.destroyedAggregateIDs.isEmpty)
        #expect(harness.controller.lastError == nil)
    }

    @Test("A disconnected device drops out of the selection")
    func prunesDisconnectedDeviceFromSelection() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2), .stub(id: 3)])

        harness.select(1, 2, 3)
        harness.system.disconnect(2)

        #expect(harness.controller.selection == [1, 3])
        #expect(harness.controller.devices.map(\.id) == [1, 3])
    }

    @Test("Disconnecting while idle raises no error")
    func silentWhenIdle() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)])

        harness.select(1, 2)
        harness.system.disconnect(1)

        #expect(harness.controller.lastError == nil)
        #expect(harness.controller.state == .idle)
    }
}
