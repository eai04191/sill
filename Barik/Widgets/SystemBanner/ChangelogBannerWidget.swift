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
                        WhatsNewBanner.shared.dismiss()
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
        // A dark, opaque green: white text on it has a contrast ratio of about 5.4:1, where the translucent system
        // green had about 2:1.
        .buttonStyle(BannerButtonStyle(color: Color(red: 0, green: 0.48, blue: 0.22)))
        // The close icon inside the button is a tap gesture that VoiceOver cannot reach, so offer it as an action.
        .accessibilityAction(named: "Hide") {
            WhatsNewBanner.shared.dismiss()
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
