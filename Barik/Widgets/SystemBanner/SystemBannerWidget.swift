import AppKit
import SwiftUI

struct BannerButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                configuration.isPressed ? color.opacity(0.7) : color
            )
            .clipShape(.capsule)
    }
}

/// Whether the "What's new" banner is shown: from the first launch of a new version until the banner is dismissed. It
/// is read from the version file and shared by every banner, so a banner created after launch shows it too, and the
/// version counts as seen only once the banner is dismissed.
final class WhatsNewBanner: ObservableObject {
    static let shared = WhatsNewBanner()

    @Published private(set) var isShown = !VersionChecker.isLatestVersion()

    private init() {}

    func dismiss() {
        VersionChecker.updateVersionFile()
        withAnimation {
            isShown = false
        }
    }
}

struct SystemBannerWidget: View {
    let withLeftPadding: Bool
    
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var whatsNew = WhatsNewBanner.shared
    
    init(withLeftPadding: Bool = false) {
        self.withLeftPadding = withLeftPadding
    }

    var body: some View {
        HStack(spacing: 15) {
            if withLeftPadding {
                Color.clear.frame(width: 0)
            }
            if configManager.reloadError != nil {
                ConfigErrorBannerWidget()
            }
            if whatsNew.isShown {
                ChangelogBannerWidget()
            }
        }
        .animation(.default, value: configManager.reloadError != nil)
    }
}

struct SystemBannerWidget_Previews: PreviewProvider {
    static var previews: some View {
        SystemBannerWidget()
            .frame(width: 200, height: 100)
            .background(Color.black)
    }
}
