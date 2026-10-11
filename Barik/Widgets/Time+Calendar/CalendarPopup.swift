import EventKit
import SwiftUI

struct CalendarPopup: View {
    let calendarManager: CalendarManager

    @ObservedObject var configProvider: ConfigProvider
    @State private var selectedVariant: MenuBarPopupVariant = .box

    var body: some View {
        // The colors of every variant adapt to the appearance; popups are always dark (see MenuBarPopupView).
        variantView
    }

    private var variantView: some View {
        MenuBarPopupVariantView(
            selectedVariant: selectedVariant,
            onVariantSelected: { variant in
                selectedVariant = variant
                ConfigManager.shared.updateConfigValue(
                    key: "widgets.default.time.popup.view-variant",
                    newValue: variant.rawValue
                )
            },
            box: { CalendarBoxPopup(calendarManager) },
            vertical: { CalendarVerticalPopup(calendarManager) },
            horizontal: { CalendarHorizontalPopup(calendarManager) }
        )
        .onAppear {
            if let variantString = configProvider.config["popup"]?
                .dictionaryValue?["view-variant"]?.stringValue,
                let variant = MenuBarPopupVariant(rawValue: variantString)
            {
                selectedVariant = variant
            } else {
                selectedVariant = .box
            }
        }
        .onReceive(configProvider.$config) { newConfig in
            if let variantString = newConfig["popup"]?.dictionaryValue?[
                "view-variant"]?.stringValue,
                let variant = MenuBarPopupVariant(rawValue: variantString)
            {
                selectedVariant = variant
            }
        }
    }
}

struct CalendarBoxPopup: View {
    @ObservedObject var calendarManager: CalendarManager

    init(_ calendarManager: CalendarManager) {
        _calendarManager = ObservedObject(wrappedValue: calendarManager)
    }

    var body: some View {
        let today = calendarManager.today
        VStack(spacing: 0) {
            Text(monthYear(of: today))
                .font(.title2)
                .padding(.bottom, 25)
            WeekdayHeaderView()
            CalendarDaysView(today: today)
        }
        .padding(30)
        .fontWeight(.semibold)
    }
}

struct CalendarVerticalPopup: View {
    @ObservedObject var calendarManager: CalendarManager

    init(_ calendarManager: CalendarManager) {
        _calendarManager = ObservedObject(wrappedValue: calendarManager)
    }

    var body: some View {
        let today = calendarManager.today
        VStack(spacing: 0) {
            Text(monthYear(of: today))
                .font(.title2)
                .padding(.bottom, 25)
            WeekdayHeaderView()
            CalendarDaysView(today: today)
            
            Group {
                if calendarManager.accessDenied {
                    CalendarAccessDeniedText()
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 3)
                } else if calendarManager.todaysEvents.isEmpty && calendarManager.tomorrowsEvents.isEmpty {
                    Text(NSLocalizedString("EMPTY_EVENTS", comment: ""))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .font(.callout)
                        .padding(.top, 3)
                }
                EventListView(
                    todaysEvents: calendarManager.todaysEvents,
                    tomorrowsEvents: calendarManager.tomorrowsEvents
                )
            }
            .frame(width: 255)
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 30)
        .fontWeight(.semibold)
    }
}

struct CalendarHorizontalPopup: View {
    @ObservedObject var calendarManager: CalendarManager

    init(_ calendarManager: CalendarManager) {
        _calendarManager = ObservedObject(wrappedValue: calendarManager)
    }

    var body: some View {
        let today = calendarManager.today
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(monthYear(of: today))
                    .font(.title2)
                    .padding(.bottom, 25)
                    .fixedSize(horizontal: true, vertical: false)
                WeekdayHeaderView()
                CalendarDaysView(today: today)
            }
            
            Group {
                if calendarManager.accessDenied {
                    CalendarAccessDeniedText()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if calendarManager.todaysEvents.isEmpty && calendarManager.tomorrowsEvents.isEmpty {
                    Text(NSLocalizedString("EMPTY_EVENTS", comment: ""))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout)
                }
                EventListView(
                    todaysEvents: calendarManager.todaysEvents,
                    tomorrowsEvents: calendarManager.tomorrowsEvents
                )
            }
            .frame(width: 255)
            .padding(.leading, 30)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 30)
        .fontWeight(.semibold)
    }
}

