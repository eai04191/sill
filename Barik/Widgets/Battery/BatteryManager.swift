import Combine
import Foundation
import IOKit.ps

/// This class monitors the battery status.
class BatteryManager: ObservableObject {
    /// One manager, polling every second, for all battery widgets on the bar.
    static let inUse = SharedWhileInUse<BatteryManager>()

    /// Whether the Mac has an internal battery. Desktop Macs have none, and the widget shows nothing then.
    @Published var hasBattery: Bool = false
    @Published var batteryLevel: Int = 0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    private var timer: Timer?

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        // Update every 1 second.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            self?.updateBatteryStatus()
        }
        updateBatteryStatus()
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// This method updates the battery level and charging state from the internal battery. Other power sources, such
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
            DispatchQueue.main.async {
                self.hasBattery = false
            }
            return
        }
        let isAC = (powerSourceState == kIOPSACPowerValue)

        DispatchQueue.main.async {
            self.hasBattery = true
            self.batteryLevel = (currentCapacity * 100) / maxCapacity
            self.isCharging = charging
            self.isPluggedIn = isAC
        }
    }
}
