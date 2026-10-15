import AppKit
import EventKit
import SwiftUI

/// One event in the agenda, styled as a modern card with calendar accent, status badge,
/// quick join button for video meetings, and a context menu.
@MainActor
struct EventRow: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: EventStore

    let event: EKEvent
    let day: Date

    @State private var isHovered = false
    private var scale: CGFloat { settings.textSize.scale }

    var body: some View {
        let meeting = MeetingLink.find(in: event)
        let status = currentStatus
        let calColor = sanitizePinkColor(event.calendar.color)

        HStack(alignment: .top, spacing: 8 * scale) {
            // Calendar color bar
            Capsule()
                .fill(Color(nsColor: calColor))
                .frame(width: 3.5 * scale)
                .padding(.vertical, 2 * scale)

            // Event Details
            VStack(alignment: .leading, spacing: 3 * scale) {
                // Title and status badge
                HStack(spacing: 5 * scale) {
                    Text(title)
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if settings.showRelativeTime, let status {
                        statusBadge(status)
                    }

                    Spacer(minLength: 0)
                }

                // Time and Calendar tag
                HStack(spacing: 6 * scale) {
                    Text(timeText)
                        .font(.system(size: 10.5 * scale, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text(event.calendar.title)
                        .font(.system(size: 9.5 * scale, weight: .medium))
                        .foregroundStyle(Color(nsColor: calColor))
                        .padding(.horizontal, 5 * scale)
                        .padding(.vertical, 1 * scale)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: calColor).opacity(0.12))
                        )
                        .lineLimit(1)
                }

                // Location if present
                if settings.showLocation, let location = event.location, !location.isEmpty {
                    HStack(spacing: 3 * scale) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 9 * scale))
                        Text(location)
                            .font(.system(size: 10 * scale))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            // Meeting Join Button
            if let meeting, settings.showMeetingButton {
                Button {
                    NSWorkspace.shared.open(meeting)
                } label: {
                    HStack(spacing: 3 * scale) {
                        Image(systemName: "video.fill")
                        Text(L("event.joinShort"))
                    }
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .padding(.horizontal, 7 * scale)
                    .padding(.vertical, 3.5 * scale)
                    .background(
                        Capsule()
                            .fill(status == .active ? Color.green : settings.accentColor)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help(L("event.join"))
            }
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 6 * scale)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.02))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            openInCalendar()
        }
        .help(helpText)
        .contextMenu {
            if let meeting {
                Button(L("event.join")) { NSWorkspace.shared.open(meeting) }
                Button(L("event.copyMeetingLink")) { copyMeetingLink(meeting) }
                Divider()
            }
            Button(L("event.openCalendar")) { openInCalendar() }
            Button(L("event.copy")) { copyDetails() }
            if event.calendar.allowsContentModifications {
                Divider()
                Button(L("event.delete"), role: .destructive) { confirmDelete(span: .thisEvent) }
                if event.hasRecurrenceRules {
                    Button(L("event.deleteFuture"), role: .destructive) { confirmDelete(span: .futureEvents) }
                }
            }
        }
    }

    private var title: String {
        let raw = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? L("event.untitled") : raw
    }

    private enum EventStatus: Equatable {
        case active
        case startingSoon(minutes: Int)
    }

    private var currentStatus: EventStatus? {
        guard !event.isAllDay else { return nil }
        let now = Date()
        let cal = settings.calendar
        guard cal.isDateInToday(day) else { return nil }

        if event.startDate <= now && event.endDate >= now {
            return .active
        }
        let diff = event.startDate.timeIntervalSince(now)
        if diff > 0 && diff <= 3600 {
            let minutes = max(1, Int(ceil(diff / 60)))
            return .startingSoon(minutes: minutes)
        }
        return nil
    }

    @ViewBuilder
    private func statusBadge(_ status: EventStatus) -> some View {
        switch status {
        case .active:
            HStack(spacing: 3 * scale) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5 * scale, height: 5 * scale)
                Text(L("event.now"))
                    .font(.system(size: 9 * scale, weight: .bold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 5 * scale)
            .padding(.vertical, 1 * scale)
            .background(Capsule().fill(Color.green.opacity(0.12)))

        case .startingSoon(let minutes):
            Text(L("event.inMinutes", minutes))
                .font(.system(size: 9 * scale, weight: .semibold))
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 5 * scale)
                .padding(.vertical, 1 * scale)
                .background(Capsule().fill(Color.orange.opacity(0.12)))
        }
    }

    private var timeText: String {
        let cal = settings.calendar
        if event.isAllDay { return L("event.allDay") }
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let startsToday = cal.isDate(event.startDate, inSameDayAs: day)
        let endsToday = cal.isDate(event.endDate, inSameDayAs: day)
        let start = startsToday ? formatter.string(from: event.startDate) : "…"
        let end = endsToday ? formatter.string(from: event.endDate) : "…"
        if event.startDate == event.endDate { return start }
        return "\(start) – \(end)"
    }

    private var helpText: String {
        var lines = [title]
        lines.append(event.calendar.title)
        if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            lines.append(String(notes.prefix(300)))
        }
        return lines.joined(separator: "\n")
    }

    private func openInCalendar() {
        let url = URL(fileURLWithPath: "/System/Applications/Calendar.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    private func copyMeetingLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func copyDetails() {
        var text = "\(title)\n\(timeText)"
        if let location = event.location, !location.isEmpty { text += "\n\(location)" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func confirmDelete(span: EKSpan) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("delete.confirm.title", title)
        alert.informativeText = span == .futureEvents ? L("delete.confirm.future") : L("delete.confirm.body")
        alert.addButton(withTitle: L("delete.confirm.delete"))
        alert.addButton(withTitle: L("common.cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.delete(event, span: span)
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
        }
    }
}

/// Finds video call links in an event's URL, location, or notes.
enum MeetingLink {
    private static let hosts = [
        "zoom.us", "zoomgov.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "meet.jit.si", "facetime.apple.com", "gotomeeting.com",
        "chime.aws", "bluejeans.com", "slack.com", "discord.com", "discord.gg", "skype.com",
        "ringcentral.com", "tandem.chat", "around.co", "tuple.app"
    ]

    static func find(in event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, isMeeting(url) { return url }
        }
        return nil
    }

    private static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
