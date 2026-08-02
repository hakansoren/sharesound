import CoreAudio
import Foundation

/// The real CoreAudio implementation of `AudioDeviceProviding`.
///
/// Reads the device list and default output from the system and listens for
/// changes. Requires no TCC permission: audio is routed, never captured.
@MainActor
public final class CoreAudioDeviceProvider: AudioDeviceProviding {

    public var onSystemChange: (@MainActor () -> Void)?

    /// Records kept so the listeners can be torn down again.
    private var listeners: [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []

    public init() {
        installListeners()
    }

    deinit {
        // `listeners` is only mutated from the main actor; the teardown lives in
        // its own helper so reading it here is safe.
        MainActor.assumeIsolated {
            removeListeners()
        }
    }

    // MARK: - Device list

    public func outputDevices() -> [AudioDevice] {
        let allDeviceIDs = CoreAudioBridge.objectIDs(
            CoreAudioBridge.systemObject,
            CoreAudioBridge.address(kAudioHardwarePropertyDevices)
        )

        return allDeviceIDs.compactMap(makeDevice)
    }

    /// Turns a device ID into a model. Devices with no output channels
    /// (microphones, virtual inputs) return `nil` and never reach the list.
    private func makeDevice(_ deviceID: AudioObjectID) -> AudioDevice? {
        guard CoreAudioBridge.channelCount(deviceID, scope: kAudioObjectPropertyScopeOutput) > 0 else {
            return nil
        }

        guard let uid = CoreAudioBridge.string(
            deviceID,
            CoreAudioBridge.address(kAudioDevicePropertyDeviceUID)
        ) else { return nil }

        let name = CoreAudioBridge.string(
            deviceID,
            CoreAudioBridge.address(kAudioObjectPropertyName)
        ) ?? "Unnamed Device"

        let rawTransport = CoreAudioBridge.value(
            deviceID,
            CoreAudioBridge.address(kAudioDevicePropertyTransportType),
            as: UInt32.self
        ) ?? kAudioDeviceTransportTypeUnknown

        return AudioDevice(
            id: DeviceID(deviceID),
            uid: uid,
            name: name,
            transport: TransportType(coreAudioTransportType: rawTransport),
            supportsVolumeControl: hasVolumeControl(deviceID),
            isAggregate: rawTransport == kAudioDeviceTransportTypeAggregate
        )
    }

    // MARK: - Default output

    public func defaultOutputDeviceID() -> DeviceID? {
        let deviceID = CoreAudioBridge.value(
            CoreAudioBridge.systemObject,
            CoreAudioBridge.address(kAudioHardwarePropertyDefaultOutputDevice),
            as: AudioDeviceID.self
        )

        guard let deviceID, deviceID != kAudioObjectUnknown else { return nil }
        return DeviceID(deviceID)
    }

    public func setDefaultOutputDevice(_ id: DeviceID) throws {
        let status = CoreAudioBridge.setValue(
            CoreAudioBridge.systemObject,
            CoreAudioBridge.address(kAudioHardwarePropertyDefaultOutputDevice),
            to: AudioDeviceID(id)
        )

        guard status == noErr else {
            throw ShareSoundError.defaultOutputChangeFailed(status: status)
        }
    }

    // MARK: - Volume

    /// If the device supports the main volume property, or at least one stereo
    /// channel's volume, then software volume control is possible.
    private func hasVolumeControl(_ deviceID: AudioObjectID) -> Bool {
        var mainAddress = CoreAudioBridge.address(
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput
        )
        if AudioObjectHasProperty(deviceID, &mainAddress) { return true }

        return CoreAudioBridge.preferredStereoChannels(deviceID).contains { channel in
            var channelAddress = CoreAudioBridge.address(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: channel
            )
            return AudioObjectHasProperty(deviceID, &channelAddress)
        }
    }

    public func volume(for id: DeviceID) -> Float? {
        let deviceID = AudioDeviceID(id)

        if let mainVolume = CoreAudioBridge.value(
            deviceID,
            CoreAudioBridge.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput),
            as: Float32.self
        ) {
            return mainVolume
        }

        // With no main volume, the stereo channels are averaged instead.
        let channelVolumes = CoreAudioBridge.preferredStereoChannels(deviceID).compactMap { channel in
            CoreAudioBridge.value(
                deviceID,
                CoreAudioBridge.address(
                    kAudioDevicePropertyVolumeScalar,
                    scope: kAudioObjectPropertyScopeOutput,
                    element: channel
                ),
                as: Float32.self
            )
        }

        guard !channelVolumes.isEmpty else { return nil }
        return channelVolumes.reduce(0, +) / Float(channelVolumes.count)
    }

