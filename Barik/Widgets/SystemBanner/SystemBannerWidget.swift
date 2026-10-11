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

struct SystemBannerWidget: View {
    let withLeftPadding: Bool
    
    @ObservedObject private var configManager = ConfigManager.shared
    
    init(withLeftPadding: Bool = false) {
        self.withLeftPadding = withLeftPadding
    }

    var body: some View {
        HStack(spacing: 15) {
            if withLeftPadding {
                Color.clear.frame(width: 0)
            }
            if hasConfigError {
                ConfigErrorBannerWidget()
            }
        }
        .animation(.default, value: hasConfigError)
    }

    /// The config file could not be read, or a change made in Barik could not be saved to it.
    private var hasConfigError: Bool {
        configManager.reloadError != nil || configManager.updateError != nil
    }
}

struct SystemBannerWidget_Previews: PreviewProvider {
    static var previews: some View {
        SystemBannerWidget()
            .frame(width: 200, height: 100)
            .background(Color.black)
    }
}
