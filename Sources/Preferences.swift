import AppKit
import EventKit
import SwiftUI

enum AppInfo {
    // Update these when the SoftAI site moves to its new domain.
    static let websiteURL = URL(string: "https://soft-ai-gilt.vercel.app")!
    static let helpURL = URL(string: "https://soft-ai-gilt.vercel.app")!
    static let dateFormatReference = URL(string: "https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    convenience init(settings: AppSettings, store: EventStore) {
        let root = PreferencesView()
            .environmentObject(settings)
            .environmentObject(store)
        // Default sizing options pin the window to the SwiftUI content, so it resizes per tab.
        let hosting = NSHostingController(rootView: root)

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "AleCal"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
struct PreferencesView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var tab: PreferencesTab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(PreferencesTab.allCases) { item in
                    tabButton(item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            Group {
                switch tab {
                case .general: GeneralPane()
                case .appearance: AppearancePane()
                case .about: AboutPane()
                }
            }
            .padding(20)
            .frame(width: 440, alignment: .topLeading)
        }
    }

    private func tabButton(_ item: PreferencesTab) -> some View {
        let isSelected = tab == item
        return VStack(spacing: 4) {
            Image(systemName: item.symbol)
                .font(.system(size: 22, weight: .regular))
                .frame(height: 26)
            Text(L(item.labelKey))
                .font(.system(size: 12))
        }
        .frame(width: 100, height: 58)
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { tab = item }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general, appearance, about
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .about: return "info.circle"
        }
    }

    var labelKey: String { "prefs.tab.\(rawValue)" }
}

// MARK: General

@MainActor
struct GeneralPane: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: EventStore

    var body: some View {
        Form {
            Toggle(L("prefs.launchAtLogin"), isOn: $settings.launchAtLogin)

            LabeledContent(L("prefs.shortcut")) {
                ShortcutRecorder()
            }

            Picker(L("prefs.firstWeekday"), selection: $settings.firstWeekday) {
                ForEach(1...7, id: \.self) { day in
                    Text(weekdayName(day)).tag(day)
                }
            }

            LabeledContent(L("prefs.eventDays")) {
                Stepper(value: $settings.eventDays, in: 0...31) {
                    Text(eventDaysLabel)
                        .monospacedDigit()
                }
            }

            Picker(L("prefs.language"), selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(L(language.labelKey)).tag(language)
                }
            }

            LabeledContent(L("prefs.calendars")) {
                calendarList
            }
        }
        .formStyle(.columns)
    }

    private var eventDaysLabel: String {
        switch settings.eventDays {
        case 0: return L("prefs.eventDays.none")
        case 1: return L("prefs.eventDays.one")
        default: return L("prefs.eventDays.many", settings.eventDays)
        }
    }

    private func weekdayName(_ day: Int) -> String {
        var cal = Calendar.current
        cal.locale = L10n.locale
        return cal.standaloneWeekdaySymbols[day - 1]
    }

    @ViewBuilder
    private var calendarList: some View {
        switch store.access {
        case .authorized:
            let calendars = store.calendars
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(groupedSources(calendars), id: \.self) { source in
                        Text(source)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(calendars.filter { $0.source.title == source }, id: \.calendarIdentifier) { cal in
                            Toggle(isOn: visibilityBinding(for: cal.calendarIdentifier)) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(nsColor: cal.color))
                                        .frame(width: 8, height: 8)
                                    Text(cal.title)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: min(CGFloat(calendars.count) * 22 + CGFloat(groupedSources(calendars).count) * 22, 180))
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Text(L("access.denied.body"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("access.denied.button")) { store.openPrivacySettings() }
            }
        case .notDetermined:
            Button(L("access.request")) {
                Task { await store.requestAccessIfNeeded() }
            }
        }
    }

    private func groupedSources(_ calendars: [EKCalendar]) -> [String] {
        var seen = Set<String>()
        return calendars.map(\.source.title).filter { seen.insert($0).inserted }
    }

    private func visibilityBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !settings.hiddenCalendarIDs.contains(id) },
            set: { visible in
                if visible {
                    settings.hiddenCalendarIDs.remove(id)
                } else {
                    settings.hiddenCalendarIDs.insert(id)
                }
            }
        )
    }
}

