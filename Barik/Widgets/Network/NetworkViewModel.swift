import CoreLocation
import CoreWLAN
import Network
import SwiftUI

enum NetworkState: String {
    case connected = "Connected"
    case connectedWithoutInternet = "No Internet"
    case disconnected = "Disconnected"
    case disabled = "Disabled"
    case notSupported = "Not Supported"
}

enum WifiSignalStrength: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case unknown = "Unknown"
}

/// Unified view model for monitoring network and Wi‑Fi status.
final class NetworkStatusViewModel: NSObject, ObservableObject,
    CLLocationManagerDelegate
{
    /// One view model, with its path monitors and Wi-Fi polling, for all network widgets on the bar.
    static let inUse = SharedWhileInUse<NetworkStatusViewModel>()

    /// Wi‑Fi state from CoreWLAN (power and association) and a Wi‑Fi path monitor (internet access).
    @Published var wifiState: NetworkState = .disconnected
    /// Ethernet state from an Ethernet path monitor.
    @Published var ethernetState: NetworkState = .disconnected

    // Wi‑Fi details obtained via CoreWLAN.
    /// The network name, or nil when Wi‑Fi is not connected or the name is unavailable. macOS gives the name only to
    /// apps with Location access, so a connected Wi‑Fi can have no name.
    @Published var ssid: String?
    @Published var rssi: Int = 0
    @Published var noise: Int = 0
    @Published var channel: String = "N/A"

    /// Whether Wi‑Fi is associated with a network, with or without internet access.
    var isWifiConnected: Bool {
        wifiState == .connected || wifiState == .connectedWithoutInternet
    }

    /// Computed property for signal strength.
    var wifiSignalStrength: WifiSignalStrength {
        if !isWifiConnected {
            return .unknown
        }
        if rssi >= -50 {
            return .high
        } else if rssi >= -70 {
            return .medium
        } else {
            return .low
        }
    }

    // Each monitor only considers its own interface type, so Wi‑Fi and Ethernet are both reported when the other one,
    // or a VPN, is the primary interface.
    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let ethernetMonitor = NWPathMonitor(requiredInterfaceType: .wiredEthernet)
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    /// Whether the Wi‑Fi path reaches the network, or nil before the Wi‑Fi monitor's first update.
    private var wifiPathIsSatisfied: Bool?

    private var timer: Timer?
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        startNetworkMonitoring()
        startWiFiMonitoring()
    }

    deinit {
        stopNetworkMonitoring()
        stopWiFiMonitoring()
    }

    // MARK: — NWPathMonitor for internet access per interface type.

    private func startNetworkMonitoring() {
        wifiMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.wifiPathIsSatisfied = path.status == .satisfied
                self.updateWiFiInfo()
            }
        }
        ethernetMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if path.availableInterfaces.contains(where: { $0.type == .wiredEthernet }) {
                    self.ethernetState = path.status == .satisfied ? .connected : .disconnected
                } else {
                    self.ethernetState = .notSupported
                }
            }
        }
        wifiMonitor.start(queue: monitorQueue)
        ethernetMonitor.start(queue: monitorQueue)
    }

    private func stopNetworkMonitoring() {
        wifiMonitor.cancel()
        ethernetMonitor.cancel()
    }

    // MARK: — Updating Wi‑Fi information via CoreWLAN.

    private func startWiFiMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) {
            [weak self] _ in
            self?.updateWiFiInfo()
        }
        updateWiFiInfo()
    }

    private func stopWiFiMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateWiFiInfo() {
        let client = CWWiFiClient.shared()
        if let interface = client.interface() {
            if !interface.powerOn() {
                self.wifiState = .disabled
            } else if interface.interfaceMode() == .none {
                // The interface mode, unlike the network name, does not need Location access.
                self.wifiState = .disconnected
            } else {
                // Until the Wi‑Fi monitor's first update, which follows within moments, an associated interface
                // counts as connected.
                self.wifiState = wifiPathIsSatisfied ?? true ? .connected : .connectedWithoutInternet
            }
            self.ssid = interface.ssid()
            self.rssi = interface.rssiValue()
            self.noise = interface.noiseMeasurement()
            if let wlanChannel = interface.wlanChannel() {
                let band: String
                switch wlanChannel.channelBand {
                case .bandUnknown:
                    band = "unknown"
                case .band2GHz:
                    band = "2GHz"
                case .band5GHz:
                    band = "5GHz"
                case .band6GHz:
                    band = "6GHz"
                @unknown default:
                    band = "unknown"
                }
                self.channel = "\(wlanChannel.channelNumber) (\(band))"
            } else {
                self.channel = "N/A"
            }
        } else {
            // No Wi‑Fi interface.
            self.wifiState = .notSupported
            self.ssid = nil
            self.rssi = 0
            self.noise = 0
            self.channel = "N/A"
        }
    }

    // MARK: — CLLocationManagerDelegate.

    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        updateWiFiInfo()
    }
}
