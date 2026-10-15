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
            HStack(spacing: 8) {
                ForEach(PreferencesTab.allCases) { item in
                    tabButton(item)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch tab {
                case .general: GeneralPane()
                case .appearance: AppearancePane()
                case .about: AboutPane()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(width: 520, alignment: .topLeading)
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
        .foregroundStyle(isSelected ? settings.accentColor : Color.secondary)
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
                .frame(maxWidth: 240)

                Picker(L("prefs.accentColor"), selection: $settings.accentTheme) {
                    ForEach(AccentTheme.allCases) { theme in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 10, height: 10)
                            Text(L(theme.labelKey))
                        }
                        .tag(theme)
                    }
                }
                .frame(maxWidth: 240)

                Picker(L("prefs.textSize"), selection: $settings.textSize) {
                    ForEach(TextSize.allCases) { size in
                        Text(L(size.labelKey)).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

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
        .padding(.bottom, 14)
    }

    private var previewText: String {
        let text = settings.menuBarTitle(for: Date())
        return text.isEmpty ? L("prefs.clockFormat.iconOnly") : L("prefs.clockFormat.preview", text)
    }
}

// MARK: - Open Source Card

struct OpenSourceCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                        .frame(width: 24, height: 24)
                    Text("{}")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                Text("Open Source | Free to Fork & Use")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
            }

            Text("Feel free to fork, modify, use, and contribute!")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Developed by:")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("SoftAI Yazılım")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                }
                HStack(spacing: 6) {
                    Text("Developer:")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("Assoc. Prof. Dr. Mehmet Akif Cifci")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                }
                HStack(spacing: 6) {
                    Text("GitHub:")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Link("@themanoftalent", destination: URL(string: "https://github.com/themanoftalent")!)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Follow & Support Card

struct FollowSupportCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("❤️")
                    .font(.system(size: 16))
                Text("Follow & Support")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
            }

            Text("If you find this project useful, star the repository, follow me, or buy me a coffee! Your support helps keep future projects free and open-source.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                // Button 1: GitHub
                Link(destination: URL(string: "https://github.com/themanoftalent/alecal")!) {
                    HStack(spacing: 6) {
                        Text("</>")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                        Text("GitHub")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.4), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Button 2: Sponsor Me
                Link(destination: URL(string: "https://github.com/sponsors/themanoftalent")!) {
                    HStack(spacing: 6) {
                        Text("❤️")
                            .font(.system(size: 12))
                        Text("Sponsor Me")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.red.opacity(0.4), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Button 3: Buy Me a Coffee
                Link(destination: URL(string: "https://buymeacoffee.com/themanoftalent")!) {
                    HStack(spacing: 6) {
                        Text("☕")
                            .font(.system(size: 12))
                        Text("Buy Me a Coffee")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - About Pane

@MainActor
struct AboutPane: View {
    var body: some View {
        VStack(spacing: 16) {
            // Header: Icon, Name, Version, Tagline
            VStack(spacing: 6) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 68, height: 68)
                        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                } else {
                    Image(systemName: "calendar")
                        .font(.system(size: 50))
                        .foregroundColor(.accentColor)
                }

                VStack(spacing: 3) {
                    Text("AleCal")
                        .font(.system(size: 20, weight: .bold))
                    Text("\(AppInfo.version) (\(AppInfo.build))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text(L("about.tagline"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            // Card 1: Open Source | Free to Fork & Use
            OpenSourceCard()

            // Card 2: Follow & Support
            FollowSupportCard()

            Spacer().frame(height: 2)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

