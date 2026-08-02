import Foundation

/// Identifier of an audio object in the system. Same representation as
/// CoreAudio's `AudioDeviceID`, renamed here so the core model carries no
/// CoreAudio dependency — which is what lets tests run without real hardware.
public typealias DeviceID = UInt32

/// A snapshot of an audio output device, limited to what the app needs.
public struct AudioDevice: Identifiable, Hashable, Sendable {
    /// The device's numeric ID, valid for this session. It can change when a
    /// device is unplugged and reconnected; `uid` is the stable identity.
    public let id: DeviceID

    /// Identity that survives restarts. Sub-devices are referenced by this
    /// value when the aggregate device is assembled.
    public let uid: String

    /// The name shown to the user, e.g. "Hakan's AirPods".
    public let name: String

    public let transport: TransportType

    /// Whether the device supports software volume control. Some HDMI and
    /// digital outputs do not; the interface hides the slider for those.
    public let supportsVolumeControl: Bool

    /// Whether the device is itself an aggregate/multi-output device. Those
    /// cannot join a share, so no device can end up containing itself.
    public let isAggregate: Bool

    public init(
        id: DeviceID,
        uid: String,
        name: String,
        transport: TransportType,
        supportsVolumeControl: Bool,
        isAggregate: Bool
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transport = transport
        self.supportsVolumeControl = supportsVolumeControl
        self.isAggregate = isAggregate
    }

    /// Whether this device may join a share.
    public var isEligibleForSharing: Bool {
        !isAggregate
    }
}

/// How the device is attached to the machine. Drives the icon and label in the
/// interface, and the latency hint shown to the user.
public enum TransportType: String, Hashable, Sendable, CaseIterable {
    case builtIn
    case bluetooth
    case usb
    case airPlay
    case hdmi
    case displayPort
    case thunderbolt
    case virtual
    case unknown

    /// SF Symbol name used in the interface.
    public var symbolName: String {
        switch self {
        case .builtIn: "laptopcomputer"
        case .bluetooth: "wave.3.right"
        case .usb: "cable.connector"
        case .airPlay: "airplayaudio"
        case .hdmi, .displayPort: "display"
        case .thunderbolt: "bolt"
        case .virtual: "square.stack.3d.up"
        case .unknown: "hifispeaker"
        }
    }

    /// Short caption shown beneath a device row.
    public var localizedLabel: String {
        switch self {
        case .builtIn: "Built-in"
        case .bluetooth: "Bluetooth"
        case .usb: "USB"
        case .airPlay: "AirPlay"
        case .hdmi: "HDMI"
        case .displayPort: "DisplayPort"
        case .thunderbolt: "Thunderbolt"
        case .virtual: "Virtual"
        case .unknown: "Unknown"
        }
    }

    /// Wireless connections add noticeable latency compared with wired ones,
    /// which is why the interface warns when two of them are selected.
    public var isWireless: Bool {
        self == .bluetooth || self == .airPlay
    }
}
