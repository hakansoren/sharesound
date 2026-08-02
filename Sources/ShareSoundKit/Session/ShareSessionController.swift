import Foundation
import Observation

/// Every decision the app makes lives here: which devices can be selected, when
/// sharing may start, and what happens when a device disappears mid-session.
///
/// The controller never talks to CoreAudio directly — only to the
/// `AudioDeviceProviding` and `AggregateDeviceControlling` protocols. That is
/// what makes all of its behaviour testable without real hardware.
@MainActor
@Observable
public final class ShareSessionController {

    // MARK: - Published state

    /// Output devices that may take part in sharing.
    /// Aggregate devices — including the one this app creates — are excluded.
    public private(set) var devices: [AudioDevice] = []

    /// Devices the user ticked, in the order they were ticked.
    public private(set) var selection: [DeviceID] = []

    public private(set) var state: SessionState = .idle

    /// Device ID to its 0...1 volume. Devices without software volume control
    /// are absent from this dictionary.
    public private(set) var volumes: [DeviceID: Float] = [:]

    /// The most recent problem worth showing. Cleared when the user dismisses it.
    public var lastError: ShareSoundError?

    // MARK: - Dependencies

    private let deviceProvider: any AudioDeviceProviding
    private let aggregateController: any AggregateDeviceControlling
    private let aggregateName: String

