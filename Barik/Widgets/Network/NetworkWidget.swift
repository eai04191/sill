import SwiftUI

/// Widget for the menu, displaying Wi‑Fi and Ethernet icons.
struct NetworkWidget: View {
    @StateObject private var viewModel = NetworkStatusViewModel.inUse.instance { NetworkStatusViewModel() }
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 15) {
            if viewModel.wifiState != .notSupported {
                wifiIcon
            }
            if viewModel.ethernetState != .notSupported {
                ethernetIcon
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rect = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, newValue in
                        rect = newValue
                    }
            }
        )
        .contentShape(Rectangle())
        .font(.system(size: 15))
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .barButton(label: "Network", value: accessibilityValue) {
            MenuBarPopup.show(rect: rect, id: "network") { NetworkPopup() }
        }
    }

    /// The Wi-Fi network and Ethernet state shown by the icons.
    private var accessibilityValue: String {
        var parts: [String] = []
        if viewModel.wifiState != .notSupported {
            let name = viewModel.ssid.map { " \($0)" } ?? ""
            parts.append("Wi-Fi\(name), \(viewModel.wifiState.rawValue)")
        }
        if viewModel.ethernetState != .notSupported { parts.append("Ethernet \(viewModel.ethernetState.rawValue)") }
        return parts.joined(separator: ", ")
    }

    // A connected icon takes the bar's foreground style, which differs between the plain bar and Liquid Glass.
    @ViewBuilder
    private var wifiIcon: some View {
        switch viewModel.wifiState {
        case .connected:
            Image(systemName: "wifi")
        case .connectedWithoutInternet:
            Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.yellow)
        case .disconnected:
            Image(systemName: "wifi.slash")
                .foregroundColor(.gray)
        case .disabled:
            Image(systemName: "wifi.slash")
                .foregroundColor(.red)
        case .notSupported:
            Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.gray)
        }
    }

    @ViewBuilder
    private var ethernetIcon: some View {
        switch viewModel.ethernetState {
        case .connected:
            Image(systemName: "network")
        case .connectedWithoutInternet:
            Image(systemName: "network")
                .foregroundColor(.yellow)
        case .disconnected:
            Image(systemName: "network.slash")
                .foregroundColor(.gray)
        case .disabled, .notSupported:
            Image(systemName: "questionmark.circle")
                .foregroundColor(.gray)
        }
    }
}

struct NetworkWidget_Previews: PreviewProvider {
    static var previews: some View {
        NetworkWidget()
            .frame(width: 200, height: 100)
            .background(Color.black)
    }
}
