import AppKit
import Combine
import EventKit

enum CalendarAccess {
    case notDetermined, authorized, denied
}

enum RepeatOption: String, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, yearly
    var id: String { rawValue }
    var labelKey: String { "repeat.\(rawValue)" }

    var rule: EKRecurrenceRule? {
        let frequency: EKRecurrenceFrequency
        switch self {
        case .none: return nil
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)
    }
}

enum AlertOption: Int, CaseIterable, Identifiable {
    case none = -1, atTime = 0, fiveMinutes = 5, fifteenMinutes = 15, thirtyMinutes = 30, oneHour = 60, oneDay = 1440
    var id: Int { rawValue }
    var labelKey: String {
        switch self {
        case .none: return "alert.none"
        case .atTime: return "alert.atTime"
        case .fiveMinutes: return "alert.5m"
        case .fifteenMinutes: return "alert.15m"
        case .thirtyMinutes: return "alert.30m"
        case .oneHour: return "alert.1h"
        case .oneDay: return "alert.1d"
        }
    }
}

struct AgendaDay: Identifiable {
    let day: Date
    let events: [EKEvent]
    var id: Date { day }
}

enum EventStoreError: LocalizedError {
    case endBeforeStart, noWritableCalendar

    @MainActor var message: String {
        switch self {
        case .endBeforeStart: return L("error.endBeforeStart")
        case .noWritableCalendar: return L("error.noWritableCalendar")
        }
    }
}

/// Thin wrapper over EventKit. Reads and writes the same calendars the Calendar app uses.
@MainActor
final class EventStore: ObservableObject {
    let ekStore = EKEventStore()

    @Published private(set) var access: CalendarAccess = .notDetermined
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var markedDays: Set<Date> = []
    @Published private(set) var eventColorsByDay: [Date: [NSColor]] = [:]
    /// Bumps whenever the underlying data changes so views refetch.
    @Published private(set) var revision = 0

    private let settings: AppSettings
    private var gridRange: (start: Date, end: Date)?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
        updateAccessStatus()

        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: ekStore)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadCalendars()
                self?.reload()
            }
            .store(in: &cancellables)

        settings.$hiddenCalendarIDs
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    // MARK: Access

    func updateAccessStatus() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .authorized
        case .notDetermined: access = .notDetermined
        default: access = .denied
        }
    }

    func requestAccessIfNeeded() async {
        updateAccessStatus()
        if access == .notDetermined {
            do {
                _ = try await ekStore.requestFullAccessToEvents()
            } catch {
                NSLog("AleCal: calendar access request failed: \(error.localizedDescription)")
            }
            updateAccessStatus()
        }
        if access == .authorized {
            ekStore.refreshSourcesIfNecessary()
            reloadCalendars()
            reload()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Calendars

    func reloadCalendars() {
        guard access == .authorized else { calendars = []; return }
        calendars = ekStore.calendars(for: .event).sorted {
            if $0.source.title != $1.source.title {
                return $0.source.title.localizedCaseInsensitiveCompare($1.source.title) == .orderedAscending
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var visibleCalendars: [EKCalendar] {
        calendars.filter { !settings.hiddenCalendarIDs.contains($0.calendarIdentifier) }
    }

    var writableCalendars: [EKCalendar] {
        calendars.filter { $0.allowsContentModifications }
    }

    var defaultCalendar: EKCalendar? {
        if let preferred = ekStore.defaultCalendarForNewEvents, preferred.allowsContentModifications {
            return preferred
        }
        return writableCalendars.first
    }

    // MARK: Fetching

    func events(from start: Date, to end: Date) -> [EKEvent] {
        guard access == .authorized, end > start else { return [] }
        let cals = visibleCalendars
        guard !cals.isEmpty else { return [] }
        let predicate = ekStore.predicateForEvents(withStart: start, end: end, calendars: cals)
        return ekStore.events(matching: predicate).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return (lhs.title ?? "") < (rhs.title ?? "")
        }
    }

    /// Events grouped by day for the event list, skipping empty days.
    func agenda(from day: Date, days: Int, calendar cal: Calendar) -> [AgendaDay] {
        guard days > 0 else { return [] }
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: days, to: start) else { return [] }
        let all = events(from: start, to: end)
        var result: [AgendaDay] = []
        for offset in 0..<days {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: start),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let matches = all.filter { event in
                let eventEnd = max(event.startDate, event.endDate)
                return event.startDate < dayEnd && (eventEnd > dayStart || event.startDate == dayStart)
            }
            if !matches.isEmpty { result.append(AgendaDay(day: dayStart, events: matches)) }
        }
        return result
    }

    /// Loads which days in the visible month grid have events (for the dots).
    func setGrid(start: Date, end: Date) {
        gridRange = (start, end)
        recomputeMarks()
    }

    func hasEvents(on day: Date) -> Bool {
        markedDays.contains(Calendar.current.startOfDay(for: day))
    }

    func eventColors(on day: Date) -> [NSColor] {
        eventColorsByDay[Calendar.current.startOfDay(for: day)] ?? []
    }

    func nextUpcomingEvent(on day: Date = Date()) -> EKEvent? {
        guard access == .authorized else { return nil }
        let now = Date()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
        let dayEvents = events(from: startOfDay, to: endOfDay)
        return dayEvents.first { event in
            !event.isAllDay && event.endDate > now
        }
    }

    func reload() {
        recomputeMarks()
        revision += 1
    }

    private func recomputeMarks() {
        guard let range = gridRange else { return }
        let cal = Calendar.current
        var marks = Set<Date>()
        var colorsMap: [Date: [NSColor]] = [:]

        for event in events(from: range.start, to: range.end) {
            var day = cal.startOfDay(for: max(event.startDate, range.start))
            let last = min(max(event.startDate, event.endDate.addingTimeInterval(-1)), range.end)
            let color = event.calendar.color ?? NSColor.systemBlue
            while day <= last {
                marks.insert(day)
                var currentColors = colorsMap[day] ?? []
                if !currentColors.contains(where: { $0.isEqual(color) }) {
                    currentColors.append(color)
                    colorsMap[day] = currentColors
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        if marks != markedDays { markedDays = marks }
        eventColorsByDay = colorsMap
    }

    // MARK: Writing

    func createEvent(title: String,
                     start: Date,
                     end: Date,
                     allDay: Bool,
                     calendar: EKCalendar?,
                     location: String,
                     repeatOption: RepeatOption,
                     alert: AlertOption) throws {
        guard let target = calendar ?? defaultCalendar else { throw EventStoreError.noWritableCalendar }
        let cal = Calendar.current
        let event = EKEvent(eventStore: ekStore)
        event.title = title
        event.calendar = target
        event.isAllDay = allDay
        if allDay {
            let first = cal.startOfDay(for: start)
            let lastDay = cal.startOfDay(for: end)
            guard lastDay >= first else { throw EventStoreError.endBeforeStart }
            event.startDate = first
            event.endDate = lastDay
        } else {
            guard end >= start else { throw EventStoreError.endBeforeStart }
            event.startDate = start
            event.endDate = end
        }
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = trimmedLocation.isEmpty ? nil : trimmedLocation
        if let rule = repeatOption.rule { event.addRecurrenceRule(rule) }
        if alert != .none {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alert.rawValue * 60)))
        }
        try ekStore.save(event, span: .thisEvent, commit: true)
        reload()
    }

    func delete(_ event: EKEvent, span: EKSpan) throws {
        try ekStore.remove(event, span: span, commit: true)
        reload()
    }
}
