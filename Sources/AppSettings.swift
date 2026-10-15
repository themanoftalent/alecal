import AppKit
import Combine
import ServiceManagement
import SwiftUI

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

enum AccentTheme: String, CaseIterable, Identifiable {
    case cyberCyan, electricBlue, emeraldGreen, sunsetOrange, royalViolet, solarAmber, pacificTeal
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .cyberCyan: return Color(red: 0.00, green: 0.85, blue: 0.95)   // #00D8F2 Cyber Neon Cyan
        case .electricBlue: return Color(red: 0.10, green: 0.45, blue: 0.98) // #1A73E8 Electric Blue
        case .emeraldGreen: return Color(red: 0.06, green: 0.75, blue: 0.45) // #10B981 Neon Emerald Green
        case .sunsetOrange: return Color(red: 1.00, green: 0.42, blue: 0.00) // #FF6B00 Sunset Orange
        case .royalViolet: return Color(red: 0.55, green: 0.35, blue: 0.95)  // #8B5CF6 Royal Violet
        case .solarAmber: return Color(red: 0.96, green: 0.62, blue: 0.04)   // #F59E0B Solar Amber
        case .pacificTeal: return Color(red: 0.05, green: 0.70, blue: 0.65)  // #0D9488 Pacific Teal
        }
    }

    var nsColor: NSColor {
        switch self {
        case .cyberCyan: return NSColor(srgbRed: 0.00, green: 0.85, blue: 0.95, alpha: 1.0)
        case .electricBlue: return NSColor(srgbRed: 0.10, green: 0.45, blue: 0.98, alpha: 1.0)
        case .emeraldGreen: return NSColor(srgbRed: 0.06, green: 0.75, blue: 0.45, alpha: 1.0)
        case .sunsetOrange: return NSColor(srgbRed: 1.00, green: 0.42, blue: 0.00, alpha: 1.0)
        case .royalViolet: return NSColor(srgbRed: 0.55, green: 0.35, blue: 0.95, alpha: 1.0)
        case .solarAmber: return NSColor(srgbRed: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)
        case .pacificTeal: return NSColor(srgbRed: 0.05, green: 0.70, blue: 0.65, alpha: 1.0)
        }
    }

    var labelKey: String { "prefs.accent.\(rawValue)" }
}

/// Sanitizes any NSColor so pink / magenta / rose hues are transformed into vibrant cyber cyan or royal violet.
/// Ensures zero pink across event dots, tags, and calendar markers.
public func sanitizePinkColor(_ color: NSColor) -> NSColor {
    guard let rgb = color.usingColorSpace(.sRGB) else { return color }
    let red = rgb.redComponent
    let green = rgb.greenComponent
    let blue = rgb.blueComponent

    var hue: CGFloat = 0
    var sat: CGFloat = 0
    var bri: CGFloat = 0
    var alpha: CGFloat = 0
    rgb.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)

    // Hue 0.0 ... 1.0. Pink / Magenta / Rose is around 0.77 (277°) to 0.98 (353°)
    let isPinkHue = (hue >= 0.77 && hue <= 0.98) && sat > 0.22
    let isPinkRGB = (red > 0.68 && blue > 0.35 && green < (red * 0.78))

    if isPinkHue || isPinkRGB {
        // Remap away from pink to vibrant Cyber Neon Cyan
        return NSColor(srgbRed: 0.00, green: 0.85, blue: 0.95, alpha: alpha)
    }

    return color
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
    @Published var accentTheme: AccentTheme { didSet { defaults.set(accentTheme.rawValue, forKey: "accentTheme") } }
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    @Published var multiColorDots: Bool { didSet { defaults.set(multiColorDots, forKey: "multiColorDots") } }
    @Published var showRelativeTime: Bool { didSet { defaults.set(showRelativeTime, forKey: "showRelativeTime") } }
    @Published var showMeetingButton: Bool { didSet { defaults.set(showMeetingButton, forKey: "showMeetingButton") } }

    var accentColor: Color { accentTheme.color }
    var accentNSColor: NSColor { accentTheme.nsColor }

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
            "accentTheme": AccentTheme.cyberCyan.rawValue,
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
        accentTheme = AccentTheme(rawValue: d.string(forKey: "accentTheme") ?? "") ?? .cyberCyan
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
