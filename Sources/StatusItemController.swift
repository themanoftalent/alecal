import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item, the calendar popover and the preferences window.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let settings: AppSettings
    private let store: EventStore
    private var timer: Timer?
    private var lastRenderKey = ""
    private var cancellables = Set<AnyCancellable>()
    private var preferencesController: PreferencesWindowController?

    private var preferences: PreferencesWindowController {
        if let preferencesController { return preferencesController }
        let controller = PreferencesWindowController(settings: settings, store: store)
        preferencesController = controller
        return controller
    }

    init(settings: AppSettings, store: EventStore) {
        self.settings = settings
        self.store = store
        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        let root = CalendarView(
            onOpenPreferences: { [weak self] in self?.showPreferences() },
            onClose: { [weak self] in self?.popover.performClose(nil) }
        )
        .environmentObject(settings)
        .environmentObject(store)

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.setAccessibilityTitle("AleCal")
        }

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)

        GlobalHotKey.shared.action = { [weak self] in self?.togglePopover() }

        let center = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged,
                     .NSSystemClockDidChange,
                     .NSSystemTimeZoneDidChange] {
            center.addObserver(self, selector: #selector(timeChanged), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(timeChanged),
            name: NSWorkspace.didWakeNotification, object: nil)

        startTimer()
        applySettings()

        Task { await store.requestAccessIfNeeded() }
    }

    // MARK: Menu bar rendering

    private func startTimer() {
        // A one-second tick keeps a custom clock with seconds accurate.
        // The render key check below means the button only redraws when its text changes.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateButton() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func applySettings() {
        popover.appearance = settings.theme.appearance
        preferencesController?.window?.appearance = settings.theme.appearance
        GlobalHotKey.shared.register(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
        lastRenderKey = ""
        updateButton()
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let now = Date()
        let title = settings.menuBarTitle(for: now)
        let day = dayString(for: now)
        let showIcon = !(settings.hideIcon && !title.isEmpty)
        let key = "\(title)|\(day)|\(showIcon)|\(settings.outlineIcon)"
        guard key != lastRenderKey else { return }
        lastRenderKey = key

        button.image = showIcon ? MenuBarIcon.make(day: day, outline: settings.outlineIcon) : nil
        button.title = (showIcon && !title.isEmpty) ? " " + title : title
        button.toolTip = fullDateString(for: now)
    }

    private func dayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func fullDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    @objc private func timeChanged() {
        lastRenderKey = ""
        updateButton()
        store.reload()
    }

    // MARK: Interaction

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            togglePopover()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let prefs = NSMenuItem(title: L("menu.preferences"), action: #selector(openPreferencesFromMenu), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openPreferencesFromMenu() {
        showPreferences()
    }

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        NotificationCenter.default.post(name: .aleCalPopoverWillShow, object: nil)
        store.reload()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func showPreferences() {
        popover.performClose(nil)
        preferences.window?.appearance = settings.theme.appearance
        preferences.show()
    }

    // MARK: NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        statusItem.button?.highlight(true)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }
}
