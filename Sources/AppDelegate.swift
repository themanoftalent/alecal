import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusController = StatusItemController(settings: .shared, store: EventStore(settings: .shared))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again from Finder or Spotlight shows the calendar.
        statusController?.showPopover()
        return false
    }
}

extension Notification.Name {
    static let aleCalPopoverWillShow = Notification.Name("AleCalPopoverWillShow")
}
