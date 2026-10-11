import EventKit
import SwiftUI

struct TimeWidget: View {
    /// The widget's entry in the config, for its popup (see `CalendarPopup.item`).
    let item: TomlWidgetItem
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

    @State private var currentTime = Date()
    @ObservedObject var calendarManager: CalendarManager

    @State private var rect = CGRect()

    /// Seconds between updates of the bar's time: every second only when the shown format has seconds.
    private var tickInterval: TimeInterval {
        let showsSeconds =
            if let fixedFormat {
                // Quoted text is literal, so its letters are not fields.
                fixedFormat.replacing(#/'[^']*'?/#, with: "").contains(where: { "sSA".contains($0) })
            } else {
                format.contains("s")
            }
        return showsSeconds ? 1 : 60
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(barTime)
            if let event = calendarManager.nextEvent, calendarShowEvents {
                Text(eventText(for: event))
                    .opacity(0.8)
                    .font(.subheadline)
            }
        }
        .font(.barText)
        .task(id: tickInterval) {
            // Wake at each boundary of the interval, e.g. on the minute, instead of polling every second.
            currentTime = Date()
            while !Task.isCancelled {
                let interval = tickInterval
                let now = Date().timeIntervalSinceReferenceDate
                let next = ((now / interval).rounded(.down) + 1) * interval
                try? await Task.sleep(for: .seconds(next - now))
                // The sleep can end slightly early; the time shown is then still the new boundary's.
                currentTime = max(Date(), Date(timeIntervalSinceReferenceDate: next))
            }
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
        .experimentalConfiguration()
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .monospacedDigit()
        .barWidgetButton(label: "Calendar", value: accessibilityValue) {
            MenuBarPopup.show(rect: rect, id: "calendar") {
                CalendarPopup(item: item)
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

    /// Formatters by pattern, time zone and locale, as creating one on every render is costly. Used on the main thread
    /// only.
    private static var formatters: [String: DateFormatter] = [:]

    // Format the current time. A fixed pattern is used as is; otherwise it is a template localized for the locale.
    private func formattedTime(pattern: String, from time: Date, fixed: Bool = false) -> String {
        formatter(pattern: pattern, fixed: fixed).string(from: time)
    }

    private func formatter(pattern: String, fixed: Bool) -> DateFormatter {
        let timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? TimeZone.current
        let key = "\(fixed)|\(pattern)|\(timeZone.identifier)|\(Locale.current.identifier)"
        if let formatter = Self.formatters[key] {
            return formatter
        }
        let formatter = DateFormatter()
        if fixed {
            // The POSIX locale keeps the pattern as written: with the user's locale, the 12-hour time setting turns
            // "HH:mm" into "午前10:00". Names such as weekdays are then in English.
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
        } else {
            formatter.setLocalizedDateFormatFromTemplate(pattern)
        }

        formatter.timeZone = timeZone
        Self.formatters[key] = formatter
        return formatter
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
            TimeWidget(item: TomlWidgetItem(id: "default.time", inlineParams: [:]), calendarManager: manager)
                .environmentObject(provider)
        }.frame(width: 500, height: 100)
    }
}