/// Shown instead of the events when calendar access is denied, as the event list is then empty for that reason.
private struct CalendarAccessDeniedText: View {
    var body: some View {
        Text("Barik has no access to your calendars. Allow it in System Settings > Privacy & Security > Calendars.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func monthYear(of date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "LLLL yyyy"
    return formatter.string(from: date).capitalized
}

/// The days of the month of `date`, preceded by blanks for the weekdays before the first day.
private func calendarDays(of date: Date) -> [Int?] {
    let calendar = Calendar.current
    guard
        let range = calendar.range(of: .day, in: .month, for: date),
        let firstOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        )
    else {
        return []
    }
    let startOfMonthWeekday = calendar.component(.weekday, from: firstOfMonth)
    let blanks = (startOfMonthWeekday - calendar.firstWeekday + 7) % 7
    var days: [Int?] = Array(repeating: nil, count: blanks)
    days.append(contentsOf: range.map { $0 })
    return days
}

private func weeks(of date: Date) -> [[Int?]] {
    var days = calendarDays(of: date)
    let remainder = days.count % 7
    if remainder != 0 {
        days.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
    }
    return stride(from: 0, to: days.count, by: 7).map {
        Array(days[$0..<min($0 + 7, days.count)])
    }
}

private struct WeekdayHeaderView: View {
    var body: some View {
        let calendar = Calendar.current
        let weekdaySymbols = calendar.shortWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1
        let reordered = Array(
            weekdaySymbols[firstWeekdayIndex...]
                + weekdaySymbols[..<firstWeekdayIndex]
        )
        let referenceDate = DateComponents(
            calendar: calendar, year: 2020, month: 12, day: 13
        ).date!
        let referenceDays = (0..<7).map { i in
            calendar.date(byAdding: .day, value: i, to: referenceDate)!
        }

        HStack {
            ForEach(reordered.indices, id: \.self) { i in
                let originalIndex = (i + firstWeekdayIndex) % 7
                let isWeekend = calendar.isDateInWeekend(
                    referenceDays[originalIndex]
                )
                let color = isWeekend ? Color.secondary : Color.primary

                Text(reordered[i])
                    .frame(width: 30)
                    .foregroundColor(color)
            }
        }
        .padding(.bottom, 10)
    }
}

private struct CalendarDaysView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var configManager = ConfigManager.shared
    /// On Liquid Glass, a primary-colored circle takes on the glass's vibrancy and fades, so today uses the system
    /// red like the macOS Calendar, as the color that marks the one emphasized day.
    private var todayFill: Color { configManager.config.usesLiquidGlass ? .red : .primary }
    private var todayText: Color {
        if configManager.config.usesLiquidGlass { return .white }
        return colorScheme == .dark ? .black : .white
    }
    /// The day the popup shows; it marks this day in this day's month.
    let today: Date

    var body: some View {
        let calendar = Calendar.current
        let weeks = weeks(of: today)
        let currentYear = calendar.component(.year, from: today)
        let currentMonth = calendar.component(.month, from: today)
        VStack(spacing: 10) {
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 8) {
                    ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                        if let day = weeks[weekIndex][dayIndex] {
                            let date = calendar.date(
                                from: DateComponents(
                                    year: currentYear,
                                    month: currentMonth,
                                    day: day
                                )
                            )!
                            let isWeekend = calendar.isDateInWeekend(date)
                            let isToday = calendar.component(.day, from: today) == day
                            let color =
                                isToday
                                ? todayText
                                : (isWeekend ? Color.secondary : Color.primary)

                            ZStack {
                                if isToday {
                                    Circle()
                                        .fill(todayFill)
                                        .frame(width: 30, height: 30)
                                }
                                Text("\(day)")
                                    .foregroundColor(color)
                                    .frame(width: 30, height: 30)
                            }
                        } else {
                            Color.clear.frame(width: 30, height: 30)
                        }
                    }
                }
            }
        }.compositingGroup()
    }
}

private struct EventListView: View {
    let todaysEvents: [EKEvent]
    let tomorrowsEvents: [EKEvent]

    var body: some View {
        if !todaysEvents.isEmpty || !tomorrowsEvents.isEmpty {
            VStack(spacing: 10) {
                eventSection(
                    title: NSLocalizedString("TODAY", comment: "").uppercased(),
                    events: todaysEvents)
                eventSection(
                    title: NSLocalizedString("TOMORROW", comment: "")
                        .uppercased(), events: tomorrowsEvents)
            }
        }
    }

    @ViewBuilder
    func eventSection(title: String, events: [EKEvent]) -> some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(events, id: \.eventIdentifier) { event in
                    EventRow(event: event)
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: EKEvent

    var body: some View {
        let eventTime = getEventTime(event)
        HStack(spacing: 4) {
            Rectangle()
                .fill(Color(event.calendar.cgColor))
                .frame(width: 3, height: 30)
                .clipShape(Capsule())
            VStack(alignment: .leading) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(eventTime)
                    .font(.caption)
                    .fontWeight(.regular)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(5)
        .padding(.trailing, 5)
        .foregroundStyle(Color(event.calendar.cgColor))
        .background(Color(event.calendar.cgColor).opacity(0.2))
        .cornerRadius(6)
        .frame(maxWidth: .infinity)
    }

    func getEventTime(_ event: EKEvent) -> String {
        var text = ""
        if !event.isAllDay {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("j:mm")
            text += formatter.string(from: event.startDate).replacing(":00", with: "")
            text += " — "
            text += formatter.string(from: event.endDate).replacing(":00", with: "")
        } else {
            return NSLocalizedString("ALL_DAY", comment: "")
        }
        return text
    }
}

struct CalendarPopup_Previews: PreviewProvider {
    var configProvider: ConfigProvider = ConfigProvider(config: ConfigData())
    var calendarManager: CalendarManager

    init() {
        self.calendarManager = CalendarManager(configProvider: configProvider)
    }

    static var previews: some View {
        let configProvider = ConfigProvider(config: ConfigData())
        let calendarManager = CalendarManager(configProvider: configProvider)

        CalendarBoxPopup(calendarManager)
            .background(Color.black)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Box")
        CalendarVerticalPopup(calendarManager)
            .background(Color.black)
            .frame(height: 600)
            .previewDisplayName("Vertical")
        CalendarHorizontalPopup(calendarManager)
            .background(Color.black)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Horizontal")
    }
}
