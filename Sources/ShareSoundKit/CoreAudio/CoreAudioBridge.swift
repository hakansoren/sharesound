import CoreAudio
import Foundation

/// A thin layer between CoreAudio's C interface and Swift.
///
/// CoreAudio reads every property through `AudioObjectGetPropertyData` with
/// manually computed sizes. These helpers gather that repetition in one place
/// and hand clean Swift types to the layers above.
enum CoreAudioBridge {

    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    // MARK: - Fixed-size values

    /// Reads a fixed-size property (UInt32, Float32, AudioDeviceID and friends).
    ///
    /// The `BitwiseCopyable` constraint guarantees types that are safe to read
    /// through raw memory — nothing carrying an object reference gets in here.
    static func value<T: BitwiseCopyable>(
        _ objectID: AudioObjectID,
        _ propertyAddress: AudioObjectPropertyAddress,
        as type: T.Type
    ) -> T? {
        var propertyAddress = propertyAddress
        var size = UInt32(MemoryLayout<T>.size)
        let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { storage.deallocate() }

        let status = AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &size, storage)
        guard status == noErr else { return nil }
        return storage.pointee
    }

    /// Writes a fixed-size property.
    @discardableResult
    static func setValue<T: BitwiseCopyable>(
        _ objectID: AudioObjectID,
        _ propertyAddress: AudioObjectPropertyAddress,
        to newValue: T
    ) -> OSStatus {
        var propertyAddress = propertyAddress
        let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { storage.deallocate() }
        storage.initialize(to: newValue)
        defer { storage.deinitialize(count: 1) }

        return AudioObjectSetPropertyData(
            objectID,
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<T>.size),
            storage
        )
    }

    // MARK: - Variable-size values

    /// Reads properties that return a variable number of `AudioObjectID`s.
    static func objectIDs(
        _ objectID: AudioObjectID,
        _ propertyAddress: AudioObjectPropertyAddress
    ) -> [AudioObjectID] {
        var propertyAddress = propertyAddress
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(objectID, &propertyAddress, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)

        let status = ids.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &size, buffer.baseAddress!)
        }

        return status == noErr ? ids : []
    }

    /// Reads `CFString`-returning properties as a Swift `String`.
    static func string(
        _ objectID: AudioObjectID,
        _ propertyAddress: AudioObjectPropertyAddress
    ) -> String? {
        var propertyAddress = propertyAddress
        var size = UInt32(MemoryLayout<CFString?>.size)
        var result: CFString?

        let status = withUnsafeMutablePointer(to: &result) { pointer in
            AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &size, pointer)
        }

        guard status == noErr, let result else { return nil }
        return result as String
    }

    // MARK: - Device queries

    /// Total channel count for the device in the given scope.
    ///
    /// Used to filter out input-only devices such as microphones: zero output
    /// channels means the device is not an audio output.
    static func channelCount(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var propertyAddress = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &size) == noErr,
              size > 0 else { return 0 }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, rawBuffer) == noErr else {
            return 0
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(
            rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Channel numbers that form the device's stereo pair.
    ///
    /// Devices without a main volume property are read and written channel by
    /// channel; this decides which channels to use.
    static func preferredStereoChannels(_ deviceID: AudioObjectID) -> [AudioObjectPropertyElement] {
        var propertyAddress = address(
            kAudioDevicePropertyPreferredChannelsForStereo,
            scope: kAudioObjectPropertyScopeOutput
        )
        var channels: (UInt32, UInt32) = (1, 2)
        var size = UInt32(MemoryLayout<(UInt32, UInt32)>.size)

        let status = withUnsafeMutablePointer(to: &channels) { pointer in
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, pointer)
        }

        guard status == noErr else { return [1, 2] }
        return [channels.0, channels.1]
    }
}
