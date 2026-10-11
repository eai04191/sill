import Combine
import EventKit
import Foundation
import os

class CalendarManager: ObservableObject {
    private static let inUse = SharedWhileInUse<CalendarManager>()

    /// One manager, with its event store and timer, for all time widgets with the same calendar filter and time zone,
    /// instead of a new one on every evaluation of the bar's body.
    static func shared(for configProvider: ConfigProvider) -> CalendarManager {
        let config = configProvider.config["calendar"]?.dictionaryValue
        let filter = [calendars(in: config, for: "allow-list"), calendars(in: config, for: "deny-list")]
        let key = "\(filter)|\(configuredTimeZone(in: configProvider.config)?.identifier ?? "")"
        return inUse.instance(for: key) { CalendarManager(configProvider: configProvider) }
    }

    /// The time widget's `time-zone`, or nil to follow the system time zone. The bar's time, the popup's days and times
    /// and the fetched day ranges all use the same zone, so they agree on what today is.
    private static func configuredTimeZone(in config: ConfigData) -> TimeZone? {
        config["time-zone"]?.stringValue.flatMap(TimeZone.init(identifier:))
    }

    let configProvider: ConfigProvider
    private let configuredTimeZone: TimeZone?
    /// The calendar in the configured time zone, or in the system time zone, updated on refresh when it changes.
    private(set) var calendar = Calendar.current
    var config: ConfigData? {
        configProvider.config["calendar"]?.dictionaryValue
    }
    var allowList: [String] {
        Self.calendars(in: config, for: "allow-list")
    }
    var denyList: [String] {
        Self.calendars(in: config, for: "deny-list")
    }

    private static func calendars(in config: ConfigData?, for key: String) -> [String] {
        config?[key]?.arrayValue?.compactMap(\.stringValue).filter { !$0.isEmpty } ?? []
    }

    @Published var nextEvent: EKEvent?
    @Published var todaysEvents: [EKEvent] = []
    @Published var tomorrowsEvents: [EKEvent] = []
    /// The current day, replaced when the day changes so that the popups move to the new day.
    @Published private(set) var today = Date()
    /// True when the user denied access to the calendars, so that the popups do not show this as having no events.
    @Published private(set) var accessDenied = false
    private let eventStore = EKEventStore()
    private var observers: [NSObjectProtocol] = []
    /// Fetches the events again when one of today's events starts or ends, which changes the next event and today's
    /// events without a change to the store, and when the day changes in the configured time zone, which the system's
    /// day change notification does not follow.
    private var rolloverTimer: Timer?

    init(configProvider: ConfigProvider) {
        self.configProvider = configProvider
        configuredTimeZone = Self.configuredTimeZone(in: configProvider.config)
        calendar.timeZone = configuredTimeZone ?? .current
        requestAccess()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    /// Fetches the events again when the store changes, and when the day or the clock changes, which moves the fetched
    /// day ranges, instead of polling the store.
    private func startMonitoring() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.refresh()
                })
        }
        refresh()
    }

    private func stopMonitoring() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        rolloverTimer?.invalidate()
        rolloverTimer = nil
    }

    private func requestAccess() {
        if HiddenInstance.isEnabled, EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            Logger.calendar.error("Not requesting calendar access in a hidden instance; sign it like the installed Sill")
            return
        }
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            if !granted || error != nil {
                Logger.calendar.error(
                    "Calendar access not granted: \(String(describing: error), privacy: .public)")
            }
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    /// Fetches every list and schedules the next rollover. Called on the main thread.
    private func refresh() {
        let now = Date()
        let timeZone = configuredTimeZone ?? .current
        if calendar.timeZone != timeZone {
            calendar.timeZone = timeZone
        }
        if !calendar.isDate(today, inSameDayAs: now) {
            today = now
        }
        let status = EKEventStore.authorizationStatus(for: .event)
        accessDenied = status == .denied || status == .restricted || status == .writeOnly
        todaysEvents = fetchTodaysEvents(now: now)
        tomorrowsEvents = fetchTomorrowsEvents(now: now)
        nextEvent = fetchNextEvent(now: now)
        scheduleRollover(after: now)
    }

    private func scheduleRollover(after now: Date) {
        rolloverTimer?.invalidate()
        rolloverTimer = nil
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        let boundaries = (todaysEvents.flatMap { [$0.startDate, $0.endDate] } + [startOfTomorrow]).compactMap { $0 }
        guard let boundary = boundaries.filter({ $0 > now }).min() else { return }
        // A second after the boundary, so that an event ending then is no longer fetched as ongoing.
        let timer = Timer(fire: boundary.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        rolloverTimer = timer
    }

    private func filterEvents(_ events: [EKEvent]) -> [EKEvent] {
        var filtered = events
        if !allowList.isEmpty {
            filtered = filtered.filter { allowList.contains($0.calendar.title) }
        }
        if !denyList.isEmpty {
            filtered = filtered.filter { !denyList.contains($0.calendar.title) }
        }
        return filtered
    }

    private func fetchNextEvent(now: Date) -> EKEvent? {
        let calendars = eventStore.calendars(for: .event)
        guard
            let endOfDay = calendar.date(
                bySettingHour: 23, minute: 59, second: 59, of: now)
        else {
            Logger.calendar.error("Could not get the end of the day")
            return nil
        }
        let predicate = eventStore.predicateForEvents(
            withStart: now, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate).sorted {
            $0.startDate < $1.startDate
        }
        let filteredEvents = filterEvents(events).filter { !Self.isCanceledOrDeclined($0) }
        // The range also matches events that already started; a timed one of those is not the next event. All-day
        // events, which started at midnight, are shown when no timed event is left today.
        let upcomingEvents = filteredEvents.filter { !$0.isAllDay && $0.startDate >= now }
        return upcomingEvents.first ?? filteredEvents.first { $0.isAllDay }
    }

    /// Events the user will not attend: canceled by the organizer, or declined by the user.
    private static func isCanceledOrDeclined(_ event: EKEvent) -> Bool {
        event.status == .canceled
            || event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    private func fetchTodaysEvents(now: Date) -> [EKEvent] {
        let calendars = eventStore.calendars(for: .event)
        let startOfDay = calendar.startOfDay(for: now)
        guard
            let endOfDay = calendar.date(
                bySettingHour: 23, minute: 59, second: 59, of: now)
        else {
            Logger.calendar.error("Could not get the end of the day")
            return []
        }
        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
        return filterEvents(events)
    }

    private func fetchTomorrowsEvents(now: Date) -> [EKEvent] {
        let calendars = eventStore.calendars(for: .event)
        let startOfToday = calendar.startOfDay(for: now)
        guard
            let startOfTomorrow = calendar.date(
                byAdding: .day, value: 1, to: startOfToday),
            let endOfTomorrow = calendar.date(
                bySettingHour: 23, minute: 59, second: 59, of: startOfTomorrow)
        else {
            Logger.calendar.error("Could not get tomorrow's date range")
            return []
        }
        let predicate = eventStore.predicateForEvents(
            withStart: startOfTomorrow, end: endOfTomorrow, calendars: calendars
        )
        let events = eventStore.events(matching: predicate).sorted {
            $0.startDate < $1.startDate
        }
        return filterEvents(events)
    }
}
