import Combine
import EventKit
import SwiftUI

struct TimeWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }
    var calendarConfig: ConfigData? { config["calendar"]?.dictionaryValue }

    var format: String { config["format"]?.stringValue ?? "E d, J:mm" }
    /// A fixed date format pattern used as is instead of `format`. `format` is a template the locale reorders and
    /// rewrites, so it cannot keep a zero-padded hour like "09:05" in locales such as Japanese.
    var fixedFormat: String? { config["fixed-format"]?.stringValue }
    var timeZone: String? { config["time-zone"]?.stringValue }

    var calendarFormat: String {
        calendarConfig?["format"]?.stringValue ?? "J:mm"
    }
    var calendarShowEvents: Bool {
        calendarConfig?["show-events"]?.boolValue ?? true
    }

    @ObservedObject private var configManager = ConfigManager.shared
    @State private var currentTime = Date()
    let calendarManager: CalendarManager

    @State private var rect = CGRect()

    private let timer = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(barTime)
                .fontWeight(.semibold)
            if let event = calendarManager.nextEvent, calendarShowEvents {
                Text(eventText(for: event))
                    .opacity(0.8)
                    .font(.subheadline)
            }
        }
        .font(.headline)
        // The shadow keeps the white text legible on the wallpaper; glass already provides the contrast.
        .applying(!configManager.config.usesLiquidGlass) { $0.shadow(color: .foregroundShadowOutside, radius: 3) }
        .onReceive(timer) { date in
            currentTime = date
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        rect = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) {
                        oldState, newState in
                        rect = newState
                    }
            }
        )
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .monospacedDigit()
        .barButton(label: "Calendar", value: accessibilityValue) {
            MenuBarPopup.show(rect: rect, id: "calendar") {
                CalendarPopup(
                    calendarManager: calendarManager,
                    configProvider: configProvider)
            }
        }
    }

    /// The time and, when shown on the bar, the next event, so VoiceOver reads what is displayed.
    private var accessibilityValue: String {
        let time = barTime
        guard let event = calendarManager.nextEvent, calendarShowEvents else { return time }
        return "\(time), \(eventText(for: event))"
    }

    /// The time shown on the bar.
    private var barTime: String {
        if let fixedFormat {
            return formattedTime(pattern: fixedFormat, from: currentTime, fixed: true)
        }
        return formattedTime(pattern: format, from: currentTime)
    }

    // Format the current time. A fixed pattern is used as is; otherwise it is a template localized for the locale.
    private func formattedTime(pattern: String, from time: Date, fixed: Bool = false) -> String {
        let formatter = DateFormatter()
        if fixed {
            // The POSIX locale keeps the pattern as written: with the user's locale, the 12-hour time setting turns
            // "HH:mm" into "午前10:00". Names such as weekdays are then in English.
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
        } else {
            formatter.setLocalizedDateFormatFromTemplate(pattern)
        }

        if let timeZone = timeZone,
            let tz = TimeZone(identifier: timeZone)
        {
            formatter.timeZone = tz
        } else {
            formatter.timeZone = TimeZone.current
        }

        return formatter.string(from: time)
    }

    // Create text for the calendar event.
    private func eventText(for event: EKEvent) -> String {
        var text = event.title ?? ""
        if !event.isAllDay {
            text += " ("
            text += formattedTime(
                pattern: calendarFormat, from: event.startDate)
            text += ")"
        }
        return text
    }
}

struct TimeWidget_Previews: PreviewProvider {
    static var previews: some View {
        let provider = ConfigProvider(config: ConfigData())
        let manager = CalendarManager(configProvider: provider)

        ZStack {
            TimeWidget(calendarManager: manager)
                .environmentObject(provider)
        }.frame(width: 500, height: 100)
    }
}
