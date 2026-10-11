import SwiftUI

/// Shown while the config file cannot be read after launch. Barik keeps the config it read before, so without this
/// banner an edit with a mistake would seem to be ignored. Also shown when a change made in Barik, such as the calendar
/// layout, could not be saved to the file, which would otherwise be lost at the next launch without notice.
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
        .blurReplaceTransition()
    }
}

private struct ConfigErrorPopup: View {
    @ObservedObject private var configManager = ConfigManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Config error")
                .font(.popupHeading)
            // Without either error, as once the file is fixed while the popup is open, it says the file has been read.
            if configManager.reloadError != nil || configManager.updateError == nil {
                Text("The config file could not be read, so the config read before is still in use. Fix the file and save it to apply it.")
                    .fixedSize(horizontal: false, vertical: true)
                if let error = configManager.reloadError {
                    errorText(error)
                } else {
                    Text("The config file has been read.")
                }
            }
            if let error = configManager.updateError {
                Text("A change made in Barik could not be saved to the config file, which was left as it was.")
                    .fixedSize(horizontal: false, vertical: true)
                errorText(error)
            }
        }
        .padding(Constants.popupPadding)
        .frame(width: 420, alignment: .leading)
    }

    private func errorText(_ error: String) -> some View {
        Text(error)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
