import Foundation
@testable import ShareSoundKit

/// An in-memory audio system for tests.
///
/// Stands in for the real CoreAudio: the device list, default output and volumes
/// are plain data, every call is recorded, and any call can be made to fail —
/// which is what lets the failure paths be tested too.
@MainActor
final class FakeAudioSystem: AudioDeviceProviding, AggregateDeviceControlling {

    // MARK: - Configurable state

    var installedDevices: [AudioDevice] = []
    var defaultOutput: DeviceID?
    var deviceVolumes: [DeviceID: Float] = [:]

    /// Error to throw from the next `createAggregate` call.
    var createAggregateError: ShareSoundError?

    /// Error to throw from `setDefaultOutputDevice`.
    var setDefaultError: ShareSoundError?

    /// Error to throw from `destroyAggregate`.
    var destroyAggregateError: ShareSoundError?

    /// Error to throw from `setVolume`.
    var setVolumeError: ShareSoundError?

    var onSystemChange: (@MainActor () -> Void)?

    // MARK: - Recorded calls

    private(set) var createdAggregates: [(id: DeviceID, members: [DeviceID], master: DeviceID)] = []
    private(set) var destroyedAggregateIDs: [DeviceID] = []
    private(set) var defaultOutputHistory: [DeviceID] = []
    private(set) var volumeWrites: [(id: DeviceID, volume: Float)] = []

    /// The next ID handed to a created aggregate device.
    private var nextAggregateID: DeviceID = 9000

    // MARK: - AudioDeviceProviding

    func outputDevices() -> [AudioDevice] {
        installedDevices
    }

    func defaultOutputDeviceID() -> DeviceID? {
        defaultOutput
    }

    func setDefaultOutputDevice(_ id: DeviceID) throws {
        if let setDefaultError {
            throw setDefaultError
        }
        defaultOutput = id
        defaultOutputHistory.append(id)
    }

    func volume(for id: DeviceID) -> Float? {
        deviceVolumes[id]
    }

    func setVolume(_ volume: Float, for id: DeviceID) throws {
        if let setVolumeError {
            throw setVolumeError
        }
        deviceVolumes[id] = volume
        volumeWrites.append((id, volume))
    }

    // MARK: - AggregateDeviceControlling

    func createAggregate(name: String, members: [AudioDevice], master: AudioDevice) throws -> DeviceID {
        if let createAggregateError {
            throw createAggregateError
        }

        let id = nextAggregateID
        nextAggregateID += 1

        createdAggregates.append((id, members.map(\.id), master.id))

        // As in the real system, the created aggregate device also shows up in
        // the device list. The controller is expected to filter it out.
        installedDevices.append(
            AudioDevice(
                id: id,
                uid: "\(CoreAudioAggregateController.uidPrefix).\(id)",
                name: name,
                transport: .virtual,
                supportsVolumeControl: false,
                isAggregate: true
            )
        )

        return id
    }

    func destroyAggregate(_ id: DeviceID) throws {
        if let destroyAggregateError {
            throw destroyAggregateError
        }
        destroyedAggregateIDs.append(id)
        installedDevices.removeAll { $0.id == id }
    }

    // MARK: - Test helpers

    /// Simulates a device disconnecting and notifies the controller.
    func disconnect(_ id: DeviceID) {
        installedDevices.removeAll { $0.id == id }
        onSystemChange?()
    }

    /// Simulates a device being connected and notifies the controller.
    func connect(_ device: AudioDevice) {
        installedDevices.append(device)
        onSystemChange?()
    }

    /// Aggregate devices created by the app that are still in the system.
    var liveAggregateIDs: [DeviceID] {
        installedDevices.filter(\.isAggregate).map(\.id)
    }
}

// MARK: - Test data shortcuts

extension AudioDevice {
    /// Shortcut for building readable device fixtures in tests.
    static func stub(
        id: DeviceID,
        name: String? = nil,
        transport: TransportType = .bluetooth,
        supportsVolumeControl: Bool = true,
        isAggregate: Bool = false
    ) -> AudioDevice {
        AudioDevice(
            id: id,
            uid: "uid-\(id)",
            name: name ?? "Device \(id)",
            transport: transport,
            supportsVolumeControl: supportsVolumeControl,
            isAggregate: isAggregate
        )
    }
}
