import CoreAudio
import Foundation

/// The real CoreAudio implementation that creates and removes multi-output devices.
///
/// The `kAudioAggregateDeviceIsStackedKey` flag makes the device "stacked":
/// incoming audio is copied to every sub-device. It is exactly the mechanism
/// behind "Multi-Output Device" in Audio MIDI Setup.
@MainActor
public final class CoreAudioAggregateController: AggregateDeviceControlling {

    /// Prefix used in the UID of devices this app creates. If the app exits
    /// unexpectedly, leftovers can be recognised by it.
    public nonisolated static let uidPrefix = "com.sharesound.aggregate"

    /// Injectable UID generator, for testability.
    private let uidGenerator: @Sendable () -> String

    public init(uidGenerator: @escaping @Sendable () -> String = { "\(uidPrefix).\(UUID().uuidString)" }) {
        self.uidGenerator = uidGenerator
    }

    public func createAggregate(name: String, members: [AudioDevice], master: AudioDevice) throws -> DeviceID {
        guard members.count >= 2 else {
            throw ShareSoundError.needsAtLeastTwoDevices
        }

        // Drift compensation is enabled on every member except the master:
        // devices running on independent clocks (Bluetooth especially) slide
        // apart over time, and this flag keeps them aligned to the master.
        let subDeviceList: [[String: Any]] = members.map { device in
            [
                kAudioSubDeviceUIDKey as String: device.uid,
                kAudioSubDeviceDriftCompensationKey as String: device.uid == master.uid ? 0 : 1,
            ]
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: name,
            kAudioAggregateDeviceUIDKey as String: uidGenerator(),
            kAudioAggregateDeviceSubDeviceListKey as String: subDeviceList,
            kAudioAggregateDeviceMasterSubDeviceKey as String: master.uid,
            kAudioAggregateDeviceIsStackedKey as String: 1,
            kAudioAggregateDeviceIsPrivateKey as String: 0,
        ]

        var aggregateDeviceID = AudioDeviceID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)

        guard status == noErr, aggregateDeviceID != kAudioObjectUnknown else {
            throw ShareSoundError.aggregateCreationFailed(status: status)
        }

        return DeviceID(aggregateDeviceID)
    }

    public func destroyAggregate(_ id: DeviceID) throws {
        let status = AudioHardwareDestroyAggregateDevice(AudioDeviceID(id))

        guard status == noErr else {
            throw ShareSoundError.aggregateCleanupFailed(status: status)
        }
    }

    /// Clears ShareSound devices possibly left over from an earlier run.
    ///
    /// If the app crashes or is force-quit, the aggregate device it created stays
    /// behind. Calling this at launch starts from a clean slate.
    public func removeOrphanedAggregates() {
        let allDeviceIDs = CoreAudioBridge.objectIDs(
            CoreAudioBridge.systemObject,
            CoreAudioBridge.address(kAudioHardwarePropertyDevices)
        )

        for deviceID in allDeviceIDs {
            guard let uid = CoreAudioBridge.string(
                deviceID,
                CoreAudioBridge.address(kAudioDevicePropertyDeviceUID)
            ), uid.hasPrefix(Self.uidPrefix) else { continue }

            AudioHardwareDestroyAggregateDevice(deviceID)
        }
    }
}
