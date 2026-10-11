import Combine
import Foundation
import IOKit.ps

/// This class monitors the battery status.
class BatteryManager: ObservableObject {
    /// One manager, with its power source notifications, for all battery widgets on the bar.
    static let inUse = SharedWhileInUse<BatteryManager>()

    /// Whether the Mac has an internal battery. Desktop Macs have none, and the widget shows nothing then.
    @Published var hasBattery: Bool = false
    @Published var batteryLevel: Int = 0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    private var runLoopSource: CFRunLoopSource?

    /// The level and power state read by VoiceOver.
    var accessibilityValue: String {
        if isCharging {
            return String(localized: "\(batteryLevel)%, charging", comment: "VoiceOver value of the battery.")
        } else if isPluggedIn {
            return String(
                localized: "\(batteryLevel)%, plugged in, not charging", comment: "VoiceOver value of the battery.")
        } else {
            return "\(batteryLevel)%"
        }
    }

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    /// IOKit calls back on the main run loop whenever power source information changes, such as the level or the
    /// adapter. The callback gets the manager unretained; the source is removed in deinit.
    private func startMonitoring() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard
            let source = IOPSNotificationCreateRunLoopSource(
                { context in
                    guard let context else { return }
                    Unmanaged<BatteryManager>.fromOpaque(context).takeUnretainedValue().updateBatteryStatus()
                }, context)?.takeRetainedValue()
        else {
            print("Battery: cannot observe power source changes")
            updateBatteryStatus()
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        updateBatteryStatus()
    }

    private func stopMonitoring() {
        guard let runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CFRunLoopSourceInvalidate(runLoopSource)
    }

    /// This method updates the battery level and charging state from the internal battery, on the main thread, and
    /// publishes only the values that changed. Other power sources, such
    /// as a UPS, are ignored, so they neither replace the battery's values nor show a battery on a desktop Mac.
    func updateBatteryStatus() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?
                .takeRetainedValue() as? [CFTypeRef]
        else {
            return
        }

        let battery = sources.lazy
            .compactMap {
                IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any]
            }
            .first { $0[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType }

        guard let battery,
            let currentCapacity = battery[kIOPSCurrentCapacityKey as String] as? Int,
            let maxCapacity = battery[kIOPSMaxCapacityKey as String] as? Int,
            maxCapacity > 0,
            let charging = battery[kIOPSIsChargingKey as String] as? Bool,
            let powerSourceState = battery[kIOPSPowerSourceStateKey as String] as? String
        else {
            if hasBattery { hasBattery = false }
            return
        }
        let level = (currentCapacity * 100) / maxCapacity
        let isAC = (powerSourceState == kIOPSACPowerValue)

        if !hasBattery { hasBattery = true }
        if batteryLevel != level { batteryLevel = level }
        if isCharging != charging { isCharging = charging }
        if isPluggedIn != isAC { isPluggedIn = isAC }
    }
}
