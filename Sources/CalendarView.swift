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
    @State private var isHoveringPlus = false
    @State private var isHoveringCalendar = false
    @State private var isHoveringDate = false

    private var cal: Calendar { settings.calendar }
    private var scale: CGFloat { settings.textSize.scale }
    private var cellWidth: CGFloat { 34 * scale }
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
        HStack(spacing: 4 * scale) {
            // Month title & picker toggle
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    showMonthPicker.toggle()
                }
            } label: {
                HStack(spacing: 3 * scale) {
                    Text(monthTitle)
                        .font(.system(size: 12 * scale, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .allowsTightening(true)
                        .foregroundStyle(settings.accentColor)

                    Image(systemName: showMonthPicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5 * scale, weight: .semibold))
                        .foregroundStyle(settings.accentColor.opacity(0.8))
                }
                .padding(.horizontal, 5 * scale)
                .padding(.vertical, 3 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(showMonthPicker ? settings.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
            .help(L("calendar.jumpToMonth"))

            Spacer(minLength: 4 * scale)

            // Today button
            Button {
                goToday()
                showMonthPicker = false
            } label: {
                HStack(spacing: 2.5 * scale) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 9.5 * scale))
                    Text(L("calendar.today"))
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 5 * scale)
                .padding(.vertical, 2.5 * scale)
                .background(
                    Capsule()
                        .fill(settings.accentColor.opacity(0.12))
                )
                .foregroundStyle(settings.accentColor)
            }
            .buttonStyle(.plain)
            .help(L("calendar.today"))

            // Month navigation chevrons
            HStack(spacing: 1 * scale) {
                Button {
                    shiftMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .frame(width: 20 * scale, height: 20 * scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(L("calendar.previousMonth"))

                Button {
                    shiftMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .frame(width: 20 * scale, height: 20 * scale)
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
                    .foregroundStyle(settings.accentColor)
                    .lineLimit(1)

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
                                    .fill(isCurrent ? settings.accentColor : Color.primary.opacity(0.04))
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
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                let weekday = (cal.firstWeekday - 1 + index) % 7 + 1
                let isWeekend = (weekday == 1 || weekday == 7)
                Text(symbol)
                    .frame(width: cellWidth)
                    .foregroundStyle(isWeekend && settings.highlightWeekend ? settings.accentColor.opacity(0.85) : .secondary)
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
                        Circle().fill(settings.accentColor)
                    } else if isSelected {
                        Circle()
                            .fill(settings.accentColor.opacity(0.18))
                            .overlay(Circle().strokeBorder(settings.accentColor, lineWidth: 1.5))
                    } else if isHovered {
                        Circle().fill(settings.accentColor.opacity(0.08))
                    }
                }

            // Event Dots
            if settings.showEventDots && hasEvents {
                if settings.multiColorDots && !colors.isEmpty {
                    HStack(spacing: 2 * scale) {
                        ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, nsColor in
                            let safeColor = sanitizePinkColor(nsColor)
                            Circle()
                                .fill(Color(nsColor: safeColor).opacity(inMonth ? 1.0 : 0.45))
                                .frame(width: 3.5 * scale, height: 3.5 * scale)
                        }
                    }
                    .frame(height: 4 * scale)
                } else {
                    Circle()
                        .fill(settings.accentColor.opacity(inMonth ? 0.9 : 0.4))
                        .frame(width: 4 * scale, height: 4 * scale)
                }
            } else {
                Spacer().frame(height: 4 * scale)
            }
        }
        .frame(width: cellWidth, height: cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isWeekend && settings.highlightWeekend ? settings.accentColor.opacity(0.06) : Color.clear)
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
                        .foregroundStyle(settings.accentColor.opacity(0.85))

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
                    .background(Capsule().fill(settings.accentColor))
            } else if isTomorrow {
                Text(L("agenda.tomorrow"))
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(settings.accentColor)
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(Capsule().fill(settings.accentColor.opacity(0.12)))
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
                    .font(.system(size: 11.5 * scale, weight: .bold))
                    .frame(width: 26 * scale, height: 26 * scale)
                    .background(Circle().fill(Color.primary.opacity(isHoveringPlus ? 0.12 : 0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringPlus = $0 }
            .help(L("toolbar.newEvent"))
            .disabled(store.access != .authorized || newEventDate != nil)

            // Open System Calendar
            Button {
                openCalendarApp()
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 11.5 * scale, weight: .medium))
                    .frame(width: 26 * scale, height: 26 * scale)
                    .background(Circle().fill(Color.primary.opacity(isHoveringCalendar ? 0.12 : 0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringCalendar = $0 }
            .help(L("toolbar.openCalendar"))

            Spacer()

            // Selected Date Pill (click to jump today)
            Button {
                goToday()
            } label: {
                Text(selectedTitle)
                    .font(.system(size: 11 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10 * scale)
                    .padding(.vertical, 4 * scale)
                    .background(Capsule().fill(Color.primary.opacity(isHoveringDate ? 0.10 : 0.05)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringDate = $0 }
            .help(L("calendar.today"))

            Spacer()

            // Settings Gear Menu Button (Native AppKit instant response on click)
            SettingsGearButton(
                scale: scale,
                onOpenPreferences: onOpenPreferences,
                onOpenCalendar: { openCalendarApp() }
            )
            .frame(width: 26 * scale, height: 26 * scale)
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

// MARK: - Settings Gear Menu Button (Native AppKit)

@MainActor
struct SettingsGearButton: NSViewRepresentable {
    let scale: CGFloat
    let onOpenPreferences: () -> Void
    let onOpenCalendar: () -> Void

    func makeNSView(context: Context) -> SettingsNSButton {
        let button = SettingsNSButton()
        button.scale = scale
        button.onOpenPreferences = onOpenPreferences
        button.onOpenCalendar = onOpenCalendar
        button.toolTip = L("toolbar.settings")
        return button
    }

    func updateNSView(_ button: SettingsNSButton, context: Context) {
        button.scale = scale
        button.onOpenPreferences = onOpenPreferences
        button.onOpenCalendar = onOpenCalendar
        button.toolTip = L("toolbar.settings")
        button.needsDisplay = true
    }
}

final class SettingsNSButton: NSButton {
    var scale: CGFloat = 1.0
    var onOpenPreferences: (() -> Void)?
    var onOpenCalendar: (() -> Void)?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw smooth circular background
        let circlePath = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        let alpha: CGFloat = isHovered ? 0.12 : 0.06
        NSColor.labelColor.withAlphaComponent(alpha).setFill()
        circlePath.fill()

        // Draw gearshape SF Symbol centered
        let pointSize: CGFloat = max(11, 11.5 * scale)
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(.init(hierarchicalColor: NSColor.labelColor))
        if let img = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?.withSymbolConfiguration(config) {
            let imgSize = img.size
            let rect = NSRect(
                x: (bounds.width - imgSize.width) / 2,
                y: (bounds.height - imgSize.height) / 2,
                width: imgSize.width,
                height: imgSize.height
            )
            img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    override func mouseDown(with event: NSEvent) {
        showMenu()
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let prefsItem = NSMenuItem(
            title: L("menu.preferences"),
            action: #selector(handleOpenPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let calItem = NSMenuItem(
            title: L("toolbar.openCalendar"),
            action: #selector(handleOpenCalendar),
            keyEquivalent: ""
        )
        calItem.target = self
        menu.addItem(calItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: self)
    }

    @objc private func handleOpenPreferences() {
        onOpenPreferences?()
    }

    @objc private func handleOpenCalendar() {
        onOpenCalendar?()
    }
}

