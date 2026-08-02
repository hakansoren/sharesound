import Foundation

/// The complete description of a running share.
///
/// Everything needed to undo it lives here: which aggregate device was created,
/// who its members are, and what the system output was beforehand.
public struct ShareSession: Equatable, Sendable {
    /// ID of the aggregate device the app created.
    public let aggregateDeviceID: DeviceID

    /// Devices receiving audio, in selection order. The first element is the
    /// master: it drives the aggregate device's clock and the rest align to it.
    public let memberDeviceIDs: [DeviceID]

    /// The system output before sharing began; restored when sharing ends.
    /// `nil` when the default output could not be read at start.
    public let previousDefaultDeviceID: DeviceID?

    public init(
        aggregateDeviceID: DeviceID,
        memberDeviceIDs: [DeviceID],
        previousDefaultDeviceID: DeviceID?
    ) {
        self.aggregateDeviceID = aggregateDeviceID
        self.memberDeviceIDs = memberDeviceIDs
        self.previousDefaultDeviceID = previousDefaultDeviceID
    }

    /// The member driving the aggregate device's clock.
    public var masterDeviceID: DeviceID? {
        memberDeviceIDs.first
    }
}

/// The state the controller exposes.
public enum SessionState: Equatable, Sendable {
    /// Sharing is off; the system output is whatever the user chose.
    case idle

    /// Sharing is on; audio is reaching every member device.
    case sharing(ShareSession)

    public var isSharing: Bool {
        if case .sharing = self { return true }
        return false
    }

    public var session: ShareSession? {
        if case .sharing(let session) = self { return session }
        return nil
    }
}
