import SwiftUI

struct ChangelogBannerWidget: View {
    @State private var rect: CGRect = .zero

    var body: some View {

        Button(action: {
            MenuBarPopup.show(rect: rect, id: "changelog") {
                ChangelogPopup()
            }
        }) {
            HStack(alignment: .center) {
                Text("What's new")
                    .fontWeight(.semibold)
                Image(systemName: "xmark.circle.fill")
                    .onTapGesture {
                        NotificationCenter.default.post(name: Notification.Name("HideWhatsNewBanner"), object: nil)
                    }
            }
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
        .buttonStyle(BannerButtonStyle(color: .green.opacity(0.8)))
        // The close icon inside the button is a tap gesture that VoiceOver cannot reach, so offer it as an action.
        .accessibilityAction(named: "Hide") {
            NotificationCenter.default.post(name: Notification.Name("HideWhatsNewBanner"), object: nil)
        }
        .transition(.blurReplace)

    }
}

struct ChangelogBannerWidget_Previews: PreviewProvider {
    static var previews: some View {
        ChangelogBannerWidget()
            .frame(width: 200, height: 100)
            .background(Color.black)
    }
}