    public func setVolume(_ volume: Float, for id: DeviceID) throws {
        let deviceID = AudioDeviceID(id)
        let clamped = Float32(min(max(volume, 0), 1))

        var mainAddress = CoreAudioBridge.address(
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput
        )
        if isSettable(deviceID, &mainAddress) {
            let status = CoreAudioBridge.setValue(deviceID, mainAddress, to: clamped)
            guard status == noErr else {
                throw ShareSoundError.volumeControlUnsupported(name: nameOrFallback(deviceID))
            }
            return
        }

        // When the main volume is not writable, each stereo channel is set.
        var didSetAnyChannel = false
        for channel in CoreAudioBridge.preferredStereoChannels(deviceID) {
            var channelAddress = CoreAudioBridge.address(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: channel
            )
            guard isSettable(deviceID, &channelAddress) else { continue }
            if CoreAudioBridge.setValue(deviceID, channelAddress, to: clamped) == noErr {
                didSetAnyChannel = true
            }
        }

        guard didSetAnyChannel else {
            throw ShareSoundError.volumeControlUnsupported(name: nameOrFallback(deviceID))
        }
    }

    private func isSettable(_ deviceID: AudioObjectID, _ propertyAddress: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &propertyAddress, &settable) == noErr else { return false }
        return settable.boolValue
    }

    private func nameOrFallback(_ deviceID: AudioObjectID) -> String {
        CoreAudioBridge.string(deviceID, CoreAudioBridge.address(kAudioObjectPropertyName)) ?? "Device"
    }

    // MARK: - Listening for system changes

    /// Notified when devices come and go and when the default output changes.
    ///
    /// Bluetooth headphones drop in and out of the list as they sleep and wake;
    /// these listeners keep the interface current without the user lifting a finger.
    private func installListeners() {
        let watchedAddresses = [
            CoreAudioBridge.address(kAudioHardwarePropertyDevices),
            CoreAudioBridge.address(kAudioHardwarePropertyDefaultOutputDevice),
        ]

        for propertyAddress in watchedAddresses {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in
                    self?.onSystemChange?()
                }
            }

            var mutableAddress = propertyAddress
            let status = AudioObjectAddPropertyListenerBlock(
                CoreAudioBridge.systemObject,
                &mutableAddress,
                DispatchQueue.main,
                block
            )

            if status == noErr {
                listeners.append((propertyAddress, block))
            }
        }
    }

    private func removeListeners() {
        for listener in listeners {
            var mutableAddress = listener.address
            AudioObjectRemovePropertyListenerBlock(
                CoreAudioBridge.systemObject,
                &mutableAddress,
                DispatchQueue.main,
                listener.block
            )
        }
        listeners.removeAll()
    }
}

extension TransportType {
    /// Maps CoreAudio's four-character transport type code onto the model.
    init(coreAudioTransportType rawValue: UInt32) {
        switch rawValue {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        case kAudioDeviceTransportTypeHDMI: self = .hdmi
        case kAudioDeviceTransportTypeDisplayPort: self = .displayPort
        case kAudioDeviceTransportTypeThunderbolt: self = .thunderbolt
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: self = .virtual
        default: self = .unknown
        }
    }
}
