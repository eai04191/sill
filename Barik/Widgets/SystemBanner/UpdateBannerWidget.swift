import SwiftUI

struct UpdateBannerWidget: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var updater = AppUpdater.shared
    @State private var isUpdating = false
    /// Why the last update failed; the banner then offers to try again.
    @State private var failure: String?

    var body: some View {
        if updater.updateAvailable {
            Button(action: handleUpdate) {
                Text(isUpdating ? "Updating" : failure == nil ? "Update" : "Update failed")
                    .fontWeight(.semibold)
            }
            // White text on this red has a contrast ratio of about 6:1.
            .buttonStyle(BannerButtonStyle(color: failure == nil ? .blue : Color(red: 0.75, green: 0.1, blue: 0.1)))
            .disabled(isUpdating)
            .opacity(isUpdating ? 0.5 : 1)
            .animation(.easeInOut, value: isUpdating)
            // Clicking the banner again retries; the reason is shown on hover and read by VoiceOver.
            .help(failure ?? "")
            .accessibilityValue(failure ?? "")
        }
    }

    /// Downloads and installs the update, then terminates the application so the update can replace it. When the
    /// update fails, Barik keeps running and the banner shows the failure.
    private func handleUpdate() {
        isUpdating = true
        failure = nil
        updater.downloadAndInstall(latest: updater.latestVersion ?? "") { result in
            switch result {
            case .success:
                NSApplication.shared.terminate(nil)
            case .failure(let error):
                isUpdating = false
                failure = error.localizedDescription
            }
        }
    }
}

struct UpdateBannerWidget_Previews: PreviewProvider {
    static var previews: some View {
        UpdateBannerWidget()
            .frame(width: 200, height: 100)
            .background(Color.black)
    }
}
