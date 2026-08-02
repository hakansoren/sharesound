import Testing
@testable import ShareSoundKit

@MainActor
@Suite("Failures and recovery")
struct FailureRecoveryTests {

    @Test("If the shared output cannot be created, the system is left untouched")
    func leavesSystemUntouchedWhenAggregateCreationFails() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)], defaultOutput: 1)
        harness.system.createAggregateError = .aggregateCreationFailed(status: -4)

        harness.select(1, 2)
        harness.controller.startSharing()

        #expect(harness.controller.state == .idle)
        #expect(harness.controller.lastError == .aggregateCreationFailed(status: -4))
        #expect(harness.system.defaultOutput == 1, "The system output must not change")
        #expect(harness.system.liveAggregateIDs.isEmpty)
    }

    @Test("If the output cannot be switched, the half-built device is rolled back")
    func rollsBackAggregateWhenDefaultOutputChangeFails() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)], defaultOutput: 1)
        harness.system.setDefaultError = .defaultOutputChangeFailed(status: -7)

        harness.select(1, 2)
        harness.controller.startSharing()

        #expect(harness.controller.state == .idle)
        #expect(harness.controller.lastError == .defaultOutputChangeFailed(status: -7))
        #expect(harness.system.destroyedAggregateIDs.count == 1, "The created device must be rolled back")
        #expect(harness.system.liveAggregateIDs.isEmpty)
        #expect(harness.system.defaultOutput == 1)
    }

    @Test("If cleanup fails the state still goes idle and the user is told")
    func reportsCleanupFailureButStillGoesIdle() {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2)],
            selecting: [1, 2],
            defaultOutput: 1
        )
        harness.system.destroyAggregateError = .aggregateCleanupFailed(status: -9)

        harness.controller.stopSharing()

        #expect(harness.controller.state == .idle)
        #expect(harness.controller.lastError == .aggregateCleanupFailed(status: -9))
        #expect(harness.system.defaultOutput == 1, "The previous output must still be restored")
    }

    @Test("A failed rebuild shuts sharing down safely")
    func fallsBackToIdleWhenRebuildFails() {
        let harness = TestHarness.sharing(
            devices: [.stub(id: 1), .stub(id: 2), .stub(id: 3)],
            selecting: [1, 2],
            defaultOutput: 1
        )
        harness.system.createAggregateError = .aggregateCreationFailed(status: -4)

        harness.controller.toggleSelection(3)

        #expect(harness.controller.state == .idle)
        #expect(harness.controller.lastError == .aggregateCreationFailed(status: -4))
        #expect(harness.system.defaultOutput == 1, "The pre-sharing output must be restored")
        #expect(harness.system.liveAggregateIDs.isEmpty, "The old device must be cleaned up too")
    }

    @Test("Errors can be dismissed")
    func dismissesError() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)])

        harness.select(1)
        harness.controller.startSharing()
        #expect(harness.controller.lastError != nil)

        harness.controller.dismissError()
        #expect(harness.controller.lastError == nil)
    }

    @Test("A successful start clears the previous error")
    func successfulStartClearsPreviousError() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2)])

        harness.select(1)
        harness.controller.startSharing()
        #expect(harness.controller.lastError == .needsAtLeastTwoDevices)

        harness.select(2)
        harness.controller.startSharing()

        #expect(harness.controller.state.isSharing)
        #expect(harness.controller.lastError == nil)
    }

    @Test("The notice retires itself once the user resolves it")
    func clearsNoticeWhenUserResolvesIt() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2), .stub(id: 3)])

        harness.select(1)
        harness.controller.startSharing()
        #expect(harness.controller.lastError == .needsAtLeastTwoDevices)

        harness.select(2)

        #expect(harness.controller.lastError == nil, "The notice stops being true once a second device is ticked")
    }

    @Test("A critical error survives a selection change")
    func keepsCriticalErrorOnSelectionChange() {
        let harness = TestHarness(devices: [.stub(id: 1), .stub(id: 2), .stub(id: 3)])
        harness.system.createAggregateError = .aggregateCreationFailed(status: -4)

        harness.select(1, 2)
        harness.controller.startSharing()
        #expect(harness.controller.lastError == .aggregateCreationFailed(status: -4))

        harness.select(3)

        #expect(harness.controller.lastError == .aggregateCreationFailed(status: -4))
    }

    @Test("Every error tells the user what to do", arguments: [
        ShareSoundError.needsAtLeastTwoDevices,
        .aggregateCreationFailed(status: -1),
        .defaultOutputChangeFailed(status: -1),
        .memberDeviceDisappeared(name: "AirPods"),
        .volumeControlUnsupported(name: "HDMI"),
        .aggregateCleanupFailed(status: -1),
    ])
    func everyErrorHasUserFacingText(error: ShareSoundError) {
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }

    @Test("Recoverable notices are separated from critical errors")
    func separatesInformationalFromCriticalErrors() {
        #expect(ShareSoundError.needsAtLeastTwoDevices.severity == .informational)
        #expect(ShareSoundError.volumeControlUnsupported(name: "HDMI").severity == .informational)
        #expect(ShareSoundError.aggregateCreationFailed(status: -1).severity == .critical)
        #expect(ShareSoundError.memberDeviceDisappeared(name: "AirPods").severity == .critical)
    }
}
