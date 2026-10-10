import AudioToolbox
import CoreAudio
import Foundation

/// Follows the default output device's volume and mute state through CoreAudio property listeners.
final class VolumeManager: ObservableObject {
    static let shared = VolumeManager()

    /// Volume between 0 and 1, or nil when the current output device does not expose a volume (e.g. some HDMI displays).
    @Published private(set) var volume: Float?
    @Published private(set) var isMuted = false

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private let listenerQueue = DispatchQueue.main

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.attachToDefaultDevice()
    }
    private lazy var valueListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.readValues()
    }

    private init() {
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, listenerQueue, deviceListener)
        attachToDefaultDevice()
    }

    /// Sets the volume between 0 and 1, unmuting first so that dragging the slider is audible.
    func setVolume(_ newValue: Float) {
        guard deviceID != kAudioObjectUnknown else { return }
        if isMuted { setMuted(false) }
        var value = min(max(newValue, 0), 1)
        AudioObjectSetPropertyData(
            deviceID, &Self.volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    func setMuted(_ muted: Bool) {
        guard deviceID != kAudioObjectUnknown else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(
            deviceID, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func attachToDefaultDevice() {
        if deviceID != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.volumeAddress, listenerQueue, valueListener)
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.muteAddress, listenerQueue, valueListener)
        }
        var newDevice = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, 0, nil, &size, &newDevice)
        deviceID = newDevice
        if deviceID != kAudioObjectUnknown {
            AudioObjectAddPropertyListenerBlock(deviceID, &Self.volumeAddress, listenerQueue, valueListener)
            AudioObjectAddPropertyListenerBlock(deviceID, &Self.muteAddress, listenerQueue, valueListener)
        }
        readValues()
    }

    private func readValues() {
        var newVolume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let hasVolume = deviceID != kAudioObjectUnknown
            && AudioObjectHasProperty(deviceID, &Self.volumeAddress)
            && AudioObjectGetPropertyData(deviceID, &Self.volumeAddress, 0, nil, &size, &newVolume) == noErr
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        let hasMute = deviceID != kAudioObjectUnknown
            && AudioObjectHasProperty(deviceID, &Self.muteAddress)
            && AudioObjectGetPropertyData(deviceID, &Self.muteAddress, 0, nil, &size, &muted) == noErr

        let volumeValue: Float? = hasVolume ? newVolume : nil
        if volume != volumeValue { volume = volumeValue }
        let mutedValue = hasMute && muted != 0
        if isMuted != mutedValue { isMuted = mutedValue }
    }
}
