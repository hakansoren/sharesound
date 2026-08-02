import Foundation

/// The layer that reads audio devices and steers the system output.
///
/// `ShareSessionController` knows only this interface; the real implementation
/// talks to CoreAudio, while tests substitute an in-memory fake.
@MainActor
public protocol AudioDeviceProviding: AnyObject {
    /// Devices currently present that have at least one output channel.
    func outputDevices() -> [AudioDevice]

    /// The system's default audio output, or `nil` if it cannot be read.
    func defaultOutputDeviceID() -> DeviceID?

    /// Changes the system's default audio output.
    func setDefaultOutputDevice(_ id: DeviceID) throws

    /// The device's volume in 0...1, or `nil` if it is not supported.
    func volume(for id: DeviceID) -> Float?

    /// Sets the device's volume.
    func setVolume(_ volume: Float, for id: DeviceID) throws

    /// Invoked when the device list or the default output changes.
    /// The controller uses it to refresh its own state.
    var onSystemChange: (@MainActor () -> Void)? { get set }
}

/// The layer that manages the lifecycle of aggregate (multi-output) devices.
@MainActor
public protocol AggregateDeviceControlling: AnyObject {
    /// Creates a multi-output device that copies the same audio to every member.
    ///
    /// - Parameters:
    ///   - name: The name shown in Audio MIDI Setup.
    ///   - members: Devices that should receive the audio. At least two expected.
    ///   - master: The clock-driving member. Drift compensation applies to the rest.
    /// - Returns: The ID of the created aggregate device.
    func createAggregate(name: String, members: [AudioDevice], master: AudioDevice) throws -> DeviceID

    /// Removes the aggregate device from the system.
    func destroyAggregate(_ id: DeviceID) throws
}
