import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private let runner = ActionRunner()
    private var monitor: GestureEventMonitor?
    private var settingsWindowController: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var isMonitoring = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = GestureEventMonitor(store: store, runner: runner)
        monitor?.start()
        buildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.shutdown()
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "EdgeSwipe")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "EdgeSwipe", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Pause Monitoring", action: #selector(toggleMonitoring), keyEquivalent: "p"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: store, runner: runner)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleMonitoring(_ sender: NSMenuItem) {
        isMonitoring.toggle()

        if isMonitoring {
            monitor?.start()
            sender.title = "Pause Monitoring"
        } else {
            monitor?.stop()
            sender.title = "Resume Monitoring"
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
