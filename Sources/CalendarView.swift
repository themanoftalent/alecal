import AppKit
import EventKit
import SwiftUI

/// The main popover content: month grid, quick month/year picker, agenda, and bottom toolbar.
@MainActor
struct CalendarView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: EventStore

    var onOpenPreferences: () -> Void
    var onClose: () -> Void

    @State private var month = Date()
    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var newEventDate: Date?
    @State private var showMonthPicker = false
    @State private var hoveredDay: Date?

    private var cal: Calendar { settings.calendar }
    private var scale: CGFloat { settings.textSize.scale }
    private var cellWidth: CGFloat { 32 * scale }
    private var cellHeight: CGFloat { 28 * scale }
    private var weekColumnWidth: CGFloat { 24 * scale }

    var body: some View {
        VStack(spacing: 0) {
            if store.access == .denied {
                accessBanner
                    .padding(.bottom, 8 * scale)
            }

            header
                .padding(.bottom, 4 * scale)

            if showMonthPicker {
                monthYearPicker
                    .padding(.vertical, 8 * scale)
            } else {
                weekdayRow
                    .padding(.top, 4 * scale)
                monthGrid
                    .padding(.top, 2 * scale)
            }

            if let date = newEventDate {
                Divider().padding(.vertical, 8 * scale)
                NewEventView(initialDate: date) { newEventDate = nil }
            } else if settings.eventDays > 0 && store.access == .authorized && !showMonthPicker {
                Divider().padding(.vertical, 8 * scale)
                agendaList
            }

            Divider().padding(.top, 8 * scale)
            bottomBar
                .padding(.top, 6 * scale)
        }
        .padding(10 * scale)
        .frame(width: 7 * cellWidth + (settings.showWeekNumbers ? weekColumnWidth : 0) + 20 * scale)
        .background(keyboardShortcuts)
        .task(id: gridKey) {
            let days = gridDays
            if let first = days.first, let last = days.last,
               let end = cal.date(byAdding: .day, value: 1, to: last) {
                store.setGrid(start: first, end: end)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aleCalPopoverWillShow)) { _ in
            goToday()
            newEventDate = nil
            showMonthPicker = false
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6 * scale) {
            // Month title & picker toggle
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    showMonthPicker.toggle()
                }
            } label: {
                HStack(spacing: 4 * scale) {
                    Text(monthTitle)
                        .font(.system(size: 13.5 * scale, weight: .bold))
                        .foregroundStyle(.primary)

                    Image(systemName: showMonthPicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 3 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(showMonthPicker ? Color.primary.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .help(L("calendar.jumpToMonth"))

            Spacer()

            // Today button
            Button {
                goToday()
                showMonthPicker = false
            } label: {
                HStack(spacing: 3 * scale) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 10 * scale))
                    Text(L("calendar.today"))
                        .font(.system(size: 10.5 * scale, weight: .semibold))
                }
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 3 * scale)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.12))
                )
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(L("calendar.today"))

            // Month navigation chevrons
            HStack(spacing: 2 * scale) {
                Button {
                    shiftMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .frame(width: 22 * scale, height: 22 * scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(L("calendar.previousMonth"))

                Button {
                    shiftMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .frame(width: 22 * scale, height: 22 * scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(L("calendar.nextMonth"))
            }
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("LLLLy")
        return formatter.string(from: month)
    }

    // MARK: Month/Year Picker

    private var monthYearPicker: some View {
        let currentYear = cal.component(.year, from: month)
        let months = cal.shortMonthSymbols

        return VStack(spacing: 8 * scale) {
            // Year navigation
            HStack {
                Button {
                    shiftYear(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(String(currentYear))
                    .font(.system(size: 13 * scale, weight: .bold))

                Spacer()

                Button {
                    shiftYear(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12 * scale)

            // 12 Months Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4 * scale), count: 3), spacing: 6 * scale) {
                ForEach(0..<12, id: \.self) { index in
                    let isCurrent = cal.component(.month, from: month) == (index + 1)
                    Button {
                        jumpToMonth(index + 1)
                        withAnimation { showMonthPicker = false }
                    } label: {
                        Text(months[index])
                            .font(.system(size: 11 * scale, weight: isCurrent ? .bold : .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6 * scale)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isCurrent ? Color.accentColor : Color.primary.opacity(0.04))
                            )
                            .foregroundStyle(isCurrent ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8 * scale)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func jumpToMonth(_ newMonth: Int) {
        var comps = cal.dateComponents([.year], from: month)
        comps.month = newMonth
        comps.day = 1
        if let newDate = cal.date(from: comps) {
            month = newDate
        }
    }

    private func shiftYear(_ delta: Int) {
        if let newDate = cal.date(byAdding: .year, value: delta, to: month) {
            month = newDate
        }
    }

    // MARK: Weekday Row

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            if settings.showWeekNumbers {
                Text(L("calendar.weekShort"))
                    .frame(width: weekColumnWidth)
                    .foregroundStyle(.tertiary)
            }
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .frame(width: cellWidth)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10 * scale, weight: .semibold))
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.shortStandaloneWeekdaySymbols
        let shift = cal.firstWeekday - 1
        let rotated = Array(symbols[shift...] + symbols[..<shift])
        return rotated.map { String($0.prefix(2)) }
    }

    // MARK: Month Grid

    private var gridDays: [Date] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let weekday = cal.component(.weekday, from: monthStart)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -offset, to: monthStart) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var gridKey: String {
        let comps = cal.dateComponents([.year, .month], from: month)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(cal.firstWeekday)-\(store.revision)-\(store.access == .authorized)"
    }

    private var monthGrid: some View {
        let days = gridDays
        return VStack(spacing: 1 * scale) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    if settings.showWeekNumbers, days.count == 42 {
                        Text(weekNumber(for: days[row * 7 + 3]))
                            .font(.system(size: 9 * scale).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: weekColumnWidth, height: cellHeight)
                    }
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column
                        if index < days.count {
                            dayCell(days[index])
                        }
                    }
                }
            }
        }
    }

    private func weekNumber(for day: Date) -> String {
        let iso = Calendar(identifier: .iso8601)
        return String(iso.component(.weekOfYear, from: day))
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isWeekend = cal.isDateInWeekend(day)
        let colors = store.eventColors(on: day)
        let hasEvents = !colors.isEmpty || store.hasEvents(on: day)
        let number = String(cal.component(.day, from: day))
        let isHovered = hoveredDay.map { cal.isDate($0, inSameDayAs: day) } ?? false

        return VStack(spacing: 1 * scale) {
            Text(number)
                .font(.system(size: 12 * scale, weight: isToday ? .bold : .medium).monospacedDigit())
                .foregroundStyle(dayTextColor(inMonth: inMonth, isToday: isToday))
                .frame(width: 22 * scale, height: 20 * scale)
                .background {
                    if isToday {
                        Circle().fill(Color.accentColor)
                    } else if isSelected {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    } else if isHovered {
                        Circle().fill(Color.primary.opacity(0.06))
                    }
                }

            // Event Dots
            if settings.showEventDots && hasEvents {
                if settings.multiColorDots && !colors.isEmpty {
                    HStack(spacing: 2 * scale) {
                        ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, nsColor in
                            Circle()
                                .fill(Color(nsColor: nsColor).opacity(inMonth ? 1.0 : 0.45))
                                .frame(width: 3.5 * scale, height: 3.5 * scale)
                        }
                    }
                    .frame(height: 4 * scale)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(inMonth ? 0.9 : 0.4))
                        .frame(width: 4 * scale, height: 4 * scale)
                }
            } else {
                Spacer().frame(height: 4 * scale)
            }
        }
        .frame(width: cellWidth, height: cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isWeekend && settings.highlightWeekend ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredDay = hovering ? day : nil
        }
        .onTapGesture(count: 2) {
            select(day)
            if store.access == .authorized { newEventDate = day }
        }
        .onTapGesture {
            select(day)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDate(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dayTextColor(inMonth: Bool, isToday: Bool) -> Color {
        if isToday { return .white }
        return inMonth ? .primary : .secondary.opacity(0.4)
    }

    private func accessibilityDate(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateStyle = .full
        return formatter.string(from: day)
    }

    // MARK: Agenda

    private var agendaList: some View {
        let groups = store.agenda(from: selected, days: settings.eventDays, calendar: cal)
        let rowCount = groups.reduce(0) { $0 + $1.events.count }
        let estimated = CGFloat(groups.count) * 26 * scale
            + CGFloat(rowCount) * (settings.showLocation ? 52 : 40) * scale

        return Group {
            if groups.isEmpty {
                VStack(spacing: 6 * scale) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 24 * scale))
                        .foregroundStyle(Color.accentColor.opacity(0.8))

                    Text(L("agenda.noEventsTitle"))
                        .font(.system(size: 12 * scale, weight: .semibold))

                    Text(L("agenda.noEventsSubtitle"))
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.02))
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6 * scale) {
                        ForEach(groups) { group in
                            dayHeaderView(group.day, count: group.events.count)
                                .padding(.top, 2 * scale)

                            ForEach(group.events, id: \.calendarItemExternalIdentifierOrID) { event in
                                EventRow(event: event, day: group.day)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(estimated, 280 * scale))
            }
        }
    }

    private func dayHeaderView(_ day: Date, count: Int) -> some View {
        let isToday = cal.isDateInToday(day)
        let isTomorrow = cal.isDateInTomorrow(day)

        return HStack(spacing: 6 * scale) {
            if isToday {
                Text(L("agenda.today"))
                    .font(.system(size: 10 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(Capsule().fill(Color.accentColor))
            } else if isTomorrow {
                Text(L("agenda.tomorrow"))
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }

            Text(formattedDayHeader(day))
                .font(.system(size: 11 * scale, weight: .semibold))
                .foregroundStyle(isToday ? .primary : .secondary)

            Spacer()

            Text(count == 1 ? L("agenda.eventCountSingle") : L("agenda.eventsCount", count))
                .font(.system(size: 9.5 * scale))
                .foregroundStyle(.tertiary)
        }
    }

    private func formattedDayHeader(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: day)
    }

    private var accessBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("access.denied.title"))
                .font(.system(size: 11 * scale, weight: .semibold))
            Text(L("access.denied.body"))
                .font(.system(size: 10 * scale))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L("access.denied.button")) { store.openPrivacySettings() }
                .controlSize(.small)
        }
        .padding(8 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.15)))
    }

    // MARK: Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 8 * scale) {
            // New Event Button
            Button {
                newEventDate = selected
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11 * scale, weight: .bold))
                    .frame(width: 22 * scale, height: 22 * scale)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help(L("toolbar.newEvent"))
            .disabled(store.access != .authorized || newEventDate != nil)

            // Open System Calendar
            Button {
                openCalendarApp()
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 11 * scale, weight: .medium))
                    .frame(width: 22 * scale, height: 22 * scale)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help(L("toolbar.openCalendar"))

            Spacer()

            // Selected Date Pill (click to jump today)
            Button {
                goToday()
            } label: {
                Text(selectedTitle)
                    .font(.system(size: 10.5 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 3 * scale)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help(L("calendar.today"))

            Spacer()

            // Settings Menu
            Menu {
                Button(L("menu.preferences")) { onOpenPreferences() }
                Divider()
                Button(L("toolbar.openCalendar")) { openCalendarApp() }
                Divider()
                Button(L("menu.quit")) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11 * scale, weight: .medium))
                    .frame(width: 22 * scale, height: 22 * scale)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help(L("toolbar.settings"))
        }
    }

    private var selectedTitle: String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateStyle = .medium
        return formatter.string(from: selected)
    }

    // MARK: Keyboard

    @ViewBuilder
    private var keyboardShortcuts: some View {
        if newEventDate == nil {
            Group {
                Button("") { move(days: -1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { move(days: 1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { move(days: -7) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { move(days: 7) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("") { shiftMonth(-1) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button("") { shiftMonth(1) }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("") { goToday() }.keyboardShortcut("t", modifiers: [])
                Button("") {
                    if store.access == .authorized { newEventDate = selected }
                }.keyboardShortcut("n", modifiers: .command)
                Button("") { onOpenPreferences() }.keyboardShortcut(",", modifiers: .command)
                Button("") { onClose() }.keyboardShortcut(.escape, modifiers: [])
                Button("") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    // MARK: Navigation

    private func select(_ day: Date) {
        selected = cal.startOfDay(for: day)
        if !cal.isDate(day, equalTo: month, toGranularity: .month) {
            month = day
        }
    }

    private func move(days: Int) {
        if let day = cal.date(byAdding: .day, value: days, to: selected) {
            select(day)
        }
    }

    private func shiftMonth(_ delta: Int) {
        guard let newMonth = cal.date(byAdding: .month, value: delta, to: month) else { return }
        month = newMonth
        if let newSelected = cal.date(byAdding: .month, value: delta, to: selected) {
            selected = cal.startOfDay(for: newSelected)
        }
    }

    private func goToday() {
        let today = cal.startOfDay(for: Date())
        month = today
        selected = today
    }

    private func openCalendarApp() {
        let url = URL(fileURLWithPath: "/System/Applications/Calendar.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        onClose()
    }
}

extension EKEvent {
    var calendarItemExternalIdentifierOrID: String {
        "\(eventIdentifier ?? calendarItemIdentifier)-\(startDate.timeIntervalSinceReferenceDate)"
    }
}
