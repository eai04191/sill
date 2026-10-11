import Combine
import EventKit
import Foundation

class CalendarManager: ObservableObject {
    private static let inUse = SharedWhileInUse<CalendarManager>()

    /// One manager, with its event store and timer, for all time widgets with the same calendar filter, instead of a
    /// new one on every evaluation of the bar's body.
    static func shared(for configProvider: ConfigProvider) -> CalendarManager {
        let config = configProvider.config["calendar"]?.dictionaryValue
        let filter = [calendars(in: config, for: "allow-list"), calendars(in: config, for: "deny-list")]
        return inUse.instance(for: filter.description) { CalendarManager(configProvider: configProvider) }
    }

    let configProvider: ConfigProvider
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
    private let eventStore = EKEventStore()
    private var observers: [NSObjectProtocol] = []
    /// Fetches the events again when one of today's events starts or ends, which changes the next event and today's
    /// events without a change to the store.
    private var rolloverTimer: Timer?

    init(configProvider: ConfigProvider) {
        self.configProvider = configProvider
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
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            if granted && error == nil {
                DispatchQueue.main.async { self?.refresh() }
            } else {
                print(
                    "Calendar access not granted: \(String(describing: error))")
            }
        }
    }

    /// Fetches every list and schedules the next rollover. Called on the main thread.
    private func refresh() {
        let now = Date()
        todaysEvents = fetchTodaysEvents(now: now)
        tomorrowsEvents = fetchTomorrowsEvents(now: now)
        nextEvent = fetchNextEvent(now: now)
        scheduleRollover(after: now)
    }

    private func scheduleRollover(after now: Date) {
        rolloverTimer?.invalidate()
        rolloverTimer = nil
        let boundaries = todaysEvents.flatMap { [$0.startDate, $0.endDate] }.compactMap { $0 }
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
        let calendar = Calendar.current
        guard
            let endOfDay = calendar.date(
                bySettingHour: 23, minute: 59, second: 59, of: now)
        else {
            print("Failed to get end of day.")
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
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard
            let endOfDay = calendar.date(
                bySettingHour: 23, minute: 59, second: 59, of: now)
        else {
            print("Failed to get end of day.")
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
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        guard
            let startOfTomorrow = calendar.date(
                byAdding: .day, value: 1, to: startOfToday),
            let endOfTomorrow = calendar.date(
                bySettingHour: 23, minute: 59, second: 59, of: startOfTomorrow)
        else {
            print("Failed to get tomorrow's date range.")
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
