import SwiftUI

struct BatteryPopup: View {
    /// The widget's manager, so the ring opens at the current level instead of animating up from 0%.
    @ObservedObject var batteryManager: BatteryManager
    /// The battery widget's config, for the same warning and critical levels as the widget.
    @ObservedObject var configProvider: ConfigProvider
    var warningLevel: Int { configProvider.config["warning-level"]?.intValue ?? 20 }
    var criticalLevel: Int { configProvider.config["critical-level"]?.intValue ?? 10 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(batteryManager.batteryLevel) / 100)
                .stroke(
                    batteryColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(Angle(degrees: -90))
                .animation(
                    .easeOut(duration: 0.5), value: batteryManager.batteryLevel)
            Image(systemName: "laptopcomputer")
                .resizable()
                .scaledToFit()
                .padding(14)
                .foregroundStyle(Color.primary)
            if batteryManager.isPluggedIn {
                Image(
                    systemName: batteryManager.isCharging
                        ? "bolt.fill" : "powerplug.portrait.fill"
                )
                .foregroundColor(.white)
                .offset(y: -30)
                .shadow(color: Color.black, radius: 2, x: 0, y: 0)
                .shadow(color: Color.black, radius: 2, x: 0, y: 0)
                .blurReplaceTransition()
            }
        }
        .frame(width: 60, height: 60)
        .padding(30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(batteryManager.accessibilityValue)
    }

    private var batteryColor: Color {
        if batteryManager.isCharging {
            return .green
        } else {
            if batteryManager.batteryLevel <= criticalLevel {
                return .red
            } else if batteryManager.batteryLevel <= warningLevel {
                return .yellow
            } else {
                return .primary
            }
        }
    }
}

struct BatteryPopup_Previews: PreviewProvider {
    static var previews: some View {
        BatteryPopup(batteryManager: BatteryManager(), configProvider: ConfigProvider(config: [:]))
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