    public init(
        deviceProvider: any AudioDeviceProviding,
        aggregateController: any AggregateDeviceControlling,
        aggregateName: String = "ShareSound Output"
    ) {
        self.deviceProvider = deviceProvider
        self.aggregateController = aggregateController
        self.aggregateName = aggregateName

        self.deviceProvider.onSystemChange = { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    // MARK: - Derived values

    /// The selected devices, resolved against the current device list.
    public var selectedDevices: [AudioDevice] {
        selection.compactMap { id in devices.first { $0.id == id } }
    }

    public func isSelected(_ id: DeviceID) -> Bool {
        selection.contains(id)
    }

    /// Sharing needs at least two devices.
    public var canStartSharing: Bool {
        selection.count >= 2
    }

    /// Shown as a hint when more than one wireless device is selected: Bluetooth
    /// devices can play a constant distance apart in time.
    public var showsWirelessLatencyHint: Bool {
        selectedDevices.filter(\.transport.isWireless).count >= 2
    }

    /// The member that will drive the aggregate device's clock.
    ///
    /// A wired device keeps steadier time than a wireless one, so a non-wireless
    /// member is preferred as master and the others align to it. If everything is
    /// wireless, the first selected device takes the role.
    public var masterDevice: AudioDevice? {
        let selected = selectedDevices
        return selected.first { !$0.transport.isWireless } ?? selected.first
    }

    // MARK: - Device list

    /// Refreshes the device list and volumes from the system.
    ///
    /// Devices that no longer exist drop out of the selection. If a member is
    /// lost while sharing, the session is rebuilt with whoever is left; falling
    /// below two members stops sharing altogether.
    public func refresh() {
        let systemDevices = deviceProvider.outputDevices()
        rememberNames(systemDevices)
        let activeAggregateID = state.session?.aggregateDeviceID

        devices = systemDevices.filter { device in
            device.isEligibleForSharing && device.id != activeAggregateID
        }

        let availableIDs = Set(devices.map(\.id))
        let vanished = selection.filter { !availableIDs.contains($0) }
        selection.removeAll { !availableIDs.contains($0) }

        volumes = devices.reduce(into: [:]) { result, device in
            guard device.supportsVolumeControl,
                  let volume = deviceProvider.volume(for: device.id) else { return }
            result[device.id] = volume
        }

        guard case .sharing(let session) = state else { return }

        let lostMembers = session.memberDeviceIDs.filter { !availableIDs.contains($0) }
        guard !lostMembers.isEmpty else { return }

        reportError(.memberDeviceDisappeared(name: vanishedName(for: lostMembers, fallbackCount: vanished.count)))
        rebuildOrStop(previousDefault: session.previousDefaultDeviceID, replacing: session)
    }

    /// Toggles a device's selection. Called while sharing, the session is rebuilt
    /// around the new member list, so the user never has to stop and start again.
    public func toggleSelection(_ id: DeviceID) {
        guard devices.contains(where: { $0.id == id }) else { return }

        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }

        clearResolvedNotice()

        guard case .sharing(let session) = state else { return }
        rebuildOrStop(previousDefault: session.previousDefaultDeviceID, replacing: session)
    }

    // MARK: - Sharing lifecycle

    /// Builds a shared output across the selected devices and routes system
    /// audio to it.
    ///
    /// Does nothing if sharing is already running. Should any step fail, the
    /// system is put back the way it was and the problem lands in `lastError`.
    public func startSharing() {
        guard !state.isSharing else { return }

        guard canStartSharing else {
            reportError(.needsAtLeastTwoDevices)
            return
        }

        let previousDefault = deviceProvider.defaultOutputDeviceID()

        do {
            let session = try establishSession(previousDefault: previousDefault)
            state = .sharing(session)
            lastError = nil
            refresh()
        } catch let error as ShareSoundError {
            reportError(error)
        } catch {
            reportError(.aggregateCreationFailed(status: 0))
        }
    }

    /// Ends sharing: restores the previous system output and removes the
    /// aggregate device this app created.
    ///
    /// The aggregate device is removed even if restoring the output fails —
    /// otherwise an orphaned device would be left behind in the system.
    public func stopSharing() {
        guard case .sharing(let session) = state else { return }

        state = .idle
        teardown(session, restoringDefaultTo: session.previousDefaultDeviceID)
        refresh()
    }

    /// Called as the app quits. Restores the system if sharing is still running.
    public func shutdown() {
        guard case .sharing(let session) = state else { return }
        state = .idle
        teardown(session, restoringDefaultTo: session.previousDefaultDeviceID)
    }

    // MARK: - Volume

    /// Sets a device's volume. The value is clamped to 0...1.
    ///
    /// While a shared output is in use the keyboard volume keys never reach the
    /// member devices, so each one is controlled individually from here.
    public func setVolume(_ volume: Float, for id: DeviceID) {
        guard let device = devices.first(where: { $0.id == id }) else { return }

        guard device.supportsVolumeControl else {
            reportError(.volumeControlUnsupported(name: device.name))
            return
        }

        let clamped = min(max(volume, 0), 1)

        do {
            try deviceProvider.setVolume(clamped, for: id)
            volumes[id] = clamped
        } catch {
            // If the write fails the slider snaps back to the device's real
            // level; the interface never shows a value that was not applied.
            reportError(.volumeControlUnsupported(name: device.name))
            volumes[id] = deviceProvider.volume(for: id)
        }
    }

    public func volume(for id: DeviceID) -> Float? {
        volumes[id]
    }

    public func dismissError() {
        lastError = nil
    }

    // MARK: - Private helpers

    /// Creates the aggregate device and points the system output at it.
    ///
    /// If switching the system output fails, the freshly created aggregate
    /// device is rolled back — no half-built state is left behind.
    private func establishSession(previousDefault: DeviceID?) throws -> ShareSession {
        let members = selectedDevices
        guard members.count >= 2, let master = masterDevice else {
            throw ShareSoundError.needsAtLeastTwoDevices
        }

        let aggregateID = try aggregateController.createAggregate(
            name: aggregateName,
            members: members,
            master: master
        )

        do {
            try deviceProvider.setDefaultOutputDevice(aggregateID)
        } catch {
            try? aggregateController.destroyAggregate(aggregateID)
            throw asShareSoundError(error, fallback: .defaultOutputChangeFailed(status: 0))
        }

        return ShareSession(
            aggregateDeviceID: aggregateID,
            memberDeviceIDs: members.map(\.id),
            previousDefaultDeviceID: previousDefault
        )
    }

    /// Rebuilds the session when the selection changes or a member disappears.
    ///
    /// The new aggregate is created and made the system output first; only then
    /// is the old device removed, which keeps the audio gap as short as possible.
    private func rebuildOrStop(previousDefault: DeviceID?, replacing session: ShareSession) {
        guard canStartSharing else {
            state = .idle
            teardown(session, restoringDefaultTo: previousDefault)
            return
        }

        do {
            let newSession = try establishSession(previousDefault: previousDefault)
            try? aggregateController.destroyAggregate(session.aggregateDeviceID)
            state = .sharing(newSession)
        } catch let error as ShareSoundError {
            state = .idle
            teardown(session, restoringDefaultTo: previousDefault)
            reportError(error)
        } catch {
            state = .idle
            teardown(session, restoringDefaultTo: previousDefault)
            reportError(.aggregateCreationFailed(status: 0))
        }
    }

    /// Restores the system output and removes the aggregate device.
    private func teardown(_ session: ShareSession, restoringDefaultTo deviceID: DeviceID?) {
        if let deviceID {
            do {
                try deviceProvider.setDefaultOutputDevice(deviceID)
            } catch {
                reportError(asShareSoundError(error, fallback: .defaultOutputChangeFailed(status: 0)))
            }
        }

        do {
            try aggregateController.destroyAggregate(session.aggregateDeviceID)
        } catch {
            reportError(asShareSoundError(error, fallback: .aggregateCleanupFailed(status: 0)))
        }
    }

    private func reportError(_ error: ShareSoundError) {
        lastError = error
    }

    /// Drops a notice once the user has resolved what caused it.
    ///
    /// "Select at least two devices" becomes misleading the moment a second
    /// device is ticked; rather than making the user dismiss it, it retires
    /// itself as soon as it stops being true.
    private func clearResolvedNotice() {
        if lastError == .needsAtLeastTwoDevices, canStartSharing {
            lastError = nil
        }
    }

    private func asShareSoundError(_ error: any Error, fallback: ShareSoundError) -> ShareSoundError {
        (error as? ShareSoundError) ?? fallback
    }

    /// Resolves a name so a lost member can be reported by name. The device is
    /// gone from the system, so the name can only come from what was last seen.
    private func vanishedName(for lostMembers: [DeviceID], fallbackCount: Int) -> String {
        if let id = lostMembers.first,
           let name = lastKnownNames[id] {
            return name
        }
        return fallbackCount > 1 ? "Devices" : "Device"
    }

    /// Last known names, kept so disconnected devices can still be named.
    private var lastKnownNames: [DeviceID: String] = [:]

    /// Feeds the name cache on every `refresh`.
    private func rememberNames(_ devices: [AudioDevice]) {
        for device in devices {
            lastKnownNames[device.id] = device.name
        }
    }
}
