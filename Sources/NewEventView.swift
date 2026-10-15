import EventKit
import SwiftUI

/// Inline form for creating a new event, styled as a modern macOS card with duration presets,
/// calendar color cues, and keyboard shortcuts.
@MainActor
struct NewEventView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: EventStore

    let initialDate: Date
    let onDone: () -> Void

    @State private var title = ""
    @State private var allDay = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var duration: TimeInterval = 3600
    @State private var location = ""
    @State private var calendarID = ""
    @State private var repeatOption: RepeatOption = .none
    @State private var alert: AlertOption = .none
    @State private var errorText: String?
    @FocusState private var titleFocused: Bool

    private var scale: CGFloat { settings.textSize.scale }

    private var selectedCalendar: EKCalendar? {
        store.writableCalendars.first { $0.calendarIdentifier == calendarID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            // Header with Calendar indicator
            HStack(spacing: 6 * scale) {
                if let cal = selectedCalendar {
                    Circle()
                        .fill(Color(nsColor: cal.color))
                        .frame(width: 8 * scale, height: 8 * scale)
                }
                Text(L("newEvent.heading"))
                    .font(.system(size: 13 * scale, weight: .bold))

                Spacer()

                Button {
                    onDone()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13 * scale))
                }
                .buttonStyle(.plain)
                .help(L("common.cancel"))
            }

            // Title Input
            TextField(L("newEvent.title"), text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12 * scale))
                .focused($titleFocused)
                .onSubmit(save)

            // Duration preset buttons
            HStack(spacing: 4 * scale) {
                durationButton(label: "15m", seconds: 900)
                durationButton(label: "30m", seconds: 1800)
                durationButton(label: "1h", seconds: 3600)
                durationButton(label: "2h", seconds: 7200)

                Button {
                    allDay.toggle()
                } label: {
                    Text(L("newEvent.allDay"))
                        .font(.system(size: 10 * scale, weight: allDay ? .bold : .medium))
                        .padding(.horizontal, 6 * scale)
                        .padding(.vertical, 2 * scale)
                        .background(
                            Capsule()
                                .fill(allDay ? settings.accentColor : Color.primary.opacity(0.06))
                        )
                        .foregroundStyle(allDay ? .white : .primary)
                }
                .buttonStyle(.plain)
            }

            // Date Pickers
            VStack(spacing: 4 * scale) {
                LabeledContent(L("newEvent.starts")) {
                    DatePicker("", selection: $start, displayedComponents: components)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
                if !allDay {
                    LabeledContent(L("newEvent.ends")) {
                        DatePicker("", selection: $end, in: start..., displayedComponents: components)
                            .labelsHidden()
                            .datePickerStyle(.field)
                    }
                }
            }
            .font(.system(size: 11 * scale))

            // Location
            HStack(spacing: 4 * scale) {
                Image(systemName: "mappin")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11 * scale))
                    .frame(width: 14 * scale)
                TextField(L("newEvent.location"), text: $location)
                    .textFieldStyle(.roundedBorder)
            }

            // Calendar Picker
            HStack(spacing: 4 * scale) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11 * scale))
                    .frame(width: 14 * scale)
                Picker("", selection: $calendarID) {
                    ForEach(store.writableCalendars, id: \.calendarIdentifier) { cal in
                        HStack {
                            Circle().fill(Color(nsColor: sanitizePinkColor(cal.color))).frame(width: 6, height: 6)
                            Text(cal.title)
                        }
                        .tag(cal.calendarIdentifier)
                    }
                }
                .labelsHidden()
            }

            // Repeat and Alert Pickers
            HStack(spacing: 8 * scale) {
                Picker(L("newEvent.repeat"), selection: $repeatOption) {
                    ForEach(RepeatOption.allCases) { option in
                        Text(L(option.labelKey)).tag(option)
                    }
                }

                Picker(L("newEvent.alert"), selection: $alert) {
                    ForEach(AlertOption.allCases) { option in
                        Text(L(option.labelKey)).tag(option)
                    }
                }
            }
            .font(.system(size: 10.5 * scale))

            if let errorText {
                Text(errorText)
                    .font(.system(size: 10.5 * scale))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Action Buttons
            HStack {
                Button(L("common.cancel"), action: onDone)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: save) {
                    Text(L("newEvent.save"))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8 * scale)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4 * scale)
        }
        .padding(10 * scale)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .font(.system(size: 11 * scale))
        .controlSize(scale < 1 ? .small : .regular)
        .onAppear(perform: prepare)
        .onChange(of: start) { _, newValue in
            end = newValue.addingTimeInterval(duration)
        }
        .onChange(of: end) { _, newValue in
            duration = max(newValue.timeIntervalSince(start), 0)
        }
    }

    private func durationButton(label: String, seconds: TimeInterval) -> some View {
        let isSelected = !allDay && abs(duration - seconds) < 60
        return Button {
            allDay = false
            duration = seconds
            end = start.addingTimeInterval(seconds)
        } label: {
            Text(label)
                .font(.system(size: 10 * scale, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 2 * scale)
                .background(
                    Capsule()
                        .fill(isSelected ? settings.accentColor : Color.primary.opacity(0.06))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var components: DatePickerComponents {
        allDay ? [.date] : [.date, .hourAndMinute]
    }

    private func prepare() {
        let cal = settings.calendar
        let day = cal.startOfDay(for: initialDate)
        let now = Date()
        if cal.isDateInToday(day) {
            let hour = cal.component(.hour, from: now)
            start = cal.date(bySettingHour: min(hour + 1, 23), minute: 0, second: 0, of: day) ?? now
        } else {
            start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        duration = 3600
        end = start.addingTimeInterval(duration)
        calendarID = store.defaultCalendar?.calendarIdentifier ?? store.writableCalendars.first?.calendarIdentifier ?? ""
        titleFocused = true
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let target = store.writableCalendars.first { $0.calendarIdentifier == calendarID }
        do {
            try store.createEvent(
                title: trimmed,
                start: start,
                end: end,
                allDay: allDay,
                calendar: target,
                location: location,
                repeatOption: repeatOption,
                alert: alert
            )
            onDone()
        } catch let error as EventStoreError {
            errorText = error.message
        } catch {
            errorText = error.localizedDescription
        }
    }
}
