import SwiftUI

/// Shown while the config file cannot be read after launch. Barik keeps the config it read before, so without this
/// banner an edit with a mistake would seem to be ignored.
struct ConfigErrorBannerWidget: View {
    @State private var rect: CGRect = .zero

    var body: some View {
        Button(action: {
            MenuBarPopup.show(rect: rect, id: "config-error") {
                ConfigErrorPopup()
            }
        }) {
            Text("Config error")
                .fontWeight(.semibold)
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rect = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) {
                        _, newValue in
                        rect = newValue
                    }
            }
        )
        // White text on this red has a contrast ratio of about 6:1.
        .buttonStyle(BannerButtonStyle(color: Color(red: 0.75, green: 0.1, blue: 0.1)))
        .transition(.blurReplace)
    }
}

private struct ConfigErrorPopup: View {
    @ObservedObject private var configManager = ConfigManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Config error")
                .font(.system(size: 14))
                .fontWeight(.medium)
            Text("The config file could not be read, so the config read before is still in use. Fix the file and save it to apply it.")
                .fixedSize(horizontal: false, vertical: true)
            if let error = configManager.reloadError {
                Text(error)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The config file has been read.")
            }
        }
        .padding(15)
        .frame(width: 420, alignment: .leading)
    }
}