/// Records a global shortcut. Esc cancels, at least one of ⌘ ⌥ ⌃ is required.
@MainActor
struct ShortcutRecorder: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(buttonTitle) {
                recording ? stop() : start()
            }
            .frame(minWidth: 140)
            if !settings.hotKeyDisplay.isEmpty && !recording {
                Button {
                    settings.clearHotKey()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("prefs.shortcut.clear"))
            }
        }
        .onDisappear(perform: stop)
    }

    private var buttonTitle: String {
        if recording { return L("prefs.shortcut.recording") }
        return settings.hotKeyDisplay.isEmpty ? L("prefs.shortcut.record") : settings.hotKeyDisplay
    }

    private func start() {
        recording = true
        GlobalHotKey.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Copy the Sendable parts out of the event, then handle them on the main actor.
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let characters = event.charactersIgnoringModifiers ?? ""
            MainActor.assumeIsolated {
                handleKey(keyCode: keyCode, flags: flags, characters: characters)
            }
            return nil
        }
    }

    private func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String) {
        if keyCode == 53 { // Esc
            stop()
            return
        }
        guard !flags.intersection([.command, .option, .control]).isEmpty else {
            NSSound.beep()
            return
        }
        settings.setHotKey(keyCode: UInt32(keyCode), flags: flags, characters: characters)
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            GlobalHotKey.shared.register(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
        }
    }
}

// MARK: Appearance

@MainActor
struct AppearancePane: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(L("prefs.showMonth"), isOn: $settings.showMonth)
                Toggle(L("prefs.showDayOfWeek"), isOn: $settings.showDayOfWeek)
                Toggle(L("prefs.outlineIcon"), isOn: $settings.outlineIcon)
                Toggle(L("prefs.hideIcon"), isOn: $settings.hideIcon)
                    .help(L("prefs.hideIcon.help"))
                LabeledContent(L("prefs.clockFormat")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(L("prefs.clockFormat.placeholder"), text: $settings.clockFormat)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        HStack(spacing: 4) {
                            Text(previewText)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Link(L("prefs.clockFormat.reference"), destination: AppInfo.dateFormatReference)
                        }
                        .font(.system(size: 11))
                    }
                }
            } header: {
                Text(L("prefs.section.menuBar")).font(.headline)
            }

            Section {
                Picker(L("prefs.theme"), selection: $settings.theme) {
                    ForEach(Theme.allCases) { theme in
                        Text(L(theme.labelKey)).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Picker(L("prefs.textSize"), selection: $settings.textSize) {
                    ForEach(TextSize.allCases) { size in
                        Text(L(size.labelKey)).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Toggle(L("prefs.weekNumbers"), isOn: $settings.showWeekNumbers)
                Toggle(L("prefs.highlightWeekend"), isOn: $settings.highlightWeekend)
                Toggle(L("prefs.eventDots"), isOn: $settings.showEventDots)
                if settings.showEventDots {
                    Toggle(L("prefs.multiColorDots"), isOn: $settings.multiColorDots)
                        .padding(.leading, 16)
                }
                Toggle(L("prefs.showLocation"), isOn: $settings.showLocation)
                Toggle(L("prefs.showRelativeTime"), isOn: $settings.showRelativeTime)
                Toggle(L("prefs.showMeetingButton"), isOn: $settings.showMeetingButton)
            } header: {
                Text(L("prefs.section.calendar")).font(.headline)
                    .padding(.top, 10)
            }
        }
        .formStyle(.columns)
    }

    private var previewText: String {
        let text = settings.menuBarTitle(for: Date())
        return text.isEmpty ? L("prefs.clockFormat.iconOnly") : L("prefs.clockFormat.preview", text)
    }
}

// MARK: About

@MainActor
struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("AleCal")
                            .font(.system(size: 22, weight: .bold))
                        Text("\(AppInfo.version) (\(AppInfo.build))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(L("about.tagline"))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("about.whatsnew.title"))
                    .font(.system(size: 12, weight: .semibold))
                Text(L("about.whatsnew.body"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )

            VStack(alignment: .leading, spacing: 10) {
                Link(destination: AppInfo.helpURL) {
                    Label(L("about.help"), systemImage: "questionmark.circle")
                }
                Link(destination: AppInfo.websiteURL) {
                    Label(L("about.website"), systemImage: "globe")
                }
            }
            .font(.system(size: 13))

            Text("© 2026 SoftAI Yazılım")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
