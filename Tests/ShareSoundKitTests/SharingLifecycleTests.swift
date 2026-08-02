import Testing
@testable import ShareSoundKit

@MainActor
@Suite("Sharing lifecycle")
struct SharingLifecycleTests {

    @Test("Starting builds the shared output and routes the system to it")
    func startsSharing() throws {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2)],
            selecting: [1, 2],
            defaultOutput: 1
        )

        let session = try #require(harness.controller.state.session)

        #expect(session.memberDeviceIDs == [1, 2])
        #expect(session.previousDefaultDeviceID == 1)
        #expect(harness.system.defaultOutput == session.aggregateDeviceID)
        #expect(harness.system.createdAggregates.count == 1)
        #expect(harness.controller.lastError == nil)
    }

    @Test("The master device is passed to the aggregate setup")
    func passesMasterToAggregate() throws {
        let harness = TestHarness.sharing(
            devices: [
                .stub(id: 1, transport: .bluetooth),
                .stub(id: 2, transport: .builtIn),
            ],
            selecting: [1, 2]
        )

        let created = try #require(harness.system.createdAggregates.first)
        #expect(created.master == 2)
        #expect(created.members == [1, 2])
    }

    @Test("Sharing will not start without two devices")
    func refusesToStartWithoutTwoDevices() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)])

        harness.select(1)
        harness.controller.startSharing()

        #expect(harness.controller.state == .idle)
        #expect(harness.controller.lastError == .needsAtLeastTwoDevices)
        #expect(harness.system.createdAggregates.isEmpty)
    }

    @Test("Starting again while sharing creates no second device")
    func startingTwiceIsNoOp() {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2)],
            selecting: [1, 2]
        )

        harness.controller.startSharing()

        #expect(harness.system.createdAggregates.count == 1)
    }

    @Test("Stopping restores the previous output and removes the device")
    func stopsSharingAndRestores() throws {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2)],
            selecting: [1, 2],
            defaultOutput: 2
        )
        let aggregateID = try #require(harness.controller.state.session?.aggregateDeviceID)

        harness.controller.stopSharing()

        #expect(harness.controller.state == .idle)
        #expect(harness.system.defaultOutput == 2)
        #expect(harness.system.destroyedAggregateIDs == [aggregateID])
        #expect(harness.system.liveAggregateIDs.isEmpty)
    }

    @Test("Stopping while idle does nothing")
    func stoppingWhenIdleIsNoOp() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)])

        harness.controller.stopSharing()

        #expect(harness.system.destroyedAggregateIDs.isEmpty)
        #expect(harness.controller.lastError == nil)
    }

    @Test("Quitting restores the system")
    func shutdownRestoresSystem() throws {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2)],
            selecting: [1, 2],
            defaultOutput: 1
        )
        let aggregateID = try #require(harness.controller.state.session?.aggregateDeviceID)

        harness.controller.shutdown()

        #expect(harness.controller.state == .idle)
        #expect(harness.system.defaultOutput == 1)
        #expect(harness.system.destroyedAggregateIDs == [aggregateID])
    }

    @Test("Adding a device while sharing rebuilds the session")
    func addingDeviceWhileSharingRebuilds() throws {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2), .stub(id: 3)],
            selecting: [1, 2],
            defaultOutput: 1
        )
        let firstAggregateID = try #require(harness.controller.state.session?.aggregateDeviceID)

        harness.controller.toggleSelection(3)

        let session = try #require(harness.controller.state.session)
        #expect(session.memberDeviceIDs == [1, 2, 3])
        #expect(session.aggregateDeviceID != firstAggregateID)
        #expect(session.previousDefaultDeviceID == 1, "The pre-sharing output must be preserved")
        #expect(harness.system.destroyedAggregateIDs == [firstAggregateID])
        #expect(harness.system.defaultOutput == session.aggregateDeviceID)
    }

    @Test("On rebuild the new device goes live before the old one is removed")
    func rebuildActivatesNewDeviceBeforeDestroyingOld() throws {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2), .stub(id: 3)],
            selecting: [1, 2]
        )
        let firstAggregateID = try #require(harness.controller.state.session?.aggregateDeviceID)

        harness.controller.toggleSelection(3)

        let newAggregateID = try #require(harness.controller.state.session?.aggregateDeviceID)
        // The order that minimises the audio gap: switch to the new device first,
        // then remove the old one.
        #expect(harness.system.defaultOutputHistory.last == newAggregateID)
        #expect(harness.system.destroyedAggregateIDs == [firstAggregateID])
    }

    @Test("Dropping to one device stops sharing")
    func rebuildStopsWhenSelectionDropsBelowTwo() throws {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2)],
            selecting: [1, 2],
            defaultOutput: 2
        )
        let aggregateID = try #require(harness.controller.state.session?.aggregateDeviceID)

        harness.controller.toggleSelection(1)

        #expect(harness.controller.state == .idle)
        #expect(harness.system.defaultOutput == 2)
        #expect(harness.system.destroyedAggregateIDs == [aggregateID])
    }
}
