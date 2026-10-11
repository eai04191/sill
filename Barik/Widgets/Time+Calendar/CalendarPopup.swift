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
            Text(monthYear(of: today, in: calendarManager.calendar))
                .font(.title2)
                .padding(.bottom, 25)
            WeekdayHeaderView()
            CalendarDaysView(today: today, calendar: calendarManager.calendar)
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
            Text(monthYear(of: today, in: calendarManager.calendar))
                .font(.title2)
                .padding(.bottom, 25)
            WeekdayHeaderView()
            CalendarDaysView(today: today, calendar: calendarManager.calendar)
            
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
                    today: today,
                    calendar: calendarManager.calendar,
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
                Text(monthYear(of: today, in: calendarManager.calendar))
                    .font(.title2)
                    .padding(.bottom, 25)
                    .fixedSize(horizontal: true, vertical: false)
                WeekdayHeaderView()
                CalendarDaysView(today: today, calendar: calendarManager.calendar)
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
                    today: today,
                    calendar: calendarManager.calendar,
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
            .foregroundStyle(Color.primary.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func monthYear(of date: Date, in calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "LLLL yyyy"
    formatter.timeZone = calendar.timeZone
    return formatter.string(from: date).capitalized
}

/// The days of the month of `date`, preceded by blanks for the weekdays before the first day.
private func calendarDays(of date: Date, in calendar: Calendar) -> [Int?] {
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

private func weeks(of date: Date, in calendar: Calendar) -> [[Int?]] {
    var days = calendarDays(of: date, in: calendar)
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
                // The secondary color takes on the glass behind it and faded out; weekends are dimmed primary.
                let color = isWeekend ? Color.primary.opacity(0.75) : Color.primary

                Text(reordered[i])
                    .frame(width: 30)
                    .foregroundColor(color)
            }
        }
        .padding(.bottom, 10)
    }
}

private struct CalendarDaysView: View {
    /// On Liquid Glass, a primary-colored circle takes on the glass's vibrancy and fades, so today uses the system
    /// red like the macOS Calendar, as the color that marks the one emphasized day.
    private let todayFill = Color(red: 0.75, green: 0.1, blue: 0.1)
    private let todayText = Color.white
    /// The day the popup shows; it marks this day in this day's month.
    let today: Date
    /// The calendar in the configured time zone, in which `today` is the current day.
    let calendar: Calendar

    var body: some View {
        let weeks = weeks(of: today, in: calendar)
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
                                : (isWeekend ? Color.primary.opacity(0.75) : Color.primary)

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
    let today: Date
    let calendar: Calendar
    let todaysEvents: [EKEvent]
    let tomorrowsEvents: [EKEvent]

    var body: some View {
        if !todaysEvents.isEmpty || !tomorrowsEvents.isEmpty {
            VStack(spacing: 10) {
                eventSection(
                    title: NSLocalizedString("TODAY", comment: "").uppercased(),
                    day: today, events: todaysEvents)
                eventSection(
                    title: NSLocalizedString("TOMORROW", comment: "")
                        .uppercased(),
                    day: calendar.date(byAdding: .day, value: 1, to: today) ?? today, events: tomorrowsEvents)
            }
        }
    }

    @ViewBuilder
    func eventSection(title: String, day: Date, events: [EKEvent]) -> some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.6))
                ForEach(events, id: \.eventIdentifier) { event in
                    EventRow(event: event, day: day, calendar: calendar)
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: EKEvent
    /// The day of the section showing the event.
    let day: Date
    let calendar: Calendar

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
                    .opacity(0.8)
            }
            Spacer()
        }
        .padding(5)
        .padding(.trailing, 5)
        // The calendar's color marks the event with the bar on its leading edge. Text in that color on a background
        // tinted with it was unreadable on glass (blue on blue), so the text uses the primary color.
        .foregroundStyle(Color.primary)
        .background(Color(event.calendar.cgColor).opacity(0.2))
        .cornerRadius(6)
        .frame(maxWidth: .infinity)
    }

    func getEventTime(_ event: EKEvent) -> String {
        var text = ""
        if !event.isAllDay {
            text += time(event.startDate)
            text += " — "
            text += time(event.endDate)
        } else {
            return NSLocalizedString("ALL_DAY", comment: "")
        }
        return text
    }

    /// The time, with the date when it is not on the section's day, as for an event spanning several days.
    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, inSameDayAs: day) ? "j:mm" : "MMMd j:mm")
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date).replacing(":00", with: "")
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
