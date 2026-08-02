import Foundation

/// Problems that can occur while establishing or maintaining a share.
///
/// Every case is worded to tell the user what happened and what they can do;
/// raw `OSStatus` codes ride along purely as technical detail.
public enum ShareSoundError: Error, Equatable, Sendable {
    /// Sharing requires at least two output devices.
    case needsAtLeastTwoDevices

    /// The aggregate (multi-output) device could not be created.
    case aggregateCreationFailed(status: Int32)

    /// The aggregate device was created but the system output would not switch.
    case defaultOutputChangeFailed(status: Int32)

    /// A member device disconnected while sharing was running.
    case memberDeviceDisappeared(name: String)

    /// The device does not support software volume control.
    case volumeControlUnsupported(name: String)

    /// The aggregate device could not be cleaned up; the user may need to step in.
    case aggregateCleanupFailed(status: Int32)
}

extension ShareSoundError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .needsAtLeastTwoDevices:
            "Select at least two devices to share."
        case .aggregateCreationFailed:
            "Could not create the shared output device."
        case .defaultOutputChangeFailed:
            "Could not change the system audio output."
        case .memberDeviceDisappeared(let name):
            "\(name) disconnected."
        case .volumeControlUnsupported(let name):
            "\(name) volume cannot be set from software."
        case .aggregateCleanupFailed:
            "Could not remove the shared output device."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .needsAtLeastTwoDevices:
            "Pick two headphones from the list."
        case .aggregateCreationFailed:
            "Make sure the devices are connected and try again."
        case .defaultOutputChangeFailed:
            "Check your sound settings and try again."
        case .memberDeviceDisappeared:
            "Reconnect the device and start sharing again."
        case .volumeControlUnsupported(let name):
            "Adjust \(name) volume on the device itself."
        case .aggregateCleanupFailed:
            "You can delete the leftover device in Audio MIDI Setup."
        }
    }

    /// How much attention the problem deserves in the interface.
    public var severity: Severity {
        switch self {
        case .needsAtLeastTwoDevices, .volumeControlUnsupported:
            .informational
        case .aggregateCreationFailed, .defaultOutputChangeFailed,
             .memberDeviceDisappeared, .aggregateCleanupFailed:
            .critical
        }
    }

    public enum Severity: Sendable {
        case informational
        case critical
    }
}
