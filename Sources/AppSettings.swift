import AppKit
import Combine
import ServiceManagement

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, turkish
    var id: String { rawValue }

    /// lproj folder name, nil means follow the system.
    var code: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .turkish: return "tr"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .english: return "en_US"
        case .turkish: return "tr_TR"
        }
    }

    var labelKey: String {
        switch self {
        case .system: return "prefs.language.system"
        case .english: return "prefs.language.english"
        case .turkish: return "prefs.language.turkish"
        }
    }
}

enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    var labelKey: String { "prefs.theme.\(rawValue)" }
}

enum TextSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.15
        }
    }

    var labelKey: String { "prefs.textSize.\(rawValue)" }
}

/// Single source of truth for user preferences. Every property persists to UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let titleFormatter = DateFormatter()

    // Menu bar
    @Published var showMonth: Bool { didSet { defaults.set(showMonth, forKey: "showMonth") } }
    @Published var showDayOfWeek: Bool { didSet { defaults.set(showDayOfWeek, forKey: "showDayOfWeek") } }
    @Published var hideIcon: Bool { didSet { defaults.set(hideIcon, forKey: "hideIcon") } }
    @Published var outlineIcon: Bool { didSet { defaults.set(outlineIcon, forKey: "outlineIcon") } }
    @Published var clockFormat: String { didSet { defaults.set(clockFormat, forKey: "clockFormat") } }

    // Calendar
    @Published var firstWeekday: Int { didSet { defaults.set(firstWeekday, forKey: "firstWeekday") } }
    @Published var showWeekNumbers: Bool { didSet { defaults.set(showWeekNumbers, forKey: "showWeekNumbers") } }
    @Published var highlightWeekend: Bool { didSet { defaults.set(highlightWeekend, forKey: "highlightWeekend") } }
    @Published var showEventDots: Bool { didSet { defaults.set(showEventDots, forKey: "showEventDots") } }
    @Published var showLocation: Bool { didSet { defaults.set(showLocation, forKey: "showLocation") } }
    @Published var eventDays: Int { didSet { defaults.set(eventDays, forKey: "eventDays") } }
    @Published var hiddenCalendarIDs: Set<String> {
        didSet { defaults.set(Array(hiddenCalendarIDs), forKey: "hiddenCalendarIDs") }
    }

    // Look
    @Published var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var textSize: TextSize { didSet { defaults.set(textSize.rawValue, forKey: "textSize") } }
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    @Published var multiColorDots: Bool { didSet { defaults.set(multiColorDots, forKey: "multiColorDots") } }
    @Published var showRelativeTime: Bool { didSet { defaults.set(showRelativeTime, forKey: "showRelativeTime") } }
    @Published var showMeetingButton: Bool { didSet { defaults.set(showMeetingButton, forKey: "showMeetingButton") } }

    // Global shortcut (Carbon key code and modifier mask)
    @Published private(set) var hotKeyCode: UInt32?
    @Published private(set) var hotKeyModifiers: UInt32 = 0
    @Published private(set) var hotKeyDisplay: String = ""

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "showMonth": false,
            "showDayOfWeek": false,
            "hideIcon": false,
            "outlineIcon": false,
            "clockFormat": "",
            "firstWeekday": Calendar.current.firstWeekday,
            "showWeekNumbers": false,
            "highlightWeekend": true,
            "showEventDots": true,
            "showLocation": true,
            "eventDays": 7,
            "theme": Theme.system.rawValue,
            "textSize": TextSize.medium.rawValue,
            "language": AppLanguage.system.rawValue,
            "multiColorDots": true,
            "showRelativeTime": true,
            "showMeetingButton": true
        ])

        showMonth = d.bool(forKey: "showMonth")
        showDayOfWeek = d.bool(forKey: "showDayOfWeek")
        hideIcon = d.bool(forKey: "hideIcon")
        outlineIcon = d.bool(forKey: "outlineIcon")
        clockFormat = d.string(forKey: "clockFormat") ?? ""
        firstWeekday = min(max(d.integer(forKey: "firstWeekday"), 1), 7)
        showWeekNumbers = d.bool(forKey: "showWeekNumbers")
        highlightWeekend = d.bool(forKey: "highlightWeekend")
        showEventDots = d.bool(forKey: "showEventDots")
        showLocation = d.bool(forKey: "showLocation")
        eventDays = min(max(d.integer(forKey: "eventDays"), 0), 31)
        hiddenCalendarIDs = Set(d.stringArray(forKey: "hiddenCalendarIDs") ?? [])
        theme = Theme(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        textSize = TextSize(rawValue: d.string(forKey: "textSize") ?? "") ?? .medium
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .system
        multiColorDots = d.object(forKey: "multiColorDots") != nil ? d.bool(forKey: "multiColorDots") : true
        showRelativeTime = d.object(forKey: "showRelativeTime") != nil ? d.bool(forKey: "showRelativeTime") : true
        showMeetingButton = d.object(forKey: "showMeetingButton") != nil ? d.bool(forKey: "showMeetingButton") : true

        if d.object(forKey: "hotKeyCode") != nil {
            hotKeyCode = UInt32(d.integer(forKey: "hotKeyCode"))
            hotKeyModifiers = UInt32(d.integer(forKey: "hotKeyModifiers"))
            hotKeyDisplay = d.string(forKey: "hotKeyDisplay") ?? ""
        }
    }

    // MARK: Derived values

    /// Gregorian (or user) calendar configured with the chosen first weekday and locale.
    var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = firstWeekday
        cal.locale = L10n.locale
        return cal
    }

    /// Text shown next to (or instead of) the menu bar icon.
    func menuBarTitle(for date: Date) -> String {
        titleFormatter.locale = L10n.locale
        let custom = clockFormat.trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty {
            titleFormatter.dateFormat = custom
            return titleFormatter.string(from: date)
        }
        var parts: [String] = []
        if showDayOfWeek {
            titleFormatter.dateFormat = "EEE"
            parts.append(titleFormatter.string(from: date))
        }
        if showMonth {
            titleFormatter.dateFormat = "MMM"
            parts.append(titleFormatter.string(from: date))
        }
        return parts.joined(separator: " ")
    }

    /// True when the custom clock format shows seconds, so the menu bar needs per-second updates.
    var clockShowsSeconds: Bool {
        clockFormat.contains("s")
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("AleCal: launch at login change failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Global shortcut

    func setHotKey(keyCode: UInt32, flags: NSEvent.ModifierFlags, characters: String) {
        hotKeyCode = keyCode
        hotKeyModifiers = GlobalHotKey.carbonModifiers(from: flags)
        hotKeyDisplay = GlobalHotKey.displayString(keyCode: keyCode, flags: flags, characters: characters)
        defaults.set(Int(keyCode), forKey: "hotKeyCode")
        defaults.set(Int(hotKeyModifiers), forKey: "hotKeyModifiers")
        defaults.set(hotKeyDisplay, forKey: "hotKeyDisplay")
    }

    func clearHotKey() {
        hotKeyCode = nil
        hotKeyModifiers = 0
        hotKeyDisplay = ""
        defaults.removeObject(forKey: "hotKeyCode")
        defaults.removeObject(forKey: "hotKeyModifiers")
        defaults.removeObject(forKey: "hotKeyDisplay")
    }
}
